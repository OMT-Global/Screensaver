import AppKit

struct ThumbnailRenderer {
    let width: Int
    let height: Int
    let scale: CGFloat

    func render(to url: URL) throws -> NSBitmapImageRep {
        let pixelWidth = Int(CGFloat(width) * scale)
        let pixelHeight = Int(CGFloat(height) * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ThumbnailRenderer", code: 1)
        }

        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ThumbnailRenderer", code: 2)
        }
        try png.write(to: url, options: .atomic)
        return rep
    }

    private func draw(in rect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.045, alpha: 1).setFill()
        rect.fill()

        let gridColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 0.75)
        gridColor.setStroke()

        let cellW: CGFloat = 4
        let cellH: CGFloat = 5
        let path = NSBezierPath()
        path.lineWidth = 0.5

        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: rect.height))
            x += cellW
        }

        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: rect.width, y: y))
            y += cellH
        }
        path.stroke()

        let panelRect = NSRect(
            x: rect.width * 0.24,
            y: rect.height * 0.39,
            width: rect.width * 0.52,
            height: rect.height * 0.22
        )

        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 2, yRadius: 2)
        NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.065, alpha: 0.96).setFill()
        panelPath.fill()
        NSColor(calibratedRed: 0.015, green: 0.015, blue: 0.02, alpha: 1).setStroke()
        panelPath.lineWidth = 0.7
        panelPath.stroke()

        let divider = NSRect(x: panelRect.minX, y: panelRect.midY - 0.25, width: panelRect.width, height: 0.5)
        NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.015, alpha: 1).setFill()
        divider.fill()

        let text = "FLAPLINE" as NSString
        let font = NSFont.monospacedSystemFont(ofSize: rect.height * 0.105, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.25, alpha: 1),
            .kern: 1.2
        ]
        let size = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (rect.width - size.width) / 2,
            y: (rect.height - size.height) / 2 - 0.5,
            width: size.width,
            height: size.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("SplitFlap/Resources", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let standard = try ThumbnailRenderer(width: 90, height: 58, scale: 1).render(
    to: output.appendingPathComponent("thumbnail.png")
)
let retina = try ThumbnailRenderer(width: 90, height: 58, scale: 2).render(
    to: output.appendingPathComponent("thumbnail@2x.png")
)

let image = NSImage(size: NSSize(width: 90, height: 58))
image.addRepresentation(standard)
image.addRepresentation(retina)
if let tiff = image.tiffRepresentation {
    try tiff.write(to: output.appendingPathComponent("thumbnail.tiff"), options: .atomic)
}

let iconset = output.appendingPathComponent("Flapline.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let iconSizes = [16, 32, 128, 256, 512]
for size in iconSizes {
    _ = try ThumbnailRenderer(width: size, height: size, scale: 1).render(
        to: iconset.appendingPathComponent("icon_\(size)x\(size).png")
    )
    _ = try ThumbnailRenderer(width: size, height: size, scale: 2).render(
        to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png")
    )
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", output.appendingPathComponent("Flapline.icns").path
]
try iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 {
    throw NSError(domain: "ThumbnailRenderer", code: Int(iconutil.terminationStatus))
}
try FileManager.default.removeItem(at: iconset)
