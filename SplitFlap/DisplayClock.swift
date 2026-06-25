import Foundation
import QuartzCore
import AppKit

private protocol DisplayTicker: AnyObject {
    func invalidate()
}

private final class TimerTicker: DisplayTicker {
    private var timer: Timer?

    init(interval: TimeInterval, onFrame: @escaping (CFTimeInterval) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            onFrame(CACurrentMediaTime())
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}

// Controls *when* and *which* panels flip.
// Three phases cycle automatically:
//   1. Hold        — completed message remains untouched
//   2. Idle shuffle — panels drift to random characters individually
//   3. Wave update  — a left-to-right wave sweeps across all panels
final class DisplayClock: NSObject {

    private weak var grid: CharacterGrid?
    private let animator = FlipAnimator()
    private let contentProvider: SplitFlapContentProvider
    private var configuration: SplitFlapConfiguration
    private let isPreview: Bool

    private var ticker: DisplayTicker?
    private var lastIdleTickTimestamp: CFTimeInterval?
    private var lastClockTickTimestamp: CFTimeInterval?
    private var phase: Phase = .idle
    private var phaseTickCount: Int = 0
    private var isRunning = false

    private enum Phase {
        case hold       // message remains fully visible
        case idle       // random individual flips
        case wave       // coordinated left-to-right wave
    }

    // Tick interval for the idle phase (seconds between random panel checks)
    private let idleTickInterval: TimeInterval = 0.15
    private let maxIdleFlipStartsPerTick: Int = 12
    private let maxActiveIdleFlips: Int = 48
    private var runGeneration: Int = 0
    private let tickerInterval: TimeInterval = 0.1

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

    func showImmediateFrame(advanceMessages: Bool = false) {
        guard let grid else { return }
        applyTargets(
            contentProvider.immediateTargets(
                rows: grid.rows,
                cols: grid.cols,
                preview: isPreview,
                advanceMessages: advanceMessages
            ),
            grid: grid
        )
    }

    // MARK: - Lifecycle

    func start(screen: NSScreen? = NSScreen.main) {
        stop()
        runGeneration += 1
        isRunning = true
        phase = .hold
        phaseTickCount = 0
        lastIdleTickTimestamp = nil
        lastClockTickTimestamp = nil

        ticker = makeTicker(screen: screen)
        if ticker == nil {
            isRunning = false
        }

        showImmediateFrame(advanceMessages: true)
    }

    func stop() {
        runGeneration += 1
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        lastIdleTickTimestamp = nil
        lastClockTickTimestamp = nil
        grid?.allPanelsFlat.forEach { panel in
            if panel.isFlipping {
                panel.cancelFlip()
            }
        }
        phase = .hold
        phaseTickCount = 0
    }

    // MARK: - Tick

    private func makeTicker(screen: NSScreen?) -> DisplayTicker? {
        TimerTicker(interval: tickerInterval) { [weak self] timestamp in
            self?.displayTick(timestamp: timestamp)
        }
    }

    private func displayTick(timestamp: CFTimeInterval) {
        guard isRunning else { return }
        if configuration.displayMode == .clock {
            guard let grid = grid else { return }
            guard let last = lastClockTickTimestamp else {
                lastClockTickTimestamp = timestamp
                return
            }
            guard timestamp - last >= 1 else { return }
            lastClockTickTimestamp = timestamp
            clockTick(grid: grid)
            return
        }

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
        case .hold:
            if phaseTickCount >= holdTickDuration {
                phase = .idle
                phaseTickCount = 0
            }

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
                phase = .hold
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
            let target = SplitFlapCharacter.random(in: configuration.randomAlphabet)
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

    private func clockTick(grid: CharacterGrid) {
        startWave(grid: grid)
    }

    private var holdTickDuration: Int {
        max(0, Int(configuration.messageHoldSeconds / idleTickInterval))
    }

    private var idleTickDuration: Int {
        max(1, Int(configuration.waveIntervalSeconds / idleTickInterval))
    }

    private var waveTickDuration: Int {
        max(20, Int(3 / idleTickInterval))
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
