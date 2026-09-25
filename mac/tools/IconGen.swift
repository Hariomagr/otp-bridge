import AppKit

// Renders the shared mascot app icon and writes:
//   argv[1] = macOS .iconset dir  (PNGs for iconutil)
//   argv[2] = Android res dir     (mipmap-*/ic_launcher.png + _round)
// One source of truth so the Mac and Android icons match.

func draw(size s: CGFloat, round: Bool) {
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // Rounded/circular background with a soft lavender gradient.
    let bgPath: NSBezierPath
    if round {
        bgPath = NSBezierPath(ovalIn: rect)
    } else {
        let inset = s * 0.06
        bgPath = NSBezierPath(
            roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
            xRadius: s * 0.22, yRadius: s * 0.22
        )
    }
    NSGradient(
        starting: NSColor(srgbRed: 0.82, green: 0.78, blue: 0.93, alpha: 1),
        ending:   NSColor(srgbRed: 0.55, green: 0.49, blue: 0.76, alpha: 1)
    )!.draw(in: bgPath, angle: -90)

    // Original mascot: a worried pink pup with big nervous eyes and floppy ears.
    drawMascot(s: s)
}

/// Original timid-dog mascot art.
func drawMascot(s: CGFloat) {
    let pink = NSColor(srgbRed: 0.94, green: 0.68, blue: 0.81, alpha: 1)
    let earPink = NSColor(srgbRed: 0.78, green: 0.42, blue: 0.60, alpha: 1)
    let dark = NSColor(srgbRed: 0.12, green: 0.10, blue: 0.16, alpha: 1)

    // Floppy ears (drawn behind the head).
    earPink.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.19, y: s * 0.28, width: s * 0.17, height: s * 0.36)).fill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.64, y: s * 0.28, width: s * 0.17, height: s * 0.36)).fill()

    // Head.
    pink.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.26, y: s * 0.30, width: s * 0.48, height: s * 0.45)).fill()

    // Big worried eyes, set close together.
    let eyeW = s * 0.15, eyeH = s * 0.20
    let eyeY = s * 0.47
    let eyeCx = [s * 0.435, s * 0.565]
    for cx in eyeCx {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - eyeW / 2, y: eyeY, width: eyeW, height: eyeH)).fill()
        // Small pupils darting down — the nervous look.
        dark.setFill()
        let pr = s * 0.03
        NSBezierPath(ovalIn: NSRect(x: cx - pr, y: eyeY + eyeH * 0.22, width: pr * 2, height: pr * 2)).fill()
    }

    // Worried eyebrows (angled up toward the middle).
    dark.setStroke()
    let brow = NSBezierPath()
    brow.lineWidth = s * 0.022
    brow.lineCapStyle = .round
    brow.move(to: NSPoint(x: s * 0.34, y: eyeY + eyeH * 1.02))
    brow.line(to: NSPoint(x: s * 0.44, y: eyeY + eyeH * 1.16))
    brow.move(to: NSPoint(x: s * 0.66, y: eyeY + eyeH * 1.02))
    brow.line(to: NSPoint(x: s * 0.56, y: eyeY + eyeH * 1.16))
    brow.stroke()

    // Snout + nose.
    NSColor(srgbRed: 0.98, green: 0.86, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.41, y: s * 0.33, width: s * 0.18, height: s * 0.13)).fill()
    dark.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.47, y: s * 0.41, width: s * 0.06, height: s * 0.045)).fill()

    // Small wavy, anxious mouth.
    let mouth = NSBezierPath()
    mouth.lineWidth = s * 0.018
    mouth.lineCapStyle = .round
    mouth.move(to: NSPoint(x: s * 0.44, y: s * 0.375))
    mouth.curve(to: NSPoint(x: s * 0.50, y: s * 0.375),
                controlPoint1: NSPoint(x: s * 0.46, y: s * 0.40),
                controlPoint2: NSPoint(x: s * 0.48, y: s * 0.355))
    mouth.curve(to: NSPoint(x: s * 0.56, y: s * 0.375),
                controlPoint1: NSPoint(x: s * 0.52, y: s * 0.40),
                controlPoint2: NSPoint(x: s * 0.54, y: s * 0.355))
    dark.setStroke()
    mouth.stroke()
}

func renderPNG(pixels: Int, round: Bool) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(size: CGFloat(pixels), round: round)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// White mascot silhouette on transparent — for Android status-bar small icons
/// (Android masks small icons to their alpha channel, so they must be white).
func drawSilhouette(s: CGFloat) {
    NSColor.white.setFill()
    // Ears + head as one white shape.
    NSBezierPath(ovalIn: NSRect(x: s * 0.19, y: s * 0.28, width: s * 0.17, height: s * 0.36)).fill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.64, y: s * 0.28, width: s * 0.17, height: s * 0.36)).fill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.26, y: s * 0.30, width: s * 0.48, height: s * 0.45)).fill()

    // Punch out eyes and nose so features read as holes.
    NSGraphicsContext.current?.compositingOperation = .destinationOut
    NSColor.black.setFill()
    let eyeR = s * 0.055, eyeY = s * 0.55
    for cx in [s * 0.42, s * 0.58] {
        NSBezierPath(ovalIn: NSRect(x: cx - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)).fill()
    }
    NSBezierPath(ovalIn: NSRect(x: s * 0.46, y: s * 0.40, width: s * 0.08, height: s * 0.06)).fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
}

func renderSilhouettePNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawSilhouette(s: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconsetDir = CommandLine.arguments[1]
let androidRes = CommandLine.arguments[2]

// macOS .iconset
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
let macSizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in macSizes {
    let data = renderPNG(pixels: px, round: false)
    try! data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name).png"))
}

// Android mipmaps (legacy square + round).
let androidSizes: [(Int, String)] = [
    (48, "mipmap-mdpi"), (72, "mipmap-hdpi"), (96, "mipmap-xhdpi"),
    (144, "mipmap-xxhdpi"), (192, "mipmap-xxxhdpi"),
]
for (px, dir) in androidSizes {
    let path = "\(androidRes)/\(dir)"
    try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    try! renderPNG(pixels: px, round: false).write(to: URL(fileURLWithPath: "\(path)/ic_launcher.png"))
    try! renderPNG(pixels: px, round: true).write(to: URL(fileURLWithPath: "\(path)/ic_launcher_round.png"))
}

// Android notification small icons (white silhouette) in drawable-*.
let notifSizes: [(Int, String)] = [
    (24, "drawable-mdpi"), (36, "drawable-hdpi"), (48, "drawable-xhdpi"),
    (72, "drawable-xxhdpi"), (96, "drawable-xxxhdpi"),
]
for (px, dir) in notifSizes {
    let path = "\(androidRes)/\(dir)"
    try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    try! renderSilhouettePNG(pixels: px).write(to: URL(fileURLWithPath: "\(path)/ic_stat_mascot.png"))
}

print("Icons written: \(iconsetDir) and \(androidRes)/mipmap-* + drawable-*/ic_stat_mascot")
