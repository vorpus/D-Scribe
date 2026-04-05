//
//  D_ScribeApp.swift
//  D Scribe
//
//  Created by li on 4/4/26.
//

import SwiftUI

@main
struct D_ScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView(appState: appDelegate.appState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 650)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    let s = appDelegate.appState
                    s.transcriptFontSize = min(s.transcriptFontSize + 1, AppState.maxFontSize)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    let s = appDelegate.appState
                    s.transcriptFontSize = max(s.transcriptFontSize - 1, AppState.minFontSize)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    appDelegate.appState.transcriptFontSize = AppState.defaultFontSize
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    let appState = AppState()
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var iconTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "D Scribe")
        }

        buildMenu()

        // Local hotkey: Cmd+D when app is focused.
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command) && event.keyCode == 2 {
                guard self.appState.isRecording else { return event }
                self.appState.toggleMute()
                self.updateIcon()
                self.buildMenu()
                return nil
            }
            return event
        }

        // Try to register global hotkey (needs Accessibility).
        registerGlobalHotkeyIfNeeded()

        // Poll icon state and re-check accessibility periodically.
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
            self?.registerGlobalHotkeyIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalHotkeyMonitor { NSEvent.removeMonitor(m) }
        if let m = localHotkeyMonitor { NSEvent.removeMonitor(m) }
        iconTimer?.invalidate()
        if appState.isRecording {
            appState.stopRecording()
        }
    }

    private func registerGlobalHotkeyIfNeeded() {
        appState.checkAccessibility()
        guard appState.hasAccessibility, globalHotkeyMonitor == nil else { return }

        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.modifierFlags.contains(.command) && event.keyCode == 2 {
                DispatchQueue.main.async {
                    guard self.appState.isRecording else { return }
                    self.appState.toggleMute()
                    self.updateIcon()
                    self.buildMenu()
                }
            }
        }
        print("[AppDelegate] Global hotkey registered")
    }

    // MARK: - Menu Bar Menu

    private func buildMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open D Scribe", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        if appState.isRecording {
            let muteTitle = appState.isMuted ? "Unmute" : "Mute"
            let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleMuteFromMenu), keyEquivalent: "")
            muteItem.target = self
            menu.addItem(muteItem)
            menu.addItem(NSMenuItem.separator())
        }

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title != "" || $0.contentView is NSHostingView<MainView> }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func toggleMuteFromMenu() {
        appState.toggleMute()
        updateIcon()
        buildMenu()
    }

    // MARK: - Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let color: NSColor

        if !appState.isRecording {
            symbolName = "mic.fill"
            color = .secondaryLabelColor
        } else if appState.isMuted {
            symbolName = "mic.slash.fill"
            color = .systemYellow
        } else {
            symbolName = "mic.fill"
            color = .systemRed
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "D Scribe")?
            .withSymbolConfiguration(config) {
            let coloredImage = image.tinted(with: color)
            button.image = coloredImage
        }
    }
}

// MARK: - NSImage tinting helper

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
