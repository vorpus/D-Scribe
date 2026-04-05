# Liquid Glass UI — Implementation Plan

## Proposed Layout

```
+==============================================================================+
|                           TOOLBAR (NSToolbar)                                |
|  +------------------+  +----------------------------------------------+  +-+|
|  | meeting-2026-... |  |  [Stop]   (o) Recording  3m 42s  12 lines   |  |⚙||
|  +------------------+  +----------------------------------------------+  +-+|
|   ^ file name            ^ record/stop + status (center)         settings ^  |
+==============================================================================+
|        |                                                                     |
|  SIDE  |  MAIN CONTENT                                                       |
|  BAR   |                                                                     |
|        |  [10:30:01] YOU: So the idea is we migrate the auth service         |
| ----   |  [10:30:08] MEETING: Right, and the timeline is end of Q2           |
| Files  |  [10:30:15] YOU: What about the token storage changes?              |
| from   |  [10:30:22] MEETING: Legal already approved the new format          |
| output |  [10:30:30] YOU: Got it, I'll update the middleware this week        |
| dir    |  [10:30:45] MEETING: Sounds good, let's sync again Friday           |
|        |  [10:30:52] YOU: One more thing — do we need to notify...            |
| ----   |  [10:31:01] MEETING: Yes, send a heads-up to the platform team      |
|        |                                                                     |
|>*rec.* |                                    <- auto-scrolls to bottom        |
| file1  |                                       unless user scrolled up       |
| file2  |                                                                     |
| file3  |                                                                     |
+--------+--------------------------------------------------------------------+
```

**Toolbar detail (Xcode-style):**

```
+------------------------------------------------------------------------------+
|  Top-Left            |         Top-Center                        | Top-Right |
|  (file name)         |  (recording status + controls)            | (settings)|
|                      |                                           |           |
|  meeting-2026-04-... |  [Stop]  (o) Recording  3m 42s  12 ln    |    [⚙]   |
+------------------------------------------------------------------------------+
```

- Top-left: name of the currently selected transcript file (like Xcode's project name)
- Top-center: record/stop toggle button + status area.
  When idle: [Record] button. When recording: [Stop] button + status dot + "Recording"/"Muted" + duration + line count.
  Each recording is a distinct conversation — no pause/resume.
- Top-right: settings gear (opens Cmd+, settings window)

**Sidebar detail:**

```
+-------------------+
| > *recording...*  |  <- active file, distinct style (bold, dot, pulse?)
|   2026-04-04_10.. |
|   2026-04-03_14.. |
|   2026-04-02_09.. |
|   ...             |
+-------------------+
```

- Lists .md files from the configured output directory
- Active recording file shown at top with visual indicator (TBD)
- Clicking a file loads its content in the main area
- Selected file highlighted

**Menu bar item (retained):**

```
Click menu bar icon ->
+---------------------+
| Open D Scribe       |
| ---                 |
| Mute / Unmute       |
| ---                 |
| Quit                |
+---------------------+
```

- Icon still shows recording state (gray/red/yellow)
- No longer opens a popover — opens a regular NSMenu
- "Open D Scribe" brings the main window to front


## Architecture Changes

### Current -> New

| Aspect | Current (menu bar popover) | New (windowed app) |
|--------|---------------------------|-------------------|
| Window | None (NSPopover) | NSWindow with NavigationSplitView |
| Dock | Hidden (.accessory) | Visible (.regular) |
| Menu bar | Click -> popover | Click -> NSMenu |
| Toolbar | None | NSToolbar with Liquid Glass |
| Transcript view | Last 10 lines in popover | Full file content, scrollable |
| File browser | None | Sidebar listing output dir |
| Activation | macOS 15+ | macOS 26 (Liquid Glass) |


## Implementation Steps

### Phase 1: Window + App Lifecycle

1. **Change activation policy** from `.accessory` to `.regular`
   - File: `D_ScribeApp.swift`
   - App gets a dock icon and can be Cmd+Tab'd to

2. **Create main window** using SwiftUI `Window` scene
   - Replace `Settings { EmptyView() }` with a `WindowGroup` + `Settings` scene
   - Use `.windowStyle(.automatic)` — Liquid Glass is the default on macOS 26
   - Set a minimum size (~800x500)
   - Window opens automatically on launch

3. **Replace NSPopover with NSMenu** on the status item
   - Keep NSStatusItem with mic icon + color states
   - `statusItem.menu = NSMenu(...)` with "Open D Scribe", "Mute/Unmute", "Quit"
   - "Open D Scribe" calls `NSApplication.shared.activate()` + window `makeKeyAndOrderFront`
   - Remove popover code entirely

### Phase 2: Main Content View

4. **Create `MainView`** — top-level SwiftUI view
   - `NavigationSplitView` with sidebar + detail
   - Toolbar items via `.toolbar { }` modifier
   - Pass `appState` as environment or bindable

5. **Create `TranscriptContentView`** — the detail/main area
   - Reads and displays full file content (not just last 50 lines from memory)
   - For non-active files: read from disk, parse and render with colored labels (same styling as live view)
   - For active recording file: combine disk content + live `transcriptLines`
   - User can browse other files while recording continues in the background
   - Active file stays visually distinct in sidebar so user can click back
   - ScrollView with auto-scroll logic:
     - Track scroll position via `ScrollView` + `GeometryReader` or `onScrollGeometryChange`
     - `isNearBottom` flag: if user is within ~50pt of bottom, auto-scroll on new lines
     - If user scrolls up, set `isNearBottom = false`, stop auto-scrolling
     - If user scrolls back to bottom, re-enable

6. **Adapt `AppState`** for full-file reading
   - Add `selectedFile: URL?` property
   - Add `fileList: [URL]` property (populated from output dir)
   - Keep `transcriptLines` for live streaming, but also need to load historical lines
   - Method to scan output directory and list .md files sorted by date (newest first)
   - FileManager-based directory watcher or periodic refresh for sidebar

### Phase 3: Sidebar

7. **Create `SidebarView`** — file list
   - `List(selection:)` bound to `appState.selectedFile`
   - Each row: file name (truncated), maybe date subtitle
   - Active recording file: distinct affordance (bold, colored dot, etc — details TBD)
   - Active file pinned to top of list
   - On selection change, load file content into detail view

8. **Directory watching**
   - Use `DispatchSource.makeFileSystemObjectSource` or poll every few seconds
   - Re-scan output directory when files change
   - Auto-select new file when recording starts

### Phase 4: Toolbar

9. **Toolbar items** (Xcode-style layout)
   - `.toolbar` modifier on NavigationSplitView
   - **Leading (`.navigation`)**: file name label
   - **Center (`.principal` / custom `ToolbarItem(placement:)`)**: 
     - Record/Stop toggle button: [Record] when idle, [Stop] when recording
     - When recording: status dot + "Recording"/"Muted" + duration timer + line count
   - **Trailing**: settings gear button (triggers Cmd+, settings window)
   - Use `.toolbarStyle(.unified)` for Liquid Glass integration

10. **Wire up controls**
    - Record button: starts a new recording, auto-selects the new file in sidebar
    - Stop button: stops recording, file stays selected for review
    - No pause/resume — each recording is a distinct conversation
    - Settings gear: opens the standard Settings window (Cmd+,)

### Phase 5: Polish + Cleanup

11. **Remove old popover code**
    - Delete `TranscriptPopover.swift` (functionality moved to new views)
    - Clean up AppDelegate — remove popover setup, simplify to menu-only

12. **Liquid Glass specifics**
    - `.glassEffect()` modifier on sidebar and toolbar if needed (may be automatic)
    - Ensure sidebar uses standard `List` styling for automatic Liquid Glass
    - Test translucency and vibrancy

13. **Settings integration**
    - Use `Settings` scene (standard macOS Cmd+, preferences window)
    - Toolbar gear button triggers `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
    - Also accessible via app menu > Settings

14. **Keyboard shortcuts**
    - Cmd+D mute still works (global + local)
    - Cmd+N for new recording
    - Cmd+, for settings


## Key Decisions / Open Questions

- **Active file affordance**: exact visual treatment TBD (pulsing dot? bold + red accent? recording icon?)
- **File content loading**: for large transcripts, may want lazy loading or streaming reads
- **Search**: not in scope for initial implementation, but the layout supports adding it later
- **Multiple windows**: single window for now; can revisit
- **Minimum macOS version**: bumps to macOS 26 (Tahoe) for Liquid Glass


## Files to Create / Modify

| File | Action | Purpose |
|------|--------|---------|
| `D_ScribeApp.swift` | Modify | Window scene, activation policy, menu bar menu |
| `AppState.swift` | Modify | Add selectedFile, fileList, directory scanning |
| `MainView.swift` | Create | NavigationSplitView + toolbar |
| `SidebarView.swift` | Create | File list sidebar |
| `TranscriptContentView.swift` | Create | Full transcript display with auto-scroll |
| `TranscriptPopover.swift` | Delete | Replaced by new views |
| `SettingsView.swift` | Modify | Minor — launch context changes (sheet vs popover) |
