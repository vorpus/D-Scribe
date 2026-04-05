//
//  SettingsView.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState

    @State private var pollingTask: Task<Void, Never>?
    @State private var outputDirDraft = ""

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionRow(
                    name: "Microphone",
                    detail: "Required for transcribing your voice",
                    granted: appState.hasMicrophone,
                    action: { appState.requestMicrophone() }
                )

                PermissionRow(
                    name: "Audio Capture",
                    detail: "Required for capturing system/meeting audio",
                    granted: appState.hasAudioCapture,
                    action: { appState.requestAudioCapture() }
                )

                PermissionRow(
                    name: "Accessibility",
                    detail: "Required for global hotkeys",
                    granted: appState.hasAccessibility,
                    action: { appState.promptAccessibility() }
                )
            }

            Section("Hotkey") {
                HotkeyRecorderRow(appState: appState)
            }

            Section("Transcription") {
                Picker("Language", selection: $appState.language) {
                    Text("English").tag("en")
                    Text("Chinese").tag("zh")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                }

                LabeledContent("Output") {
                    HStack {
                        TextField("~/transcripts", text: $outputDirDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitOutputDir() }

                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            panel.directoryURL = URL(fileURLWithPath: (outputDirDraft as NSString).expandingTildeInPath)
                            if panel.runModal() == .OK, let url = panel.url {
                                outputDirDraft = url.path
                                commitOutputDir()
                            }
                        }

                        Button {
                            let path = (appState.outputDirectory as NSString).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Open in Finder")
                    }
                }

                HStack {
                    Slider(value: $appState.vadThreshold, in: 0.1...0.95, step: 0.05)
                    Text(String(format: "%.2f", appState.vadThreshold))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                .formLabel("VAD threshold")

                HStack {
                    Slider(value: Binding(
                        get: { Float(appState.silenceMs) },
                        set: { appState.silenceMs = Int($0) }
                    ), in: 200...2000, step: 100)
                    Text("\(appState.silenceMs) ms")
                        .monospacedDigit()
                        .frame(width: 60)
                }
                .formLabel("Silence duration")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .onAppear {
            outputDirDraft = appState.outputDirectory
            appState.checkAllPermissions()
            pollingTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    appState.checkAllPermissions()
                }
            }
        }
        .onDisappear {
            commitOutputDir()
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    private func commitOutputDir() {
        let trimmed = outputDirDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appState.outputDirectory = trimmed

        // Ensure the directory exists.
        let path = (trimmed as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
        appState.refreshFileList()
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let name: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") { action() }
                    .controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                    if !granted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderRow: View {
    @Bindable var appState: AppState
    @State private var isRecording = false

    var body: some View {
        LabeledContent("Toggle Mute") {
            Button {
                isRecording = true
            } label: {
                if isRecording {
                    Text("Press a key…")
                        .foregroundStyle(.secondary)
                } else {
                    Text(appState.hotkeyDisplayString)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 80)
            .background {
                if isRecording {
                    HotkeyCapture { keyCode, modifiers in
                        appState.hotkeyKeyCode = keyCode
                        appState.hotkeyModifiers = modifiers.rawValue
                        isRecording = false
                        // Re-register hotkey monitors with new key.
                        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                    } onCancel: {
                        isRecording = false
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("hotkeyDidChange")
}

/// Invisible NSView that captures the next key press for hotkey recording.
struct HotkeyCapture: NSViewRepresentable {
    let onCapture: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyCaptureView {
        let view = HotkeyCaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }
}

class HotkeyCaptureView: NSView {
    var onCapture: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape cancels
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        onCapture?(event.keyCode, mods)
    }

    override func resignFirstResponder() -> Bool {
        onCancel?()
        return super.resignFirstResponder()
    }
}

// Helper for custom form labels on HStack rows
extension View {
    func formLabel(_ label: String) -> some View {
        LabeledContent(label) { self }
    }
}
