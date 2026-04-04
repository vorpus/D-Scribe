//
//  AppState.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import AppKit
import ApplicationServices
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
    // MARK: - UI State

    var isRecording = false
    var statusText = "Idle"
    var isSpeechDetected = false
    var isMuted = false
    var transcriptLines: [TranscriptLine] = []
    var lineCount = 0
    var sessionStart: Date?
    var outputPath: String = ""
    var isModelLoading = false
    var systemAudioActive = false
    var hasAccessibility = false

    // MARK: - Settings (persisted via UserDefaults)

    var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }

    var outputDirectory: String {
        get { UserDefaults.standard.string(forKey: "outputDirectory") ?? "~/transcripts" }
        set { UserDefaults.standard.set(newValue, forKey: "outputDirectory") }
    }

    var vadThreshold: Float {
        get { UserDefaults.standard.object(forKey: "vadThreshold") as? Float ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: "vadThreshold") }
    }

    var silenceMs: Int {
        get { UserDefaults.standard.object(forKey: "silenceMs") as? Int ?? 800 }
        set { UserDefaults.standard.set(newValue, forKey: "silenceMs") }
    }

    // MARK: - Private

    private let micCapture = MicCapture()
    private let systemCapture = SystemCapture()
    private var micVAD: VADChannel?
    private var meetingVAD: VADChannel?
    private var whisperEngine: WhisperEngine?
    private var transcriptionQueue: TranscriptionQueue?
    private var writer: TranscriptWriter?

    init() {
        checkAccessibility()

        micCapture.onAudio = { [weak self] samples in
            self?.micVAD?.feed(samples)
        }

        systemCapture.onAudio = { [weak self] samples in
            self?.meetingVAD?.feed(samples)
        }
    }

    // MARK: - Accessibility

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility {
            hasAccessibility = trusted
            print("[AppState] Accessibility: \(hasAccessibility)")
        }
    }

    /// Prompt the system to show the Accessibility permission dialog.
    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        hasAccessibility = result
        print("[AppState] Accessibility prompt result: \(result)")
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        micCapture.muted = isMuted
        statusText = isMuted ? "Mic muted" : "Listening..."
    }

    // MARK: - Recording

    func startRecording() {
        Task {
            do {
                // Create engine with current language setting.
                var needsLoad = whisperEngine == nil
                if !needsLoad, let engine = whisperEngine {
                    needsLoad = await !engine.isLoaded
                }
                if needsLoad {
                    let engine = WhisperEngine(language: language)
                    whisperEngine = engine
                    isModelLoading = true
                    statusText = "Downloading model..."
                    try await engine.setup { [weak self] status in
                        DispatchQueue.main.async {
                            self?.statusText = status
                        }
                    }
                    isModelLoading = false
                }

                // Set up transcription queue.
                let queue = TranscriptionQueue(engine: whisperEngine!)
                await queue.setOnTranscription { [weak self] result in
                    DispatchQueue.main.async {
                        self?.handleTranscription(result)
                    }
                }
                transcriptionQueue = queue

                // Set up writer.
                let outputDir = (outputDirectory as NSString).expandingTildeInPath
                let w = TranscriptWriter(outputDir: URL(fileURLWithPath: outputDir))
                try w.start()
                writer = w
                outputPath = w.outputPath.path

                // Create VAD channels with current settings.
                let micV = VADChannel(label: "YOU", threshold: vadThreshold, silenceMs: silenceMs)
                let meetV = VADChannel(label: "MEETING", threshold: vadThreshold, silenceMs: silenceMs)

                micV.onSpeechStart = { [weak self] in
                    guard let self else { return }
                    self.isSpeechDetected = true
                }

                micV.onSpeechEnd = { [weak self] samples in
                    guard let self else { return }
                    self.isSpeechDetected = false
                    Task {
                        await self.transcriptionQueue?.enqueue(label: "YOU", audio: samples)
                    }
                }

                meetV.onSpeechEnd = { [weak self] samples in
                    guard let self else { return }
                    Task {
                        await self.transcriptionQueue?.enqueue(label: "MEETING", audio: samples)
                    }
                }

                try await micV.setup()
                try await meetV.setup()
                micVAD = micV
                meetingVAD = meetV

                // Start captures.
                try micCapture.start()

                do {
                    try systemCapture.start()
                    systemAudioActive = true
                } catch {
                    systemAudioActive = false
                    print("[AppState] System audio unavailable: \(error.localizedDescription)")
                }

                isRecording = true
                isMuted = false
                micCapture.muted = false
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
        micVAD?.flushRemaining()
        meetingVAD?.flushRemaining()

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
        isMuted = false
        systemAudioActive = false
        statusText = "Idle"
        sessionStart = nil
    }

    private func handleTranscription(_ result: TranscriptionQueue.Result) {
        let line = TranscriptLine(label: result.label, timestamp: result.timestamp, text: result.text)
        transcriptLines.append(line)
        lineCount = transcriptLines.count

        if transcriptLines.count > 50 {
            transcriptLines.removeFirst(transcriptLines.count - 50)
        }

        writer?.writeLine(label: result.label, timestamp: result.timestamp, text: result.text)

        if isRecording && !isMuted {
            statusText = "Listening..."
        }
    }
}
