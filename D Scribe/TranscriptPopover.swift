//
//  TranscriptPopover.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import SwiftUI

struct TranscriptPopover: View {
    @Bindable var appState: AppState

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

            // Transcript lines
            if appState.transcriptLines.isEmpty {
                Spacer()
                Text(appState.isModelLoading ? "Loading model..." : appState.statusText)
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
            HStack {
                Button(appState.isRecording ? "Stop" : "Start") {
                    if appState.isRecording {
                        appState.stopRecording()
                    } else {
                        appState.startRecording()
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(appState.isModelLoading)

                Spacer()

                if appState.isRecording, !appState.outputPath.isEmpty {
                    Text(appState.outputPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 400, height: 300)
    }

    private var statusDot: some View {
        Circle()
            .fill(appState.isSpeechDetected ? Color.orange : Color.red)
            .frame(width: 8, height: 8)
    }

    private var sessionDuration: String {
        guard let start = appState.sessionStart else { return "" }
        let elapsed = Int(Date().timeIntervalSince(start))
        return "\(elapsed / 60)m \(elapsed % 60)s"
    }
}
