#!/usr/bin/env swift

import AppKit

// Keep the app icon identical to MenuBarController's normal status symbol.
let symbolName = "gauge.with.dots.needle.33percent"
let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("codex-remaining-icon-\(UUID().uuidString)")
let iconsetDirectory = temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: temporaryDirectory) }

func renderSymbol(size: Int, to destination: URL) throws {
    let canvasSize = CGFloat(size)
    let configuration = NSImage.SymbolConfiguration(pointSize: canvasSize * 0.82, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [
            NSColor(calibratedWhite: 0.12, alpha: 1)
        ]))
    guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration),
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
          ),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to render SF Symbol \(symbolName)."
        ])
    }

    bitmap.size = NSSize(width: canvasSize, height: canvasSize)
    symbol.isTemplate = false
    let scale = canvasSize * 0.82 / max(symbol.size.width, symbol.size.height)
    let symbolSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    let rect = NSRect(
        x: (canvasSize - symbolSize.width) / 2,
        y: (canvasSize - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    context.imageInterpolation = .high
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to encode the app icon as PNG."
        ])
    }
    try png.write(to: destination, options: .atomic)
}

for size in [16, 32, 128, 256, 512] {
    try renderSymbol(size: size, to: iconsetDirectory.appendingPathComponent("icon_\(size)x\(size).png"))
    try renderSymbol(size: size * 2, to: iconsetDirectory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let iconURL = temporaryDirectory.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDirectory.path, "-o", iconURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "AppIcon", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "iconutil failed to create the app icon."
    ])
}

try Data(contentsOf: iconURL).write(
    to: projectDirectory.appendingPathComponent("Resources/AppIcon.icns"), options: .atomic
)
try Data(contentsOf: iconsetDirectory.appendingPathComponent("icon_512x512@2x.png")).write(
    to: projectDirectory.appendingPathComponent("assets/app-icon.png"), options: .atomic
)
print("Generated app icon from SF Symbol: \(symbolName)")
