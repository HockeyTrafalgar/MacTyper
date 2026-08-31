import Foundation
import AppKit
import ApplicationServices

/// Accessibility queries: caret position (HUD anchoring) and click-target
/// editability (mouse long-press gate). Ported from the Python reference
/// (`_caret_screen_rect`, `_ax_element_editability`,
/// `_click_should_start_dictation`).
enum AXQueries {
    private static let systemWide = AXUIElementCreateSystemWide()

    // MARK: - Caret rect

    /// Rect of the focused text caret in NSScreen coordinates (origin
    /// bottom-left of the primary display), or nil when unavailable —
    /// callers fall back to the mouse cursor.
    static func caretScreenRect() -> CGRect? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        let el = focused as! AXUIElement
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let range = rangeRef else {
            return nil
        }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForRange" as CFString, range, &boundsRef) == .success,
              let boundsVal = boundsRef, CFGetTypeID(boundsVal) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect) else { return nil }
        // Degenerate (0,0,0,0) means "no caret" in some apps.
        if rect.size.width == 0 && rect.size.height == 0 { return nil }
        // AX = top-left global coords (y down); NSScreen = bottom-left of
        // primary (y up). Flip against the primary screen height so the
        // returned y is the caret's BOTTOM edge in NS coords.
        guard let main = NSScreen.screens.first else { return nil }
        let mainH = main.frame.size.height
        let y = mainH - rect.origin.y - rect.size.height
        return CGRect(x: rect.origin.x, y: y, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Editability gate (mouse trigger)

    enum Editability { case editable, nonEditable, unknown }

    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]
    private static let nonEditableRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXMenuItem", "AXMenuBarItem",
        "AXLink", "AXStaticText", "AXImage", "AXCheckBox", "AXRadioButton",
        "AXSlider", "AXIncrementor", "AXStepper", "AXDisclosureTriangle",
        "AXColorWell", "AXScrollBar", "AXTabGroup", "AXToolbar",
        "AXSegmentedControl", "AXRadioGroup", "AXDockItem",
    ]

    private static func role(of el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// 'editable' = a place keystrokes can land: a text-input role, OR it
    /// exposes a selected-text range (every real text input does), OR its
    /// AXValue is settable. 'nonEditable' = a known non-text control.
    /// Anything else is 'unknown' so the caller can stay permissive.
    static func editability(of el: AXUIElement) -> Editability {
        let r = role(of: el)
        if let r, editableRoles.contains(r) { return .editable }
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           rangeRef != nil {
            return .editable
        }
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return .editable
        }
        if let r, nonEditableRoles.contains(r) { return .nonEditable }
        return .unknown
    }

    /// Should a left-click long-press at global top-left point (x, y) start
    /// dictation? Classify the element under the click first; fall back to
    /// the focused element; block only on a POSITIVE non-editable signal
    /// (permissive for apps with no AX data — Electron, GPU terminals).
    /// CGEventTap mouse coordinates are already top-left global — no flip.
    static func clickShouldStartDictation(x: Double, y: Double) -> Bool {
        // Without Accessibility, every query below fails and the permissive
        // default would fire the trigger on ANY long hold anywhere. Blind ≠
        // permissive: require the permission before allowing mouse starts.
        guard AXIsProcessTrusted() else {
            Log.input.warning("mouse trigger blocked: Accessibility permission missing")
            return false
        }
        var pointState = Editability.unknown
        var elRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(x), Float(y), &elRef) == .success,
           let el = elRef {
            pointState = editability(of: el)
        }
        if pointState == .editable { return true }
        if pointState == .nonEditable {
            Log.input.debug("mouse trigger gated: click target non-editable")
            return false
        }
        var focState = Editability.unknown
        var focRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
           let foc = focRef, CFGetTypeID(foc) == AXUIElementGetTypeID() {
            focState = editability(of: foc as! AXUIElement)
        }
        if focState == .editable { return true }
        if focState == .nonEditable {
            Log.input.debug("mouse trigger gated: focused element non-editable")
            return false
        }
        Log.input.debug("mouse trigger: editability unknown — starting (permissive)")
        return true
    }
}
