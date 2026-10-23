import Accelerate
import CoreGraphics
import UIKit

/// A premultiplied RGBA8888 buffer allocated with `malloc`. Ownership passes
/// to Dart once it is described in a reply; only failure paths free it here.
struct PixelBuffer {
    let data: UnsafeMutableRawPointer
    let width: Int
    let height: Int
    let rowBytes: Int

    var reply: NativeImageReply {
        [
            "pointer": Int64(Int(bitPattern: data)),
            "width": Int64(width),
            "height": Int64(height),
            "rowBytes": Int64(rowBytes),
        ]
    }

    func free() {
        Foundation.free(data)
    }
}

enum PixelBufferError: Error {
    case conversionFailed
    case allocationFailed
}

enum PixelBufferFactory {
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    /// Flutter's `PixelFormat.rgba8888`: R,G,B,A in memory, premultiplied.
    static var rgbaFormat: vImage_CGImageFormat {
        vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent)
    }

    /// Decoded pixels are capped at this many target squares, so panoramas stay bounded.
    static let maxPixelsInTargetSquares: CGFloat = 4

    /// Size that scales `image` so its shorter side equals the target's
    /// shorter side, then shrinks further until the area is at most
    /// `maxPixelsInTargetSquares` target squares. Never upscales.
    static func scaledSize(for image: CGSize, target: CGSize) -> CGSize? {
        guard image.width > 0, image.height > 0 else { return nil }
        let shorter = min(image.width, image.height)
        let targetShorter = min(target.width, target.height)
        var scale = shorter > targetShorter ? targetShorter / shorter : 1
        let maxPixels = maxPixelsInTargetSquares * targetShorter * targetShorter
        let pixels = image.width * scale * image.height * scale
        if pixels > maxPixels { scale *= (maxPixels / pixels).squareRoot() }
        guard scale < 1 else { return nil }
        return CGSize(
            width: max(1, (image.width * scale).rounded()),
            height: max(1, (image.height * scale).rounded()))
    }

    /// Converts `cgImage` to RGBA and downscales it to `target` when larger.
    /// Pixel passes: conversion (1) and, only when needed, scaling and alpha clipping (2).
    static func make(from cgImage: CGImage, target: CGSize) throws -> PixelBuffer {
        var format = rgbaFormat
        var source = vImage_Buffer()
        let initError = vImageBuffer_InitWithCGImage(
            &source, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        guard initError == kvImageNoError, let sourceData = source.data else {
            throw PixelBufferError.conversionFailed
        }
        let sourceSize = CGSize(width: Int(source.width), height: Int(source.height))
        guard let scaled = scaledSize(for: sourceSize, target: target) else {
            return PixelBuffer(
                data: sourceData, width: Int(source.width), height: Int(source.height),
                rowBytes: source.rowBytes)
        }
        let width = Int(scaled.width)
        let height = Int(scaled.height)
        let rowBytes = width * 4
        guard let destData = malloc(rowBytes * height) else {
            Foundation.free(sourceData)
            throw PixelBufferError.allocationFailed
        }
        var dest = vImage_Buffer(
            data: destData, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: rowBytes)
        let scaleError = vImageScale_ARGB8888(&source, &dest, nil, vImage_Flags(kvImageNoFlags))
        Foundation.free(sourceData)
        // Lanczos ringing can push a colour above its alpha, which is invalid premultiplied data.
        let clipError = scaleError == kvImageNoError
            ? vImageClipToAlpha_RGBA8888(&dest, &dest, vImage_Flags(kvImageNoFlags)) : scaleError
        guard clipError == kvImageNoError else {
            Foundation.free(destData)
            throw PixelBufferError.conversionFailed
        }
        return PixelBuffer(data: destData, width: width, height: height, rowBytes: rowBytes)
    }

    /// Returns a `CGImage` whose pixels are upright; PhotoKit thumbnails
    /// already are, so this only redraws the rare rotated `UIImage`.
    static func uprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up {
            return image.cgImage
        }
        let renderer = UIGraphicsImageRenderer(size: image.size, format: {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return format
        }())
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }
}
