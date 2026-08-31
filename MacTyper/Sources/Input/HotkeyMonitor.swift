import Foundation
import CoreGraphics
import AppKit

/// Listen-only CGEventTap for the keyboard triggers:
///  - hold Right-⌘ (keycode 54, via flagsChanged) → push-to-talk
///  - hold F18 (79) → push-to-talk
///  - tap F19 (80) → toggle; F19 while F18 held → latch
///  - Esc (53) while recording → cancel
///
/// The callback does nothing but decode and hop to the main actor. Handles
/// tapDisabledByTimeout/UserInput by re-enabling. Requires Input Monitoring.
final class HotkeyMonitor {
    weak var controller: DictationController?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Trigger-key state (accessed only on the tap callback = main run loop).
    fileprivate var rcmdHeld = false
    fileprivate var f18Held = false
    fileprivate var f19Held = false

    private static let kRightCmd: Int64 = 54
    private static let kF18: Int64 = 79
    private static let kF19: Int64 = 80
    private static let kEsc: Int64 = 53

    /// Returns false when the tap could not be created (Input Monitoring
    /// not granted, or grant not live yet — recreate after granting).
    @discardableResult
    func start() -> Bool {
        stop()
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.input.error("keyboard event tap creation FAILED (Input Monitoring missing?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.input.info("keyboard tap active")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.input.warning("keyboard tap disabled (\(type.rawValue)) — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            guard keyCode == Self.kRightCmd else { return }
            let hasCmd = event.flags.contains(.maskCommand)
            // flagsChanged events for keycode 54 alternate press/release;
            // track keycode 54 specifically, not the flag bit alone (the
            // bit stays set if the LEFT Cmd is also held).
            if !rcmdHeld && hasCmd {
                rcmdHeld = true
                Log.input.debug("right-cmd press → hold-to-talk start")
                dispatch { $0.start(trigger: .rightCmd) }
            } else if rcmdHeld {
                rcmdHeld = false
                Log.input.debug("right-cmd release → hold-to-talk stop")
                dispatch { $0.stop(trigger: .rightCmd) }
            }
        case .keyDown:
            // Ignore auto-repeat.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            switch keyCode {
            case Self.kF18:
                guard !f18Held else { return }
                f18Held = true
                Log.input.debug("F18 press → hold-to-talk start")
                dispatch { $0.start(trigger: .f18) }
            case Self.kF19:
                guard !f19Held else { return }
                f19Held = true
                let f18 = f18Held
                Log.input.debug("F19 press")
                dispatch { $0.f19Tapped(whileF18Held: f18) }
            case Self.kEsc:
                dispatch { $0.cancel() }
            default:
                break
            }
        case .keyUp:
            switch keyCode {
            case Self.kF18:
                f18Held = false
                Log.input.debug("F18 release")
                dispatch { $0.stop(trigger: .f18) }
            case Self.kF19:
                f19Held = false
            default:
                break
            }
        default:
            break
        }
    }

    private func dispatch(_ action: @escaping @MainActor (DictationController) -> Void) {
        guard let controller else { return }
        Task { @MainActor in action(controller) }
    }
}
