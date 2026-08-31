import AppKit

/// Menu bar presence: a template mic icon that switches to a filled red
/// variant while recording, plus the app menu.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    var onToggleDictation: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setRecording(false)

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let about = NSMenuItem(title: "MacTyper \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit MacTyper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private var toggleItem: NSMenuItem?

    func setRecording(_ recording: Bool) {
        let name = recording ? "mic.fill" : "mic"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacTyper")
        image?.isTemplate = !recording
        if recording, let image {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            statusItem.button?.image = image.withSymbolConfiguration(config) ?? image
        } else {
            statusItem.button?.image = image
        }
        toggleItem?.title = recording ? "Stop Dictation" : "Start Dictation"
    }

    @objc private func toggleDictation() { onToggleDictation?() }
    @objc private func openSettings() { onOpenSettings?() }
}
