# Core Audio Tap API Research

## Overview

Introduced in **macOS 14.2 (Sonoma)**. First-party API for capturing system audio output. Centers on three operations:

1. Create a `CATapDescription` (what to capture)
2. Create a process tap via `AudioHardwareCreateProcessTap`
3. Route into an aggregate device, read buffers via IO proc callback

Audio is captured **pre-mixer** -- works regardless of system volume (even muted).

## Data Flow

```
System Audio Output
    -> CATapDescription (defines capture target)
    -> AudioHardwareCreateProcessTap (creates tap)
    -> Aggregate Device (virtual input device)
    -> AudioDeviceIOProc callback (~10ms cycles)
    -> Your code
```

## Step-by-Step Setup

### 1. Create CATapDescription

```swift
// All system audio (stereo, exclude self)
let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
tap.uuid = UUID()
tap.isPrivate = true
tap.muteBehavior = .unmuted  // .unmuted | .muted | .mutedWhenTapped

// Mono variant
let tap = CATapDescription(monoGlobalTapButExcludeProcesses: [])

// Specific process
let tap = CATapDescription(stereoMixdownOfProcesses: [processObjectID])

// Specific output device
let tap = CATapDescription(processes: [], andDeviceUID: deviceUID, withStream: 0)
```

Key properties:
```swift
tap.isExclusive = true   // true = exclude listed; false = include only listed
tap.isMixdown = true
tap.isMono = true
tap.deviceUID = nil      // nil = system default output
```

### 2. Create Process Tap

```swift
var tapID = AudioObjectID(kAudioObjectUnknown)
let status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
```

### 3. Read Tap Format

```swift
var addr = AudioObjectPropertyAddress(
    mSelector: kAudioTapPropertyFormat,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
var streamDesc = AudioStreamBasicDescription()
AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &streamDesc)
```

Format: 32-bit float, non-interleaved, device's native sample rate (typically 44.1/48kHz).

### 4. Create Aggregate Device

```swift
let aggDesc: [String: Any] = [
    kAudioAggregateDeviceNameKey: "ScribeTap",
    kAudioAggregateDeviceUIDKey: UUID().uuidString,
    kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: outputDeviceUID]
    ],
    kAudioAggregateDeviceTapListKey: [
        [
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: tapDescription.uuid.uuidString
        ]
    ]
]

var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
```

### 5. IO Proc Callback + Start

```swift
var deviceProcID: AudioDeviceIOProcID?

AudioDeviceCreateIOProcIDWithBlock(
    &deviceProcID, aggregateDeviceID,
    DispatchQueue(label: "audio-capture", qos: .userInitiated)
) { _, inInputData, _, _, _ in
    guard let format = AVAudioFormat(streamDescription: &streamDesc),
          let buffer = AVAudioPCMBuffer(
              pcmFormat: format,
              bufferListNoCopy: inInputData,
              deallocator: nil
          ) else { return }
    // Process buffer here -- real-time thread, keep it fast
}

AudioDeviceStart(aggregateDeviceID, deviceProcID)
```

### 6. Cleanup

```swift
AudioDeviceStop(aggregateDeviceID, deviceProcID)
AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID!)
AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
AudioHardwareDestroyProcessTap(tapID)
```

## Getting Default Output Device UID

```swift
func getDefaultOutputDeviceUID() -> String {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                               &addr, 0, nil, &size, &deviceID)
    
    addr.mSelector = kAudioDevicePropertyDeviceUID
    var uid: CFString = "" as CFString
    size = UInt32(MemoryLayout<CFString>.size)
    AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &uid)
    return uid as String
}
```

## Translating PID to AudioObjectID

```swift
func translatePID(_ pid: pid_t) -> AudioObjectID {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var pidValue = pid
    AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &addr, UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &objectID
    )
    return objectID
}
```

## Permissions

### Info.plist
```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Scribe needs system audio access to transcribe meeting participants.</string>
```
**Not in Xcode's dropdown** -- must type manually.

### Entitlements (sandboxed apps)
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### TCC Permission
- Service: `kTCCServiceAudioCapture` (separate from microphone)
- **No public API** to check/request -- system prompts automatically on first tap creation
- Users manage in: System Settings > Privacy & Security > Audio Recording
- Private SPI exists (`TCCAccessPreflight`/`TCCAccessRequest` via dlopen) but not App Store safe

## Reference Projects

- **[AudioTee](https://github.com/makeusabrew/audiotee)** -- Swift CLI, captures all system audio to stdout as raw PCM. Has `AudioTeeCore` library (reusable). Handles sample rate conversion.
- **[AudioCap](https://github.com/insidegui/AudioCap)** -- SwiftUI sample app by Guilherme Rambo (macOS 14.4+). Per-process capture, TCC handling via private SPI.

## Gotchas

1. **Multi-channel volume bug**: Global tap with >2 channel output device halves volume. Use device-specific tap or compensate manually.
2. **Aggregate device UID collision**: Error 1852797029 if UID already exists. Always use `UUID().uuidString`.
3. **Real-time thread**: IO proc runs on RT audio thread. No allocations, no locks, no I/O. Copy to ring buffer and process elsewhere.
4. **No public TCC API**: Can't check permission status without private SPI.
5. **Info.plist key**: `NSAudioCaptureUsageDescription`, not `NSSystemAudioRecordingUsageDescription`.
6. **Private flag mismatch**: If tap is private, aggregate device must also be private.
7. **macOS 14.2 minimum**: Some initializer names changed in 14.4.
8. **Sample rate**: Tap delivers at device native rate (44.1/48kHz). Must resample to 16kHz for WhisperKit/VAD.

## Key Headers

```
CoreAudio/AudioHardware.h
CoreAudio/AudioHardwareTapping.h
CoreAudio/CATapDescription.h

AudioHardwareCreateProcessTap / DestroyProcessTap
AudioHardwareCreateAggregateDevice / DestroyAggregateDevice
AudioDeviceCreateIOProcIDWithBlock
AudioDeviceStart / AudioDeviceStop
kAudioTapPropertyFormat
```
