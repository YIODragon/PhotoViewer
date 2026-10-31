import CoreGraphics
import Foundation
import Observation

/// Controls the visibility of the floating image overlays (edge arrows and the
/// zoom bar). They fade out after a short period of mouse inactivity and come
/// back as soon as the pointer moves over the image.
@MainActor
@Observable
public final class ChromeVisibility {
    public private(set) var isVisible = true

    @ObservationIgnored
    private var isPointerOverControls = false

    @ObservationIgnored
    private var hideTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastActivity = ContinuousClock().now

    @ObservationIgnored
    private var monitorGeneration = 0

    @ObservationIgnored
    private var lastMouseLocation: CGPoint?

    @ObservationIgnored
    private var isPointerInsideImage = false

    private let idleDelay: Duration
    private let tick: Duration

    public init(
        idleDelay: Duration = .seconds(2),
        tick: Duration = .milliseconds(150)
    ) {
        self.idleDelay = idleDelay
        self.tick = tick
    }

    public func mouseMoved(to location: CGPoint) {
        isPointerInsideImage = true
        guard lastMouseLocation != location else { return }
        lastMouseLocation = location
        showTemporarily()
    }

    public func mouseExited() {
        isPointerInsideImage = false
        lastMouseLocation = nil
        hideNow()
    }

    public func showTemporarily() {
        if !isVisible {
            isVisible = true
        }
        lastActivity = ContinuousClock().now
        guard hideTask == nil else { return }
        startMonitor()
    }

    public func pointerEnteredControls() {
        isPointerOverControls = true
        isVisible = true
        cancelMonitor()
    }

    public func pointerExitedControls() {
        isPointerOverControls = false
        if isPointerInsideImage {
            showTemporarily()
        } else {
            hideNow()
        }
    }

    public func hideNow() {
        cancelMonitor()
        if !isPointerOverControls {
            isVisible = false
        }
    }

    private func startMonitor() {
        monitorGeneration += 1
        let generation = monitorGeneration
        let tick = self.tick

        hideTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard let self, generation == self.monitorGeneration else { return }

                if self.isPointerOverControls {
                    continue
                }

                if ContinuousClock().now - self.lastActivity >= self.idleDelay {
                    self.isVisible = false
                    self.hideTask = nil
                    self.monitorGeneration += 1
                    return
                }
            }
        }
    }

    private func cancelMonitor() {
        monitorGeneration += 1
        hideTask?.cancel()
        hideTask = nil
    }
}
