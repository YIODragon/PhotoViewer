import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Also support launching the executable directly from a terminal:
        //   PhotoViewer.app/Contents/MacOS/PhotoViewer /path/to/image.jpg
        let arguments = CommandLine.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-") }
            .map { URL(fileURLWithPath: $0) }
        if !arguments.isEmpty {
            OpenRequestCenter.shared.enqueue(arguments)
        }
    }

    /// Finder sends opened files here. `OpenRequestCenter` queues them until the
    /// SwiftUI window is ready.
    func application(_ application: NSApplication, open urls: [URL]) {
        OpenRequestCenter.shared.enqueue(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
