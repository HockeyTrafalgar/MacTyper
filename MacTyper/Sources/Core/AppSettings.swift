import Foundation
import Combine
import ServiceManagement

/// UserDefaults-backed settings. The Gemini API key lives in the Keychain,
/// not here — `apiKey` proxies to it.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // Register defaults once so first launch behaves.
    private init() {
        d.register(defaults: [
            "geminiModel": "gemini-3.5-transcribe-live",
            "languageHints": "",
            "vocabulary": "",
            "finishTimeoutS": 6.0,
            "mouseTriggerEnabled": true,
            "mouseHoldMs": 700,
            "mouseMoveThresholdPx": 5.0,
            "overlayEnabled": true,
            "overlayPlacement": "caret",
            "levelMeterEnabled": true,
            "restoreClipboard": true,
            "clipboardRestoreDelayS": 1.0,
        ])
        apiKeyPresent = Keychain.loadAPIKey() != nil
    }

    @Published var apiKeyPresent: Bool

    var apiKey: String {
        get { Keychain.loadAPIKey() ?? "" }
        set {
            Keychain.saveAPIKey(newValue)
            apiKeyPresent = Keychain.loadAPIKey() != nil
            objectWillChange.send()
        }
    }

    var geminiModel: String {
        get { d.string(forKey: "geminiModel") ?? "gemini-3.5-transcribe-live" }
        set { d.set(newValue, forKey: "geminiModel"); objectWillChange.send() }
    }

    /// Comma-separated BCP-47 hints, e.g. "en-US,ru-RU". Empty = auto-detect.
    var languageHints: String {
        get { d.string(forKey: "languageHints") ?? "" }
        set { d.set(newValue, forKey: "languageHints"); objectWillChange.send() }
    }

    var languageHintList: [String] {
        languageHints.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Comma-separated custom vocabulary (names/jargon).
    var vocabulary: String {
        get { d.string(forKey: "vocabulary") ?? "" }
        set { d.set(newValue, forKey: "vocabulary"); objectWillChange.send() }
    }

    var vocabularyList: [String] {
        vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var finishTimeoutS: Double {
        get { d.double(forKey: "finishTimeoutS") }
        set { d.set(newValue, forKey: "finishTimeoutS"); objectWillChange.send() }
    }

    var mouseTriggerEnabled: Bool {
        get { d.bool(forKey: "mouseTriggerEnabled") }
        set { d.set(newValue, forKey: "mouseTriggerEnabled"); objectWillChange.send() }
    }

    var mouseHoldMs: Int {
        get { d.integer(forKey: "mouseHoldMs") }
        set { d.set(newValue, forKey: "mouseHoldMs"); objectWillChange.send() }
    }

    var mouseMoveThresholdPx: Double {
        get { d.double(forKey: "mouseMoveThresholdPx") }
        set { d.set(newValue, forKey: "mouseMoveThresholdPx"); objectWillChange.send() }
    }

    var overlayEnabled: Bool {
        get { d.bool(forKey: "overlayEnabled") }
        set { d.set(newValue, forKey: "overlayEnabled"); objectWillChange.send() }
    }

    /// "caret" | "cursor" | "bottom"
    var overlayPlacement: String {
        get { d.string(forKey: "overlayPlacement") ?? "caret" }
        set { d.set(newValue, forKey: "overlayPlacement"); objectWillChange.send() }
    }

    var levelMeterEnabled: Bool {
        get { d.bool(forKey: "levelMeterEnabled") }
        set { d.set(newValue, forKey: "levelMeterEnabled"); objectWillChange.send() }
    }

    var restoreClipboard: Bool {
        get { d.bool(forKey: "restoreClipboard") }
        set { d.set(newValue, forKey: "restoreClipboard"); objectWillChange.send() }
    }

    var clipboardRestoreDelayS: Double {
        get { d.double(forKey: "clipboardRestoreDelayS") }
        set { d.set(newValue, forKey: "clipboardRestoreDelayS"); objectWillChange.send() }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("launch-at-login toggle failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
