//
//  AppState.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import Foundation
import Observation

struct TranscriptLine: Identifiable {
    let id = UUID()
    let label: String
    let timestamp: Date
    let text: String

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

@Observable
@MainActor
final class AppState {
    var isRecording = false
    var statusText = "Idle"
    var isSpeechDetected = false
    var transcriptLines: [TranscriptLine] = []
    var lineCount = 0
    var sessionStart: Date?
    var outputPath: String = ""
    var isModelLoading = false
    var systemAudioActive = false

    private let micCapture = MicCapture()
    private let systemCapture = SystemCapture()
    private let micVAD = VADChannel(label: "YOU", threshold: 0.5, silenceMs: 800)
    private let meetingVAD = VADChannel(label: "MEETING", threshold: 0.5, silenceMs: 800)
    private let whisperEngine = WhisperEngine()
    private var transcriptionQueue: TranscriptionQueue?
    private var writer: TranscriptWriter?

    init() {
        // Wire mic → VAD(YOU)
        micCapture.onAudio = { [weak self] samples in
            self?.micVAD.feed(samples)
        }

        micVAD.onSpeechStart = { [weak self] in
            guard let self else { return }
            self.isSpeechDetected = true
        }

        micVAD.onSpeechEnd = { [weak self] samples in
            guard let self else { return }
            self.isSpeechDetected = false
            Task {
                await self.transcriptionQueue?.enqueue(label: "YOU", audio: samples)
            }
        }

        // Wire system audio → VAD(MEETING)
        systemCapture.onAudio = { [weak self] samples in
            self?.meetingVAD.feed(samples)
        }

        meetingVAD.onSpeechEnd = { [weak self] samples in
            guard let self else { return }
            Task {
                await self.transcriptionQueue?.enqueue(label: "MEETING", audio: samples)
            }
        }
    }

    func startRecording() {
        Task {
            do {
                // Load model if needed.
                if await !whisperEngine.isLoaded {
                    isModelLoading = true
                    statusText = "Downloading model..."
                    try await whisperEngine.setup { [weak self] status in
                        DispatchQueue.main.async {
                            self?.statusText = status
                        }
                    }
                    isModelLoading = false
                }

                // Set up transcription queue.
                let queue = TranscriptionQueue(engine: whisperEngine)
                await queue.setOnTranscription { [weak self] result in
                    DispatchQueue.main.async {
                        self?.handleTranscription(result)
                    }
                }
                transcriptionQueue = queue

                // Set up writer.
                let w = TranscriptWriter()
                try w.start()
                writer = w
                outputPath = w.outputPath.path

                // Set up VAD channels.
                try await micVAD.setup()
                try await meetingVAD.setup()

                // Start mic capture.
                try micCapture.start()

                // Start system audio capture (non-fatal if it fails).
                do {
                    try systemCapture.start()
                    systemAudioActive = true
                } catch {
                    systemAudioActive = false
                    print("[AppState] System audio unavailable: \(error.localizedDescription)")
                    print("[AppState] Continuing with mic-only mode")
                }

                isRecording = true
                sessionStart = Date()
                statusText = "Listening..."
            } catch {
                isRecording = false
                isModelLoading = false
                statusText = "Error: \(error.localizedDescription)"
                print("[AppState] Start error: \(error)")
            }
        }
    }

    func stopRecording() {
        micCapture.stop()
        systemCapture.stop()
        micVAD.flushRemaining()
        meetingVAD.flushRemaining()

        // Give a moment for final transcriptions, then finalize.
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                writer?.finalize()
                let path = writer?.outputPath.path ?? ""
                let count = writer?.lineCount ?? 0
                print("[AppState] Saved to \(path) — \(count) lines")
                writer = nil
                transcriptionQueue = nil
            }
        }

        isRecording = false
        isSpeechDetected = false
        systemAudioActive = false
        statusText = "Idle"
        sessionStart = nil
    }

    private func handleTranscription(_ result: TranscriptionQueue.Result) {
        let line = TranscriptLine(label: result.label, timestamp: result.timestamp, text: result.text)
        transcriptLines.append(line)
        lineCount = transcriptLines.count

        // Keep only last 50 lines in memory.
        if transcriptLines.count > 50 {
            transcriptLines.removeFirst(transcriptLines.count - 50)
        }

        writer?.writeLine(label: result.label, timestamp: result.timestamp, text: result.text)

        if isRecording {
            statusText = "Listening..."
        }
    }
}
