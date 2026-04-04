//
//  SettingsView.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            // Language
            HStack {
                Text("Language")
                    .frame(width: 100, alignment: .leading)
                Picker("", selection: Binding(
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
                .labelsHidden()
                .frame(width: 120)
            }

            // Output directory
            HStack {
                Text("Output")
                    .frame(width: 100, alignment: .leading)
                TextField("~/transcripts", text: Binding(
                    get: { appState.outputDirectory },
                    set: { appState.outputDirectory = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            // VAD threshold
            HStack {
                Text("VAD threshold")
                    .frame(width: 100, alignment: .leading)
                Slider(value: Binding(
                    get: { appState.vadThreshold },
                    set: { appState.vadThreshold = $0 }
                ), in: 0.1...0.95, step: 0.05)
                Text(String(format: "%.2f", appState.vadThreshold))
                    .monospacedDigit()
                    .frame(width: 40)
            }

            // Silence duration
            HStack {
                Text("Silence (ms)")
                    .frame(width: 100, alignment: .leading)
                Slider(value: Binding(
                    get: { Float(appState.silenceMs) },
                    set: { appState.silenceMs = Int($0) }
                ), in: 200...2000, step: 100)
                Text("\(appState.silenceMs)")
                    .monospacedDigit()
                    .frame(width: 40)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 360, height: 280)
    }
}
