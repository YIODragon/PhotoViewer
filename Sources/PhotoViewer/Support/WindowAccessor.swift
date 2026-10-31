import AppKit
import SwiftUI

private final class WindowProbeView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            AppState.shared.mainWindow = window
            window.title = AppState.shared.browser.windowTitle
        }
    }
}

/// Attaches to the SwiftUI content so plain-key handling can be limited to the
/// main browser window rather than panels such as open/save dialogs.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            AppState.shared.mainWindow = window
        }
    }
}
