import SwiftUI
import UIKit

/// "Fresh cuts": the shop's photos of its work in a two-column grid. Tap one to see it full screen.
///
/// No text sits on the photos (VoiceOver reads each one's description) and nothing here is red:
/// the Book button in the tab bar is always one tap away.
struct GalleryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPhoto: GalleryPhoto?
    @State private var titleIsUnderBar = false
    @State private var isScrolled = false

    /// Two columns, or one at the largest text sizes, where the photos get the full width.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l), count: count)
    }

    var body: some View {
        GeometryReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ScreenHeader(kicker: "From the shop · \(GalleryPhoto.allCases.count) photos", title: "Fresh cuts")
                            .pageScrolledUnderBar($titleIsUnderBar)
                        Text("Work from the barbers at \(AppData.shop.name). Tap a photo to see it up close.")
                            .textRole(.body)
                            .foregroundStyle(Theme.smoke)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    grid
                    actions
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xxl)
                .pageScrolled($isScrolled)
            }
        }
        .coordinateSpace(.named(PageBar.space))
        .screenBackground()
        .pageBar(title: "Fresh cuts", showsTitle: titleIsUnderBar, isScrolled: isScrolled)
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(startingAt: photo)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: Theme.Space.l) {
            ForEach(GalleryPhoto.allCases) { photo in
                Button {
                    selectedPhoto = photo
                } label: {
                    GalleryPhotoTile(photo: photo)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(PhotoViewer.spokenLabel(for: photo))
                .accessibilityHint("Opens the photo full screen")
                .accessibilityIdentifier("photo-\(photo.rawValue)")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.m) {
            Button {
                router.openOutside(AppData.shop.instagramURL)
            } label: {
                HStack(spacing: 6) {
                    Text("More on Instagram")
                    Image(systemName: Symbol.external)
                        .font(.system(size: 13, weight: .heavy))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.secondary)
            .accessibilityLabel("More cuts on \(AppData.shop.name)'s Instagram")
            .accessibilityHint("Opens Instagram")
            .accessibilityIdentifier("galleryInstagramButton")

            Button {
                router.startBooking()
            } label: {
                Text("Book an appointment")
            }
            // Quiet ink, not red: the gallery has no red.
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("galleryBookButton")
        }
    }
}

/// A photo in the grid: 3:4, radius 18, cropped around the cut. No text on it.
private struct GalleryPhotoTile: View {
    let photo: GalleryPhoto
    private let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)

    var body: some View {
        // A clear 3:4 box sizes the tile; the photo fills it.
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                FillImage(name: photo.assetName, anchor: FillImage.editorial)
            }
            .clipShape(shape)
            .contentShape(shape)
    }
}

/// The photos full screen on ink: swipe between them, pinch or double-tap to zoom. A mono "3 / 6"
/// counter and a 44 pt close button stay put on top, and the photo's description sits on a solid
/// ink band at the bottom.
struct PhotoViewer: View {
    @State private var current: GalleryPhoto
    @Environment(\.dismiss) private var dismiss

    init(startingAt photo: GalleryPhoto) {
        _current = State(initialValue: photo)
    }

    /// "Photo 3 of 6, fade with a full, shaped beard".
    static func spokenLabel(for photo: GalleryPhoto) -> String {
        let position = (GalleryPhoto.allCases.firstIndex(of: photo) ?? 0) + 1
        return "Photo \(position) of \(GalleryPhoto.allCases.count), \(photo.caption.lowercased())"
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            TabView(selection: $current) {
                ForEach(GalleryPhoto.allCases) { photo in
                    PhotoViewerPage(photo: photo)
                        .tag(photo)
                }
            }
            // The counter says where you are, so no page dots.
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        // Pinned over the pages, so paging never moves them.
        .overlay(alignment: .top) {
            HStack(alignment: .center) {
                counter
                Spacer(minLength: Theme.Space.l)
                closeButton
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
        }
        .overlay(alignment: .bottom) {
            caption
        }
        // The photo gets the whole screen.
        .statusBarHidden()
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: Symbol.close)
        }
        .buttonStyle(.icon)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("closePhoto")
    }

    /// "3 / 6". VoiceOver hears "Photo 3 of 6".
    private var counter: some View {
        Text("\(position) / \(GalleryPhoto.allCases.count)")
            .textRole(.detail)
            .foregroundStyle(Theme.bone)
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: 32)
            .background(Theme.ink3, in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityLabel("Photo \(position) of \(GalleryPhoto.allCases.count)")
    }

    /// The photo's description on a solid band of ink at 80%. VoiceOver reads it on the photo.
    private var caption: some View {
        Text(current.caption)
            .textRole(.callout)
            .foregroundStyle(Theme.bone)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
            .background(Theme.ink.opacity(0.8).ignoresSafeArea(edges: .bottom))
            .accessibilityHidden(true)
    }

    private var position: Int {
        (GalleryPhoto.allCases.firstIndex(of: current) ?? 0) + 1
    }
}

private struct PhotoViewerPage: View {
    let photo: GalleryPhoto

    var body: some View {
        if let image = UIImage(named: photo.assetName) {
            ZoomableImage(image: image, accessibilityLabel: PhotoViewer.spokenLabel(for: photo))
        } else {
            Image(systemName: Symbol.gallery)
                .font(.largeTitle)
                .foregroundStyle(Theme.smoke)
                .accessibilityLabel(PhotoViewer.spokenLabel(for: photo))
        }
    }
}
