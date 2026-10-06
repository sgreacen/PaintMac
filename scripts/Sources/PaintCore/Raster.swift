import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum PaintError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

/// Premultiplied RGBA8 pixels, with row zero at the top of the image.
public struct Raster {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    public static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    public init(width: Int, height: Int, color: NSColor? = nil) {
        precondition(width > 0 && height > 0 && width <= 8192 && height <= 8192 && width * height <= 16_777_216)
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bounds = self.bounds
        if let color { paint { context in
            context.setFillColor(color.cgColor)
            context.fill(bounds)
        } }
    }

    public init(image: CGImage) throws {
        try Self.validateSize(width: image.width, height: image.height)
        self.init(width: image.width, height: image.height)
        let bounds = self.bounds
        paint { Self.draw(image, in: bounds, context: $0) }
    }

    public static func validateSize(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_777_216 else {
            throw PaintError.message("Use dimensions from 1 to 8192 pixels, with at most 16 megapixels in total.")
        }
    }

    public static func load(data: Data) throws -> Raster {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw PaintError.message("This file is not a supported image.")
        }
        try validateSize(width: width, height: height)
        // Apply camera orientation while decoding, without reducing the resolution.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PaintError.message("The image could not be decoded.")
        }
        return try Raster(image: image)
    }

    public var image: CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: Self.colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Presents a top-left coordinate system to callers.
    public mutating func paint(_ operation: (CGContext) -> Void) {
        let w = width, h = height
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                                    bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: Self.colorSpace, bitmapInfo: Self.bitmapInfo)!
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)
            operation(context)
        }
    }

    public static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    public func encoded(type: UTType = .png) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw PaintError.message("This export format is unavailable.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PaintError.message("Could not encode the image.") }
        return data as Data
    }

    public func color(at point: CGPoint) -> NSColor {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return .clear }
        let i = (y * width + x) * 4, a = CGFloat(pixels[i + 3])
        guard a > 0 else { return .clear }
        return NSColor(srgbRed: CGFloat(pixels[i]) / a, green: CGFloat(pixels[i + 1]) / a,
                       blue: CGFloat(pixels[i + 2]) / a, alpha: a / 255)
    }

    public mutating func stroke(from start: CGPoint, to end: CGPoint, color: NSColor,
                                size: CGFloat, erasing: Bool = false, pixelated: Bool = false,
                                clip: CGRect? = nil) {
        paint { context in
            if let clip { context.clip(to: clip) }
            context.setShouldAntialias(!pixelated)
            context.setBlendMode(erasing ? .clear : .normal)
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(size)
            context.setLineCap(.round)
            if start == end {
                context.fillEllipse(in: CGRect(x: start.x - size / 2, y: start.y - size / 2, width: size, height: size))
            } else {
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
            }
        }
    }

    public mutating func floodFill(at point: CGPoint, color: NSColor, tolerance: Int, clip: CGRect? = nil) {
        let x = Int(point.x), y = Int(point.y)
        let region = (clip ?? bounds).intersection(bounds).integral
        guard x >= 0, y >= 0, x < width, y < height,
              region.contains(CGPoint(x: x, y: y)) else { return }
        let c = color.usingColorSpace(.sRGB) ?? .black
        let replacement = [UInt8((c.redComponent * c.alphaComponent * 255).rounded()),
                           UInt8((c.greenComponent * c.alphaComponent * 255).rounded()),
                           UInt8((c.blueComponent * c.alphaComponent * 255).rounded()),
                           UInt8((c.alphaComponent * 255).rounded())]
        let start = y * width + x
        let target = Array(pixels[(start * 4)..<(start * 4 + 4)])
        if target == replacement { return }
        var visited = [Bool](repeating: false, count: width * height)
        var queue = [start]
        visited[start] = true
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let px = index % width, py = index / width
            guard region.contains(CGPoint(x: px, y: py)) else { continue }
            let offset = index * 4
            guard (0..<4).allSatisfy({ abs(Int(pixels[offset + $0]) - Int(target[$0])) <= tolerance }) else { continue }
            for channel in 0..<4 { pixels[offset + channel] = replacement[channel] }
            for neighbor in [px > 0 ? index - 1 : -1, px + 1 < width ? index + 1 : -1,
                             py > 0 ? index - width : -1, py + 1 < height ? index + width : -1] {
                if neighbor >= 0 && !visited[neighbor] { visited[neighbor] = true; queue.append(neighbor) }
            }
        }
    }

    public func resized(width: Int, height: Int) -> Raster {
        var result = Raster(width: width, height: height)
        let image = self.image, bounds = result.bounds
        result.paint { context in
            context.interpolationQuality = .high
            Self.draw(image, in: bounds, context: context)
        }
        return result
    }

    public func cropped(to rect: CGRect) -> Raster {
        let area = rect.intersection(bounds).integral
        var result = Raster(width: Int(area.width), height: Int(area.height))
        for y in 0..<result.height {
            let sourceStart = ((y + Int(area.minY)) * width + Int(area.minX)) * 4
            let targetStart = y * result.width * 4
            result.pixels.replaceSubrange(targetStart..<(targetStart + result.width * 4),
                                          with: pixels[sourceStart..<(sourceStart + result.width * 4)])
        }
        return result
    }

    public func flipped(horizontal: Bool) -> Raster {
        var result = Raster(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            let from = (y * width + x) * 4
            let to = ((horizontal ? y : height - 1 - y) * width + (horizontal ? width - 1 - x : x)) * 4
            for c in 0..<4 { result.pixels[to + c] = pixels[from + c] }
        } }
        return result
    }

    public func rotatedClockwise() -> Raster {
        var result = Raster(width: height, height: width)
        for y in 0..<height { for x in 0..<width {
            let from = (y * width + x) * 4, to = (x * height + (height - 1 - y)) * 4
            for c in 0..<4 { result.pixels[to + c] = pixels[from + c] }
        } }
        return result
    }

    public func effect(_ effect: Effect) throws -> Raster {
        if effect == .invert || effect == .grayscale || effect == .sepia {
            var result = self
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let a = Double(pixels[i + 3]), r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
                let channels: [Double]
                switch effect {
                case .invert: channels = [a - r, a - g, a - b]
                case .grayscale:
                    let value = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    channels = [value, value, value]
                default: channels = [0.393*r + 0.769*g + 0.189*b, 0.349*r + 0.686*g + 0.168*b, 0.272*r + 0.534*g + 0.131*b]
                }
                for c in 0..<3 { result.pixels[i + c] = UInt8(max(0, min(a, channels[c])).rounded()) }
            }
            return result
        }
        let input = CIImage(cgImage: image)
        let output: CIImage
        switch effect {
        case .blur: output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
        case .sharpen: output = input.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.7])
        case .brightness: output = input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.08])
        case .contrast: output = input.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2])
        case .saturate: output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
        default: output = input
        }
        guard let image = CIContext(options: [.workingColorSpace: Self.colorSpace]).createCGImage(output, from: input.extent) else {
            throw PaintError.message("The image effect could not be rendered.")
        }
        return try Raster(image: image)
    }
}

public enum Effect: String, CaseIterable {
    case grayscale = "Black & White", invert = "Invert Colors", sepia = "Sepia"
    case blur = "Gaussian Blur", sharpen = "Sharpen", brightness = "Brighten"
    case contrast = "Increase Contrast", saturate = "Boost Saturation"
}
