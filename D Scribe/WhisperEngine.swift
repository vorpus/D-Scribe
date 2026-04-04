//
//  WhisperEngine.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import WhisperKit
import Foundation

/// Wraps WhisperKit for on-device speech-to-text transcription.
actor WhisperEngine {

    private var whisperKit: WhisperKit?
    private let modelName: String
    private let language: String

    var isLoaded: Bool { whisperKit != nil }

    init(model: String = "distil-large-v3", language: String = "en") {
        self.modelName = model
        self.language = language
    }

    /// Download (if needed) and load the model.
    /// `onStatus` is called with a human-readable status string (e.g., "Downloading 42%", "Loading model...").
    func setup(onStatus: (@Sendable (String) -> Void)? = nil) async throws {
        // Phase 1: Download model (with progress).
        onStatus?("Downloading model...")
        let modelFolder = try await WhisperKit.download(
            variant: modelName,
            progressCallback: { progress in
                let pct = Int(progress.fractionCompleted * 100)
                onStatus?("Downloading model... \(pct)%")
            }
        )

        // Phase 2: Load model into memory.
        onStatus?("Loading model...")
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )
        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        onStatus?("Ready")
        print("[WhisperEngine] Model loaded: \(modelName)")
    }

    /// Transcribe a 16kHz mono Float32 audio buffer. Returns the transcribed text.
    func transcribe(_ audioBuffer: [Float]) async throws -> String {
        guard let kit = whisperKit else {
            throw WhisperEngineError.notLoaded
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6
        )

        let results = try await kit.transcribe(
            audioArray: audioBuffer,
            decodeOptions: options
        )

        let text = results.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return text
    }
}

enum WhisperEngineError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "Whisper model not loaded."
        }
    }
}
