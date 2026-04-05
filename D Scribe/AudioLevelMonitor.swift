//
//  AudioLevelMonitor.swift
//  D Scribe
//

import Accelerate
import Foundation
import Observation

@Observable
@MainActor
final class AudioLevelMonitor {
    var micLevels: [Float] = []
    var systemLevels: [Float] = []

    private let bufferSize = 50
    /// Amplitude ceiling for normalization — signals above this clip to 1.0.
    private let ceiling: Float = 0.3

    nonisolated func feedMic(_ samples: [Float]) {
        let level = rms(samples)
        DispatchQueue.main.async { [weak self] in
            self?.append(level, to: \.micLevels)
        }
    }

    nonisolated func feedSystem(_ samples: [Float]) {
        let level = rms(samples)
        DispatchQueue.main.async { [weak self] in
            self?.append(level, to: \.systemLevels)
        }
    }

    private func append(_ level: Float, to keyPath: ReferenceWritableKeyPath<AudioLevelMonitor, [Float]>) {
        self[keyPath: keyPath].append(level)
        if self[keyPath: keyPath].count > bufferSize {
            self[keyPath: keyPath].removeFirst(self[keyPath: keyPath].count - bufferSize)
        }
    }

    private nonisolated func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        let value = sqrt(meanSquare) / ceiling
        return min(value, 1.0)
    }
}
