import QuartzCore
import AppKit
import IOSurface
import CoreVideo
import Darwin

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
        half: Half,
        palette: SplitFlapPalette
    ) -> Any? {
        let panelW = panelSize.width
        let panelH = panelSize.height
        let halfH = panelH / 2

        let pixelWidth = max(1, Int((panelW * scale).rounded(.up)))
        let pixelHalfHeight = max(1, Int((halfH * scale).rounded(.up)))
        let key = "\(pixelWidth)x\(pixelHalfHeight):\(half.rawValue):\(palette.identifier):\(character.displayString)" as NSString

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

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let string = character.displayString as NSString
        let color = NSColor(cgColor: palette.character) ?? .systemYellow
        let maxTextWidth = panelW * 0.92
        let maxTextHeight = panelH * 0.86
        var fontSize = max(8, panelH * 0.72)
        var attributes = textAttributes(fontSize: fontSize, color: color, paragraph: paragraph)
        var textSize = string.size(withAttributes: attributes)

        while fontSize > 7 && (textSize.width > maxTextWidth || textSize.height > maxTextHeight) {
            fontSize -= 1
            attributes = textAttributes(fontSize: fontSize, color: color, paragraph: paragraph)
            textSize = string.size(withAttributes: attributes)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

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

    private func textAttributes(
        fontSize: CGFloat,
        color: NSColor,
        paragraph: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }
}

// Fires exactly once when a batched flip animation finishes (or is torn down).
// The guard prevents a re-entrant callback when the panel removes the
// animations from inside the completion handler.
private final class FlipCompletionDelegate: NSObject, CAAnimationDelegate {
    private var didFire = false
    private let handler: (Bool) -> Void

    init(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
        super.init()
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        guard !didFire else { return }
        didFire = true
        handler(finished)
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
    private let palette: SplitFlapPalette

    // MARK: - Setup

    init(size: CGSize, scale: CGFloat, palette: SplitFlapPalette) {
        w = size.width
        h = size.height
        mid = size.height / 2
        contentsScale = scale
        self.palette = palette
        buildLayerTree()
        setCharacter(.space, animated: false)
    }

    private func buildLayerTree() {
        panelLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        panelLayer.anchorPoint = CGPoint(x: 0, y: 0)
        panelLayer.backgroundColor = palette.panelBackground
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
        dividerLayer.backgroundColor = palette.divider

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
        staticTopLayer.removeAllAnimations()
        staticBottomLayer.removeAllAnimations()
        topFlapContainer.removeAllAnimations()
        bottomFlapContainer.removeAllAnimations()
        applyGlyph(currentCharacter, half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(currentCharacter, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(currentCharacter, half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(currentCharacter, half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
        topFlapContainer.transform    = CATransform3DIdentity
        bottomFlapContainer.transform = CATransform3DIdentity
        bottomFlapContainer.isHidden  = false
        bottomFlapContainer.opacity   = 1
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

    /// Animate a full multi-step flip to `target` entirely on the render
    /// server. Every intermediate character and both half-flap rotations are
    /// encoded once as keyframe animations and committed in a single pass, so
    /// no per-step main-thread work runs while the flip plays. A single
    /// completion fires when the whole sequence settles.
    ///
    /// When `beginTime` is in the future the panel keeps showing its current
    /// character (its untouched model state) until then — this is how the wave
    /// sweep staggers without per-panel timers.
    func flip(
        to target: SplitFlapCharacter,
        beginTime: CFTimeInterval,
        batchedTransaction: Bool,
        shouldContinue: @escaping () -> Bool,
        completion: (() -> Void)?
    ) {
        let steps = currentCharacter.stepsTo(target)
        guard steps > 0 else { completion?(); return }
        guard !isFlipping else { completion?(); return }

        // Drum characters keep their mechanical forward sequence. Arbitrary
        // Unicode graphemes are valid targets and resolve as a direct flip.
        let seq = currentCharacter.sequence(to: target)

        // Pre-resolve every glyph half the sequence will show. If any surface
        // is unavailable, fall back to a plain snap so the board still reaches
        // the target character.
        var topGlyphs: [Any] = []       // top halves of seq[0...steps]
        var bottomGlyphs: [Any] = []    // bottom halves of seq[1...steps]
        topGlyphs.reserveCapacity(steps + 1)
        bottomGlyphs.reserveCapacity(steps)
        for (index, character) in seq.enumerated() {
            guard let top = glyph(character, .top) else {
                setCharacter(target, animated: false); completion?(); return
            }
            topGlyphs.append(top)
            if index > 0 {
                guard let bottom = glyph(character, .bottom) else {
                    setCharacter(target, animated: false); completion?(); return
                }
                bottomGlyphs.append(bottom)
            }
        }

        beginFlipping()

        let fall  = FlipAnimator.topFallDuration
        let rise  = FlipAnimator.bottomRiseDuration
        let pause = FlipAnimator.interStepPause
        let span  = fall + rise + pause            // one mechanical step
        let total = Double(steps) * span
        let kFall = fall / span                     // fraction of a step spent falling
        let kRise = (fall + rise) / span            // fraction elapsed once risen

        let easeIn  = CAMediaTimingFunction(name: .easeIn)
        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let linear  = CAMediaTimingFunction(name: .linear)

        // Top flap: falls 0 -> -90deg (revealing the new top behind it), then
        // stays folded/edge-on; the per-step jump back to flat is invisible
        // because the static top already shows the settled character.
        let topRotation = CAKeyframeAnimation(keyPath: "transform.rotation.x")
        topRotation.values = [0.0, -Double.pi / 2, -Double.pi / 2, -Double.pi / 2].map { NSNumber(value: $0) }
        topRotation.keyTimes = [0.0, kFall, kRise, 1.0].map { NSNumber(value: $0) }
        topRotation.timingFunctions = [easeIn, linear, linear]
        topRotation.duration = span
        topRotation.repeatCount = Float(steps)

        // Bottom flap: stays folded during the fall, then rises 90deg -> flat.
        let bottomRotation = CAKeyframeAnimation(keyPath: "transform.rotation.x")
        bottomRotation.values = [Double.pi / 2, Double.pi / 2, 0.0, 0.0].map { NSNumber(value: $0) }
        bottomRotation.keyTimes = [0.0, kFall, kRise, 1.0].map { NSNumber(value: $0) }
        bottomRotation.timingFunctions = [linear, easeOut, linear]
        bottomRotation.duration = span
        bottomRotation.repeatCount = Float(steps)

        // Bottom flap is invisible while folded (during the fall) and visible as
        // it rises — reproducing the old per-step isHidden toggle with no timer.
        // Discrete keyTimes need one more entry than values.
        let bottomOpacity = CAKeyframeAnimation(keyPath: "opacity")
        bottomOpacity.values = [0.0, 1.0].map { NSNumber(value: $0) }
        bottomOpacity.keyTimes = [0.0, kFall, 1.0].map { NSNumber(value: $0) }
        bottomOpacity.calculationMode = .discrete
        bottomOpacity.duration = span
        bottomOpacity.repeatCount = Float(steps)

        // Glyph tracks span the whole flip. Top halves advance one character as
        // each step settles (after the rise); bottom halves show the incoming
        // character for the full step. Discrete mode => keyTimes = values + 1.
        var topKeyTimes: [NSNumber] = [NSNumber(value: 0)]
        topKeyTimes.reserveCapacity(steps + 2)
        for i in 0..<steps {
            topKeyTimes.append(NSNumber(value: (Double(i) * span + fall + rise) / total))
        }
        topKeyTimes.append(NSNumber(value: 1))

        var bottomKeyTimes: [NSNumber] = [NSNumber(value: 0)]
        bottomKeyTimes.reserveCapacity(steps + 1)
        for i in 1..<steps {
            bottomKeyTimes.append(NSNumber(value: Double(i) * span / total))
        }
        bottomKeyTimes.append(NSNumber(value: 1))

        func glyphTrack(_ values: [Any], _ keyTimes: [NSNumber]) -> CAKeyframeAnimation {
            let track = CAKeyframeAnimation(keyPath: "contents")
            track.values = values
            track.keyTimes = keyTimes
            track.calculationMode = .discrete
            track.duration = total
            return track
        }

        // The top-flap glyph track spans the full duration and anchors the
        // single completion callback for the whole flip.
        let topFlapTrack = glyphTrack(topGlyphs, topKeyTimes)
        topFlapTrack.delegate = FlipCompletionDelegate { [weak self] finished in
            guard let self = self else { return }
            guard finished, shouldContinue() else { completion?(); return }
            self.concludeFlip(to: target)
            completion?()
        }

        let tracks: [(CALayer, String, CAKeyframeAnimation)] = [
            (staticTopLayer,      "flipTopGlyph",    glyphTrack(topGlyphs, topKeyTimes)),
            (staticBottomLayer,   "flipBottomGlyph", glyphTrack(bottomGlyphs, bottomKeyTimes)),
            (topFlapContainer,    "flipRotation",    topRotation),
            (topFlapContainer,    "flipTopGlyph",    topFlapTrack),
            (bottomFlapContainer, "flipRotation",    bottomRotation),
            (bottomFlapContainer, "flipOpacity",     bottomOpacity),
            (bottomFlapContainer, "flipBottomGlyph", glyphTrack(bottomGlyphs, bottomKeyTimes)),
        ]

        if !batchedTransaction {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        for (layer, key, anim) in tracks {
            anim.beginTime = beginTime
            anim.fillMode = .forwards           // hold the settled state until concludeFlip
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: key)
        }
        if !batchedTransaction {
            CATransaction.commit()
        }
    }

    private func glyph(_ character: SplitFlapCharacter, _ half: GlyphImageCache.Half) -> Any? {
        GlyphImageCache.shared.contents(
            for: character,
            panelSize: CGSize(width: w, height: h),
            scale: contentsScale,
            half: half,
            palette: palette
        )
    }

    /// Settle the panel onto its final character and drop the flip animations
    /// in one transaction so the presentation never flickers back to the model.
    private func concludeFlip(to char: SplitFlapCharacter) {
        staticTopLayer.removeAllAnimations()
        staticBottomLayer.removeAllAnimations()
        topFlapContainer.removeAllAnimations()
        bottomFlapContainer.removeAllAnimations()
        finalizeFlip(to: char, done: true)
    }

    /// Snap the panel's model state to its final character. Called once when a
    /// flip settles (and reused to reset state elsewhere).
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
        bottomFlapContainer.opacity   = 1
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
            half: half,
            palette: palette
        )
    }

    private func refreshGlyphs() {
        applyGlyph(staticTopCharacter,    half: .top,    to: staticTopLayer,      storedIn: \.staticTopCharacter)
        applyGlyph(staticBottomCharacter, half: .bottom, to: staticBottomLayer,   storedIn: \.staticBottomCharacter)
        applyGlyph(topFlapCharacter,      half: .top,    to: topFlapContainer,    storedIn: \.topFlapCharacter)
        applyGlyph(bottomFlapCharacter,   half: .bottom, to: bottomFlapContainer, storedIn: \.bottomFlapCharacter)
    }
}
