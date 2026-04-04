//
//  TranscriptionQueue.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import Foundation

/// Serializes speech segments through WhisperKit one at a time to avoid GPU contention.
actor TranscriptionQueue {

    struct Result: Sendable {
        let label: String
        let timestamp: Date
        let text: String
    }

    private let engine: WhisperEngine
    private var onTranscription: (@Sendable (Result) -> Void)?

    init(engine: WhisperEngine) {
        self.engine = engine
    }

    func setOnTranscription(_ callback: @escaping @Sendable (Result) -> Void) {
        self.onTranscription = callback
    }

    /// Enqueue a speech segment for transcription. Processed serially.
    func enqueue(label: String, audio: [Float]) async {
        let timestamp = Date()
        do {
            let text = try await engine.transcribe(audio)
            guard !text.isEmpty else { return }

            let duration = Float(audio.count) / 16_000.0
            print(String(format: "[TranscriptionQueue] %@ %.1fs → \"%@\"", label, duration, text))

            let result = Result(label: label, timestamp: timestamp, text: text)
            onTranscription?(result)
        } catch {
            print("[TranscriptionQueue] Transcription error: \(error)")
        }
    }
}
