//
//  VADChannel.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import FluidAudio
import CoreML
import Foundation

/// Wraps FluidAudio's streaming VAD to detect speech boundaries in a single audio channel.
final class VADChannel: @unchecked Sendable {

    let label: String

    /// Called when a speech segment ends, with the accumulated audio buffer.
    var onSpeechEnd: (([Float]) -> Void)?

    /// Called when speech starts.
    var onSpeechStart: (() -> Void)?

    // MARK: - Configuration

    private let threshold: Float
    private let silenceMs: Int
    private let maxSpeechSeconds: Float

    // MARK: - VAD state (accessed only from processingQueue)

    private var vadManager: VadManager?
    private var streamState: VadStreamState = .initial()
    private var segConfig: VadSegmentationConfig = .default
    private var isSpeaking = false
    private var speechBuffer: [Float] = []
    private var speechSampleCount: Int = 0

    /// Overlap kept when force-flushing long speech (2 seconds at 16 kHz).
    private let overlapSamples = 2 * 16_000

    // MARK: - Thread-safe pending buffer

    private let pendingLock = NSLock()
    private var pendingSamples: [Float] = []
    private var processingScheduled = false

    // MARK: - Init

    init(label: String, threshold: Float = 0.5, silenceMs: Int = 800, maxSpeechSeconds: Float = 10.0) {
        self.label = label
        self.threshold = threshold
        self.silenceMs = silenceMs
        self.maxSpeechSeconds = maxSpeechSeconds
    }

    // MARK: - Setup

    func setup() async throws {
        let config = VadConfig(defaultThreshold: threshold)
        vadManager = try await VadManager(config: config)
        streamState = .initial()

        segConfig = VadSegmentationConfig(
            minSpeechDuration: 0.25,
            minSilenceDuration: Double(silenceMs) / 1000.0,
            speechPadding: 0.1
        )

        print("[VAD:\(label)] Initialized with threshold=\(threshold), silenceMs=\(silenceMs)")
    }

    // MARK: - Feed audio from real-time thread

    /// Called from the audio callback thread. Copies data and schedules processing.
    func feed(_ samples: [Float]) {
        pendingLock.lock()
        pendingSamples.append(contentsOf: samples)
        let shouldSchedule = !processingScheduled
        processingScheduled = true
        pendingLock.unlock()

        if shouldSchedule {
            Task { await self.processPending() }
        }
    }

    // MARK: - Processing

    private func drainPending() -> [Float] {
        pendingLock.lock()
        let samples = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        pendingLock.unlock()
        return samples
    }

    private func clearScheduled() {
        pendingLock.lock()
        processingScheduled = false
        pendingLock.unlock()
    }

    private func processPending() async {
        while true {
            let samples = drainPending()

            guard !samples.isEmpty else {
                clearScheduled()
                return
            }

            guard let manager = vadManager else { return }

            // Accumulate into speech buffer if currently speaking.
            if isSpeaking {
                speechBuffer.append(contentsOf: samples)
                speechSampleCount += samples.count
            }

            do {
                let result = try await manager.processStreamingChunk(
                    samples,
                    state: streamState,
                    config: segConfig,
                    returnSeconds: true,
                    timeResolution: 2
                )

                streamState = result.state

                if let event = result.event {
                    switch event.kind {
                    case .speechStart:
                        handleSpeechStart(samples: samples)
                    case .speechEnd:
                        handleSpeechEnd()
                    }
                }

                checkMaxDuration()

            } catch {
                print("[VAD:\(label)] Processing error: \(error)")
            }
        }
    }

    private func handleSpeechStart(samples: [Float]) {
        guard !isSpeaking else { return }
        isSpeaking = true
        speechBuffer = samples
        speechSampleCount = samples.count
        if ENABLE_AUDIO_CONSOLE { print("[VAD:\(label)] Speech started") }
        DispatchQueue.main.async { self.onSpeechStart?() }
    }

    private func handleSpeechEnd() {
        guard isSpeaking else { return }
        isSpeaking = false
        let duration = Float(speechSampleCount) / 16_000.0
        if ENABLE_AUDIO_CONSOLE { print(String(format: "[VAD:%@] Speech ended — %.1fs, %d samples", label, duration, speechSampleCount)) }
        let buffer = speechBuffer
        DispatchQueue.main.async { self.onSpeechEnd?(buffer) }
        speechBuffer.removeAll(keepingCapacity: true)
        speechSampleCount = 0
    }

    private func checkMaxDuration() {
        guard isSpeaking else { return }
        let durationSeconds = Float(speechSampleCount) / 16_000.0
        guard durationSeconds >= maxSpeechSeconds else { return }

        let totalSamples = speechBuffer.count
        let overlapCount = min(overlapSamples, totalSamples)
        let flushBuffer = speechBuffer
        let overlap = Array(speechBuffer[(totalSamples - overlapCount)...])

        if ENABLE_AUDIO_CONSOLE { print(String(format: "[VAD:%@] Force flush at %.1fs — keeping %.1fs overlap",
                      label, durationSeconds, Float(overlapCount) / 16_000.0)) }

        DispatchQueue.main.async { self.onSpeechEnd?(flushBuffer) }

        speechBuffer = overlap
        speechSampleCount = overlapCount
    }

    // MARK: - Shutdown

    func flushRemaining() {
        guard isSpeaking, !speechBuffer.isEmpty else { return }
        let duration = Float(speechSampleCount) / 16_000.0
        if ENABLE_AUDIO_CONSOLE { print(String(format: "[VAD:%@] Flushing remaining speech — %.1fs, %d samples",
                      label, duration, speechSampleCount)) }
        let buffer = speechBuffer
        onSpeechEnd?(buffer)
        speechBuffer.removeAll()
        speechSampleCount = 0
        isSpeaking = false
    }
}
