import ScreenSaver
import QuartzCore
import AppKit

// The principal class loaded by macOS's screensaver engine.
// Registered via NSPrincipalClass = "SplitFlap.SplitFlapView" in Info.plist.
@objc(SplitFlapView)
final class SplitFlapView: ScreenSaverView {

    private var grid: CharacterGrid?
    private var clock: DisplayClock?
    private var rootLayer: CALayer!
    private var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var isClockRunning = false

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup(isPreview: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(isPreview: false)
    }

    private func setup(isPreview: Bool) {
        // CALayer-backed view is required for all CAAnimation to work.
        wantsLayer = true

        rootLayer = CALayer()
        rootLayer.frame = bounds
        rootLayer.backgroundColor = BoardColors.screenBg
        layer = rootLayer

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        let g = CharacterGrid(bounds: bounds, isPreview: isPreview, scale: scale)
        rootLayer.addSublayer(g.containerLayer)
        grid = g

        clock = DisplayClock(grid: g)

        // Do NOT use animateOneFrame() timer — all animation is CAAnimation-driven.
        animationTimeInterval = 60.0  // keep ScreenSaverView's empty framework timer cold
    }

    deinit {
        removeWindowObservers()
        clock?.stop()
    }

    // MARK: - Lifecycle

    override func startAnimation() {
        super.startAnimation()
        updateClockForVisibility()
        DispatchQueue.main.async { [weak self] in
            self?.updateClockForVisibility()
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        stopClock()
    }

    // animateOneFrame is called by ScreenSaverView's built-in timer.
    // All actual animation runs through CABasicAnimation and DisplayClock,
    // so we have nothing to do here.
    override func animateOneFrame() {}

    // MARK: - Layout

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        let isPreview = self.bounds.width < 400
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootLayer.frame = bounds
        grid?.rebuild(bounds: bounds, isPreview: isPreview, scale: scale)
        updateClockForVisibility(restartIfRunning: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeCurrentWindow()
        updateClockForVisibility()
        DispatchQueue.main.async { [weak self] in
            self?.updateClockForVisibility()
        }
    }

    // MARK: - Misc

    override var isOpaque: Bool { true }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    private func observeCurrentWindow() {
        guard observedWindow !== window else { return }
        removeWindowObservers()
        observedWindow = window

        guard let window else { return }
        let center = NotificationCenter.default
        let notifications: [NSNotification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification
        ]

        windowObservers = notifications.map { name in
            center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updateClockForVisibility()
            }
        }
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach { center.removeObserver($0) }
        windowObservers = []
        observedWindow = nil
    }

    private var shouldRunClock: Bool {
        guard isAnimating, let window else { return false }
        return window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }

    private func updateClockForVisibility(restartIfRunning: Bool = false) {
        guard shouldRunClock else {
            stopClock()
            return
        }

        if restartIfRunning || !isClockRunning {
            clock?.start(screen: window?.screen ?? NSScreen.main)
            isClockRunning = true
        }
    }

    private func stopClock() {
        guard isClockRunning else { return }
        clock?.stop()
        isClockRunning = false
    }
}
