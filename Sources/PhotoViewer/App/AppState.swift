import AppKit
import Observation
import PhotoViewerCore

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let browser = BrowserViewModel()
    let chrome = ChromeVisibility()

    @ObservationIgnored
    weak var mainWindow: NSWindow?

    @ObservationIgnored
    weak var activeZoom: ZoomState?

    private init() {}

    func toggleFullScreen() {
        mainWindow?.toggleFullScreen(nil)
    }

    /// Handles plain-key shortcuts. Command-based shortcuts stay in the menu bar
    /// so they show up as normal macOS menu items.
    func handleKey(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window else { return false }
        if mainWindow == nil {
            mainWindow = eventWindow
        }
        guard eventWindow === mainWindow, NSApp.modalWindow == nil else { return false }
        if eventWindow.firstResponder is NSTextView { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Handle Command-based zoom shortcuts here as well as in the menu so
        // Command-= works in addition to Command-Shift-= (Command-+).
        if flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option) {
            switch event.keyCode {
            case 24: // =
                NotificationCenter.default.post(name: .zoomIn, object: nil)
                return true
            case 27: // -
                NotificationCenter.default.post(name: .zoomOut, object: nil)
                return true
            case 29: // 0
                NotificationCenter.default.post(name: .zoomFit, object: nil)
                return true
            case 18: // 1
                NotificationCenter.default.post(name: .zoomActualSize, object: nil)
                return true
            case 6: // z: undo deletion
                browser.undoLastDeletion()
                return true
            default:
                return false
            }
        }

        guard !flags.contains(.command),
              !flags.contains(.control),
              !flags.contains(.option)
        else {
            return false
        }

        switch event.keyCode {
        case 18: // 1 star
            if !event.isARepeat { browser.rate(1) }
            return true
        case 19: // 2 stars
            if !event.isARepeat { browser.rate(2) }
            return true
        case 20: // 3 stars
            if !event.isARepeat { browser.rate(3) }
            return true
        case 21: // 4 stars
            if !event.isARepeat { browser.rate(4) }
            return true
        case 23: // 5 stars
            if !event.isARepeat { browser.rate(5) }
            return true
        case 29: // 0: clear rating
            if !event.isARepeat { browser.clearRating() }
            return true
        case 35: // p: pick
            if !event.isARepeat { browser.setFlag(.pick) }
            return true
        case 7: // x: reject
            if !event.isARepeat { browser.setFlag(.reject) }
            return true
        case 32: // u: clear flag
            if !event.isARepeat { browser.clearFlag() }
            return true
        case 123: // left arrow
            browser.goPrevious()
            return true
        case 124: // right arrow
            browser.goNext()
            return true
        case 51, 117: // delete / forward delete
            // Ignore key repeat so holding Delete cannot empty a folder by accident.
            if !event.isARepeat {
                browser.requestDelete()
            }
            return true
        case 5: // g: grid view
            if !event.isARepeat { browser.toggleGridView() }
            return true
        case 14: // e: loupe / single image
            if !event.isARepeat { browser.showLoupe() }
            return true
        case 8: // c: compare
            if !event.isARepeat { browser.toggleCompare() }
            return true
        case 45: // n: 4-up survey
            if !event.isARepeat { browser.toggleSurvey() }
            return true
        case 17: // t: collapse / expand filmstrip
            if !event.isARepeat { browser.toggleFilmstrip() }
            return true
        case 3: // f: Lightroom-style full screen
            if !event.isARepeat {
                toggleFullScreen()
            }
            return true
        case 6: // z: 100% / fit toggle
            if !event.isARepeat {
                if browser.viewMode == .compare || browser.viewMode == .survey {
                    NotificationCenter.default.post(name: .compareZoomToggle, object: nil)
                } else if let zoom = activeZoom {
                    zoom.toggleFitActual()
                    chrome.showTemporarily()
                }
            }
            return true
        case 38: // j: RAW / JPEG for the current shot
            if !event.isARepeat {
                browser.toggleDisplayFormat()
                chrome.showTemporarily()
            }
            return true
        case 53: // escape
            if let window = mainWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Mouse-wheel / trackpad scrolling. Plain mouse wheels zoom when the pointer
    /// is over the image; trackpads use pinch, or Command-scroll for zoom.
    func handleScroll(_ event: NSEvent) -> Bool {
        guard let eventWindow = event.window,
              eventWindow === mainWindow,
              NSApp.modalWindow == nil,
              let zoom = activeZoom
        else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let plainMouseWheel = !event.hasPreciseScrollingDeltas

        guard command || (plainMouseWheel && zoom.isHovering) else {
            return false
        }

        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return false }

        let step = event.hasPreciseScrollingDeltas
            ? min(abs(delta) * 0.01, 0.15)
            : 0.12
        chrome.showTemporarily()
        zoom.zoomBy(delta > 0 ? 1 + step : 1 / (1 + step))
        return true
    }
}
