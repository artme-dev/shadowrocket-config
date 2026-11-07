import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let bounds = NSRect(x: s * 0.055, y: s * 0.055, width: s * 0.89, height: s * 0.89)
    let shape = NSBezierPath(roundedRect: bounds, xRadius: s * 0.20, yRadius: s * 0.20)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.56, blue: 1, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.84, alpha: 1))!.draw(in: shape, angle: 270)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.53, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "network", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let ratio = symbol.size.width / symbol.size.height
    let h = s * 0.59; let w = h * ratio
    symbol.draw(in: NSRect(x: (s-w)/2, y: (s-h)/2, width: w, height: h))
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = rep.representation(using: .png, properties: [:])!
    for (logical, scale) in [(size, 1), (size/2, 2)] where [16,32,128,256,512].contains(logical) && (scale == 1 || size >= 32) {
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: destination.appendingPathComponent("icon_\(logical)x\(logical)\(suffix).png"))
    }
}
