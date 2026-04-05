//
//  RecordingBar.swift
//  D Scribe
//

import Combine
import SwiftUI

struct RecordingBar: View {
    @Bindable var appState: AppState
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if appState.isRecording {
                recordingContent
            } else if appState.isModelLoading {
                loadingContent
            } else {
                idleContent
            }
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Idle

    private var idleContent: some View {
        barChrome(tint: .clear) {
            Button { appState.startRecording() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    Text("Record")
                        .font(.system(size: 14))
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    private var loadingContent: some View {
        barChrome(tint: .clear) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.statusText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recording

    private var recordingContent: some View {
        barChrome(tint: appState.isMuted ? .yellow.opacity(0.5) : .red.opacity(0.5)) {
            HStack(spacing: 0) {
                // Left zone: stop
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .frame(width: 20, height: 20)
                }
                .contentShape(Rectangle())
                .onTapGesture { appState.stopRecording() }
                .help("Stop Recording")

                Divider().frame(height: 18).padding(.horizontal, 10)

                // Right zone: mute toggle (everything right of divider)
                HStack(spacing: 10) {
                    Image(systemName: appState.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(appState.isMuted ? .yellow : .primary)

                    Text(appState.isMuted ? "Muted" : "Recording")
                        .font(.system(size: 14))

                    Text(sessionDuration)
                        .font(.system(size: 14))
                        .monospacedDigit()

                    Spacer()

                    if let monitor = appState.audioLevelMonitor {
                        WaveformView(levels: monitor.micLevels, color: .red)
                        WaveformView(levels: monitor.systemLevels, color: .green)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { appState.toggleMute() }
                .help(appState.isMuted ? "Click to unmute" : "Click to mute")
            }
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private func barChrome<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26.0, *) {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(tint), in: .capsule)
        } else {
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Helpers

    private var sessionDuration: String {
        guard let start = appState.sessionStart else { return "" }
        let elapsed = Int(now.timeIntervalSince(start))
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
}
