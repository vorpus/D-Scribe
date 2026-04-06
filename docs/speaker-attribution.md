# Speaker Attribution Design

> Status: Proposal
> Date: 2026-04-05

## Problem

D Scribe currently labels all system audio as **MEETING** — a single label for every remote participant. In a call with three people, there's no way to tell who said what. This design adds per-speaker attribution to the system audio channel, with persistent speaker recognition across sessions.

## Goals

1. **Identify individual speakers** in the system audio channel (the mixed audio from a call)
2. **Remember speakers across sessions** — once you name "Alice", she's recognized in future meetings
3. **Preserve real-time feel** — don't block the user or degrade the live transcription experience
4. **Run entirely on-device** — no cloud APIs, no data leaving the machine

## Non-Goals

- Diarizing the microphone channel (it's always one person — "You")
- Supporting more than ~10 speakers per meeting (practical limit of offline diarization)

---

## Architecture Overview

**Two-phase approach:** live tentative labels during recording, then offline refinement after.

During recording, a streaming diarizer runs in parallel with VAD+Whisper, providing tentative `Speaker 1`, `Speaker 2` labels in real time. After recording stops, an offline pipeline re-processes the full audio for higher accuracy and maps speakers to persistent profiles with real names.

```
Recording (live)                           Post-processing (after stop)
─────────────────                          ────────────────────────────
                 ┌──► VAD ──► Whisper      System audio WAV
System audio ────┤                           │
                 ├──► Streaming diarizer     ├─ 1. Offline diarization (PyAnnote + VBx)
                 │    (speaker timeline)     ├─ 2. Embedding extraction + clustering
                 └──► WAV file (temp)        ├─ 3. Match against speaker database
                                             ├─ 4. Per-speaker transcription (Whisper)
Mic audio ──► VAD ──► Whisper               └─ 5. Rewrite transcript with real names

Live output:                               Final output:
  [14:30:52] Speaker 1: Hello everyone       [14:30:52] Alice: Hello everyone
  [14:30:55] Speaker 2: Hi, can you hear     [14:30:55] Bob: Hi, can you hear
  [14:31:01] YOU: Yes, loud and clear         [14:31:01] YOU: Yes, loud and clear
```

The live labels are tentative — the streaming diarizer may occasionally swap or split speakers. The offline pass corrects these errors and adds name recognition. This gives users something useful immediately while still delivering high-quality final transcripts.

---

## Detailed Design

### 1. Live Streaming Diarization

A streaming diarizer runs alongside the existing VAD pipeline on system audio. It doesn't replace VAD — it runs in parallel, maintaining a speaker timeline that the VAD consults when labeling segments.

**Model choice: LS-EEND (.dihard3 variant)**

FluidAudio provides two streaming diarizers. For our use case:

| | Sortformer | LS-EEND |
|---|---|---|
| Max speakers | 4 | 10 |
| Latency | ~1s (480ms updates) | ~900ms (100ms updates) |
| Speaker stability | Excellent | Good |
| Overlap handling | Good | Best |
| Quiet speech | Misses it | Catches it |
| Model input | 16kHz | 8kHz (auto-resamples) |
| Compute | ANE-heavy | CPU-only (lightweight) |

**LS-EEND is the better fit** because meetings routinely have 4+ remote participants and the `.dihard3` variant is designed for mixed/unknown recording conditions (exactly what system audio capture produces). It also runs on CPU, leaving the ANE free for Whisper.

If speaker count is known to be ≤ 4 (e.g., a 1:1 call), Sortformer would give more stable IDs. We could auto-select based on detected speaker count, but that's a future optimization.

**Integration with the existing pipeline:**

```swift
// Initialize once at recording start
let liveDiarizer = LSEENDDiarizer(computeUnits: .cpuOnly)
try await liveDiarizer.initialize(variant: .dihard3)

// In the system audio callback (same samples that feed VAD):
liveDiarizer.addAudio(samples, sourceSampleRate: 16_000)
if let update = try liveDiarizer.process() {
    // Timeline is updated with finalized + tentative segments
}
```

The diarizer and VAD both receive the same system audio stream. They operate independently — VAD detects speech boundaries, the diarizer tracks who's speaking when.

**Correlating VAD segments with the diarizer timeline:**

When VAD fires `onSpeechEnd` for the MEETING channel, we need to figure out which speaker was active during that segment. The approach:

```swift
meetingVAD.onSpeechEnd = { [weak self] samples in
    guard let self else { return }
    
    // Ask the diarizer: who was speaking during this time window?
    let segmentEnd = liveDiarizer.timeline.currentTimeSeconds
    let segmentDuration = Float(samples.count) / 16_000.0
    let segmentStart = segmentEnd - segmentDuration
    
    let speakerId = liveDiarizer.timeline.dominantSpeaker(
        from: segmentStart, to: segmentEnd
    ) ?? "Speaker ?"
    
    // Use "Speaker 1", "Speaker 2" etc. as the label
    let label = speakerId
    
    Task {
        await self.transcriptionQueue?.enqueue(label: label, audio: samples)
    }
}
```

`dominantSpeaker(from:to:)` queries the `DiarizerTimeline` for whichever speaker had the most active frames in the given time window. If the diarizer hasn't caught up yet (it lags ~900ms behind real-time), we use the most recently active speaker as a best guess.

**Timeline query helper** (wraps FluidAudio's `DiarizerTimeline`):

```swift
extension DiarizerTimeline {
    /// Returns the speaker ID with the most active frames in [start, end].
    /// Falls back to the most recent speaker if the window has no data yet.
    func dominantSpeaker(from start: Float, to end: Float) -> String? {
        let segments = self.segments(in: start...end)
        
        // Count total duration per speaker in the window
        var durations: [String: Float] = [:]
        for seg in segments {
            let overlap = min(seg.endTimeSeconds, end) - max(seg.startTimeSeconds, start)
            if overlap > 0 {
                durations[seg.speakerId, default: 0] += overlap
            }
        }
        
        // Return speaker with most speaking time in window
        return durations.max(by: { $0.value < $1.value })?.key
    }
}
```

**Speaker enrollment from the database:**

At recording start, if we have persistent speaker profiles with embeddings, we can pre-enroll them into the streaming diarizer. This lets the live labels show recognized names immediately rather than generic "Speaker 1" IDs.

```swift
// At recording start, after initializing the diarizer:
let knownSpeakers = try speakerDatabase.fetchRecentSpeakers(limit: 4)
for speaker in knownSpeakers {
    // Convert stored 256-dim WeSpeaker embedding to enrollment audio
    // Note: LS-EEND enrollment takes raw audio, not embeddings directly.
    // We store a short audio clip (~5s) per profile for this purpose.
    if let enrollmentClip = speaker.enrollmentAudio {
        try liveDiarizer.enrollSpeaker(
            withSamples: enrollmentClip,
            sourceSampleRate: 16_000,
            named: speaker.displayName ?? "Speaker \(speaker.id)"
        )
    }
}
```

**Handling diarizer lag and corrections:**

The streaming diarizer produces both *finalized* and *tentative* segments. Tentative segments may change as more audio arrives. Since our VAD-driven transcript appends lines immediately, we won't retroactively fix live labels — the offline pass handles that. The live labels are "good enough" for following along in real time.

Edge cases:
- **Diarizer hasn't produced output yet** (first ~2s of audio): label as `Speaker ?` — will be resolved quickly
- **Multiple speakers in one VAD segment** (crosstalk): use the dominant speaker; the offline pass will segment more precisely
- **Speaker ID instability** (LS-EEND sometimes swaps IDs): accept it during live; offline corrects it

**Resource budget:**

LS-EEND on CPU is lightweight (~2ms per 100ms of audio on M1). Combined with the existing VAD (also lightweight) and Whisper (ANE/GPU), the three models run on different compute units with minimal contention:

| Model | Compute | Duty cycle |
|-------|---------|-----------|
| Silero VAD (×2 channels) | CPU/ANE | Continuous, ~0.5ms per chunk |
| LS-EEND diarizer | CPU | Continuous, ~2ms per 100ms |
| WhisperKit | ANE/GPU | On-demand per speech segment |

### 2. Audio Capture Changes

**Buffer system audio to disk.** Currently `SystemCapture` streams 16kHz chunks through VAD and discards them. We need to also write the raw audio to a temporary WAV file for post-processing.

```swift
// SystemCapture additions
private var audioFileWriter: AVAudioFile?

func startBuffering(to url: URL) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 16_000, channels: 1, interleaved: false)!
    audioFileWriter = try AVAudioFile(forWriting: url, settings: format.settings)
}

// In the audio callback, alongside feeding VAD:
audioFileWriter?.write(from: buffer)
```

The WAV file lives in a temp directory and is deleted after processing. Audio never persists beyond the current session unless the user explicitly exports it.

**Mic audio timing.** We also need per-100ms RMS levels from the mic channel during recording. This tells us when the local user is speaking, which is critical for filtering mic bleed from system audio embeddings (see Section 4).

### 3. Offline Diarization Pipeline

FluidAudio already provides everything we need. The `OfflineDiarizerManager` runs PyAnnote segmentation + VBx clustering — the same pipeline used in research-grade tools.

```swift
func processRecording(systemAudioURL: URL) async throws -> DiarizationResult {
    let config = OfflineDiarizerConfig(
        clustering: .init(
            clusteringThreshold: 0.6,  // Tuned for meeting audio
            Fa: 0.25                   // VBx prior — improves DER significantly
        ),
        vbx: .init(maxIterations: 24)
    )
    
    let manager = OfflineDiarizerManager(config: config)
    try await manager.prepareModels()
    return try await manager.process(systemAudioURL)
}
```

This returns timed segments with speaker IDs and 256-dimensional WeSpeaker embeddings per speaker. Processing a 1-hour meeting takes ~25 seconds on M1.

**VBx parameter tuning.** The clustering threshold and VBx priors significantly affect quality. The defaults above are a starting point — we should run a grid search across a set of real meeting recordings to optimize. Key parameters:

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `clusteringThreshold` | 0.6 | 0.4–0.8 | Higher = fewer speakers (more merging) |
| `Fa` | 0.25 | 0.05–0.5 | VBx speaker reassignment prior |
| `maxVBxIterations` | 24 | 10–50 | More iterations = better clustering, slower |
| `minSpeakers` | 2 | 1–4 | Floor on speaker count |
| `maxSpeakers` | 11 | 4–20 | Ceiling on speaker count |

### 4. Embedding Clustering Post-Processing

Raw diarizer output often has errors: one person split across two IDs, or two people merged into one. A post-processing step cleans this up using the WeSpeaker embeddings.

**Three-stage cleanup:**

**Stage 1 — Pairwise merge.** Compute cosine similarity between all speaker pairs. If two speakers have similarity > 0.78, merge them (union-find for transitive closure). This catches fragmentation from codec-compressed audio where the same voice sounds slightly different across segments.

**Stage 2 — Small cluster absorption.** Clusters with very little speaking time are likely fragments of a real speaker. Absorb them into the nearest large cluster:
- Micro-clusters (< 10s total speech): merge if nearest neighbor similarity > 0.62
- Small clusters (< 30s): merge if similarity > 0.72
- Safety: never absorb a cluster with 3+ distinct segments, and never reduce total speakers below 2

**Stage 3 — Database-informed split.** Compare per-segment embeddings against known speaker profiles (from the persistent database). If a cluster contains segments that match two different known profiles, split it. This catches the diarizer incorrectly merging two people who happen to sound similar to the model but are distinct in our database.

### 5. Mic Contamination Filtering

In a meeting app (Zoom, Meet, Teams), the system audio capture picks up the local user's voice via echo/sidetone. These contaminated segments produce bad embeddings that pollute speaker profiles.

**Solution:** Use the mic channel's RMS energy to detect when the local user is speaking, then downweight or exclude those segments from embedding computation.

Per-segment contamination scoring based on mic overlap:

| Mic overlap fraction | Weight | Rationale |
|---------------------|--------|-----------|
| > 80% | Exclude entirely | Almost certainly local speaker echo |
| 50–80% | 0.2 | Heavily contaminated |
| 30–50% | 0.5 | Moderately contaminated |
| < 30% | 1.0 | Clean remote speech |

When computing the mean embedding for a speaker cluster, use these weights. This produces much cleaner voiceprints for remote participants.

### 6. Persistent Speaker Database

Speakers are stored in a local SQLite database so they're recognized across sessions.

**Schema:**

```sql
CREATE TABLE speakers (
    id TEXT PRIMARY KEY,
    display_name TEXT,
    name_source TEXT DEFAULT 'auto',   -- 'auto' or 'user_manual'
    embedding BLOB NOT NULL,            -- 256-dim float32 (1024 bytes)
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    call_count INTEGER DEFAULT 1,
    confidence REAL DEFAULT 0.5,
    dispute_count INTEGER DEFAULT 0
);
```

**Location:** `~/Library/Application Support/D Scribe/speakers.sqlite` (WAL mode for crash safety).

**Matching flow after diarization:**

1. Take a snapshot of the database before matching (prevents feedback loops where a profile created during this recording matches itself)
2. For each diarized speaker cluster, compute a quality-filtered mean embedding (excluding contaminated segments, weighting by segment duration and quality)
3. Compare against all profiles using cosine similarity
4. Apply adaptive thresholds based on evidence:

| Segments in cluster | Match threshold | Rationale |
|--------------------|----------------|-----------|
| 1 segment | 0.85 | Need near-certainty with minimal evidence |
| 2–3 segments | 0.78 | Moderate evidence |
| 4+ segments | 0.70 | Strong evidence, can afford lower threshold |

5. Additional safeguards:
   - **Maturity penalty:** Profiles with ≤ 2 prior calls require +0.08 higher similarity (new profiles are noisy)
   - **Ambiguity rejection:** If the top two candidate profiles are within 0.05 similarity, reject the match entirely rather than guessing wrong

6. If matched: update the stored embedding via EMA blending (`new = 0.85 * stored + 0.15 * observed`). This lets profiles adapt to voice changes over time while maintaining stability.
7. If unmatched: create a new profile.

**Cross-cluster dedup:** After matching, if two diarizer clusters matched the same database profile, unify them under one speaker ID.

### 7. Per-Speaker Transcription

Once we have clean speaker segments, re-transcribe the system audio per-speaker. This is better than reusing the real-time transcript because:
- Speaker boundaries are known, so we can transcribe each speaker's audio independently
- No cross-talk in the audio fed to Whisper = higher accuracy
- Timestamps align with the diarization output

```swift
for segment in diarizedSegments {
    let audio = extractAudio(from: systemWAV, start: segment.start, end: segment.end)
    let text = try await whisperEngine.transcribe(audio)
    // Associate text with segment.speakerId
}
```

**Utterance merging:** Consecutive segments from the same speaker within 1.5 seconds are merged for readability, with a 30-second cap to prevent runaway merges.

### 8. Transcript Rewrite

After processing, rewrite the markdown transcript. The format changes from:

```markdown
[14:30:52] MEETING: Yes, we can hear you loud and clear.
```

To:

```markdown
[14:30:52] Alice: Yes, we can hear you loud and clear.
```

Unknown speakers appear as `Speaker 1`, `Speaker 2`, etc. until named.

**YAML frontmatter** is added to the transcript file to track speaker metadata:

```yaml
---
speakers:
  - db_id: "abc123"
    label: "Alice"
    source: "database"
  - db_id: "def456"
    label: "Speaker 2"
    source: "new"
---
```

This enables retroactive updates — when a user names "Speaker 2" as "Bob" in settings, we can scan all transcripts with that `db_id` and update the labels.

### 9. Speaker Naming UI

After recording stops and processing completes, show a speaker naming card if any speakers are unidentified or low-confidence.

**Auto-accept threshold:** Speakers with similarity > 0.88, call_count > 4, and an existing display_name are accepted silently. Everything else goes through the naming UI.

**Naming card shows:**
- A short audio clip (5–8 seconds of their clearest speech) for identification
- Suggested name if a database match exists (with confidence indicator)
- Text field to enter/correct the name
- Option to merge with an existing known speaker

**Actions:**
- **Name** — assign a new name to an unknown speaker
- **Confirm** — accept a suggested name match
- **Correct** — override a wrong suggestion
- **Merge** — combine with an existing profile (e.g., "that's the same person as Alice")

### 10. Profile Maintenance

**Duplicate merging:** After each recording, scan all profiles pairwise. If two profiles have cosine similarity < 0.6, merge them (weighted by call count). Also merge profiles that share the same display name after user naming.

**Pruning:** Remove unnamed, single-call, low-confidence profiles older than 1 hour. These are likely transient speakers (someone who briefly spoke in one meeting and was never identified).

**Retroactive updates:** When a speaker is renamed in Settings, a background task scans all saved transcripts. For each transcript whose YAML frontmatter references that speaker's `db_id`, update the label in both the frontmatter and the transcript body.

---

## Processing Pipeline (End-to-End)

When the user clicks Stop:

| Step | Progress | Operation |
|------|----------|-----------|
| 1 | 0–10% | Resample system audio to 16kHz mono |
| 2 | 10–30% | Run offline diarization (PyAnnote segmentation + VBx clustering) |
| 3 | 30–40% | Embedding post-processing (pairwise merge, absorption, DB-split) |
| 4 | 40–45% | Match speakers against persistent database |
| 5 | 45–80% | Per-speaker transcription with Whisper |
| 6 | 80–90% | Merge utterances and build final transcript |
| 7 | 90–95% | Rewrite transcript file with speaker labels |
| 8 | 95–100% | Update speaker database, cleanup temp files |

**Expected timing** for a 1-hour meeting on M1:
- Diarization: ~25s
- Transcription: ~30s (parallelizable per speaker if GPU allows)
- Everything else: < 5s
- **Total: ~60 seconds**

A progress bar replaces the recording bar during processing.

---

## Data Flow

```
                    ┌──────────────────────────────────────┐
                    │     During Recording                   │
                    │                                        │
  Mic ──────────► VAD ──► Whisper ──► "YOU: ..."            │
                    │                                        │
  System ──┬──► VAD ──────────────────────┐                 │
           │    │                          │                 │
           ├──► LS-EEND ──► timeline ──► label lookup       │
           │    (streaming diarizer)       │                 │
           │                    Whisper ◄──┘                 │
           │                      │                          │
           │                "Speaker 1: ..."                 │
           │                                                 │
           └──► WAV file (temp)                              │
                    │   Mic RMS log (temp)                    │
                    └──────────────────────────────────────┘
                                │
                          (user stops)
                                │
                    ┌───────────▼──────────────────┐
                    │     Post-Processing            │
                    │                                │
                    │  WAV ──► OfflineDiarizer       │
                    │           │                     │
                    │     segments + embeddings       │
                    │           │                     │
                    │     EmbeddingClusterer          │
                    │      (3-stage cleanup)          │
                    │           │                     │
                    │     SpeakerMatcher              │
                    │      (DB lookup + adaptive      │
                    │       thresholds)               │
                    │           │                     │
                    │     Per-speaker Whisper         │
                    │           │                     │
                    │     Transcript rewrite          │
                    │      (Speaker 1 → Alice, etc.)  │
                    │           │                     │
                    │     Speaker DB update           │
                    └──────────────────────────────┘
```

---

## New Files

| File | Purpose |
|------|---------|
| `LiveDiarizer.swift` | Wraps LS-EEND streaming, timeline queries, speaker enrollment |
| `DiarizationService.swift` | Orchestrates the post-processing pipeline |
| `EmbeddingClusterer.swift` | Three-stage cluster cleanup |
| `SpeakerDatabase.swift` | SQLite persistence for speaker profiles |
| `SpeakerMatcher.swift` | Adaptive threshold matching against DB |
| `SpeakerProfileMerger.swift` | Duplicate detection and profile pruning |
| `SpeakerNamingView.swift` | SwiftUI card for naming unknown speakers |
| `SpeakerNamingCard.swift` | Individual speaker identification card |
| `SpeakerClipExtractor.swift` | Extracts short audio clips for naming UI |
| `RetroactiveSpeakerUpdater.swift` | Updates old transcripts when speakers are renamed |

---

## Dependencies

- **FluidAudio** (already included) — provides `OfflineDiarizerManager`, `VBxClustering`, WeSpeaker embedding extraction, and `SpeakerManager`
- **SQLite** — via Foundation's `sqlite3` C API (no additional package needed)

No new dependencies required.

---

## Migration

Existing transcripts (pre-attribution) continue to work as-is. They have no YAML frontmatter and use `YOU`/`MEETING` labels. The parser already handles this format. New transcripts will include frontmatter and per-speaker labels only if diarization ran successfully; if it fails for any reason, the transcript falls back to the existing `MEETING` label.

---

## Privacy

- All processing happens on-device. No audio or embeddings leave the machine.
- Speaker embeddings are stored locally in `~/Library/Application Support/D Scribe/`.
- Raw audio is held in a temp file during the session and deleted after processing. Only short clips (5–8s) are retained temporarily for the naming UI.
- The speaker database can be cleared entirely from Settings.

---

## Open Questions

1. **Auto-select streaming model by speaker count.** If we detect ≤ 4 speakers early in the session, Sortformer would give more stable live IDs than LS-EEND. Could hot-swap after the first ~30s of audio, but adds complexity.

2. **LLM-based name inference.** An on-device small LLM (e.g., Qwen 3.5-4B) could analyze the transcript for conversational cues ("Hey Sarah, can you pull up...") to automatically suggest speaker names. Worth exploring but significantly increases model download size (~2.5 GB).

3. **Optimal VBx parameters.** The clustering threshold and priors need tuning on real meeting data. A grid search across ~15-20 real recordings would establish good defaults.

4. **Handling name variants.** Should "Mike", "Michael", and "Mikey" be treated as the same person? A small hardcoded dictionary of common English name variants could handle this during profile merging.

5. **Enrollment audio storage.** LS-EEND enrollment requires raw audio samples, not embeddings. We'd need to store a short (~5s) audio clip per speaker profile for live enrollment. This increases storage per profile from 1KB to ~160KB — acceptable but worth noting.
