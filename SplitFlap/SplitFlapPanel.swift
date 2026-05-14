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

    enum Half: String { case top, bottom }

    private final class GlyphSurface {
        let surface: IOSurface
        init(surface: IOSurface) { self.surface = surface }
    }

    private let cache = NSCache<NSString, GlyphSurface>()

    func contents(
        for character: SplitFlapCharacter,
        panelSize: CGSize,
        scale: CGFloat,
        half: Half
    ) -> Any? {
        let panelW = panelSize.width
        let panelH = panelSize.height
        let halfH = panelH / 2

        let pixelWidth = max(1, Int((panelW * scale).rounded(.up)))
        let pixelHalfHeight = max(1, Int((halfH * scale).rounded(.up)))
        let key = "\(character.rawValue)-\(pixelWidth)x\(pixelHalfHeight)-\(half.rawValue)" as NSString

        if let cached = cache.object(forKey: key) {
            return cached.surface
        }

        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: pixelWidth,
            .height: pixelHalfHeight,
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

        let byteCount = surface.bytesPerRow * pixelHalfHeight
        _ = memset(surface.baseAddress, 0, byteCount)

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: surface.baseAddress,
                  width: pixelWidth,
                  height: pixelHalfHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: surface.bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo.rawValue
              ) else {
            return nil
        }

        context.scaleBy(x: scale, y: scale)
        // Surface represents only the requested half of the panel. Translate so
        // drawing the centered full-panel glyph lands in the correct half; the
        // surface bounds clip the opposite half.
        if half == .top {
            context.translateBy(x: 0, y: -halfH)
        }

        let fontSize = panelH * 0.72
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
            y: floor((panelH - textSize.height) / 2),
            width: panelW,
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
//   staticBottomLayer    — bottom half of new char, always visible
//   staticTopLayer       — top half of old char, always visible
//   bottomFlapContainer  — bottom half of new char, rotates π/2 → 0
//   topFlapContainer     — top half of old char, rotates 0 → -π/2
//   dividerLayer         — 1-pt hairline at seam
//
// Each layer is a half-height tile holding only its half-glyph surface, so the
// panel needs no mask layers and no offscreen compositing. Flap layers are
// anchored at the seam edge so the rotation pivots around the seam.
final class SplitFlapPanel {

    let panelLayer = CALayer()

    // Static layers (never rotate, always visible behind flap layers).
    private let staticTopLayer    = CALayer()
    private let staticBottomLayer = CALayer()

    // Animated flap layers. Kept under their original public names so the
    // animator can drive them by reference.
    let topFlapContainer    = CALayer()
    let bottomFlapContainer = CALayer()

    private let dividerLayer = CALayer()

    private(set) var currentCharacter: SplitFlapCharacter = .space
    private(set) var isFlipping = false

    private var staticTopCharacter: SplitFlapCharacter = .space
    private var staticBottomCharacter: SplitFlapCharacter = .space
    private var topFlapCharacter: SplitFlapCharacter = .space
    private var bottomFlapCharacter: SplitFlapCharacter = .space

    private var w: CGFloat = 0
    private var h: CGFloat = 0
    private var mid: CGFloat = 0
    private var contentsScale: CGFloat = 1

    // MARK: - Setup

    init(size: CGSize, scale: CGFloat) {
        w = size.width
        h = size.height
        mid = size.height / 2
        contentsScale = scale
        buildLayerTree()
        setCharacter(.space, animated: false)
    }

    private func buildLayerTree() {
        panelLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        panelLayer.anchorPoint = CGPoint(x: 0, y: 0)
        panelLayer.backgroundColor = BoardColors.panelBackground
        panelLayer.cornerRadius = 1
        panelLayer.masksToBounds = true

        var persp = CATransform3DIdentity
        persp.m34 = -1.0 / 500.0
        panelLayer.sublayerTransform = persp

        configureHalfLayer(staticTopLayer,    half: .top,    isFlap: false)
        configureHalfLayer(staticBottomLayer, half: .bottom, isFlap: false)
        configureHalfLayer(topFlapContainer,  half: .top,    isFlap: true)
        configureHalfLayer(bottomFlapContainer, half: .bottom, isFlap: true)

        topFlapContainer.isDoubleSided    = false
        bottomFlapContainer.isDoubleSided = false

        dividerLayer.frame = CGRect(x: 0, y: mid - 0.5, width: w, height: 1)
        dividerLayer.backgroundColor = BoardColors.divider

        panelLayer.addSublayer(staticBottomLayer)
        panelLayer.addSublayer(staticTopLayer)
        panelLayer.addSublayer(bottomFlapContainer)
        panelLayer.addSublayer(topFlapContainer)
        panelLayer.addSublayer(dividerLayer)
    }

    private func configureHalfLayer(_ layer: CALayer, half: GlyphImageCache.Half, isFlap: Bool) {
        layer.bounds = CGRect(x: 0, y: 0, width: w, height: mid)
        layer.contentsScale = contentsScale
        layer.contentsGravity = .resize
        layer.backgroundColor = CGColor.clear

        switch (half, isFlap) {
        case (.top, false):
            // Static top half: panel y in [mid, h]; centered anchor.
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position    = CGPoint(x: w / 2, y: mid + mid / 2)
        case (.bottom, false):
            // Static bottom half: panel y in [0, mid].
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position    = CGPoint(x: w / 2, y: mid / 2)
        case (.top, true):
            // Top flap: pivots around its bottom edge (the seam).
            layer.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer.position    = CGPoint(x: w / 2, y: mid)
        case (.bottom, true):
            // Bottom flap: pivots around its top edge (the seam).
            layer.anchorPoint = CGPoint(x: 0.5, y: 1)
            layer.position    = CGPoint(x: w / 2, y: mid)
        }
    }

    // MARK: - Public API

    /// Immediately set a character on all layers without animation.
    func setCharacter(_ char: SplitFlapCharacter, animated: Bool) {
        currentCharacter = char
        isFlipping = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGlyph(char, half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(char, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(char, half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(char, half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        CATransaction.commit()
    }

    func beginFlipping() {
        isFlipping = true
    }

    func cancelFlip() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topFlapContainer.removeAllAnimations()
        bottomFlapContainer.removeAllAnimations()
        applyGlyph(currentCharacter, half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(currentCharacter, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(currentCharacter, half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(currentCharacter, half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        isFlipping = false
        CATransaction.commit()
    }

    /// Resize the existing layer tree without tearing it down.
    func resize(to size: CGSize, scale: CGFloat) {
        w = size.width
        h = size.height
        mid = size.height / 2
        contentsScale = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panelLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        configureHalfLayer(staticTopLayer,      half: .top,    isFlap: false)
        configureHalfLayer(staticBottomLayer,   half: .bottom, isFlap: false)
        configureHalfLayer(topFlapContainer,    half: .top,    isFlap: true)
        configureHalfLayer(bottomFlapContainer, half: .bottom, isFlap: true)
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
        applyGlyph(fromChar, half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(revealStaticBottom ? toChar : fromChar,
                   half: .bottom, to: staticBottomLayer, storedIn: \.staticBottomCharacter)
        applyGlyph(fromChar, half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(toChar,   half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity        // flat, visible
        bottomFlapContainer.transform = CATransform3DMakeRotation(.pi / 2, 1, 0, 0)
        bottomFlapContainer.isHidden  = true  // invisible until top flap finishes
    }

    /// Called after a single flip step completes to snap to the final state.
    func finalizeFlip(to char: SplitFlapCharacter, done: Bool) {
        currentCharacter = char
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGlyph(char, half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(char, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(char, half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(char, half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        if done {
            isFlipping = false
        }
        CATransaction.commit()
    }

    private func applyGlyph(
        _ character: SplitFlapCharacter,
        half: GlyphImageCache.Half,
        to layer: CALayer,
        storedIn keyPath: ReferenceWritableKeyPath<SplitFlapPanel, SplitFlapCharacter>
    ) {
        self[keyPath: keyPath] = character
        layer.contents = GlyphImageCache.shared.contents(
            for: character,
            panelSize: CGSize(width: w, height: h),
            scale: layer.contentsScale,
            half: half
        )
    }

    private func refreshGlyphs() {
        applyGlyph(staticTopCharacter,    half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(staticBottomCharacter, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(topFlapCharacter,      half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(bottomFlapCharacter,   half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
    }
}
