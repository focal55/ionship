// Renders the Ode app icon at every macOS size into an AppIcon.appiconset folder.
// Usage: swift AppIcon.swift <path to AppIcon.appiconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let paper = CGColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1)
let ink = CGColor(srgbRed: 0.078, green: 0.086, blue: 0.110, alpha: 1)
let accent = CGColor(srgbRed: 0.184, green: 0.294, blue: 0.878, alpha: 1)

func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(pixels) / 1024
    // Work in the 1024-point macOS icon grid with the origin at the top left, like the SVG.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)

    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(tile)
    ctx.setFillColor(paper)
    ctx.fillPath()
    ctx.restoreGState()

    // The mark's drawn extent (16...224 of its 240 box) fills 62% of the tile.
    let markScale: CGFloat = 511 / 208
    ctx.translateBy(x: 512 - 120 * markScale, y: 512 - 120 * markScale)
    ctx.scaleBy(x: markScale, y: markScale)

    ctx.addArc(center: CGPoint(x: 120, y: 120), radius: 74, startAngle: degrees(329), endAngle: degrees(241), clockwise: false)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(60)
    ctx.setLineCap(.round)
    ctx.strokePath()

    ctx.addEllipse(in: CGRect(x: 139.2 - 23, y: 48.5 - 23, width: 46, height: 46))
    ctx.setFillColor(accent)
    ctx.fillPath()

    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = "icon_\(points)x\(points)\(factor == 2 ? "@2x" : "").png"
        try render(pixels: points * factor).write(to: outDir.appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(factor)x","size":"\#(points)x\#(points)"}"#)
    }
}
let contents = #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
