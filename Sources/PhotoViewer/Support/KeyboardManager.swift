import AppKit

@MainActor
final class KeyboardManager {
    static let shared = KeyboardManager()

    private var monitor: Any?
    private var scrollMonitor: Any?

    private init() {}

    func install() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let box = KeyEventBox(event: event)
            let handled = MainActor.assumeIsolated {
                AppState.shared.handleKey(box.event)
            }
            return handled ? nil : box.event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let box = ScrollEventBox(event: event)
            let handled = MainActor.assumeIsolated {
                AppState.shared.handleScroll(box.event)
            }
            return handled ? nil : box.event
        }
    }
}


/// NSEvent is explicitly non-Sendable. Local event monitors are documented to run
/// on the main thread, so this box is only a compiler bridge for that guarantee.
private struct KeyEventBox: @unchecked Sendable {
    let event: NSEvent
}

private struct ScrollEventBox: @unchecked Sendable {
    let event: NSEvent
}
