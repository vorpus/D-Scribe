# D Scribe Implementation Plan

MVP target: feature parity with the Python CLI (`scribe/transcribe.py`). Dual-channel local transcription, menu bar app, markdown output.

---

## Milestone 1 — Project skeleton + mic capture

**Goal**: Menu bar app that captures mic audio and prints buffer sizes to the Xcode console. Proves AVAudioEngine tap works, app lifecycle is correct, and permissions prompt cleanly.

**What to build**:
- Convert from WindowGroup app to menu bar-only app (NSStatusItem, no dock icon)
- Menu bar icon (SF Symbol `mic.fill`), gray
- Click opens a popover with a "Start" / "Stop" button and a status label
- On Start: request mic permission, set up AVAudioEngine with inputNode tap at 16kHz mono Float32
- Audio callback accumulates samples into a buffer, prints chunk count to console every second
- On Stop: remove tap, stop engine
- Info.plist: `NSMicrophoneUsageDescription`

**Test**: Run the app. Click Start. Speak. See buffer counts in Xcode console. Click Stop. Confirm audio engine stops cleanly. Restart works.

**Files**:
- `D_ScribeApp.swift` — rewrite as menu bar app
- `ContentView.swift` → rename to `TranscriptPopover.swift` — popover UI
- `Audio/MicCapture.swift` — AVAudioEngine mic wrapper

---

## Milestone 2 — VAD integration

**Goal**: Feed mic audio through FluidAudio Silero VAD. Log speech start/end events to console. No transcription yet.

**What to build**:
- Add FluidAudio Swift package dependency
- `Audio/VADChannel.swift` — wraps FluidAudio streaming API
  - Accepts 16kHz Float32 chunks from MicCapture
  - Fires speech start/end events with accumulated audio buffer
  - Configurable threshold and silence duration
  - Handles max speech duration (10s) with 2s overlap on forced flush
- Wire MicCapture → VADChannel
- On speech end: log "[VAD] Speech segment: X.Xs, N samples" to console
- Popover shows "Listening..." / "Speech detected" status

**Test**: Run the app. Start. Speak, pause, speak again. Console shows discrete speech segments with reasonable durations. Silence doesn't trigger segments. Long monologue gets force-split at ~10s.

**Files**:
- `Audio/VADChannel.swift` — new
- `Audio/MicCapture.swift` — minor: expose callback for processed audio
- Package dependency: FluidAudio

---

## Milestone 3 — WhisperKit transcription (mic only)

**Goal**: Complete mic-only transcription pipeline. Speech segments from VAD feed into WhisperKit, transcript lines appear in the popover and write to a markdown file. Equivalent to `poc.py`.

**What to build**:
- Add WhisperKit Swift package dependency
- `Transcription/WhisperEngine.swift` — WhisperKit wrapper
  - Init: download/load distil-large-v3 model with progress reporting
  - `transcribe([Float]) async -> String` — single segment transcription
  - Configurable language
- `Transcription/TranscriptionQueue.swift` — serial async queue
  - Accepts (label: String, audio: [Float]) tuples
  - Processes one at a time to avoid GPU contention
  - Calls back with (label, timestamp, text)
- `Output/TranscriptWriter.swift` — markdown file writer
  - Creates `~/transcripts/YYYY-MM-DD_HH-MM.md`
  - Writes header on start, appends `[HH:MM:SS] YOU: text` lines in real-time, writes footer on stop
- Wire: MicCapture → VADChannel → TranscriptionQueue → TranscriptWriter
- Popover: show last ~10 transcript lines (live-updating), line count, duration
- First-launch UX: show model download progress in popover
- Menu bar icon turns red when recording

**Test**: Run the app. Start. Speak into mic. See `[HH:MM:SS] YOU: <your words>` appear in the popover within ~2-3s of silence. Check `~/transcripts/` for the markdown file. Stop — file has header and footer. Restart and transcribe again.

**Files**:
- `Transcription/WhisperEngine.swift` — new
- `Transcription/TranscriptionQueue.swift` — new
- `Output/TranscriptWriter.swift` — new
- `TranscriptPopover.swift` — add transcript line list, status bar
- `D_ScribeApp.swift` — wire pipeline, icon state
- Package dependency: WhisperKit

---

## Milestone 4 — System audio capture (dual channel)

**Goal**: Add system audio capture via Core Audio Tap API. Both YOU and MEETING channels transcribe simultaneously. Feature parity with `transcribe.py`.

**What to build**:
- `Audio/SystemCapture.swift` — Core Audio Tap wrapper
  - Create CATapDescription (mono global tap, exclude self)
  - Aggregate device setup
  - IO proc callback delivers audio buffers
  - Resample from device rate (44.1/48kHz) to 16kHz using AVAudioConverter
  - Start/stop lifecycle, cleanup on deinit
- Info.plist: `NSAudioCaptureUsageDescription`
- Second VADChannel instance for MEETING channel
- Wire: SystemCapture → VADChannel(MEETING) → TranscriptionQueue → TranscriptWriter
- Transcript lines labeled `YOU` (mic) and `MEETING` (system audio)
- Popover: YOU lines styled differently from MEETING lines

**Test**: Run the app. Start. Play a YouTube video or join a meeting. See `[HH:MM:SS] MEETING: <audio content>` lines appear. Speak into mic — see `YOU:` lines interleaved. Both channels in the markdown file. Stop — clean shutdown, file finalized.

**Files**:
- `Audio/SystemCapture.swift` — new
- `D_ScribeApp.swift` — wire second channel
- `TranscriptPopover.swift` — color-code YOU vs MEETING lines
- Info.plist update

---

## Milestone 5 — Mute, hotkey, settings, polish

**Goal**: Final MVP polish. Global hotkey, mic mute, settings, resilience. Full parity with the Python CLI.

**What to build**:
- Global hotkey: Cmd+D toggles mic mute via `NSEvent.addGlobalMonitorForEvents`
- Mute state: MicCapture zeros out audio (keeps engine running so unmute is instant)
- Menu bar icon: gray (idle), red (recording), yellow (muted)
- Settings view (sheet or separate window):
  - Language selection
  - Output directory picker
  - VAD threshold / silence duration sliders
  - Model selection (distil-large-v3, large-v3-turbo)
- Settings persisted via UserDefaults
- Popover enhancements:
  - Session info: duration timer, line count, output file path
  - Mute toggle button showing current state and hotkey hint
- Graceful error handling:
  - System audio tap failure: show status, continue with mic-only
  - Model download failure: retry button
- Clean app lifecycle: stop everything on quit

**Test**: Full workflow test. Start recording. Speak (YOU lines appear). Play meeting audio (MEETING lines appear). Cmd+D to mute — icon turns yellow, mic audio stops, meeting audio continues. Cmd+D again — unmute. Change language in settings. Stop — markdown file complete with header/footer. Relaunch — settings persist.

**Files**:
- `SettingsView.swift` — new
- `D_ScribeApp.swift` — hotkey, icon states, settings integration
- `TranscriptPopover.swift` — mute button, session info
- `Audio/MicCapture.swift` — mute support

---

## Architecture Summary

```
D_ScribeApp (SwiftUI, menu bar)
├── TranscriptPopover (live transcript view)
├── SettingsView (preferences)
├── Audio/
│   ├── MicCapture (AVAudioEngine, 16kHz mono)
│   ├── SystemCapture (Core Audio Tap, resamples to 16kHz)
│   └── VADChannel (FluidAudio Silero VAD, speech segmentation)
├── Transcription/
│   ├── WhisperEngine (WhisperKit, CoreML/Metal)
│   └── TranscriptionQueue (serial async processing)
└── Output/
    └── TranscriptWriter (real-time markdown file I/O)
```

## Dependency Summary

| Package | Version | Purpose |
|---------|---------|---------|
| WhisperKit | >= 0.9.0 | Speech-to-text (CoreML/Metal) |
| FluidAudio | >= 0.12.4 | Silero VAD (CoreML) |

No other external dependencies. Core Audio Tap is system API (macOS 14.2+).
