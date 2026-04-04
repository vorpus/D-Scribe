# FluidAudio VAD Research

## Package Info

- **Repo**: https://github.com/FluidInference/FluidAudio
- **Current version**: 0.12.4
- **License**: MIT (code) / Apache 2.0 (models)
- **Swift**: 6.0+ required (strict concurrency)
- **macOS minimum**: 14.0 (Sonoma)
- **Docs**: https://docs.fluidinference.com/introduction

## What It Is

Swift SDK for local audio AI on Apple devices. Includes transcription, diarization, TTS, and **Voice Activity Detection using Silero VAD v6 CoreML models**. We only need the VAD.

| Property | Value |
|----------|-------|
| VAD Model | Silero VAD v6 (language-agnostic) |
| Format | CoreML (.mlmodelc) |
| Window size | 256ms (4096 samples at 16 kHz) |
| RTFx | ~1230x real-time |
| Accuracy | 96% |
| Default compute | CPU-only |

## Adding to Project

```swift
dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
]
```

Also available via CocoaPods: `pod 'FluidAudio', '~> 0.12.4'`

## Audio Format Requirements

- **Sample rate**: 16 kHz
- **Format**: Mono Float32
- **Chunk size**: 4096 samples (256ms)
- Not normalized -- raw amplitude preserved

## Initialization

```swift
// Auto-download model on first use
let manager = try await VadManager(
    config: VadConfig(defaultThreshold: 0.75)
)

// Manual model loading (for bundled models)
let modelURL = URL(fileURLWithPath: "path/to/silero-vad-unified-256ms-v6.0.0.mlmodelc", isDirectory: true)
var configuration = MLModelConfiguration()
configuration.computeUnits = .cpuOnly
let vadModel = try MLModel(contentsOf: modelURL, configuration: configuration)
let manager = VadManager(config: .default, vadModel: vadModel)
```

## Streaming VAD (Real-Time -- Key API)

This is what we need for live transcription:

```swift
// Initialize streaming state
var state = manager.makeStreamState()

// Feed audio chunks (flexible size, not required to be exactly 4096)
let result = try await manager.processStreamingChunk(
    chunk,
    state: state,
    config: .default,
    returnSeconds: true,
    timeResolution: 2
)

// Update state for next iteration
state = result.state

// Check for speech boundary events
if let event = result.event {
    switch event {
    case .speechStart:
        print("Speech started at \(event.time ?? 0)s")
    case .speechEnd:
        print("Speech ended at \(event.time ?? 0)s")
    }
}

// Raw probability
let prob = result.probability  // 0.0 - 1.0
```

**Streaming behavior:**
- At most **one event per chunk** call
- Chunks don't need to be exactly 4096 samples (flexible buffering)
- State passed sequentially -- each call returns updated state
- Built-in hysteresis prevents rapid oscillation

## Batch Processing

```swift
// Chunk-level probabilities
let results = try await manager.process(samples)
for (index, chunk) in results.enumerated() {
    print(String(format: "Chunk %02d: prob=%.3f", index, chunk.probability))
}

// Speech segments with timestamps
let segments = try await manager.segmentSpeech(samples, config: segmentation)

// Speech segments with extracted audio buffers
let clips = try await manager.segmentSpeechAudio(samples, config: segmentation)
```

## Segmentation Configuration

```swift
var config = VadSegmentationConfig.default
config.minSpeechDuration    = 0.15   // Min speech to keep (filters clicks)
config.minSilenceDuration   = 0.75   // Silence needed to end segment
config.maxSpeechDuration    = 14.0   // Force-split long segments
config.speechPadding        = 0.1    // Context padding on boundaries
config.silenceThresholdForSplit = 0.3
config.negativeThresholdOffset = 0.15 // Hysteresis gap
```

**Hysteresis**: Speech activates above threshold, deactivates only below `threshold - negativeThresholdOffset`. Values between maintain current state.

### Recommended for transcription app

```swift
var seg = VadSegmentationConfig.default
seg.minSpeechDuration = 0.25    // Skip noise
seg.minSilenceDuration = 0.4    // Faster end-of-utterance
seg.speechPadding = 0.12        // Capture onset/offset
```

## Key Types

| Type | Purpose |
|------|---------|
| `VadManager` | Main class (@MainActor-isolated) |
| `VadConfig` | Model config: `defaultThreshold` (0.85) |
| `VadSegmentationConfig` | Segment params |
| `VadState` | LSTM hidden/cell state + context buffer |
| `VadStreamState` | Streaming: model state, trigger, sample counts |
| `VadStreamEvent` | `.speechStart` or `.speechEnd` with sample index |
| `VadStreamResult` | Combined state + event + probability |

All types conform to `Sendable`.

## Gotchas

1. **@MainActor isolation**: `VadManager` is MainActor-isolated. Cannot call from background audio thread directly -- need actor hopping.
2. **Model auto-download**: First init downloads from HuggingFace. Pre-bundle for offline use.
3. **Swift 6.0 required**: Won't compile with older Xcode.
4. **Heavy dependency**: Pulls in ASR, TTS, diarization even if you only need VAD.
5. **Beta status**: VadManager marked as beta.
6. **CPU-only default**: VAD runs on CPU, which is fine (small model, fast).
7. **One event per chunk**: May miss very short speech bursts within a single chunk.
8. **Precondition traps**: Invalid VadSegmentationConfig values crash (precondition), don't throw.

## Alternatives if FluidAudio Is Too Heavy

1. **Direct Silero VAD CoreML**: Load `.mlmodel` from `FluidInference/silero-vad-coreml` on HuggingFace, call via `MLModel` API. Manual LSTM state management.
2. **whisper.cpp VAD**: C++ Silero-based VAD, callable from Swift via bridging.
3. **Custom CoreML wrapper**: Convert ONNX Silero model via `coremltools`, thin Swift wrapper around `MLModel.prediction()`.
