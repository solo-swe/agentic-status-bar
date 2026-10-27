import AppKit

/// A window that Esc closes, like ⌘W: for Help and Settings. An open popover or menu inside it (the symbol and
/// color pickers) gets Esc first and closes only itself.
final class EscClosingWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
