import AppKit
import Carbon.HIToolbox
import os

/// Inserts transcribed text at the active cursor position.
/// Strategy: try Accessibility API first, fall back to clipboard paste.
final class TextInserter {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "TextInserter")

    /// Insert text at the current cursor position in any app.
    func insert(text: String) async {
        if tryAccessibilityInsertion(text) {
            logger.info("Inserted via Accessibility API")
        } else {
            await clipboardPasteInsertion(text)
            logger.info("Inserted via clipboard paste fallback")
        }
    }

    // MARK: - Accessibility API (Primary)

    /// Attempt to insert text using the Accessibility API.
    /// Returns true if successful.
    private func tryAccessibilityInsertion(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            logger.debug("No focused element found")
            return false
        }

        let axElement = element as! AXUIElement

        // Try inserting at selection range first (preserves cursor position)
        if insertAtSelection(axElement, text: text) {
            return true
        }

        // Fall back to setting the full value with text appended at cursor
        if setValueWithAppend(axElement, text: text) {
            return true
        }

        return false
    }

    /// Insert text at the current selection range using AXSelectedTextRange.
    private func insertAtSelection(_ element: AXUIElement, text: String) -> Bool {
        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )

        guard rangeResult == .success, let rangeValue = selectedRangeValue else {
            return false
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return false
        }

        // Get current value
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )

        guard valueResult == .success, let current = currentValue as? String else {
            return false
        }

        // Build new value with text inserted at selection
        let startIndex = current.index(current.startIndex, offsetBy: min(range.location, current.count))
        let endIndex = current.index(startIndex, offsetBy: min(range.length, current.count - min(range.location, current.count)))
        var newValue = current
        newValue.replaceSubrange(startIndex..<endIndex, with: text)

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        guard setResult == .success else {
            return false
        }

        // Verify the value actually changed
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &verifyValue)
        guard let verifiedText = verifyValue as? String, verifiedText == newValue else {
            logger.debug("AX set reported success but value didn't change")
            return false
        }

        // Move cursor to end of inserted text
        let newCursorPos = range.location + text.count
        var newRange = CFRange(location: newCursorPos, length: 0)
        if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                newRangeValue
            )
        }

        return true
    }

    /// Fall back to setting kAXValueAttribute directly.
    private func setValueWithAppend(_ element: AXUIElement, text: String) -> Bool {
        // Check if element is settable
        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )

        guard settableResult == .success, isSettable.boolValue else {
            return false
        }

        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValue
        )

        let current = (valueResult == .success ? currentValue as? String : nil) ?? ""
        let newValue = current + text

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newValue as CFTypeRef
        )

        guard setResult == .success else { return false }

        // Verify the value actually changed
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &verifyValue)
        guard let verifiedText = verifyValue as? String, verifiedText == newValue else {
            logger.debug("AX append reported success but value didn't change")
            return false
        }

        return true
    }

    // MARK: - Clipboard Paste Fallback

    /// Insert text by temporarily replacing the clipboard and simulating Cmd+V.
    private func clipboardPasteInsertion(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount

        // Save current clipboard contents
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        // Set clipboard to our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulateKeyPress(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)

        // Wait for paste to complete, then restore clipboard
        try? await Task.sleep(for: .milliseconds(200))

        // Only restore if nothing else has changed the clipboard
        if pasteboard.changeCount == changeCount + 1 {
            pasteboard.clearContents()
            for (typeRaw, data) in savedItems {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
        }
    }

    /// Simulate a key press using CGEvent.
    private func simulateKeyPress(keyCode: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Failed to create CGEvent for key simulation")
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
