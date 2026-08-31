# MacTyper

Native macOS hold-to-talk dictation, powered by Google's **Gemini Live**
streaming transcription. Hold a trigger, speak, release — your words are
typed into whatever text field has focus. A small glass HUD near the caret
previews the transcript live while you talk.

A native Swift rewrite of [typer](https://github.com/HockeyTrafalgar/typer)
(Python), built for easy distribution: one small `.app`, no Python, no
local models.

## Triggers

| Input | Behavior |
|---|---|
| Hold **Right ⌘** | push-to-talk: speak, release to paste |
| Hold **F18** | same push-to-talk |
| Tap **F19** | toggle dictation on/off; tapping F19 *while holding F18* latches the session (release F18 without stopping) |
| **Long-press left mouse button** (~700 ms, without moving) on a text field | starts dictation; release stops and pastes |
| **Esc** while recording | cancel — nothing is pasted |

The mouse long-press only fires when the click lands on (or focus is in) an
editable text field, checked via the Accessibility API — buttons, links and
drags are left alone.

## Setup

1. Download the DMG from [Releases](../../releases), drag **MacTyper** to
   Applications, and open it.
2. Grant the three permissions the onboarding window asks for
   (System Settings → Privacy & Security):
   - **Microphone** — recording your voice
   - **Accessibility** — caret location + the synthetic ⌘V paste
   - **Input Monitoring** — the key/mouse triggers
   If triggers don't react after granting Input Monitoring, quit and reopen
   MacTyper once.
3. Open **Settings…** from the menu-bar mic icon and paste your Gemini API
   key (get one at [aistudio.google.com/apikey](https://aistudio.google.com/apikey)).
   The key is stored in your Keychain.

## Notes

- Transcription runs on Google's servers (`gemini-3.5-transcribe-live` by
  default) — an internet connection is required. Nothing is stored locally.
- The transcript is delivered by copying it to the clipboard and sending
  ⌘V; your previous clipboard contents are restored ~1 s later (can be
  disabled in Settings).
- Language hints and a custom vocabulary (names, jargon) can be set in
  Settings to improve recognition.

## Building from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```
make build     # build Release into build/
make test      # run unit tests
make run       # build and launch
make release   # signed+notarized DMG (needs a Developer ID; see scripts/release.sh)
```

## License

MIT
