//
//  MainView.swift
//  D Scribe
//

import SwiftUI

struct MainView: View {
    @Bindable var appState: AppState

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
                .safeAreaInset(edge: .bottom) {
                    RecordingBar(appState: appState)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
                .navigationTitle("D Scribe")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .toolbarRole(.editor)
    }

    // MARK: - Helpers

    private var selectedFileName: String {
        guard let file = appState.selectedFile else { return "D Scribe" }
        return file.deletingPathExtension().lastPathComponent
    }
}
