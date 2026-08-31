import Foundation
import AppKit

/// Central dictation state machine. All triggers (hotkeys, mouse, menu)
/// call into this on the main actor, which gives the same ordering
/// guarantee the Python version got from running handlers inline on the
/// listener thread: a press's start always lands before its release's stop.
///
/// Semantics (ported from `on_press`/`on_release`):
///  - Right-⌘ / F18 / mouse long-press: hold-to-talk (release → stop).
///  - F19: toggle; F19 while F18 held → latch (F18 release no longer
///    stops; only another F19 tap does).
///  - Esc while recording: cancel — nothing is pasted.
@MainActor
final class DictationController {
    enum Trigger { case rightCmd, f18, f19, mouse, menu }

    private enum State { case idle, recording, finishing }

    private var state: State = .idle
    private var latched = false
    private var cancelled = false
    private var session: GeminiLiveSession?
    private var stopRequestedAt: Date?

    let audio: AudioCapture
    let paste: PasteService
    let overlay: OverlayController
    var onStateChange: ((Bool) -> Void)?  // recording indicator for the status item

    private var settings: AppSettings { AppSettings.shared }

    init(audio: AudioCapture, paste: PasteService, overlay: OverlayController) {
        self.audio = audio
        self.paste = paste
        self.overlay = overlay
        audio.onAudio = { [weak self] pcm, level in
            // Called on the audio queue — hop to the main actor and feed.
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                self.overlay.setLevel(level)
                if let session = self.session {
                    Task { await session.feed(pcm) }
                }
            }
        }
    }

    var isRecording: Bool { state == .recording }

    // MARK: - Trigger entry points

    func start(trigger: Trigger) {
        guard state == .idle else {
            Log.app.debug("start ignored (state != idle)")
            return
        }
        let apiKey = settings.apiKey
        guard !apiKey.isEmpty else {
            Log.app.warning("start blocked: no Gemini API key configured")
            overlay.showError("Set your Gemini API key in MacTyper Settings")
            NotificationCenter.default.post(name: .macTyperNeedsAPIKey, object: nil)
            return
        }
        state = .recording
        latched = false
        cancelled = false
        Log.app.info("🎤 dictation start (\(String(describing: trigger)))")

        paste.sessionBegin()
        let config = GeminiLiveSession.Config(
            apiKey: apiKey,
            model: settings.geminiModel,
            languageCodes: settings.languageHintList,
            customVocabulary: settings.vocabularyList,
            finishTimeoutS: settings.finishTimeoutS)
        let s = GeminiLiveSession(config: config) { preview in
            Task { @MainActor in
                DictationControllerShared.instance?.overlayPreview(preview)
            }
        }
        session = s
        Task { await s.connect() }
        audio.beginSession()
        overlay.show(status: "Listening…")
        onStateChange?(true)
    }

    fileprivate func overlayPreview(_ text: String) {
        guard state == .recording || state == .finishing else { return }
        overlay.setText(text)
    }

    func stop(trigger: Trigger) {
        guard state == .recording else { return }
        // Hold-to-talk releases don't stop a latched session.
        if latched && trigger != .f19 && trigger != .menu {
            Log.app.debug("release ignored (latched mode)")
            return
        }
        state = .finishing
        latched = false
        stopRequestedAt = Date()
        audio.endSession()
        overlay.setProcessing()
        onStateChange?(false)
        Log.app.info("✅ dictation stop — finishing")

        guard let session else {
            finishCleanup()
            return
        }
        self.session = nil
        Task { [weak self] in
            let text = await session.finish()
            await MainActor.run {
                self?.deliver(text)
            }
        }
    }

    func f19Tapped(whileF18Held f18Held: Bool) {
        switch state {
        case .recording:
            if f18Held && !latched {
                latched = true
                Log.app.info("F19 while F18 held → latched (permanent) mode")
            } else {
                stop(trigger: .f19)
            }
        case .idle:
            start(trigger: .f19)
        case .finishing:
            break
        }
    }

    func toggleFromMenu() {
        switch state {
        case .idle: start(trigger: .menu)
        case .recording: stop(trigger: .menu)
        case .finishing: break
        }
    }

    func cancel() {
        guard state == .recording else { return }
        Log.app.info("✖ dictation cancelled")
        cancelled = true
        state = .finishing
        latched = false
        audio.endSession()
        onStateChange?(false)
        if let session {
            self.session = nil
            Task { await session.abort() }
        }
        overlay.hide()
        finishCleanup()
    }

    // MARK: - Delivery

    private func deliver(_ text: String?) {
        defer { finishCleanup() }
        guard !cancelled else { return }
        guard let text, !text.isEmpty else {
            Log.app.warning("no transcript — nothing to paste")
            overlay.showError("No speech recognized", autoHideAfter: 1.2)
            return
        }
        if let t0 = stopRequestedAt {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            Log.app.info("transcript ready \(ms) ms after release (\(text.count) chars)")
        }
        overlay.setText(text)
        // Trailing space so consecutive dictations don't run together.
        paste.paste(text + " ")
        paste.sessionRestore()
        overlay.hide()
    }

    private func finishCleanup() {
        state = .idle
        cancelled = false
        stopRequestedAt = nil
    }
}

/// Weak global hook so the session's @Sendable interim callback can reach
/// the main-actor controller without capturing it across concurrency
/// domains at init time.
enum DictationControllerShared {
    @MainActor static weak var instance: DictationController?
}

extension Notification.Name {
    static let macTyperNeedsAPIKey = Notification.Name("macTyperNeedsAPIKey")
}
