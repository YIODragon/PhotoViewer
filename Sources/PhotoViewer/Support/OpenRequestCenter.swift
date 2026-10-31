import Foundation

extension Notification.Name {
    static let openRequestsAvailable = Notification.Name("PhotoViewer.openRequestsAvailable")
}

/// Bridges AppKit's "open document" callback to the SwiftUI view model.
///
/// Finder can send an open request before the first window exists, so requests
/// are queued and drained when the UI becomes ready.
@MainActor
final class OpenRequestCenter {
    static let shared = OpenRequestCenter()

    private var pending: [URL] = []

    private init() {}

    func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pending.append(contentsOf: urls)
        NotificationCenter.default.post(name: .openRequestsAvailable, object: nil)
    }

    func drain() -> [URL] {
        let urls = pending
        pending.removeAll()
        return urls
    }
}
