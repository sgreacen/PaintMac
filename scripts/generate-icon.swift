import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x: 60, y: 60, width: 904, height: 904)
let background = NSBezierPath(roundedRect: rect, xRadius: 208, yRadius: 208)
NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.60, blue: 1, alpha: 1),
           ending: NSColor(srgbRed: 0.25, green: 0.22, blue: 0.78, alpha: 1))!.draw(in: background, angle: -65)
NSColor.white.withAlphaComponent(0.17).setStroke()
background.lineWidth = 5; background.stroke()
let configuration = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
symbol.draw(in: NSRect(x: 220, y: 285, width: 584, height: 584))
let badge = NSBezierPath(roundedRect: NSRect(x: 195, y: 148, width: 634, height: 112), xRadius: 38, yRadius: 38)
NSColor(srgbRed: 0.08, green: 0.12, blue: 0.32, alpha: 0.65).setFill()
badge.fill()
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
("SCOTTWARE" as NSString).draw(in: NSRect(x: 205, y: 174, width: 614, height: 66), withAttributes: [
    .font: NSFont.systemFont(ofSize: 58, weight: .heavy),
    .foregroundColor: NSColor.white,
    .kern: 5,
    .paragraphStyle: paragraph
])
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
// ic10 is a 1024×1024 PNG icon representation.
func bigEndian(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var icns = Data("icns".utf8)
icns.append(bigEndian(png.count + 16))
icns.append(Data("ic10".utf8))
icns.append(bigEndian(png.count + 8))
icns.append(png)
try icns.write(to: output)
