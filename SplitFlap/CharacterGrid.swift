import QuartzCore
import AppKit

// Manages the 2-D grid of SplitFlapPanel cells and their layout inside a root layer.
final class CharacterGrid {
    private struct LayoutMetrics {
        let bounds: CGRect
        let panelSize: CGSize
        let rows: Int
        let cols: Int
        let originX: CGFloat
        let originY: CGFloat

        func canReusePanelFrames(from previous: LayoutMetrics) -> Bool {
            rows == previous.rows && cols == previous.cols && panelSize == previous.panelSize
        }
    }

    private(set) var panels: [[SplitFlapPanel]] = []
    private(set) var rows: Int = 0
    private(set) var cols: Int = 0
    private(set) var allPanelsFlat: [SplitFlapPanel] = []

    // The layer that contains all panel sublayers. Add this to the view's root layer.
    let containerLayer = CALayer()

    private var panelSize: CGSize = .zero
    private let gap: CGFloat = 2
    private var lastLayoutMetrics: LayoutMetrics?

    // MARK: - Init

    init(bounds: CGRect, isPreview: Bool, scale: CGFloat) {
        layout(bounds: bounds, isPreview: isPreview, scale: scale)
    }

    // MARK: - Layout

    private func computePanelSize(for bounds: CGRect, isPreview: Bool) -> CGSize {
        let aspectRatio: CGFloat = 0.62   // width / height (real Solari: slightly taller than wide)
        let targetRows: CGFloat = isPreview ? 5 : 15

        let totalGapH = gap * (targetRows + 1)
        let h = floor((bounds.height - totalGapH) / targetRows)
        let w = floor(h * aspectRatio)
        return CGSize(width: max(w, 8), height: max(h, 12))
    }

    private func layout(bounds: CGRect, isPreview: Bool, scale: CGFloat) {
        let metrics = makeLayoutMetrics(bounds: bounds, isPreview: isPreview)
        let dimensionsChanged = rows != metrics.rows
            || cols != metrics.cols
            || !hasPanelGrid(rows: metrics.rows, cols: metrics.cols)
        let framesOnly = lastLayoutMetrics.map { metrics.canReusePanelFrames(from: $0) } ?? false

        panelSize = metrics.panelSize
        rows = metrics.rows
        cols = metrics.cols

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.frame = metrics.bounds
        containerLayer.backgroundColor = BoardColors.screenBg

        if dimensionsChanged {
            rebuildPanels(using: metrics, scale: scale)
        } else if framesOnly {
            applyFrames(using: metrics)
        } else {
            resizePanels(using: metrics, scale: scale)
        }

        lastLayoutMetrics = metrics
        CATransaction.commit()
    }

    private func hasPanelGrid(rows: Int, cols: Int) -> Bool {
        panels.count == rows && panels.allSatisfy { $0.count == cols }
    }

    private func rebuildPanels(using metrics: LayoutMetrics, scale: CGFloat) {
        containerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        panels = []
        var flat: [SplitFlapPanel] = []

        for r in 0..<rows {
            var row: [SplitFlapPanel] = []
            for c in 0..<cols {
                let panel = SplitFlapPanel(size: metrics.panelSize, scale: scale)
                panel.panelLayer.frame = panelFrame(row: r, col: c, metrics: metrics)
                containerLayer.addSublayer(panel.panelLayer)
                row.append(panel)
                flat.append(panel)
            }
            panels.append(row)
        }
        allPanelsFlat = flat
    }

    private func resizePanels(using metrics: LayoutMetrics, scale: CGFloat) {
        let ps = metrics.panelSize
        for r in 0..<rows {
            for c in 0..<cols {
                let panel = panels[r][c]
                panel.resize(to: ps, scale: scale)
                panel.panelLayer.frame = panelFrame(row: r, col: c, metrics: metrics)
            }
        }
    }

    private func applyFrames(using metrics: LayoutMetrics) {
        for r in 0..<rows {
            for c in 0..<cols {
                panels[r][c].panelLayer.frame = panelFrame(row: r, col: c, metrics: metrics)
            }
        }
    }

    // MARK: - Access

    func panel(row: Int, col: Int) -> SplitFlapPanel? {
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return panels[row][col]
    }

    func allPanels() -> [SplitFlapPanel] {
        return allPanelsFlat
    }

    // MARK: - Resize

    func rebuild(bounds: CGRect, isPreview: Bool, scale: CGFloat) {
        layout(bounds: bounds, isPreview: isPreview, scale: scale)
    }

    private func makeLayoutMetrics(bounds: CGRect, isPreview: Bool) -> LayoutMetrics {
        let ps = computePanelSize(for: bounds, isPreview: isPreview)
        let newCols = Int(floor((bounds.width  + gap) / (ps.width  + gap)))
        let newRows = Int(floor((bounds.height + gap) / (ps.height + gap)))
        let cols = max(newCols, 1)
        let rows = max(newRows, 1)

        let totalW = CGFloat(cols) * (ps.width  + gap) - gap
        let totalH = CGFloat(rows) * (ps.height + gap) - gap
        let originX = floor((bounds.width  - totalW) / 2)
        let originY = floor((bounds.height - totalH) / 2)

        return LayoutMetrics(
            bounds: bounds,
            panelSize: ps,
            rows: rows,
            cols: cols,
            originX: originX,
            originY: originY
        )
    }

    private func panelFrame(row: Int, col: Int, metrics: LayoutMetrics) -> CGRect {
        let x = metrics.originX + CGFloat(col) * (metrics.panelSize.width  + gap)
        let y = metrics.originY + CGFloat(row) * (metrics.panelSize.height + gap)
        return CGRect(x: x, y: y, width: metrics.panelSize.width, height: metrics.panelSize.height)
    }
}
