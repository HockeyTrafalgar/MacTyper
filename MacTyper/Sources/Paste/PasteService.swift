import Foundation
import AppKit
import CoreGraphics

/// Delivers the transcript: pasteboard → synthetic Cmd+V → conditional
/// clipboard restore. Ported from `_paste_text` + the clipboard-session
/// logic in the Python reference.
final class PasteService {
    private let settings = AppSettings.shared

    // Per-session clipboard snapshot (string contents only, like the
    // Python/pyperclip original; rich content is not restored).
    private var original: String?
    private var lastWrite: String?
    private var wrote = false

    // Throttle for on-the-spot TCC re-registration (at most one
    // CGRequestPostEventAccess per minute while access is broken).
    private var lastPostAccessRequest = Date.distantPast

    /// Snapshot the user's clipboard at dictation-session start — the only
    /// moment it still holds THEIR content.
    func sessionBegin() {
        original = nil
        lastWrite = nil
        wrote = false
        guard settings.restoreClipboard else { return }
        original = NSPasteboard.general.string(forType: .string)
    }

    /// Paste `text` into the focused app. Returns false when macOS blocked
    /// the synthetic keystroke (text is left on the clipboard for a manual
    /// Cmd+V and the session restore is suppressed).
    @discardableResult
    func paste(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        Log.paste.debug("pasting \(text.count) chars")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastWrite = text
        wrote = true
        Thread.sleep(forTimeInterval: 0.03)

        // Stale-TCC guard: re-register post-event access on the spot
        // (refreshes a stale grant, may pop the system prompt; throttled).
        if !CGPreflightPostEventAccess() {
            if Date().timeIntervalSince(lastPostAccessRequest) >= 60 {
                lastPostAccessRequest = Date()
                Log.paste.warning("paste blocked: no post-event access — re-registering with TCC")
                CGRequestPostEventAccess()
            }
            if !CGPreflightPostEventAccess() {
                Log.paste.warning("paste BLOCKED: no post-event access (Accessibility) — text left on clipboard for manual Cmd+V")
                wrote = false
                return false
            }
            Log.paste.info("post-event access recovered — pasting")
        }

        releaseStuckModifiers()
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        return true
    }

    /// Post key-ups for both Command keys so a still-held trigger modifier
    /// can't turn our synthetic V into a different shortcut.
    private func releaseStuckModifiers() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for keyCode in [CGKeyCode(54), CGKeyCode(55)] {
            let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Restore the pre-dictation clipboard after a delay, only if OUR pasted
    /// text is still on the pasteboard — never clobbers something the user
    /// copied after dictating.
    func sessionRestore() {
        guard settings.restoreClipboard, wrote,
              let original, let lastWrite, original != lastWrite else { return }
        let delay = settings.clipboardRestoreDelayS
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            if pb.string(forType: .string) == lastWrite {
                pb.clearContents()
                pb.setString(original, forType: .string)
                Log.paste.debug("clipboard restored to pre-dictation contents")
            } else {
                Log.paste.debug("clipboard changed since our paste — not restoring")
            }
        }
    }
}
