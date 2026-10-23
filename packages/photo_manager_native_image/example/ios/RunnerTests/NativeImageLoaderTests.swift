import Foundation
import XCTest
@testable import photo_manager_native_image

final class NativeImageLoaderTests: XCTestCase {
    func testXPCErrorsAreRecognisedIncludingUnderlying() {
        let interrupted = NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInterrupted, userInfo: nil)
        let invalid = NSError(domain: NSCocoaErrorDomain, code: NSXPCConnectionInvalid, userInfo: nil)
        let wrapped = NSError(domain: "PHPhotosErrorDomain", code: -1, userInfo: [NSUnderlyingErrorKey: invalid])
        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        XCTAssertTrue(NativeImageLoader.isConnectionInvalidated(interrupted))
        XCTAssertTrue(NativeImageLoader.isConnectionInvalidated(invalid))
        XCTAssertTrue(NativeImageLoader.isConnectionInvalidated(wrapped))
        XCTAssertFalse(NativeImageLoader.isConnectionInvalidated(other))
    }

    func testNetworkRequiredIsMapped() {
        XCTAssertTrue(NativeImageLoader.isNetworkRequired(NSError(domain: "PHPhotosErrorDomain", code: 3164, userInfo: nil)))
        XCTAssertFalse(NativeImageLoader.isNetworkRequired(NSError(domain: "PHPhotosErrorDomain", code: 3300, userInfo: nil)))
        XCTAssertFalse(NativeImageLoader.isNetworkRequired(nil))
    }

    func testCancelBeforeRequestRepliesNilWithoutWork() {
        let loader = NativeImageLoader()
        loader.cancel(requestId: 42)
        let done = expectation(description: "reply")
        loader.request(assetId: "missing", requestId: 42, targetSize: CGSize(width: 8, height: 8), allowNetwork: false) { result in
            if case .success(let reply) = result { XCTAssertNil(reply) } else { XCTFail("expected nil reply") }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }
}
