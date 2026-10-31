import IzzyClipzKit
import UIKit
import XCTest
@testable import IzzyClipzBusiness

/// Product photos are made small enough for the server on the phone: at most
/// 1600 px on the longest side, a JPEG under 4,000,000 bytes, upright.
@MainActor
final class ProductPhotoTests: XCTestCase {
    func testPhotosAreResizedTo1600PixelsAndAJPEG() throws {
        let data = try ProductPhoto.jpeg(from: ProductEditorView.testPhoto())
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8, 0xFF]), "A JPEG")
        XCTAssertLessThanOrEqual(data.count, IzzyAPI.maxPhotoBytes)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width * image.scale, 1600)
        XCTAssertEqual(image.size.height * image.scale, 1200)
    }

    func testSmallPhotosAreNotEnlargedAndOrientationIsKept() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        // The camera's portrait photos are stored sideways with an orientation flag.
        let sideways = UIImage(cgImage: try XCTUnwrap(small.cgImage), scale: 1, orientation: .right)
        let data = try ProductPhoto.jpeg(from: sideways)
        let image = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(image.size.width * image.scale, 200, "Drawn upright: 200 wide")
        XCTAssertEqual(image.size.height * image.scale, 300)
    }

    func testAPhotoIsMadeSmallerUntilItFits() throws {
        let noise = ProductPhoto.render(ProductEditorView.testPhoto(), size: CGSize(width: 1600, height: 1200))
        let limit = 60_000
        let data = try ProductPhoto.jpeg(from: noise, maxBytes: limit)
        XCTAssertLessThanOrEqual(data.count, limit)
        XCTAssertThrowsError(try ProductPhoto.jpeg(from: noise, maxBytes: 10)) { error in
            XCTAssertEqual(error as? ProductPhoto.Failure, .tooLarge)
        }
    }

    func testImageFileDataIsConvertedOffTheMainThread() async throws {
        let png = try XCTUnwrap(ProductEditorView.testPhoto().pngData())
        let data = try await ProductPhoto.jpeg(fromImageData: png)
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8, 0xFF]))
        do {
            _ = try await ProductPhoto.jpeg(fromImageData: Data("not an image".utf8))
            XCTFail("Garbage became a photo")
        } catch {
            XCTAssertEqual(error as? ProductPhoto.Failure, .unreadable)
        }
    }
}
