import ScreenSaver
import QuartzCore
import AppKit

// The principal class loaded by macOS's screensaver engine.
// Registered via NSPrincipalClass in Info.plist.
@objc(SplitFlapView)
final class SplitFlapView: ScreenSaverView {

    private static var activeConfigureSheetController: SplitFlapConfigureSheetController?

    private var grid: CharacterGrid?
    private var clock: DisplayClock?
    private var rootLayer: CALayer!
    private var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var isClockRunning = false
    private var isPreviewInstance = false
    private var configuration = SplitFlapConfigurationStore.load()
    private var configureSheetController: SplitFlapConfigureSheetController?
    private let messageFeedLoader = SplitFlapMessageFeedLoader()
    private var messageFeedRefreshTimer: Timer?

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
        isPreviewInstance = isPreview
        configuration = SplitFlapConfigurationStore.load()

        // CALayer-backed view is required for all CAAnimation to work.
        wantsLayer = true

        rootLayer = CALayer()
        rootLayer.frame = bounds
        rootLayer.backgroundColor = configuration.theme.palette.screenBg
        layer = rootLayer

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0

        let g = CharacterGrid(
            bounds: bounds,
            isPreview: isPreview,
            scale: scale,
            configuration: configuration
        )
        rootLayer.addSublayer(g.containerLayer)
        grid = g

        clock = DisplayClock(grid: g, configuration: configuration, isPreview: isPreview)
        clock?.showImmediateFrame()
        refreshMessageFeedIfNeeded()

        // Do NOT use animateOneFrame() timer — animation is scheduled by
        // DisplayClock and played by Core Animation.
        animationTimeInterval = 60.0  // keep ScreenSaverView's empty framework timer cold
    }

    deinit {
        removeWindowObservers()
        stopMessageFeedRefresh()
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

    // animateOneFrame is called by ScreenSaverView's built-in timer. DisplayClock
    // schedules coarse updates separately, so we have nothing to do here.
    override func animateOneFrame() {}

    // MARK: - Layout

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        rootLayer.frame = bounds
        grid?.rebuild(
            bounds: bounds,
            isPreview: isPreviewInstance,
            scale: scale,
            configuration: configuration
        )
        clock?.showImmediateFrame()
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

    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        if let controller = Self.activeConfigureSheetController {
            return controller.window
        }

        let controller = SplitFlapConfigureSheetController(configuration: configuration) { [weak self] updated in
            if let self {
                self.applyConfiguration(updated)
            } else {
                SplitFlapConfigurationStore.save(updated)
            }
        }
        controller.onClose = {
            Self.activeConfigureSheetController = nil
        }
        configureSheetController = controller
        Self.activeConfigureSheetController = controller
        return controller.window
    }

    private func applyConfiguration(_ updated: SplitFlapConfiguration) {
        configuration = updated
        SplitFlapConfigurationStore.save(updated)
        rootLayer.backgroundColor = updated.theme.palette.screenBg

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        grid?.rebuild(
            bounds: bounds,
            isPreview: isPreviewInstance,
            scale: scale,
            configuration: updated
        )
        clock?.update(configuration: updated)
        clock?.showImmediateFrame()
        refreshMessageFeedIfNeeded()
        updateClockForVisibility(restartIfRunning: true)
    }

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
        guard let window else { return false }
        return window.isVisible
            && !window.isMiniaturized
    }

    private func updateClockForVisibility(restartIfRunning: Bool = false) {
        guard shouldRunClock else {
            stopClock()
            return
        }

        if restartIfRunning || !isClockRunning {
            clock?.start(screen: window?.screen ?? NSScreen.main)
            isClockRunning = true
            refreshMessageFeedIfNeeded()
        }
    }

    private func stopClock() {
        guard isClockRunning else { return }
        clock?.stop()
        isClockRunning = false
    }

    private func refreshMessageFeedIfNeeded() {
        guard configuration.displayMode == .messages,
              configuration.messageSource != .manual
        else {
            stopMessageFeedRefresh()
            return
        }

        messageFeedLoader.load(configuration: configuration) { [weak self] messages in
            self?.applyFetchedMessages(messages)
        }
        scheduleMessageFeedRefresh()
    }

    private func scheduleMessageFeedRefresh() {
        messageFeedRefreshTimer?.invalidate()
        let interval = max(60, configuration.contentRefreshSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshMessageFeedIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        messageFeedRefreshTimer = timer
    }

    private func stopMessageFeedRefresh() {
        messageFeedRefreshTimer?.invalidate()
        messageFeedRefreshTimer = nil
        messageFeedLoader.cancel()
    }

    private func applyFetchedMessages(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        configuration.fetchedMessageText = messages.joined(separator: "\n")
        clock?.update(configuration: configuration)
        clock?.showImmediateFrame()
    }
}
