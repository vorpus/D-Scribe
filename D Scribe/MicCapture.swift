//
//  MicCapture.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import AVFoundation

/// Captures microphone audio via AVAudioEngine and delivers 16 kHz mono Float32 samples.
final class MicCapture: @unchecked Sendable {

    /// Called on a background thread with a chunk of 16 kHz mono Float32 samples.
    nonisolated(unsafe) var onAudio: (([Float]) -> Void)?

    /// When true, delivers silence instead of mic audio (keeps engine running for instant unmute).
    var muted: Bool = false

    private var engine: AVAudioEngine?

    /// Desired output format: 16 kHz, mono, Float32.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Counter used to throttle console logging (~once per second).
    private var tapCallbackCount: Int = 0

    // MARK: - Public API

    func start() throws {
        stop() // Clean up any previous session.

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw MicCaptureError.noInputDevice
        }

        // Create a converter from the hardware's native format to our target format.
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw MicCaptureError.converterCreationFailed
        }

        // How many target-format frames correspond to each tap buffer.
        // We request a buffer size in terms of the *input* format.
        let inputBufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: inputFormat) {
            [weak self] (buffer, _) in
            guard let self else { return }
            self.handleTapBuffer(buffer, converter: converter)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        tapCallbackCount = 0
    }

    // MARK: - Private

    private func handleTapBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        // Figure out how many output frames we need.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("[MicCapture] Conversion error: \(error)")
            return
        }

        // Extract Float32 samples from the converted buffer.
        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        var samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Zero out audio when muted (keeps engine running for instant unmute).
        if muted {
            samples = [Float](repeating: 0, count: frameLength)
        }

        // Throttled logging: ~1 per second assuming ~16000 samples/sec.
        tapCallbackCount += frameLength
        if tapCallbackCount >= 16_000 {
            tapCallbackCount -= 16_000
            print("[MicCapture] 1s of audio captured — \(frameLength) frames this buffer, format: \(targetFormat.sampleRate) Hz")
        }

        onAudio?(samples)
    }
}

// MARK: - Errors

enum MicCaptureError: LocalizedError {
    case noInputDevice
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device available."
        case .converterCreationFailed:
            return "Could not create audio format converter."
        }
    }
}
