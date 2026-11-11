import UIKit
import XCTest
@testable import photo_manager_native_image

final class HdrAssetViewTests: XCTestCase {
    func testTargetPixelSizeScalesShorterSideAndKeepsAspect() {
        XCTAssertEqual(HdrAssetView.targetPixelSize(width: 4032, height: 3024, shortSide: 2217),
                       CGSize(width: 2956, height: 2217))
    }

    func testTargetPixelSizeNeverExceedsTheOriginal() {
        XCTAssertEqual(HdrAssetView.targetPixelSize(width: 800, height: 600, shortSide: 2217),
                       CGSize(width: 800, height: 600))
    }
}
