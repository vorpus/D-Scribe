# D Scribe

Fully local meeting transcription app for macOS. Runs in the menu bar, captures your mic and system audio simultaneously, and produces a labeled, timestamped markdown transcript. No data leaves your machine.

- **YOU** channel: your microphone input
- **MEETING** channel: system audio (Zoom, Meet, Teams, etc.)
- Speech detection via Silero VAD (CoreML)
- Transcription via WhisperKit distil-large-v3 (CoreML/Metal)
- Markdown transcripts saved to `~/transcripts/` in real time
- Global mute hotkey (Cmd+D)

Requires macOS 14.2+ and Apple Silicon.

## Building

Requirements: Xcode 16+

1. Clone the repo and open the project:
   ```
   git clone <repo-url>
   cd "D Scribe"
   open "D Scribe.xcodeproj"
   ```

2. Xcode will automatically resolve the Swift package dependencies (WhisperKit, FluidAudio). Wait for package resolution to complete in the status bar.

3. Build and run (Cmd+R). The app appears as a mic icon in the menu bar — no dock icon.

4. On first launch, the app downloads the Whisper model (~800MB) and Silero VAD model from HuggingFace. Progress is shown in the popover. Subsequent launches use the cached models.

## Permissions

The app will prompt for these on first use:

- **Microphone** — to capture your voice
- **Screen & System Audio Recording** — to capture meeting audio from other apps
- **Accessibility** (optional) — for the global Cmd+D mute hotkey to work outside the app. Click "Enable global hotkey" in the popover to trigger the prompt.

## Usage

1. Click the menu bar icon to open the popover
2. Click **Start** to begin recording
3. Speak into your mic — `YOU:` lines appear
4. Play or join a meeting — `MEETING:` lines appear
5. **Cmd+D** to mute/unmute your mic (meeting audio keeps recording)
6. Click **Stop** to end — transcript is saved to `~/transcripts/`

Settings (gear icon, available when stopped): language, output directory, VAD sensitivity, silence duration.
