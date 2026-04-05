//
//  TranscriptContentView.swift
//  D Scribe
//

import SwiftUI

struct TranscriptContentView: View {
    @Bindable var appState: AppState
    let file: URL

    @State private var diskLines: [TranscriptLine] = []
    @State private var isAtBottom = true
    @State private var barHeight: CGFloat = 60

    private var isActiveFile: Bool {
        appState.activeRecordingFile == file
    }

    private var displayLines: [TranscriptLine] {
        if isActiveFile {
            return appState.transcriptLines
        }
        if diskLines.isEmpty && !appState.transcriptLines.isEmpty && appState.activeRecordingFile == nil {
            return appState.transcriptLines
        }
        return diskLines
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(displayLines) { line in
                            TranscriptLineRow(line: line, fontSize: appState.transcriptFontSize)
                                .id(line.id)
                        }
                    }
                    .padding()

                    // Bottom spacer so content isn't hidden behind the bar
                    Color.clear
                        .frame(height: barHeight)
                        .id("bottom")
                }
                .modifier(ScrollBottomDetector(isAtBottom: $isAtBottom))
                .onChange(of: appState.lineCount) { _, _ in
                    if isAtBottom, isActiveFile {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appState.activeRecordingFile) { _, _ in
                    if !isActiveFile {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            loadFromDisk(for: file)
                        }
                    }
                }
                .onChange(of: file) { _, newFile in
                    loadFromDisk(for: newFile)
                    if appState.activeRecordingFile == newFile {
                        DispatchQueue.main.async {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    loadFromDisk(for: file)
                    if isActiveFile {
                        DispatchQueue.main.async {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Floating bar overlaid at the bottom
            RecordingBar(appState: appState)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { newHeight in
                    if newHeight > 0 { barHeight = newHeight }
                }
        }
    }

    private func loadFromDisk(for url: URL) {
        if appState.activeRecordingFile != url {
            diskLines = AppState.parseTranscriptFile(url)
        } else {
            diskLines = []
        }
    }
}

// MARK: - Scroll bottom detection

struct ScrollBottomDetector: ViewModifier {
    @Binding var isAtBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { geo in
                    let maxOffset = geo.contentSize.height - geo.containerSize.height
                    if maxOffset <= 0 { return true }
                    return geo.contentOffset.y >= maxOffset - 80
                } action: { _, newValue in
                    isAtBottom = newValue
                }
        } else {
            content
        }
    }
}

// MARK: - Transcript Line Row

struct TranscriptLineRow: View {
    let line: TranscriptLine
    var fontSize: CGFloat = 13

    var body: some View {
        (
            Text("[\(line.timeString)] ")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)
            + Text(line.label + ": ")
                .font(.system(size: fontSize).bold())
                .foregroundStyle(line.label == "YOU" ? .red : .green)
            + Text(line.text)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
        )
        .textSelection(.enabled)
    }
}
