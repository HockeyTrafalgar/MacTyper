import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import IOKit.hid

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
            || IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
        // IOHIDRequestAccess is what actually registers the app in the
        // System Settings → Input Monitoring list and pops the system
        // prompt; CGRequestListenEventAccess alone often does neither.
        let hid = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let cg = CGRequestListenEventAccess()
        Log.app.info("input monitoring request: iohid=\(hid) cg=\(cg)")
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
