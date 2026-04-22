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
        beginTime: CFTimeInterval? = nil,
        batchedTransaction: Bool = false,
        shouldContinue: @escaping () -> Bool = { true },
        completion: (() -> Void)? = nil
    ) {
        guard shouldContinue() else { completion?(); return }

        let steps = panel.currentCharacter.stepsTo(targetChar)
        guard steps > 0 else { completion?(); return }
        guard !panel.isFlipping else { completion?(); return }

        panel.beginFlipping()
        runSteps(
            remaining: steps,
            panel: panel,
            beginTime: beginTime ?? CACurrentMediaTime(),
            batchedTransaction: batchedTransaction,
            shouldContinue: shouldContinue,
            completion: completion
        )
    }

    private func runSteps(
        remaining: Int,
        panel: SplitFlapPanel,
        beginTime: CFTimeInterval,
        batchedTransaction: Bool,
        shouldContinue: @escaping () -> Bool,
        completion: (() -> Void)?
    ) {
        guard shouldContinue() else {
            panel.cancelFlip()
            completion?()
            return
        }

        guard remaining > 0 else { completion?(); return }

        let fromChar = panel.currentCharacter
        let toChar   = fromChar.next
        let startsImmediately = beginTime <= CACurrentMediaTime()
        panel.prepareFlip(
            fromChar: fromChar,
            toChar: toChar,
            revealStaticBottom: startsImmediately,
            batchedTransaction: batchedTransaction
        )

        let fallDuration = FlipAnimator.topFallDuration
        let riseDuration = FlipAnimator.bottomRiseDuration

        // Phase 1 — top flap falls
        let topFall = CABasicAnimation(keyPath: "transform.rotation.x")
        topFall.fromValue = 0.0
        topFall.toValue   = -Double.pi / 2
        topFall.duration  = fallDuration
        topFall.beginTime = beginTime
        topFall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        topFall.fillMode = .forwards
        topFall.isRemovedOnCompletion = false

        // Phase 2 — bottom flap rises after the top flap finishes.
        let bottomRise = CABasicAnimation(keyPath: "transform.rotation.x")
        bottomRise.fromValue = Double.pi / 2
        bottomRise.toValue   = 0.0
        bottomRise.duration  = riseDuration
        bottomRise.beginTime = beginTime + fallDuration
        bottomRise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bottomRise.fillMode = .forwards
        bottomRise.isRemovedOnCompletion = false

        panel.topFlapContainer.add(topFall, forKey: "topFall")

        let bottomRevealDelay = max(0, beginTime + fallDuration - CACurrentMediaTime())
        DispatchQueue.main.asyncAfter(deadline: .now() + bottomRevealDelay) { [weak panel] in
            guard let panel = panel else { return }
            guard shouldContinue() else {
                panel.cancelFlip()
                completion?()
                return
            }
            panel.bottomFlapContainer.isHidden = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak panel, weak self] in
                guard let panel = panel, let self = self else { return }
                guard shouldContinue() else {
                    panel.cancelFlip()
                    completion?()
                    return
                }
                panel.topFlapContainer.removeAllAnimations()
                panel.bottomFlapContainer.removeAllAnimations()
                panel.finalizeFlip(to: toChar, done: remaining <= 1)

                if remaining > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + FlipAnimator.interStepPause) {
                        self.runSteps(
                            remaining: remaining - 1,
                            panel: panel,
                            beginTime: CACurrentMediaTime(),
                            batchedTransaction: false,
                            shouldContinue: shouldContinue,
                            completion: completion
                        )
                    }
                } else {
                    completion?()
                }
            }

            panel.bottomFlapContainer.add(bottomRise, forKey: "bottomRise")
            CATransaction.commit()
        }
    }
}
