import Foundation
import AppKit
import CoreGraphics

/// Delivers the transcript: pasteboard → synthetic Cmd+V → conditional
/// clipboard restore. Ported from `_paste_text` + the clipboard-session
/// logic in the Python reference.
final class PasteService {
    private let settings = AppSettings.shared

    // Per-session clipboard snapshot: complete pasteboard items (every
    // type's data), so images, files and rich text survive the restore —
    // not just plain strings.
    private var originalItems: [[NSPasteboard.PasteboardType: Data]] = []
    private var lastWrite: String?
    private var wrote = false

    // Throttle for on-the-spot TCC re-registration (at most one
    // CGRequestPostEventAccess per minute while access is broken).
    private var lastPostAccessRequest = Date.distantPast

    /// Snapshot the user's clipboard at dictation-session start — the only
    /// moment it still holds THEIR content.
    func sessionBegin() {
        originalItems = []
        lastWrite = nil
        wrote = false
        guard settings.restoreClipboard else { return }
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // Lazily-promised types can return nil; keep what we can.
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            if !payload.isEmpty { originalItems.append(payload) }
        }
        Log.paste.debug("clipboard snapshot: \(self.originalItems.count) item(s)")
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
        guard settings.restoreClipboard, wrote, let lastWrite,
              !originalItems.isEmpty else { return }
        // Skip when the snapshot is just the same string we pasted.
        if originalItems.count == 1,
           let data = originalItems[0][.string],
           String(data: data, encoding: .utf8) == lastWrite {
            return
        }
        let items = originalItems
        let delay = settings.clipboardRestoreDelayS
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            guard pb.string(forType: .string) == lastWrite else {
                Log.paste.debug("clipboard changed since our paste — not restoring")
                return
            }
            let restored = items.map { payload -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in payload {
                    item.setData(data, forType: type)
                }
                return item
            }
            pb.clearContents()
            if pb.writeObjects(restored) {
                Log.paste.debug("clipboard restored (\(items.count) item(s), incl. non-text types)")
            } else {
                Log.paste.warning("clipboard restore write failed")
            }
        }
    }
}
