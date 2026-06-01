import QuartzCore

// Entry point for driving a split-flap flip.
//
// The entire mechanical sequence — every intermediate character and both
// half-flap rotations — is built once as a batch of keyframe animations and
// handed to Core Animation in a single commit (see `SplitFlapPanel.flip`). The
// render server then plays the whole flip with no per-step work on the app's
// main thread; a single completion callback fires when it settles. This keeps
// the screensaver near-idle on the CPU even while hundreds of panels animate.
final class FlipAnimator {

    static let topFallDuration:    CFTimeInterval = 0.075
    static let bottomRiseDuration: CFTimeInterval = 0.065
    static let interStepPause:     CFTimeInterval = 0.018

    /// Animate `panel` to `targetChar`. A future `beginTime` schedules the flip
    /// on the render server (used to stagger the wave sweep); `batchedTransaction`
    /// lets a caller add many panels inside one CATransaction.
    func animateTo(
        _ targetChar: SplitFlapCharacter,
        panel: SplitFlapPanel,
        beginTime: CFTimeInterval? = nil,
        batchedTransaction: Bool = false,
        shouldContinue: @escaping () -> Bool = { true },
        completion: (() -> Void)? = nil
    ) {
        guard shouldContinue() else { completion?(); return }
        panel.flip(
            to: targetChar,
            beginTime: beginTime ?? CACurrentMediaTime(),
            batchedTransaction: batchedTransaction,
            shouldContinue: shouldContinue,
            completion: completion
        )
    }
}
