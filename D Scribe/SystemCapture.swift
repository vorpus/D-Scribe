//
//  SystemCapture.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import AudioToolbox
import AVFoundation
import Accelerate
import CoreAudio
import Foundation

/// Captures system audio via the macOS 14.2+ Core Audio Tap API and delivers 16 kHz mono Float32 samples.
final class SystemCapture: @unchecked Sendable {

    /// Called on a background thread with a chunk of 16 kHz mono Float32 samples.
    nonisolated(unsafe) var onAudio: (([Float]) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var tapStreamDesc = AudioStreamBasicDescription()

    private let targetSampleRate: Double = 16_000
    private var sourceSampleRate: Double = 48_000

    /// Counter for throttled logging.
    private var sampleCounter: Int = 0

    /// Raw sample accumulation buffer at native rate.
    private var rawBuffer: [Float] = []
    /// Deliver ~100ms chunks at native rate.
    private var rawDeliverySize: Int = 4800

    /// Processing queue for resampling off the IO thread.
    private let processQueue = DispatchQueue(label: "com.dscribe.system-resample", qos: .userInitiated)

    // MARK: - Public API

    func start() throws {
        stop()

        // 1. Create tap description — capture all system audio, mono.
        let tapDesc = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.name = "D Scribe System Tap"
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted

        // 2. Create the process tap.
        var status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard status == noErr else {
            throw SystemCaptureError.tapCreationFailed(status)
        }

        // 3. Read the tap's audio format.
        var formatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        status = AudioObjectGetPropertyData(tapID, &formatAddr, 0, nil, &formatSize, &tapStreamDesc)
        guard status == noErr else {
            throw SystemCaptureError.formatReadFailed(status)
        }

        sourceSampleRate = tapStreamDesc.mSampleRate
        rawDeliverySize = Int(sourceSampleRate * 0.1)  // ~100ms

        print("[SystemCapture] Tap format: \(sourceSampleRate) Hz, \(tapStreamDesc.mChannelsPerFrame) ch")

        // 4. Get default output device UID.
        let outputUID = try getDefaultOutputDeviceUID()

        // 5. Create aggregate device containing the tap.
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "D Scribe Tap Device",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDesc.uuid.uuidString
                ]
            ]
        ]

        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            throw SystemCaptureError.aggregateDeviceFailed(status)
        }

        // 6. IO proc callback — just copies raw samples, no conversion on RT thread.
        let ioQueue = DispatchQueue(label: "com.dscribe.system-capture", qos: .userInitiated)

        status = AudioDeviceCreateIOProcIDWithBlock(
            &deviceProcID,
            aggregateDeviceID,
            ioQueue
        ) { [weak self] _, inInputData, _, _, _ in
            self?.handleIOBuffer(inInputData)
        }
        guard status == noErr else {
            throw SystemCaptureError.ioProcFailed(status)
        }

        // 7. Start capturing.
        status = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard status == noErr else {
            throw SystemCaptureError.startFailed(status)
        }

        print("[SystemCapture] Started — capturing system audio")
    }

    func stop() {
        if let proc = deviceProcID {
            AudioDeviceStop(aggregateDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
            deviceProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        sampleCounter = 0
        rawBuffer.removeAll()
        print("[SystemCapture] Stopped")
    }

    deinit {
        stop()
    }

    // MARK: - IO Callback

    private var loggedBufferInfo = false

    private func handleIOBuffer(_ inputData: UnsafePointer<AudioBufferList>) {
        let numBuffers = inputData.pointee.mNumberBuffers

        // Log buffer structure once.
        if !loggedBufferInfo {
            loggedBufferInfo = true
            // Walk all buffers in the list.
            let ptr = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            print("[SystemCapture] IO callback: \(numBuffers) buffer(s)")
            for (i, buf) in ptr.enumerated() {
                let byteSize = buf.mDataByteSize
                let channels = buf.mNumberChannels
                let hasData = buf.mData != nil
                var peak: Float = 0
                if hasData, byteSize > 0 {
                    let count = Int(byteSize) / MemoryLayout<Float>.size
                    let p = buf.mData!.assumingMemoryBound(to: Float.self)
                    vDSP_maxmgv(p, 1, &peak, vDSP_Length(count))
                }
                print(String(format: "[SystemCapture]   buffer[%d]: %d bytes, %d ch, hasData=%d, peak=%.6f",
                             i, byteSize, channels, hasData ? 1 : 0, peak))
            }
        }

        // Read from the first buffer that has data.
        let ptr = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        var samples: [Float] = []
        for buf in ptr {
            guard let dataPtr = buf.mData?.assumingMemoryBound(to: Float.self),
                  buf.mDataByteSize > 0 else { continue }
            let frameCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            if frameCount > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: dataPtr, count: frameCount))
                break  // Use first non-empty buffer (mono tap).
            }
        }

        guard !samples.isEmpty else { return }
        rawBuffer.append(contentsOf: samples)

        while rawBuffer.count >= rawDeliverySize {
            let chunk = Array(rawBuffer.prefix(rawDeliverySize))
            rawBuffer.removeFirst(rawDeliverySize)

            processQueue.async { [weak self] in
                self?.resampleAndDeliver(chunk)
            }
        }
    }

    // MARK: - Resampling via vDSP (off the IO thread)

    private func resampleAndDeliver(_ rawSamples: [Float]) {
        let ratio = sourceSampleRate / targetSampleRate
        let outputCount = Int(Double(rawSamples.count) / ratio)
        guard outputCount > 0 else { return }

        var resampled = [Float](repeating: 0, count: outputCount)

        // Use vDSP linear interpolation for downsampling.
        // For exact integer ratios (48000/16000 = 3), this is just decimation.
        if sourceSampleRate.truncatingRemainder(dividingBy: targetSampleRate) == 0 {
            // Exact integer ratio — simple decimation (pick every Nth sample).
            let step = Int(ratio)
            for i in 0..<outputCount {
                let srcIndex = i * step
                if srcIndex < rawSamples.count {
                    resampled[i] = rawSamples[srcIndex]
                }
            }
        } else {
            // Non-integer ratio — linear interpolation via vDSP.
            var control = [Float](repeating: 0, count: outputCount)
            var rampStart = Float(0)
            var rampStep = Float(ratio)
            vDSP_vramp(&rampStart, &rampStep, &control, 1, vDSP_Length(outputCount))

            vDSP_vlint(rawSamples, &control, 1, &resampled, 1,
                        vDSP_Length(outputCount), vDSP_Length(rawSamples.count))
        }

        // Throttled logging with amplitude info.
        sampleCounter += outputCount
        if sampleCounter >= 16_000 {
            sampleCounter -= 16_000
            var maxVal: Float = 0
            vDSP_maxmgv(resampled, 1, &maxVal, vDSP_Length(resampled.count))
            if ENABLE_AUDIO_CONSOLE { print(String(format: "[SystemCapture] 1s of system audio — %d samples, peak=%.6f", outputCount, maxVal)) }
        }

        onAudio?(resampled)
    }

    // MARK: - Helpers

    private func getDefaultOutputDeviceUID() throws -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        guard status == noErr else {
            throw SystemCaptureError.noOutputDevice
        }

        addr.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid)
        guard status == noErr else {
            throw SystemCaptureError.noOutputDevice
        }

        return uid as String
    }
}

// MARK: - Errors

enum SystemCaptureError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case formatReadFailed(OSStatus)
    case invalidFormat
    case converterCreationFailed
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)
    case noOutputDevice

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): return "Failed to create audio tap (error \(s))"
        case .formatReadFailed(let s): return "Failed to read tap format (error \(s))"
        case .invalidFormat: return "Invalid audio format from tap"
        case .converterCreationFailed: return "Failed to create audio converter"
        case .aggregateDeviceFailed(let s): return "Failed to create aggregate device (error \(s))"
        case .ioProcFailed(let s): return "Failed to create IO proc (error \(s))"
        case .startFailed(let s): return "Failed to start capture (error \(s))"
        case .noOutputDevice: return "No audio output device found"
        }
    }
}
