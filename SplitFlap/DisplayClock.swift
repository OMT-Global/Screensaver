import Foundation
import QuartzCore

// Controls *when* and *which* panels flip.
// Two phases alternate automatically:
//   1. Idle shuffle — panels drift to random characters individually
//   2. Wave update  — a left-to-right wave sweeps across all panels
final class DisplayClock {

    private weak var grid: CharacterGrid?
    private let animator = FlipAnimator()

    private var timer: DispatchSourceTimer?
    private var phase: Phase = .idle
    private var phaseTickCount: Int = 0

    private enum Phase {
        case idle       // random individual flips
        case wave       // coordinated left-to-right wave
    }

    // Tick interval for the idle phase (seconds between random panel checks)
    private let idleTickInterval: TimeInterval = 0.15
    // How many ticks before switching to a wave phase
    private let idleTickDuration: Int = 30
    // How many ticks the wave phase lasts
    private let waveTickDuration: Int = 80

    // Fraction of panels that flip on each idle tick
    private let idleDensity: Double = 0.04

    // MARK: - Init

    init(grid: CharacterGrid) {
        self.grid = grid
    }

    // MARK: - Lifecycle

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.5, repeating: idleTickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Tick

    private func tick() {
        guard let grid = grid else { return }
        phaseTickCount += 1

        switch phase {
        case .idle:
            idleTick(grid: grid)
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
        let all = grid.allPanels()
        guard !all.isEmpty else { return }

        let flipCount = max(1, Int(Double(all.count) * idleDensity))

        // O(k) random selection instead of O(n) shuffle + allocation.
        var selectedIndices = Set<Int>()
        while selectedIndices.count < flipCount {
            selectedIndices.insert(Int.random(in: 0..<all.count))
        }
        let toFlip = selectedIndices.map { all[$0] }

        for panel in toFlip {
            let target = SplitFlapCharacter.random()
            animator.animateTo(target, panel: panel)
        }
    }

    // MARK: - Wave phase

    private func startWave(grid: CharacterGrid) {
        // Choose a random target character for each panel (or fill with a message).
        let targets = buildWaveTargets(grid: grid)

        // Stagger column-by-column by assigning Core Animation begin times in one pass.
        let columnStagger: CFTimeInterval = 0.06
        let maxRowJitter: CFTimeInterval = 0.04
        let baseTime = CACurrentMediaTime()

        for col in 0..<grid.cols {
            let columnOffset = CFTimeInterval(col) * columnStagger

            for row in 0..<grid.rows {
                guard let panel = grid.panel(row: row, col: col) else { continue }

                let rowJitter = CFTimeInterval.random(in: 0...maxRowJitter)
                let beginTime = baseTime + columnOffset + rowJitter
                let target = targets[row][col]
                animator.animateTo(target, panel: panel, beginTime: beginTime)
            }
        }
    }

    private func buildWaveTargets(grid: CharacterGrid) -> [[SplitFlapCharacter]] {
        var targets: [[SplitFlapCharacter]] = []
        for _ in 0..<grid.rows {
            var row: [SplitFlapCharacter] = []
            for _ in 0..<grid.cols {
                row.append(SplitFlapCharacter.random())
            }
            targets.append(row)
        }
        return targets
    }
}
