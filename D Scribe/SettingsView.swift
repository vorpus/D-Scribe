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
                Picker("Language", selection: Binding(
                    get: { appState.language },
                    set: { appState.language = $0 }
                )) {
                    Text("English").tag("en")
                    Text("Chinese").tag("zh")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                }

                TextField("Output", text: Binding(
                    get: { appState.outputDirectory },
                    set: { appState.outputDirectory = $0 }
                ))

                HStack {
                    Slider(value: Binding(
                        get: { appState.vadThreshold },
                        set: { appState.vadThreshold = $0 }
                    ), in: 0.1...0.95, step: 0.05)
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
            appState.checkAllPermissions()
            pollingTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    appState.checkAllPermissions()
                }
            }
        }
        .onDisappear {
            pollingTask?.cancel()
            pollingTask = nil
        }
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
