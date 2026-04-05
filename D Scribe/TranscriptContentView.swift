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

    private var isActiveFile: Bool {
        appState.activeRecordingFile == file
    }

    private var displayLines: [TranscriptLine] {
        if isActiveFile {
            return appState.transcriptLines
        }
        // After stopping, transcriptLines may still have the session's lines
        // while diskLines hasn't loaded yet — show whichever is non-empty.
        if diskLines.isEmpty && !appState.transcriptLines.isEmpty && appState.activeRecordingFile == nil {
            return appState.transcriptLines
        }
        return diskLines
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(displayLines) { line in
                        TranscriptLineRow(line: line, fontSize: appState.transcriptFontSize)
                            .id(line.id)
                    }
                }
                .padding()

                // Invisible anchor at the very bottom, flush with scroll edge
                Color.clear
                    .frame(height: 0)
                    .id("bottom")
            }
            .safeAreaInset(edge: .bottom) {
                RecordingBar(appState: appState)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
                // Recording stopped — reload from disk after writer finalizes.
                if !isActiveFile {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        loadFromDisk(for: file)
                    }
                }
            }
            .onChange(of: file) { _, newFile in
                loadFromDisk(for: newFile)
                // Active file: jump to bottom. Historical: stay at top.
                if appState.activeRecordingFile == newFile {
                    isAtBottom = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    isAtBottom = false
                }
            }
            .onAppear {
                loadFromDisk(for: file)
                if isActiveFile {
                    isAtBottom = true
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    isAtBottom = false
                }
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
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let maxOffset = geometry.contentSize.height - geometry.containerSize.height
                    if maxOffset <= 0 { return true }
                    return geometry.contentOffset.y >= maxOffset - 30
                } action: { _, atBottom in
                    isAtBottom = atBottom
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
        HStack(alignment: .top, spacing: 6) {
            Text("[\(line.timeString)]")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(line.label + ":")
                .font(.system(size: fontSize))
                .fontWeight(.semibold)
                .foregroundStyle(line.label == "YOU" ? .red : .green)

            Text(line.text)
                .font(.system(size: fontSize))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
