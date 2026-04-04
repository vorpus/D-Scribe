# WhisperKit Research

## Package Info

- **Repo**: https://github.com/argmaxinc/WhisperKit
- **Latest version**: v0.18.0
- **License**: MIT
- **Swift tools version**: 5.9+
- **macOS minimum**: 13.0 (Package.swift), README says 14.0 + Xcode 16.0
- **Dependencies**: `swift-transformers` (HuggingFace Hub SDK) >= 1.1.6

## Adding to Project

### Xcode
File > Add Package Dependencies > `https://github.com/argmaxinc/whisperkit` > select `WhisperKit` library.

### Package.swift
```swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]
```

## Model Downloading

Models download **on-demand at runtime** from HuggingFace (`argmaxinc/whisperkit-coreml`). Pre-converted to CoreML `.mlmodelc` format.

- First launch: downloads model + shows progress
- Subsequent launches: loads from cache (no network)
- `download: false` in config skips download (use with `modelFolder` for bundled models)

```swift
// Manual download with progress
let modelFolder = try await WhisperKit.download(
    variant: "distil-large-v3",
    from: "argmaxinc/whisperkit-coreml",
    progressCallback: { progress in
        print("Download: \(progress.fractionCompleted * 100)%")
    }
)

// List available models
let models = try await WhisperKit.fetchAvailableModels()
```

## Initialization

```swift
import WhisperKit

// Basic (auto-picks best model for device)
let pipe = try await WhisperKit()

// Specific model
let config = WhisperKitConfig(model: "distil*large-v3")
let pipe = try await WhisperKit(config)

// Full config for menu bar app
let config = WhisperKitConfig(
    model: "distil*large-v3",
    modelRepo: "argmaxinc/whisperkit-coreml",
    computeOptions: ModelComputeOptions(
        melCompute: .cpuAndGPU,
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    ),
    verbose: false,
    prewarm: true,   // loads models sequentially, reduces peak memory
    load: true,
    download: true
)
let pipe = try await WhisperKit(config)
```

`prewarm: true` triggers CoreML specialization (compilation for specific chip). Reduces peak memory at cost of ~2x load time. Cache evicted after OS updates.

## Transcribing Audio Buffers (Critical API)

WhisperKit accepts `[Float]` at **16kHz mono**. This is what we feed from VAD segments.

```swift
let options = DecodingOptions(
    task: .transcribe,
    language: "en",
    temperature: 0.0,
    usePrefillPrompt: true,
    usePrefillCache: true,
    wordTimestamps: true,
    noSpeechThreshold: 0.6
)

// Single buffer
let results: [TranscriptionResult] = try await pipe.transcribe(
    audioArray: audioSamples,  // [Float], 16kHz mono
    decodeOptions: options
)

for result in results {
    print(result.text)
    for segment in result.segments {
        print("[\(segment.start)s - \(segment.end)s] \(segment.text)")
    }
}

// Batch
let results = await pipe.transcribe(
    audioArrays: [segment1, segment2, segment3],
    decodeOptions: options
)
```

### Progress callback (for long segments)
```swift
let results = try await pipe.transcribe(
    audioArray: audioSamples,
    decodeOptions: options,
    callback: { progress -> Bool? in
        print("Partial: \(progress.text)")
        return true  // false to cancel, nil to continue
    }
)
```

### Key types
```
TranscriptionResult
  .text: String
  .segments: [TranscriptionSegment]
  .language: String
  .timings: TranscriptionTimings

TranscriptionSegment
  .start / .end: Float (seconds)
  .text: String
  .words: [WordTiming]? (if wordTimestamps: true)
  .noSpeechProb: Float

WordTiming
  .word: String
  .start / .end: Float
  .probability: Float
```

## DecodingOptions Reference

```swift
DecodingOptions(
    verbose: false,
    task: .transcribe,              // .transcribe or .translate (to English)
    language: "en",                 // nil = auto-detect
    temperature: 0.0,               // 0.0 = greedy
    temperatureFallbackCount: 5,
    sampleLength: 224,              // max tokens per window
    usePrefillPrompt: true,
    usePrefillCache: true,
    wordTimestamps: true,
    compressionRatioThreshold: 2.4, // hallucination detector
    logProbThreshold: -1.0,
    noSpeechThreshold: 0.6,
    chunkingStrategy: .vad          // nil for pre-chunked segments
)
```

For short VAD segments (under 30s), no need for `chunkingStrategy: .vad` -- segments already fit one Whisper window.

## Compute Options

```swift
ModelComputeOptions(
    melCompute: .cpuAndGPU,
    audioEncoderCompute: .cpuAndNeuralEngine,  // default macOS 14+
    textDecoderCompute: .cpuAndNeuralEngine,
    prefillCompute: .cpuOnly
)
// Options: .cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine, .all
```

Using `.cpuAndNeuralEngine` for encoder+decoder leaves GPU free for other apps.

## macOS Gotchas

1. **Microphone permission**: Needs `NSMicrophoneUsageDescription` in Info.plist
2. **App Sandbox**: If sandboxed, enable "Audio Input" capability
3. **CoreML cache eviction**: Specialized models recompile after OS updates -- first run will be slow
4. **Memory**: distil-large-v3 is the right choice for a menu bar app (smaller, faster)
5. **Sample rate constant**: `WhisperKit.sampleRate` = 16000. Must resample to 16kHz mono before transcribing.
6. **Built-in streaming**: WhisperKit has `AudioStreamTranscriber` for real-time mic streaming with VAD, but we want more control via our own VAD pipeline
