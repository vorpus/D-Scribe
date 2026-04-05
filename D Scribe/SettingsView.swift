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
                    detail: "Required for global Cmd+D mute hotkey",
                    granted: appState.hasAccessibility,
                    action: { appState.promptAccessibility() }
                )
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

// Helper for custom form labels on HStack rows
extension View {
    func formLabel(_ label: String) -> some View {
        LabeledContent(label) { self }
    }
}
