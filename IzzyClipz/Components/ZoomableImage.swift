import SwiftUI
import UIKit

/// A photo that can be pinched or double-tapped to zoom, then panned.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let accessibilityLabel: String

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        ZoomingImageScrollView(image: image)
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        view.display(image)
        view.imageAccessibilityLabel = accessibilityLabel
    }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var laidOutSize: CGSize = .zero

    var imageAccessibilityLabel: String? {
        get { imageView.accessibilityLabel }
        set { imageView.accessibilityLabel = newValue }
    }

    init(image: UIImage) {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func display(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        laidOutSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fit the photo whenever the available space changes (first layout,
        // rotation); zooming alone doesn't change bounds, so it's left alone.
        guard bounds.size != laidOutSize, bounds.width > 0, bounds.height > 0 else { return }
        laidOutSize = bounds.size
        zoomScale = minimumZoomScale
        let fitted = Self.aspectFitSize(for: imageView.image?.size ?? bounds.size, in: bounds.size)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    /// Keeps the photo centered when it's smaller than the screen.
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let scale = min(maximumZoomScale, 2.5)
        let point = gesture.location(in: imageView)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    static func aspectFitSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
