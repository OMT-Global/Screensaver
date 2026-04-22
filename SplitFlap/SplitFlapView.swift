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
        animationTimeInterval = 1.0 / 30.0  // satisfies framework requirement; effectively unused
    }

    // MARK: - Lifecycle

    override func startAnimation() {
        super.startAnimation()
        clock?.start(screen: window?.screen ?? NSScreen.main)
    }

    override func stopAnimation() {
        super.stopAnimation()
        clock?.stop()
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
        if isAnimating {
            clock?.start(screen: window?.screen ?? NSScreen.main)
        }
    }

    // MARK: - Misc

    override var isOpaque: Bool { true }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
