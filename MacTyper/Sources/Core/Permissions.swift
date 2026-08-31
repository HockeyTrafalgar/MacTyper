import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// TCC preflight/request helpers for the three permissions MacTyper needs.
///
/// - Microphone: audio capture (prompts natively).
/// - Accessibility: AX queries (caret, editability) AND posting the
///   synthetic Cmd+V (`CGPreflightPostEventAccess`).
/// - Input Monitoring: the listen-only CGEventTaps
///   (`CGPreflightListenEventAccess`).
enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var postEventGranted: Bool {
        CGPreflightPostEventAccess()
    }

    static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        microphoneGranted && accessibilityGranted && inputMonitoringGranted
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// One-shot system dialog pointing at System Settings; subsequent calls
    /// are no-ops, so onboarding also deep-links to the pane.
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        CGRequestPostEventAccess()
    }

    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }

    static func openSystemSettings(pane: Pane) {
        guard let url = URL(string: pane.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    enum Pane: String {
        case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    }

    static func logStatus() {
        Log.app.info("TCC: mic=\(microphoneGranted) ax=\(accessibilityGranted) post=\(postEventGranted) listen=\(inputMonitoringGranted)")
    }
}
