//
//  TranscriptPopover.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import SwiftUI
import Combine

struct TranscriptPopover: View {
    @Bindable var appState: AppState
    @State private var showSettings = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("D Scribe")
                    .font(.headline)
                Spacer()
                if appState.isRecording {
                    statusDot
                    Text(sessionDuration)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("— \(appState.lineCount) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Transcript lines or status
            if appState.transcriptLines.isEmpty {
                Spacer()
                Text(appState.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(appState.transcriptLines.suffix(10)) { line in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("[\(line.timeString)]")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    Text(line.label + ":")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(line.label == "YOU" ? .red : .green)
                                    Text(line.text)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: appState.lineCount) { _, _ in
                        if let last = appState.transcriptLines.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Controls
            HStack(spacing: 12) {
                Button(appState.isRecording ? "Stop" : "Start") {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(appState.isModelLoading)

                if appState.isRecording {
                    Button {
                        appState.toggleMute()
                    } label: {
                        Image(systemName: appState.isMuted ? "mic.slash.fill" : "mic.fill")
                        Text(appState.isMuted ? "Unmute" : "Mute")
                    }

                    Text("Cmd+D")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !appState.hasAccessibility {
                    Button {
                        appState.promptAccessibility()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Enable global hotkey")
                            .font(.caption2)
                    }
                    .help("Grant Accessibility permission for Cmd+D to work globally")
                }

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .disabled(appState.isRecording)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 400, height: 300)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
        .onReceive(timer) { now = $0 }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        if appState.isMuted { return .yellow }
        if appState.isSpeechDetected { return .orange }
        return .red
    }

    private var sessionDuration: String {
        guard let start = appState.sessionStart else { return "" }
        let elapsed = Int(now.timeIntervalSince(start))
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
}
