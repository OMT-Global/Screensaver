import QuartzCore
import AppKit
import IOSurface
import CoreVideo
import Darwin

// Colors matching a classic Solari board.
enum BoardColors {
    static let panelBackground = CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0)
    static let character       = CGColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1.0)
    static let divider         = CGColor(red: 0.01, green: 0.01, blue: 0.02, alpha: 1.0)
    static let screenBg        = CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)
}

private final class GlyphImageCache {
    static let shared = GlyphImageCache()

    private final class GlyphSurface {
        let surface: IOSurface

        init(surface: IOSurface) {
            self.surface = surface
        }
    }

    private let cache = NSCache<NSString, GlyphSurface>()

    func contents(for character: SplitFlapCharacter, size: CGSize, scale: CGFloat) -> Any? {
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        let key = "\(character.rawValue)-\(pixelWidth)x\(pixelHeight)" as NSString

        if let cached = cache.object(forKey: key) {
            return cached.surface
        }

        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: pixelWidth,
            .height: pixelHeight,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        guard let surface = IOSurface(properties: properties) else {
            return nil
        }

        guard surface.lock(options: [], seed: nil) == KERN_SUCCESS else {
            return nil
        }
        defer {
            _ = surface.unlock(options: [], seed: nil)
        }

        let byteCount = surface.bytesPerRow * pixelHeight
        _ = memset(surface.baseAddress, 0, byteCount)

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: surface.baseAddress,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: surface.bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo.rawValue
              ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)

        let fontSize = size.height * 0.72
        let font = NSFont(name: "SFMono-Regular", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let color = NSColor(cgColor: BoardColors.character) ?? .systemYellow
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let string = character.displayString as NSString
        let textSize = string.size(withAttributes: attributes)
        let drawRect = CGRect(
            x: 0,
            y: floor((size.height - textSize.height) / 2),
            width: size.width,
            height: ceil(textSize.height)
        )
        string.draw(in: drawRect, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        let glyphSurface = GlyphSurface(surface: surface)
        cache.setObject(glyphSurface, forKey: key)
        return surface
    }
}

// A single character cell in the split-flap grid.
//
// Layer hierarchy (back → front inside panelLayer):
//   staticBottomContainer  — new char, bottom-half mask, always visible
//   staticTopContainer     — old char, top-half mask, always visible
//   bottomFlapContainer    — new char, bottom-half mask, rotates π/2→0
//   topFlapContainer       — old char, top-half mask, rotates 0→-π/2
//   dividerLayer           — 1-pt hairline at seam
//
// Each *Container layer spans the FULL panel bounds (w×h).
// A CAShapeLayer mask on each container clips it to show only the top or bottom half.
// All text layers are also full-size (w×h), so text positioning is trivial — just y=0.
// The anchor point for animated containers is set to the seam for correct rotation.
final class SplitFlapPanel {

    let panelLayer = CALayer()

    // Static layers (never rotate, always visible behind flap layers)
    private let staticTopContainer    = CALayer()
    private let staticBottomContainer = CALayer()

    // Animated flap layers
    let topFlapContainer    = CALayer()
    let bottomFlapContainer = CALayer()

    private let dividerLayer = CALayer()

    // Cached glyph bitmap layers inside each container.
    private let staticTopText    = CALayer()
    private let staticBottomText = CALayer()
    let topFlapText    = CALayer()
    let bottomFlapText = CALayer()

    private(set) var currentCharacter: SplitFlapCharacter = .space
    private(set) var isFlipping = false

    private var staticTopCharacter: SplitFlapCharacter = .space
    private var staticBottomCharacter: SplitFlapCharacter = .space
    private var topFlapCharacter: SplitFlapCharacter = .space
    private var bottomFlapCharacter: SplitFlapCharacter = .space

    private var w: CGFloat = 0
    private var h: CGFloat = 0
    private var mid: CGFloat = 0

    // MARK: - Setup

    init(size: CGSize, scale: CGFloat) {
        w = size.width
        h = size.height
        mid = size.height / 2
        buildLayerTree(scale: scale)
        setCharacter(.space, animated: false)
    }

    private func buildLayerTree(scale: CGFloat) {
        // Root panel
        panelLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        panelLayer.anchorPoint = CGPoint(x: 0, y: 0)
        panelLayer.backgroundColor = BoardColors.panelBackground
        panelLayer.cornerRadius = 1
        panelLayer.masksToBounds = true
        panelLayer.shouldRasterize = true
        panelLayer.rasterizationScale = scale

        // Perspective applied to all sub-layers
        var persp = CATransform3DIdentity
        persp.m34 = -1.0 / 500.0
        panelLayer.sublayerTransform = persp

        let fullFrame = CGRect(x: 0, y: 0, width: w, height: h)

        // --- Static top (shows current char, top half) ---
        setupContainer(staticTopContainer,
                       textLayer: staticTopText,
                       frame: fullFrame,
                       scale: scale,
                       showTop: true,
                       anchorAtSeam: false)

        // --- Static bottom (shows next char, bottom half) ---
        setupContainer(staticBottomContainer,
                       textLayer: staticBottomText,
                       frame: fullFrame,
                       scale: scale,
                       showTop: false,
                       anchorAtSeam: false)

        // --- Top flap (animates 0 → -π/2) ---
        setupContainer(topFlapContainer,
                       textLayer: topFlapText,
                       frame: fullFrame,
                       scale: scale,
                       showTop: true,
                       anchorAtSeam: true)  // pivot at seam
        topFlapContainer.isDoubleSided = false

        // --- Bottom flap (animates π/2 → 0) ---
        setupContainer(bottomFlapContainer,
                       textLayer: bottomFlapText,
                       frame: fullFrame,
                       scale: scale,
                       showTop: false,
                       anchorAtSeam: true)  // pivot at seam
        bottomFlapContainer.isDoubleSided = false

        // --- Hairline divider ---
        dividerLayer.frame = CGRect(x: 0, y: mid - 0.5, width: w, height: 1)
        dividerLayer.backgroundColor = BoardColors.divider

        // Add in back-to-front order
        panelLayer.addSublayer(staticBottomContainer)
        panelLayer.addSublayer(staticTopContainer)
        panelLayer.addSublayer(bottomFlapContainer)
        panelLayer.addSublayer(topFlapContainer)
        panelLayer.addSublayer(dividerLayer)
    }

    private func setupContainer(
        _ container: CALayer,
        textLayer: CALayer,
        frame: CGRect,
        scale: CGFloat,
        showTop: Bool,
        anchorAtSeam: Bool
    ) {
        container.bounds = frame
        container.backgroundColor = CGColor.clear

        if anchorAtSeam {
            // Anchor at the seam so rotation pivots around the seam line.
            // anchorPoint.y = mid/h (seam fraction from bottom).
            // position = (w/2, mid) so anchor sits at the seam in panel space.
            container.anchorPoint = CGPoint(x: 0.5, y: mid / h)
            container.position = CGPoint(x: w / 2, y: mid)
        } else {
            // Centered (default); frame will be set directly below.
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            container.position = CGPoint(x: w / 2, y: h / 2)
        }

        // Mask to show only top or bottom half
        let maskLayer = CAShapeLayer()
        if showTop {
            maskLayer.path = CGPath(rect: CGRect(x: 0, y: mid, width: w, height: mid), transform: nil)
        } else {
            maskLayer.path = CGPath(rect: CGRect(x: 0, y: 0, width: w, height: mid), transform: nil)
        }
        container.mask = maskLayer

        textLayer.frame = frame
        textLayer.contentsScale = scale
        textLayer.contentsGravity = .resize
        textLayer.backgroundColor = CGColor.clear

        container.addSublayer(textLayer)
    }

    // MARK: - Public API

    /// Immediately set a character on all layers without animation.
    func setCharacter(_ char: SplitFlapCharacter, animated: Bool) {
        currentCharacter = char
        isFlipping = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGlyph(char, to: staticTopText, storedIn: \.staticTopCharacter)
        applyGlyph(char, to: staticBottomText, storedIn: \.staticBottomCharacter)
        applyGlyph(char, to: topFlapText, storedIn: \.topFlapCharacter)
        applyGlyph(char, to: bottomFlapText, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        panelLayer.shouldRasterize    = true
        CATransaction.commit()
    }

    func beginFlipping() {
        isFlipping = true
        panelLayer.shouldRasterize = false
    }

    func cancelFlip() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topFlapContainer.removeAllAnimations()
        bottomFlapContainer.removeAllAnimations()
        applyGlyph(currentCharacter, to: staticTopText, storedIn: \.staticTopCharacter)
        applyGlyph(currentCharacter, to: staticBottomText, storedIn: \.staticBottomCharacter)
        applyGlyph(currentCharacter, to: topFlapText, storedIn: \.topFlapCharacter)
        applyGlyph(currentCharacter, to: bottomFlapText, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden = false
        isFlipping = false
        panelLayer.shouldRasterize = true
        CATransaction.commit()
    }

    /// Resize the existing layer tree without tearing it down.
    func resize(to size: CGSize, scale: CGFloat) {
        w = size.width
        h = size.height
        mid = size.height / 2

        let fullFrame = CGRect(x: 0, y: 0, width: w, height: h)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panelLayer.bounds = fullFrame
        panelLayer.rasterizationScale = scale
        updateContainer(staticTopContainer,
                        textLayer: staticTopText,
                        frame: fullFrame,
                        scale: scale,
                        showTop: true,
                        anchorAtSeam: false)
        updateContainer(staticBottomContainer,
                        textLayer: staticBottomText,
                        frame: fullFrame,
                        scale: scale,
                        showTop: false,
                        anchorAtSeam: false)
        updateContainer(topFlapContainer,
                        textLayer: topFlapText,
                        frame: fullFrame,
                        scale: scale,
                        showTop: true,
                        anchorAtSeam: true)
        updateContainer(bottomFlapContainer,
                        textLayer: bottomFlapText,
                        frame: fullFrame,
                        scale: scale,
                        showTop: false,
                        anchorAtSeam: true)
        dividerLayer.frame = CGRect(x: 0, y: mid - 0.5, width: w, height: 1)
        refreshGlyphs()
        CATransaction.commit()
    }

    /// Configure layers for the start of a single flip step.
    func prepareFlip(
        fromChar: SplitFlapCharacter,
        toChar: SplitFlapCharacter,
        revealStaticBottom: Bool = true,
        batchedTransaction: Bool = false
    ) {
        if batchedTransaction {
            applyPreparedFlipState(fromChar: fromChar, toChar: toChar, revealStaticBottom: revealStaticBottom)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyPreparedFlipState(fromChar: fromChar, toChar: toChar, revealStaticBottom: revealStaticBottom)
        CATransaction.commit()
    }

    private func applyPreparedFlipState(
        fromChar: SplitFlapCharacter,
        toChar: SplitFlapCharacter,
        revealStaticBottom: Bool
    ) {
        applyGlyph(fromChar, to: staticTopText, storedIn: \.staticTopCharacter)
        applyGlyph(revealStaticBottom ? toChar : fromChar, to: staticBottomText, storedIn: \.staticBottomCharacter)
        applyGlyph(fromChar, to: topFlapText, storedIn: \.topFlapCharacter)
        applyGlyph(toChar, to: bottomFlapText, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity        // flat, visible
        bottomFlapContainer.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
        bottomFlapContainer.isHidden  = true  // invisible until top flap finishes
    }

    /// Called after a single flip step completes to snap to the final state.
    func finalizeFlip(to char: SplitFlapCharacter, done: Bool) {
        currentCharacter = char
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGlyph(char, to: staticTopText, storedIn: \.staticTopCharacter)
        applyGlyph(char, to: staticBottomText, storedIn: \.staticBottomCharacter)
        applyGlyph(char, to: topFlapText, storedIn: \.topFlapCharacter)
        applyGlyph(char, to: bottomFlapText, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        if done {
            isFlipping = false
            panelLayer.shouldRasterize = true
        }
        CATransaction.commit()
    }

    private func applyGlyph(
        _ character: SplitFlapCharacter,
        to layer: CALayer,
        storedIn keyPath: ReferenceWritableKeyPath<SplitFlapPanel, SplitFlapCharacter>
    ) {
        self[keyPath: keyPath] = character
        layer.contents = GlyphImageCache.shared.contents(
            for: character,
            size: CGSize(width: w, height: h),
            scale: layer.contentsScale
        )
    }

    private func refreshGlyphs() {
        applyGlyph(staticTopCharacter, to: staticTopText, storedIn: \.staticTopCharacter)
        applyGlyph(staticBottomCharacter, to: staticBottomText, storedIn: \.staticBottomCharacter)
        applyGlyph(topFlapCharacter, to: topFlapText, storedIn: \.topFlapCharacter)
        applyGlyph(bottomFlapCharacter, to: bottomFlapText, storedIn: \.bottomFlapCharacter)
    }

    private func updateContainer(
        _ container: CALayer,
        textLayer: CALayer,
        frame: CGRect,
        scale: CGFloat,
        showTop: Bool,
        anchorAtSeam: Bool
    ) {
        container.bounds = frame

        if anchorAtSeam {
            container.anchorPoint = CGPoint(x: 0.5, y: mid / h)
            container.position = CGPoint(x: w / 2, y: mid)
        } else {
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            container.position = CGPoint(x: w / 2, y: h / 2)
        }

        if let maskLayer = container.mask as? CAShapeLayer {
            if showTop {
                maskLayer.path = CGPath(rect: CGRect(x: 0, y: mid, width: w, height: mid), transform: nil)
            } else {
                maskLayer.path = CGPath(rect: CGRect(x: 0, y: 0, width: w, height: mid), transform: nil)
            }
        }

        textLayer.frame = frame
        textLayer.contentsScale = scale
        textLayer.contentsGravity = .resize
        textLayer.backgroundColor = CGColor.clear
    }
}
