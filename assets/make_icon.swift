import AppKit

// Renders the SF Symbol cup.and.saucer.fill in white on a warm coffee-coloured squircle.
func render(_ px: Int, to path: String) {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(red: 0.80, green: 0.52, blue: 0.27, alpha: 1),
               ending: NSColor(red: 0.42, green: 0.24, blue: 0.12, alpha: 1))!.draw(in: shape, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let sym = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let sz = sym.size
    sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2 - s * 0.01, width: sz.width, height: sz.height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let dir = CommandLine.arguments[1]
for base in [16, 32, 128, 256, 512] {
    render(base, to: "\(dir)/icon_\(base)x\(base).png")
    render(base * 2, to: "\(dir)/icon_\(base)x\(base)@2x.png")
}
