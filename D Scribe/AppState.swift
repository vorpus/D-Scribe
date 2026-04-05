//
//  AppState.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation

/// Set to `true` to enable periodic audio capture logging (sample counts, peaks, VAD events).
let ENABLE_AUDIO_CONSOLE = false

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
    var hasMicrophone = false
    var hasAudioCapture = false

    // MARK: - File Browser State

    var selectedFile: URL?
    var fileList: [URL] = []
    /// The file currently being recorded to (nil when not recording)
    var activeRecordingFile: URL?

    // MARK: - Settings (stored properties synced to UserDefaults)

    var language: String = UserDefaults.standard.string(forKey: "language") ?? "en" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    var outputDirectory: String = UserDefaults.standard.string(forKey: "outputDirectory") ?? "~/transcripts" {
        didSet { UserDefaults.standard.set(outputDirectory, forKey: "outputDirectory") }
    }

    var vadThreshold: Float = UserDefaults.standard.object(forKey: "vadThreshold") as? Float ?? 0.5 {
        didSet { UserDefaults.standard.set(vadThreshold, forKey: "vadThreshold") }
    }

    var transcriptFontSize: CGFloat = UserDefaults.standard.object(forKey: "transcriptFontSize") as? CGFloat ?? 13 {
        didSet { UserDefaults.standard.set(transcriptFontSize, forKey: "transcriptFontSize") }
    }

    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 28

    var silenceMs: Int = UserDefaults.standard.object(forKey: "silenceMs") as? Int ?? 800 {
        didSet { UserDefaults.standard.set(silenceMs, forKey: "silenceMs") }
    }

    // MARK: - Hotkey

    /// The key code for the global record/mute hotkey.
    var hotkeyKeyCode: UInt16 = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode") == 0 ? 2 : UserDefaults.standard.integer(forKey: "hotkeyKeyCode")) {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }

    /// The modifier flags for the global hotkey (stored as raw value).
    var hotkeyModifiers: UInt = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt ?? NSEvent.ModifierFlags.command.rawValue {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }

    /// Human-readable string for the current hotkey.
    var hotkeyDisplayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: hotkeyModifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    /// Convert a key code to a displayable character.
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        layoutData.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            UCKeyTranslate(
                ptr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        if length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return "?"
    }

    // MARK: - Private

    private let micCapture = MicCapture()
    private let systemCapture = SystemCapture()
    private var micVAD: VADChannel?
    private var meetingVAD: VADChannel?
    private var whisperEngine: WhisperEngine?
    private var transcriptionQueue: TranscriptionQueue?
    private var writer: TranscriptWriter?
    var audioLevelMonitor: AudioLevelMonitor?

    init() {
        checkAccessibility()

        micCapture.onAudio = { [weak self] samples in
            self?.micVAD?.feed(samples)
            self?.audioLevelMonitor?.feedMic(samples)
        }

        systemCapture.onAudio = { [weak self] samples in
            self?.meetingVAD?.feed(samples)
            self?.audioLevelMonitor?.feedSystem(samples)
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

    func checkMicrophone() {
        let status = AVAudioApplication.shared.recordPermission
        hasMicrophone = status == .granted
    }

    func requestMicrophone() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.hasMicrophone = granted
            }
        }
    }

    func checkAudioCapture() {
        // System audio capture permission is the same mic/record permission on macOS.
        // The NSAudioCaptureUsageDescription entitlement gates the Core Audio Tap,
        // but the runtime check is the same record permission.
        let status = AVAudioApplication.shared.recordPermission
        hasAudioCapture = status == .granted
    }

    func requestAudioCapture() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.hasAudioCapture = granted
            }
        }
    }

    /// Check all permissions at once.
    func checkAllPermissions() {
        checkAccessibility()
        checkMicrophone()
        checkAudioCapture()
    }

    // MARK: - Mute

    func toggleMute() {
        isMuted.toggle()
        micCapture.muted = isMuted
        statusText = isMuted ? "Mic muted" : "Listening..."
    }

    // MARK: - Recording

    func startRecording() {
        // Clear previous session's live lines.
        transcriptLines = []
        lineCount = 0

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

                audioLevelMonitor = AudioLevelMonitor()
                isRecording = true
                isMuted = false
                micCapture.muted = false
                sessionStart = Date()
                statusText = "Listening..."
                activeRecordingFile = w.outputPath
                selectedFile = w.outputPath
                refreshFileList()
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

        // Capture references before niling so the flush task can finish.
        let currentWriter = writer
        let currentQueue = transcriptionQueue

        // Clear immediately so a new recording doesn't reuse stale objects.
        writer = nil
        transcriptionQueue = nil
        micVAD = nil
        meetingVAD = nil

        Task {
            // Wait for any in-flight transcriptions to finish.
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                if let w = currentWriter {
                    if w.lineCount > 0 {
                        w.finalize()
                        print("[AppState] Saved to \(w.outputPath.path) — \(w.lineCount) lines")
                    } else {
                        // Empty transcript — delete the file.
                        try? FileManager.default.removeItem(at: w.outputPath)
                        print("[AppState] Empty transcript discarded")
                        if selectedFile == w.outputPath {
                            selectedFile = nil
                        }
                    }
                }
                refreshFileList()
            }
            _ = currentQueue // keep alive until finalized
        }

        audioLevelMonitor = nil
        isRecording = false
        isSpeechDetected = false
        isMuted = false
        systemAudioActive = false
        statusText = "Idle"
        sessionStart = nil
        activeRecordingFile = nil
        refreshFileList()
    }

    private func handleTranscription(_ result: TranscriptionQueue.Result) {
        let line = TranscriptLine(label: result.label, timestamp: result.timestamp, text: result.text)
        transcriptLines.append(line)
        lineCount = transcriptLines.count

        writer?.writeLine(label: result.label, timestamp: result.timestamp, text: result.text)

        if isRecording && !isMuted {
            statusText = "Listening..."
        }
    }

    // MARK: - File Browser

    /// Scan the output directory for .md transcript files, sorted newest first.
    func refreshFileList() {
        let dir = (outputDirectory as NSString).expandingTildeInPath
        let dirURL = URL(fileURLWithPath: dir)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            fileList = []
            return
        }

        fileList = contents
            .filter { $0.pathExtension == "md" }
            .sorted { a, b in
                // Sort by filename descending (filenames are date-based: YYYY-MM-DD_HH-MM.md)
                a.lastPathComponent > b.lastPathComponent
            }
    }

    /// Parse a transcript .md file into TranscriptLine array.
    static func parseTranscriptFile(_ url: URL) -> [TranscriptLine] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let linePattern = /^\[(\d{2}:\d{2}:\d{2})\] (YOU|MEETING): (.+)$/

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        var result: [TranscriptLine] = []
        for line in content.components(separatedBy: "\n") {
            if let match = line.wholeMatch(of: linePattern) {
                let timeStr = String(match.1)
                let label = String(match.2)
                let text = String(match.3)
                let timestamp = formatter.date(from: timeStr) ?? Date()
                result.append(TranscriptLine(label: label, timestamp: timestamp, text: text))
            }
        }
        return result
    }
}
