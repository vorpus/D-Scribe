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
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let appState = AppState()
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var iconTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "D Scribe")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TranscriptPopover(appState: appState))

        // Local hotkey: Cmd+D when app/popover is focused.
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.modifierFlags.contains(.command) && event.keyCode == 2 {
                guard self.appState.isRecording else { return event }
                self.appState.toggleMute()
                self.updateIcon()
                return nil  // consume the event
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
                }
            }
        }
        print("[AppDelegate] Global hotkey registered")
    }

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

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
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
