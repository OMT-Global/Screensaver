import QuartzCore

// Drives the CABasicAnimation sequence for one or more sequential flip steps.
// One step: old top flap falls (0 → -π/2) then new bottom flap rises (π/2 → 0).
final class FlipAnimator {

    static let topFallDuration:    CFTimeInterval = 0.075
    static let bottomRiseDuration: CFTimeInterval = 0.065
    static let interStepPause:     CFTimeInterval = 0.018

    // Animate `panel` to `targetChar`, one mechanical step at a time.
    func animateTo(
        _ targetChar: SplitFlapCharacter,
        panel: SplitFlapPanel,
        completion: (() -> Void)? = nil
    ) {
        let steps = panel.currentCharacter.stepsTo(targetChar)
        guard steps > 0 else { completion?(); return }
        runSteps(remaining: steps, panel: panel, completion: completion)
    }

    private func runSteps(
        remaining: Int,
        panel: SplitFlapPanel,
        completion: (() -> Void)?
    ) {
        guard remaining > 0 else { completion?(); return }

        let fromChar = panel.currentCharacter
        let toChar   = fromChar.next
        panel.prepareFlip(fromChar: fromChar, toChar: toChar)

        // Phase 1 — top flap falls
        let topFall = CABasicAnimation(keyPath: "transform.rotation.x")
        topFall.fromValue = 0.0
        topFall.toValue   = -Double.pi / 2
        topFall.duration  = FlipAnimator.topFallDuration
        topFall.beginTime = CACurrentMediaTime()
        topFall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        topFall.fillMode = .forwards
        topFall.isRemovedOnCompletion = false
        panel.topFlapContainer.add(topFall, forKey: "topFall")

        // Phase 2 — bottom flap rises (starts after top flap vanishes)
        let fallDuration = FlipAnimator.topFallDuration
        let riseDuration = FlipAnimator.bottomRiseDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + fallDuration) { [weak panel] in
            guard let panel = panel else { return }
            panel.bottomFlapContainer.isHidden = false

            let bottomRise = CABasicAnimation(keyPath: "transform.rotation.x")
            bottomRise.fromValue = Double.pi / 2
            bottomRise.toValue   = 0.0
            bottomRise.duration  = riseDuration
            bottomRise.beginTime = CACurrentMediaTime()
            bottomRise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bottomRise.fillMode = .forwards
            bottomRise.isRemovedOnCompletion = false
            panel.bottomFlapContainer.add(bottomRise, forKey: "bottomRise")
        }

        // Finalize after both phases
        let stepTotal = fallDuration + riseDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + stepTotal) { [weak panel, weak self] in
            guard let panel = panel, let self = self else { return }
            panel.topFlapContainer.removeAllAnimations()
            panel.bottomFlapContainer.removeAllAnimations()
            panel.finalizeFlip(to: toChar)

            if remaining > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + FlipAnimator.interStepPause) {
                    self.runSteps(remaining: remaining - 1, panel: panel, completion: completion)
                }
            } else {
                completion?()
            }
        }
    }
}
