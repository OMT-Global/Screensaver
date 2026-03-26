import QuartzCore
import AppKit

// Manages the 2-D grid of SplitFlapPanel cells and their layout inside a root layer.
final class CharacterGrid {

    private(set) var panels: [[SplitFlapPanel]] = []
    private(set) var rows: Int = 0
    private(set) var cols: Int = 0

    // The layer that contains all panel sublayers. Add this to the view's root layer.
    let containerLayer = CALayer()

    private var panelSize: CGSize = .zero
    private let gap: CGFloat = 2

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
        let ps = computePanelSize(for: bounds, isPreview: isPreview)
        panelSize = ps

        let newCols = Int(floor((bounds.width  + gap) / (ps.width  + gap)))
        let newRows = Int(floor((bounds.height + gap) / (ps.height + gap)))

        rows = max(newRows, 1)
        cols = max(newCols, 1)

        // Centering offsets
        let totalW = CGFloat(cols) * (ps.width  + gap) - gap
        let totalH = CGFloat(rows) * (ps.height + gap) - gap
        let originX = floor((bounds.width  - totalW) / 2)
        let originY = floor((bounds.height - totalH) / 2)

        containerLayer.frame = bounds
        containerLayer.backgroundColor = BoardColors.screenBg

        // Remove existing sublayers
        containerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        panels = []

        for r in 0..<rows {
            var row: [SplitFlapPanel] = []
            for c in 0..<cols {
                let panel = SplitFlapPanel(size: ps, scale: scale)
                let x = originX + CGFloat(c) * (ps.width  + gap)
                let y = originY + CGFloat(r) * (ps.height + gap)
                panel.panelLayer.frame = CGRect(x: x, y: y, width: ps.width, height: ps.height)
                containerLayer.addSublayer(panel.panelLayer)
                row.append(panel)
            }
            panels.append(row)
        }
    }

    // MARK: - Access

    func panel(row: Int, col: Int) -> SplitFlapPanel? {
        guard row >= 0, row < rows, col >= 0, col < cols else { return nil }
        return panels[row][col]
    }

    func allPanels() -> [SplitFlapPanel] {
        return panels.flatMap { $0 }
    }

    // MARK: - Resize

    func rebuild(bounds: CGRect, isPreview: Bool, scale: CGFloat) {
        layout(bounds: bounds, isPreview: isPreview, scale: scale)
    }
}
