import Foundation
import QuartzCore
import AppKit
import CoreVideo

private protocol DisplayTicker: AnyObject {
    func invalidate()
}

@available(macOS 14.0, *)
private final class CADisplayTicker: NSObject, DisplayTicker {
    private var link: CADisplayLink?
    private var isInvalidated = false
    private let onFrame: (CFTimeInterval) -> Void

    init?(screen: NSScreen?, onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame
        super.init()

        guard let link = (screen ?? NSScreen.main)?.displayLink(
            target: self,
            selector: #selector(tick(_:))
        ) else {
            return nil
        }
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 6,
            maximum: 15,
            preferred: 10
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func invalidate() {
        isInvalidated = true
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !isInvalidated else { return }
        onFrame(link.targetTimestamp > 0 ? link.targetTimestamp : link.timestamp)
    }
}

private final class CVDisplayTicker: DisplayTicker {
    private var link: CVDisplayLink?
    private var isInvalidated = false
    private let onFrame: (CFTimeInterval) -> Void

    init?(onFrame: @escaping (CFTimeInterval) -> Void) {
        self.onFrame = onFrame

        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
              let createdLink = link else {
            return nil
        }

        self.link = createdLink
        let context = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(createdLink, { _, now, _, _, _, context in
            guard let context else { return kCVReturnSuccess }
            let ticker = Unmanaged<CVDisplayTicker>.fromOpaque(context).takeUnretainedValue()
            let scale = now.pointee.videoTimeScale
            let timestamp: CFTimeInterval
            if scale > 0 {
                timestamp = CFTimeInterval(now.pointee.videoTime) / CFTimeInterval(scale)
            } else {
                timestamp = CACurrentMediaTime()
            }
            DispatchQueue.main.async { [weak ticker] in
                guard let ticker, !ticker.isInvalidated else { return }
                ticker.onFrame(timestamp)
            }
            return kCVReturnSuccess
        }, context)
        CVDisplayLinkStart(createdLink)
    }

    func invalidate() {
        isInvalidated = true
        if let link {
            CVDisplayLinkStop(link)
        }
        link = nil
    }

    deinit {
        invalidate()
    }
}

// Controls *when* and *which* panels flip.
// Two phases alternate automatically:
//   1. Idle shuffle — panels drift to random characters individually
//   2. Wave update  — a left-to-right wave sweeps across all panels
final class DisplayClock: NSObject {

    private weak var grid: CharacterGrid?
    private let animator = FlipAnimator()
    private let contentProvider: SplitFlapContentProvider
    private var configuration: SplitFlapConfiguration
    private let isPreview: Bool

    private var ticker: DisplayTicker?
    private var lastIdleTickTimestamp: CFTimeInterval?
    private var phase: Phase = .idle
    private var phaseTickCount: Int = 0
    private var isRunning = false

    private enum Phase {
        case idle       // random individual flips
        case wave       // coordinated left-to-right wave
    }

    // Tick interval for the idle phase (seconds between random panel checks)
    private let idleTickInterval: TimeInterval = 0.15
    private let maxIdleFlipStartsPerTick: Int = 12
    private let maxActiveIdleFlips: Int = 48
    private var runGeneration: Int = 0

    // MARK: - Init

    init(grid: CharacterGrid, configuration: SplitFlapConfiguration, isPreview: Bool) {
        self.grid = grid
        self.configuration = configuration
        self.contentProvider = SplitFlapContentProvider(configuration: configuration)
        self.isPreview = isPreview
        super.init()
    }

    func update(configuration: SplitFlapConfiguration) {
        self.configuration = configuration
        contentProvider.update(configuration: configuration)
    }

    // MARK: - Lifecycle

    func start(screen: NSScreen? = NSScreen.main) {
        stop()
        runGeneration += 1
        isRunning = true
        phase = .idle
        phaseTickCount = 0
        lastIdleTickTimestamp = nil

        ticker = makeTicker(screen: screen)
        if ticker == nil {
            isRunning = false
        }

        if isPreview, let grid {
            applyTargets(contentProvider.nextTargets(rows: grid.rows, cols: grid.cols, preview: true), grid: grid)
        } else if configuration.displayMode != .random, let grid {
            startWave(grid: grid)
        }
    }

    func stop() {
        runGeneration += 1
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        lastIdleTickTimestamp = nil
        grid?.allPanelsFlat.forEach { panel in
            if panel.isFlipping {
                panel.cancelFlip()
            }
        }
        phase = .idle
        phaseTickCount = 0
    }

    // MARK: - Tick

    private func makeTicker(screen: NSScreen?) -> DisplayTicker? {
        if #available(macOS 14.0, *) {
            return CADisplayTicker(screen: screen) { [weak self] timestamp in
                self?.displayTick(timestamp: timestamp)
            }
        }

        return CVDisplayTicker { [weak self] timestamp in
            self?.displayTick(timestamp: timestamp)
        }
    }

    private func displayTick(timestamp: CFTimeInterval) {
        guard isRunning else { return }
        guard let last = lastIdleTickTimestamp else {
            lastIdleTickTimestamp = timestamp
            return
        }

        guard timestamp - last >= idleTickInterval else { return }
        lastIdleTickTimestamp = timestamp
        tick()
    }

    private func tick() {
        guard let grid = grid else { return }
        phaseTickCount += 1

        switch phase {
        case .idle:
            if configuration.idleShuffleEnabled {
                idleTick(grid: grid)
            }
            if phaseTickCount >= idleTickDuration {
                phase = .wave
                phaseTickCount = 0
                startWave(grid: grid)
            }

        case .wave:
            // Wave animation timing is encoded in each panel's animation beginTime.
            // We just count ticks to know when to return to idle.
            if phaseTickCount >= waveTickDuration {
                phase = .idle
                phaseTickCount = 0
            }
        }
    }

    // MARK: - Idle phase

    private func idleTick(grid: CharacterGrid) {
        let all = grid.allPanelsFlat
        guard !all.isEmpty else { return }

        let activeCount = all.reduce(0) { $0 + ($1.isFlipping ? 1 : 0) }
        let activeBudget = maxActiveIdleFlips - activeCount
        guard activeBudget > 0 else { return }
        guard configuration.idleDensity > 0 else { return }

        let requestedCount = max(1, Int(Double(all.count) * configuration.idleDensity))
        let flipCount = min(requestedCount, maxIdleFlipStartsPerTick, activeBudget, all.count)
        let generation = runGeneration

        // O(k) random selection instead of O(n) shuffle + allocation.
        var selectedIndices = Set<Int>()
        var started = 0
        var attempts = 0
        let maxAttempts = all.count * 2

        // Add every flip started this tick inside one transaction so the tick
        // produces a single render-server commit instead of one per panel.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while started < flipCount && attempts < maxAttempts {
            attempts += 1
            let index = Int.random(in: 0..<all.count)
            guard selectedIndices.insert(index).inserted else { continue }

            let panel = all[index]
            guard !panel.isFlipping else { continue }
            let target = SplitFlapCharacter.random()
            guard panel.currentCharacter != target else { continue }
            animator.animateTo(
                target,
                panel: panel,
                batchedTransaction: true,
                shouldContinue: { [weak self] in self?.isCurrentGeneration(generation) ?? false }
            )
            started += 1
        }
        CATransaction.commit()
    }

    // MARK: - Wave phase

    private func startWave(grid: CharacterGrid) {
        let targets = contentProvider.nextTargets(rows: grid.rows, cols: grid.cols)
        let generation = runGeneration

        // Stagger column-by-column by assigning Core Animation begin times in one pass.
        let columnStagger: CFTimeInterval = 0.06
        let maxRowJitter: CFTimeInterval = 0.04
        let baseTime = CACurrentMediaTime()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for col in 0..<grid.cols {
            let columnOffset = CFTimeInterval(col) * columnStagger

            for row in 0..<grid.rows {
                guard let panel = grid.panel(row: row, col: col) else { continue }

                let rowJitter = CFTimeInterval.random(in: 0...maxRowJitter)
                let beginTime = baseTime + columnOffset + rowJitter
                let target = targets[row][col]
                guard panel.currentCharacter != target else { continue }
                animator.animateTo(
                    target,
                    panel: panel,
                    beginTime: beginTime,
                    batchedTransaction: true,
                    shouldContinue: { [weak self] in self?.isCurrentGeneration(generation) ?? false }
                )
            }
        }
    }

    private var idleTickDuration: Int {
        max(1, Int(configuration.waveIntervalSeconds / idleTickInterval))
    }

    private var waveTickDuration: Int {
        max(20, idleTickDuration / 2)
    }

    private func applyTargets(_ targets: [[SplitFlapCharacter]], grid: CharacterGrid) {
        for row in 0..<min(grid.rows, targets.count) {
            for col in 0..<min(grid.cols, targets[row].count) {
                grid.panel(row: row, col: col)?.setCharacter(targets[row][col], animated: false)
            }
        }
    }

    private func isCurrentGeneration(_ generation: Int) -> Bool {
        runGeneration == generation
    }
}
