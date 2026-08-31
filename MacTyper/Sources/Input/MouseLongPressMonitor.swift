import Foundation
import CoreGraphics

/// Left-click long-press dictation trigger (the killer feature).
///
/// Hold the left button for `holdMs` without drifting more than
/// `moveThresholdPx` → start dictation, but only if the click landed on /
/// focuses an AX-editable field. Release → stop. Movement past the
/// threshold cancels the trigger so click-and-drag keeps working.
///
/// The editability gate runs at the END of the hold (focus has settled by
/// then) and OFF the event-tap path (AX is cross-process IPC).
final class MouseLongPressMonitor {
    weak var controller: DictationController?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // State (mutated on the main run loop where the tap fires).
    private var down = false
    private var moved = false
    private var firedStart = false
    private var x0 = 0.0, y0 = 0.0
    private var holdTimer: DispatchWorkItem?
    private var generation = 0

    private var holdMs: Int { AppSettings.shared.mouseHoldMs }
    private var moveThresholdPx: Double { AppSettings.shared.mouseMoveThresholdPx }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<MouseLongPressMonitor>.fromOpaque(refcon!).takeUnretainedValue()
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
            Log.input.error("mouse event tap creation FAILED (Input Monitoring missing?)")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.input.info("mouse trigger active: left-click hold ≥\(self.holdMs) ms (move <\(self.moveThresholdPx) px)")
        return true
    }

    func stop() {
        holdTimer?.cancel()
        holdTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        down = false
        firedStart = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.input.warning("mouse tap disabled — re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let loc = event.location  // global top-left coords, matches AX
        switch type {
        case .leftMouseDown:
            holdTimer?.cancel()
            down = true
            moved = false
            firedStart = false
            x0 = loc.x
            y0 = loc.y
            generation += 1
            let gen = generation
            let work = DispatchWorkItem { [weak self] in self?.holdTimerFired(generation: gen) }
            holdTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(holdMs), execute: work)
        case .leftMouseDragged:
            guard down, !moved else { return }
            let dx = loc.x - x0
            let dy = loc.y - y0
            if dx * dx + dy * dy > moveThresholdPx * moveThresholdPx {
                moved = true
                holdTimer?.cancel()
                holdTimer = nil
            }
        case .leftMouseUp:
            let fired = firedStart
            holdTimer?.cancel()
            holdTimer = nil
            down = false
            firedStart = false
            if fired {
                Log.input.debug("mouse release → hold-to-talk stop")
                dispatch { $0.stop(trigger: .mouse) }
            }
        default:
            break
        }
    }

    /// Runs `holdMs` after left-down, on the main queue. The AX gate runs on
    /// a background queue; state is re-validated (via `generation`) after it
    /// returns, since the button may have been released or dragged meanwhile.
    private func holdTimerFired(generation gen: Int) {
        guard down, !moved, !firedStart, gen == generation else { return }
        let x = x0, y = y0
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let shouldStart = AXQueries.clickShouldStartDictation(x: x, y: y)
            DispatchQueue.main.async {
                guard let self else { return }
                guard shouldStart else {
                    Log.input.debug("mouse long-press: target not editable — not starting")
                    return
                }
                // Re-validate: still the same press, still down, no drag.
                guard self.down, !self.moved, !self.firedStart, gen == self.generation else { return }
                self.firedStart = true
                Log.input.debug("mouse left-click long-press → hold-to-talk start")
                self.dispatch { $0.start(trigger: .mouse) }
            }
        }
    }

    private func dispatch(_ action: @escaping @MainActor (DictationController) -> Void) {
        guard let controller else { return }
        Task { @MainActor in action(controller) }
    }
}
