import AppKit

/// Floating glass HUD that previews the live transcript near the caret.
///
/// Non-activating borderless NSPanel: the user's focused app NEVER loses
/// key-window status — critical because we synthesize keystrokes into it.
/// The panel's TOP edge is the anchor; growth happens downward as the
/// transcript wraps, clamped to the screen with a margin.
///
/// All methods must be called on the main thread.
@MainActor
final class OverlayController {
    // Geometry (Python OVERLAY_* defaults).
    private let width: CGFloat = 832
    private let restingH: CGFloat = 72
    private let maxH: CGFloat = 420
    private let fontSize: CGFloat = 21
    private let cornerRadius: CGFloat = 36
    private let padX: CGFloat = 28
    private let edgeMargin: CGFloat = 16

    private let panel: NSPanel
    private let label: NSTextField
    private let meter: LevelMeterView?
    private let textX: CGFloat
    private let textMaxW: CGFloat
    private let lineH: CGFloat

    private var currentText = ""
    private var settings: AppSettings { AppSettings.shared }

    init() {
        let rect = NSRect(x: 0, y: 0, width: width, height: restingH)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Background: Liquid Glass on macOS 26+, vibrancy fallback below.
        let content: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: rect)
            glass.cornerRadius = cornerRadius
            glass.tintColor = .clear
            glass.autoresizingMask = [.width, .height]
            let inner = NSView(frame: rect)
            inner.autoresizingMask = [.width, .height]
            glass.contentView = inner
            panel.contentView = glass
            content = inner
        } else {
            let ve = NSVisualEffectView(frame: rect)
            ve.material = .popover
            ve.blendingMode = .behindWindow
            ve.state = .active
            ve.autoresizingMask = [.width, .height]
            // cornerRadius alone does not clip the vibrancy material — the
            // documented fix is a 9-slice resizable rounded mask image.
            ve.maskImage = Self.roundedMaskImage(radius: cornerRadius)
            ve.wantsLayer = true
            ve.layer?.cornerRadius = cornerRadius
            ve.layer?.cornerCurve = .continuous
            ve.layer?.masksToBounds = true
            ve.layer?.borderWidth = 1
            ve.layer?.borderColor = NSColor(calibratedWhite: 0, alpha: 0.08).cgColor
            panel.contentView = ve
            content = ve
        }
        panel.invalidateShadow()

        // Leading level meter.
        var tx = padX
        if AppSettings.shared.levelMeterEnabled {
            let meterW: CGFloat = 34, meterH: CGFloat = 30
            let m = LevelMeterView(frame: NSRect(x: padX, y: (restingH - meterH) / 2,
                                                 width: meterW, height: meterH))
            content.addSubview(m)
            meter = m
            tx = padX + meterW + 12
        } else {
            meter = nil
        }
        textX = tx
        textMaxW = width - tx - padX
        lineH = fontSize * 1.35

        // Transcript label — Spotlight-placeholder typography.
        label = NSTextField(frame: NSRect(x: tx, y: (restingH - lineH) / 2,
                                          width: textMaxW, height: lineH))
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = .systemFont(ofSize: fontSize, weight: .regular)
        label.textColor = OverlayTheme.ink()
        label.stringValue = ""
        label.cell?.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        label.cell?.isScrollable = false
        content.addSubview(label)
    }

    private static func roundedMaskImage(radius: CGFloat) -> NSImage {
        let diameter = radius * 2 + 1
        let img = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    // MARK: - Public API

    func show(status: String = "Listening…") {
        guard settings.overlayEnabled else { return }
        // Reset to single-line height BEFORE positioning (the panel may
        // still be at a taller frame from a previous session).
        let cur = panel.frame
        if Int(cur.height.rounded()) != Int(restingH) {
            let topY = cur.origin.y + cur.height
            panel.setFrame(NSRect(x: cur.origin.x, y: topY - restingH,
                                  width: cur.width, height: restingH), display: false)
        }
        positionNearCursor()
        currentText = ""
        meter?.setLevel(0)
        render(status, placeholder: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        currentText = ""
    }

    func setText(_ text: String) {
        guard settings.overlayEnabled else { return }
        if !text.isEmpty {
            currentText = text
            render(text, placeholder: false)
        } else {
            currentText = ""
            render("Dictating…", placeholder: true)
        }
    }

    /// Shown the instant the trigger releases, while Gemini finishes.
    func setProcessing() {
        guard settings.overlayEnabled else { return }
        currentText = ""
        meter?.setLevel(0)
        render("Processing…", placeholder: true)
    }

    func showError(_ message: String, autoHideAfter seconds: Double = 2.5) {
        guard settings.overlayEnabled else { return }
        if !panel.isVisible { positionNearCursor(); panel.orderFrontRegardless() }
        currentText = ""
        meter?.setLevel(0)
        render(message, placeholder: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            Task { @MainActor in self?.hide() }
        }
    }

    func setLevel(_ level: Double) {
        meter?.setLevel(level)
    }

    // MARK: - Rendering

    private func render(_ text: String, placeholder: Bool) {
        label.textColor = OverlayTheme.ink()
        label.stringValue = text
        resizeToFit(text)
    }

    private func measureTextHeight(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return lineH }
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font ?? .systemFont(ofSize: fontSize)]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: textMaxW, height: 1e6),
            options: [.usesLineFragmentOrigin],
            attributes: attrs)
        return max(lineH, rect.height + 1)
    }

    /// Grow the panel vertically to fit the wrapped text (top edge is the
    /// anchor; growth goes downward), keeping it fully on screen.
    private func resizeToFit(_ text: String) {
        let topPad = (restingH - lineH) / 2
        let botPad = topPad
        let needed = topPad + measureTextHeight(text) + botPad
        let newH = max(restingH, min(maxH, needed)).rounded()

        let old = panel.frame
        let oldTopY = old.origin.y + old.height
        var newX = old.origin.x
        var newY = oldTopY - newH
        if let screen = panel.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            if newX + old.width > vf.maxX - edgeMargin { newX = vf.maxX - edgeMargin - old.width }
            if newX < vf.minX + edgeMargin { newX = vf.minX + edgeMargin }
            if newY < vf.minY + edgeMargin { newY = vf.minY + edgeMargin }
        }
        if Int(old.height.rounded()) != Int(newH) || newX != old.origin.x || newY != old.origin.y {
            panel.setFrame(NSRect(x: newX, y: newY, width: old.width, height: newH), display: true)
        }

        // Anchor the meter to the FIRST line so it doesn't drift down.
        if let meter {
            let mf = meter.frame
            let mTopPad = (restingH - mf.height) / 2
            meter.frame = NSRect(x: mf.origin.x, y: newH - mTopPad - mf.height,
                                 width: mf.width, height: mf.height)
        }

        // Label spans top-pad to bottom-pad; first line at the frame top.
        let labelH = max(lineH, newH - topPad - botPad)
        label.frame = NSRect(x: textX, y: botPad, width: textMaxW, height: labelH)
    }

    // MARK: - Positioning

    private func positionNearCursor() {
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let placement = settings.overlayPlacement

        if placement == "bottom" {
            panel.setFrameOrigin(NSPoint(x: vf.minX + (vf.width - width) / 2, y: vf.minY + 40))
            return
        }

        if placement == "caret", let caret = AXQueries.caretScreenRect() {
            // Hang just below the caret line; flip above if clipped.
            var x = caret.origin.x + 6
            var y = caret.origin.y - 6 - restingH
            if y < vf.minY { y = caret.origin.y + caret.height + 6 }
            if x + width > vf.maxX { x = vf.maxX - width - 8 }
            if x < vf.minX { x = vf.minX + 8 }
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            return
        }

        // "cursor" placement, or caret lookup failed.
        let loc = NSEvent.mouseLocation
        var x = loc.x + 18
        var y = loc.y - restingH - 18
        if x + width > vf.maxX { x = loc.x - width - 18 }
        if y < vf.minY { y = loc.y + 18 }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
