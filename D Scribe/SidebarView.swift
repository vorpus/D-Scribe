//
//  SidebarView.swift
//  D Scribe
//

import SwiftUI

struct SidebarView: View {
    @Bindable var appState: AppState

    var body: some View {
        List(selection: $appState.selectedFile) {
            ForEach(appState.fileList, id: \.self) { file in
                SidebarRow(
                    file: file,
                    isActive: file == appState.activeRecordingFile,
                    onRename: { newName in renameFile(file, to: newName) },
                    onDelete: { deleteFile(file) }
                )
                .tag(file)
            }
        }
        .onAppear {
            appState.refreshFileList()
        }
    }

    private func renameFile(_ file: URL, to newName: String) {
        let newURL = file.deletingLastPathComponent()
            .appendingPathComponent(newName)
            .appendingPathExtension("md")
        do {
            try FileManager.default.moveItem(at: file, to: newURL)
            if appState.selectedFile == file {
                appState.selectedFile = newURL
            }
            if appState.activeRecordingFile == file {
                appState.activeRecordingFile = newURL
            }
            appState.refreshFileList()
        } catch {
            print("[SidebarView] Rename failed: \(error.localizedDescription)")
        }
    }

    private func deleteFile(_ file: URL) {
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            if appState.selectedFile == file {
                appState.selectedFile = nil
            }
            appState.refreshFileList()
        } catch {
            print("[SidebarView] Delete failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let file: URL
    let isActive: Bool
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editName = ""
    @FocusState private var isFieldFocused: Bool

    private var displayName: String {
        file.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 6) {
            if isActive {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
            }

            if isEditing {
                TextField("Filename", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        commitRename()
                    }
                    .onExitCommand {
                        isEditing = false
                    }
                    .focused($isFieldFocused)
            } else {
                Text(displayName)
                    .fontWeight(isActive ? .bold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu {
            Button("Rename") {
                editName = displayName
                isEditing = true
                // Focus after state update propagates
                DispatchQueue.main.async {
                    isFieldFocused = true
                }
            }
            .disabled(isActive)

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
            .disabled(isActive)
        }
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != displayName {
            onRename(trimmed)
        }
        isEditing = false
    }
}
