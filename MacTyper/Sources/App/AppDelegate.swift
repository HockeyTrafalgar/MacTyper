import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!
    private var overlay: OverlayController!
    private var audio: AudioCapture!
    private var pasteService: PasteService!
    private var controller: DictationController!
    private var hotkeys: HotkeyMonitor!
    private var mouse: MouseLongPressMonitor!

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var tapRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("MacTyper starting")
        Permissions.logStatus()

        overlay = OverlayController()
        audio = AudioCapture()
        pasteService = PasteService()
        controller = DictationController(audio: audio, paste: pasteService, overlay: overlay)
        DictationControllerShared.instance = controller

        statusItem = StatusItemController()
        statusItem.onToggleDictation = { [weak self] in self?.controller.toggleFromMenu() }
        statusItem.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem.onOpenPermissions = { [weak self] in self?.showOnboarding() }
        controller.onStateChange = { [weak self] recording in
            self?.statusItem.setRecording(recording)
        }

        hotkeys = HotkeyMonitor()
        hotkeys.controller = controller
        mouse = MouseLongPressMonitor()
        mouse.controller = controller

        NotificationCenter.default.addObserver(
            forName: .macTyperNeedsAPIKey, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showSettings() }
        }

        // Debug/testing hook: `notifyutil`-free way to toggle dictation from
        // scripts (used by the test harness; harmless locally).
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.timurvalishev.mactyper.toggle"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Log.app.info("toggle via distributed notification")
            Task { @MainActor in self?.controller.toggleFromMenu() }
        }

        // Microphone: prompt from onboarding/launch, not mid-first-dictation.
        if !Permissions.microphoneGranted {
            Permissions.requestMicrophone { granted in
                Log.app.info("microphone request → \(granted)")
            }
        }
        // Register with TCC so MacTyper appears in the Input Monitoring
        // list right away (the row does not exist until the app asks).
        if !Permissions.inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        audio.start()

        startInputMonitors()

        if !Permissions.allGranted {
            showOnboarding()
        }
        Log.app.info("🟢 ready — hold Right ⌘ to talk")
    }

    /// Create the event taps; retry every 3 s while Input Monitoring is
    /// missing (a tap created before the grant stays dead — recreate once
    /// events can actually flow).
    private func startInputMonitors() {
        // A tap created without Input Monitoring may "succeed" and then be
        // silently disabled by the system on the first event — preflight is
        // the real health signal, tapCreate alone is not.
        let listenGranted = Permissions.inputMonitoringGranted
        let keyboardOK = hotkeys.start() && listenGranted
        var mouseOK = listenGranted
        if AppSettings.shared.mouseTriggerEnabled {
            mouseOK = mouse.start() && listenGranted
        }
        if keyboardOK && mouseOK {
            tapRetryTimer?.invalidate()
            tapRetryTimer = nil
        } else if tapRetryTimer == nil {
            Log.app.warning("event taps unavailable — retrying every 3 s until Input Monitoring is granted")
            tapRetryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.startInputMonitors() }
            }
        }
    }

    /// Called from Settings when the mouse-trigger toggle changes.
    func reconfigureMouseTrigger() {
        if AppSettings.shared.mouseTriggerEnabled {
            mouse.start()
        } else {
            mouse.stop()
        }
    }

    // MARK: - Windows

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(onMouseTriggerChanged: { [weak self] in
                self?.reconfigureMouseTrigger()
            })
            let win = NSWindow(contentViewController: NSHostingController(rootView: view))
            win.title = "MacTyper Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(onAllGranted: { [weak self] in
                // Permissions may have just gone live — make sure the taps exist.
                self?.startInputMonitors()
            })
            let win = NSWindow(contentViewController: NSHostingController(rootView: view))
            win.title = "MacTyper Permissions"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            onboardingWindow = win
        }
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.stop()
        mouse?.stop()
    }
}

// MARK: - Entry point

@main
struct MacTyperMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // LSUIElement — no Dock icon
        app.run()
    }
}
