import UIKit
import XCTest
@testable import photo_manager_native_image

final class PixelBufferTests: XCTestCase {
    private func image(width: Int, height: Int) -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor(red: 0.8, green: 0.4, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.cgImage!
    }

    func testScaledSizeMatchesShorterSideWithoutUpscaling() {
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 640, height: 480), target: CGSize(width: 320, height: 320)),
                       CGSize(width: 427, height: 320))
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 480, height: 640), target: CGSize(width: 320, height: 320)),
                       CGSize(width: 320, height: 427))
        XCTAssertNil(PixelBufferFactory.scaledSize(for: CGSize(width: 300, height: 200), target: CGSize(width: 320, height: 320)))
        XCTAssertNil(PixelBufferFactory.scaledSize(for: CGSize(width: 320, height: 320), target: CGSize(width: 320, height: 320)))
    }

    func testScaledSizeCapsPanoramasAtFourTargetSquares() {
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 8000, height: 1000), target: CGSize(width: 1024, height: 1024)),
                       CGSize(width: 5793, height: 724))
        XCTAssertEqual(PixelBufferFactory.scaledSize(for: CGSize(width: 4000, height: 1000), target: CGSize(width: 160, height: 160)),
                       CGSize(width: 640, height: 160))
        XCTAssertNil(PixelBufferFactory.scaledSize(for: CGSize(width: 1280, height: 320), target: CGSize(width: 320, height: 320)))
    }

    func testLargerImageIsScaledDownToRGBA() throws {
        let buffer = try PixelBufferFactory.make(from: image(width: 64, height: 32), target: CGSize(width: 16, height: 16))
        defer { buffer.free() }
        XCTAssertEqual(buffer.width, 32)
        XCTAssertEqual(buffer.height, 16)
        XCTAssertEqual(buffer.rowBytes, 32 * 4)
        let px = buffer.data.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(px[3], 255)
        XCTAssertGreaterThan(px[0], px[1])
        XCTAssertGreaterThan(px[1], px[2])
        XCTAssertEqual(buffer.reply["width"], 32)
        XCTAssertEqual(buffer.reply["rowBytes"], 128)
        XCTAssertEqual(buffer.reply["pointer"], Int64(Int(bitPattern: buffer.data)))
    }

    func testSmallerImageIsConvertedWithoutScaling() throws {
        let buffer = try PixelBufferFactory.make(from: image(width: 10, height: 12), target: CGSize(width: 64, height: 64))
        defer { buffer.free() }
        XCTAssertEqual(buffer.width, 10)
        XCTAssertEqual(buffer.height, 12)
        XCTAssertGreaterThanOrEqual(buffer.rowBytes, 40)
        let px = buffer.data.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(px[3], 255)
        XCTAssertGreaterThan(px[0], px[2])
    }

    /// Flutter reads the bytes as sRGB, so Display P3 (231, 60, 40) must arrive as sRGB (250, 31, 14).
    func testDisplayP3IsConvertedToSRGB() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: p3, components: [231.0 / 255, 60.0 / 255, 40.0 / 255, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let buffer = try PixelBufferFactory.make(from: context.makeImage()!, target: CGSize(width: 32, height: 32))
        defer { buffer.free() }
        let bytes = buffer.data.assumingMemoryBound(to: UInt8.self)
        let o = 16 * buffer.rowBytes + 16 * 4
        let rgb = (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
        XCTAssertTrue(abs(rgb.0 - 250) <= 6 && abs(rgb.1 - 31) <= 8 && abs(rgb.2 - 14) <= 8, "\(rgb)")
    }

    /// Downscaling white and black stripes on transparency makes Lanczos push colour above alpha.
    func testScaledPixelsStayValidPremultiplied() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 750), format: format).image { ctx in
            var x = 0
            while x < 1000 {
                UIColor.white.setFill()
                ctx.fill(CGRect(x: x, y: 0, width: 2, height: 750))
                UIColor.black.setFill()
                ctx.fill(CGRect(x: x + 2, y: 0, width: 2, height: 750))
                x += 6
            }
        }.cgImage!
        let buffer = try PixelBufferFactory.make(from: image, target: CGSize(width: 320, height: 320))
        defer { buffer.free() }
        let bytes = buffer.data.assumingMemoryBound(to: UInt8.self)
        var invalid = 0
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                let o = y * buffer.rowBytes + x * 4
                if max(bytes[o], bytes[o + 1], bytes[o + 2]) > bytes[o + 3] { invalid += 1 }
            }
        }
        XCTAssertEqual(invalid, 0)
    }
}
