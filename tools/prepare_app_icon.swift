// Original image packaging helper. Reads only an owner's supplied PNG and
// produces opaque sRGB variants; it never loads a game asset or asset catalog.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum IconError: Error { case invalid }

func render() throws {
    guard CommandLine.arguments.count == 4 else { throw IconError.invalid }
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let plan = URL(fileURLWithPath: CommandLine.arguments[3])
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
          CGImageSourceGetCount(source) == 1,
          CGImageSourceGetType(source) as String? == UTType.png.identifier,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == 1024, image.height == 1024,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw IconError.invalid }
    var pixels = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
    let opaque = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress, width: 1024, height: 1024,
                                      bitsPerComponent: 8, bytesPerRow: 1024 * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        return stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }
    }
    guard opaque else { throw IconError.invalid }
    let variants = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: plan))
    for (name, size) in variants.sorted(by: { $0.key < $1.key }) {
        guard size > 0, size <= 1024, name == URL(fileURLWithPath: name).lastPathComponent,
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw IconError.invalid }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let scaled = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,
                                                               UTType.png.identifier as CFString, 1, nil) else { throw IconError.invalid }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw IconError.invalid }
    }
}

do { try render() }
catch { exit(1) }
