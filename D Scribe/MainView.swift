//
//  MainView.swift
//  D Scribe
//

import SwiftUI
import Combine

struct MainView: View {
    @Bindable var appState: AppState
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let file = appState.selectedFile {
                TranscriptContentView(appState: appState, file: file)
                    .navigationTitle(selectedFileName)
            } else {
                ContentUnavailableView(
                    "No Transcript Selected",
                    systemImage: "doc.text",
                    description: Text("Select a transcript from the sidebar or start a new recording.")
                )
                .navigationTitle("D Scribe")
            }
        }
        .toolbar {
            // Center: record/stop + status
            principalToolbarItem

            // Trailing: settings
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .toolbarRole(.editor)
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Principal toolbar item

    @ToolbarContentBuilder
    private var principalToolbarItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                principalContent
                    .glassEffect(.regular.tint(pillTint), in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                principalContent
            }
        }
    }

    /// The pill's outer padding is applied here — inner views must NOT add
    /// their own padding or backgrounds that affect sizing, otherwise the
    /// glass effect capsule won't match the visual boundary.
    private var principalContent: some View {
        HStack(spacing: 0) {
            // Record / Stop — uses overlay so hit area fills the left half
            // without affecting layout.
            recordStopButton

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            // Status — mute toggle when recording
            statusArea
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var recordStopButton: some View {
        PillZoneButton(
            action: {
                if appState.isRecording {
                    appState.stopRecording()
                } else {
                    appState.startRecording()
                }
            },
            disabled: appState.isModelLoading
        ) {
            HStack(spacing: 5) {
                Image(systemName: appState.isRecording ? "stop.fill" : "record.circle")
                    .foregroundColor(appState.isRecording ? .primary : .red)
                    .frame(width: 16, height: 16)
                Text(appState.isRecording ? "Stop" : "Record")
                    .font(.subheadline)
            }
        }
        .help(appState.isRecording ? "Stop Recording" : "Start Recording")
    }

    @ViewBuilder
    private var statusArea: some View {
        if appState.isRecording {
            PillZoneButton(action: { appState.toggleMute() }) {
                HStack(spacing: 6) {
                    Text(appState.isMuted ? "Muted" : "Recording")
                    Text(sessionDuration)
                        .monospacedDigit()
                }
            }
            .help(appState.isMuted ? "Click to unmute (⌘D)" : "Click to mute (⌘D)")
        } else if appState.isModelLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(appState.statusText)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Idle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var selectedFileName: String {
        guard let file = appState.selectedFile else { return "D Scribe" }
        return file.deletingPathExtension().lastPathComponent
    }

    private var pillTint: Color {
        if !appState.isRecording { return .clear }
        return appState.isMuted ? .yellow.opacity(0.5) : .red.opacity(0.5)
    }

    private var sessionDuration: String {
        guard let start = appState.sessionStart else { return "" }
        let elapsed = Int(now.timeIntervalSince(start))
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
}

// MARK: - Clickable zone inside a toolbar pill
// Uses overlay for hover highlight so it doesn't affect the parent's layout/sizing.

struct PillZoneButton<Label: View>: View {
    let action: () -> Void
    var disabled: Bool = false
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        label()
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(isHovered ? 0.15 : 0))
            )
            .opacity(isPressed ? 0.6 : 1.0)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                guard !disabled else { return }
                action()
            }
            .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 && !disabled }, perform: {})
            .allowsHitTesting(!disabled)
    }
}
