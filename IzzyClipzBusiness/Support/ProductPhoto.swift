import IzzyClipzKit
import UIKit

/// Turns a photo from the library or the camera into what the server takes:
/// a JPEG at most 1600 px on its longest side and under 4,000,000 bytes.
enum ProductPhoto {
    /// The longest side, in pixels.
    static let maxDimension: CGFloat = 1600
    /// JPEG quality to start with.
    static let quality: CGFloat = 0.8

    enum Failure: Error, Equatable, LocalizedError {
        case unreadable
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: return "That photo couldn't be opened. Pick another one."
            case .tooLarge: return "That photo is too big to upload, even made smaller. Pick another one."
            }
        }
    }

    /// From image file data (JPEG, HEIC, PNG…), off the main thread.
    static func jpeg(fromImageData data: Data, maxBytes: Int = IzzyAPI.maxPhotoBytes) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { throw Failure.unreadable }
            return try jpeg(from: image, maxBytes: maxBytes)
        }.value
    }

    /// Resizes (keeping the orientation the photo was taken in) and compresses,
    /// lowering the quality and then the size until it fits `maxBytes`.
    static func jpeg(from image: UIImage, maxBytes: Int = IzzyAPI.maxPhotoBytes) throws -> Data {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth >= 1, pixelHeight >= 1 else { throw Failure.unreadable }
        var longest = min(maxDimension, max(pixelWidth, pixelHeight))
        for _ in 0..<6 {
            let scale = longest / max(pixelWidth, pixelHeight)
            let size = CGSize(width: max(1, (pixelWidth * scale).rounded()), height: max(1, (pixelHeight * scale).rounded()))
            let resized = render(image, size: size)
            var compression = quality
            while compression >= 0.4 {
                if let data = resized.jpegData(compressionQuality: compression), data.count <= maxBytes {
                    return data
                }
                compression -= 0.1
            }
            longest *= 0.75
        }
        throw Failure.tooLarge
    }

    /// Draws the image at `size` pixels on an opaque white background (JPEG
    /// has no transparency), with the orientation applied.
    static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
