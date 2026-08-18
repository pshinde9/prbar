import AppKit

// Builds PRBar's icons from Resources/menubar.svg.
//
// qlmanage is the only SVG rasterizer that ships with macOS, and it flattens
// transparency onto white. So rather than using its output as artwork, we use
// it as a stencil: the mark is pure black on pure white, which is exactly the
// convention a CGImage mask wants (0 = paint, 255 = leave alone). Everything
// else is composited here, where alpha is under our control.

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

// MARK: - Rasterize the SVG to a stencil

func rasterize(_ svg: URL, size: Int) -> CGImage {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prbar-icons")
    try? FileManager.default.removeItem(at: scratch)
    try! FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
    process.arguments = ["-t", "-s", "\(size)", "-o", scratch.path, svg.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try! process.run()
    process.waitUntilExit()

    let rendered = scratch.appendingPathComponent(svg.lastPathComponent + ".png")
    guard let image = NSImage(contentsOf: rendered),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("qlmanage did not render \(svg.lastPathComponent)")
    }
    return cgImage
}

/// Flattens the render to 8-bit grayscale and wraps it as a CGImage mask.
func stencil(from image: CGImage, size: Int) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    // Copy the bytes out: the context's buffer dies with the context, and the
    // mask outlives this function.
    let pixels = Data(bytes: context.data!, count: size * size)
    let provider = CGDataProvider(data: pixels as CFData)!
    return CGImage(maskWidth: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
                   bytesPerRow: size, provider: provider, decode: nil, shouldInterpolate: true)!
}

// MARK: - Canvas helpers

func canvas(_ size: Int, draw: (CGContext) -> Void) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    draw(context)
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ name: String) {
    try! data.write(to: resources.appendingPathComponent(name))
}

let markStencil = stencil(from: rasterize(resources.appendingPathComponent("menubar.svg"), size: 1024), size: 1024)

// MARK: - Menu bar glyph
// Template images are drawn from alpha alone, so the colour here is
// irrelevant — macOS retints it for light and dark menu bars.

for (name, size) in [("MenuBarIconTemplate.png", 18), ("MenuBarIconTemplate@2x.png", 36)] {
    write(canvas(size) { context in
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        context.clip(to: rect, mask: markStencil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(rect)
    }, name)
}

// MARK: - App icon
// This is what notification banners display. Transparent outside the rounded
// square, so it doesn't sit in a white box.

let iconset = resources.appendingPathComponent("PRBar.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func writeIconset(_ data: Data, _ name: String) {
    try! data.write(to: iconset.appendingPathComponent(name))
}

func appIcon(_ size: Int) -> Data {
    canvas(size) { context in
        let scale = CGFloat(size) / 1024
        let plate = CGRect(x: 96 * scale, y: 96 * scale, width: 832 * scale, height: 832 * scale)
        context.setFillColor(red: 0.094, green: 0.090, blue: 0.090, alpha: 1)  // GitHub #181717
        context.addPath(CGPath(roundedRect: plate, cornerWidth: 186 * scale, cornerHeight: 186 * scale, transform: nil))
        context.fillPath()

        let mark = CGRect(x: 252 * scale, y: 252 * scale, width: 520 * scale, height: 520 * scale)
        context.saveGState()
        context.clip(to: mark, mask: markStencil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(mark)
        context.restoreGState()
    }
}

for size in [16, 32, 128, 256, 512] {
    writeIconset(appIcon(size), "icon_\(size)x\(size).png")
    writeIconset(appIcon(size * 2), "icon_\(size)x\(size)@2x.png")
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("PRBar.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

print("icons built")
