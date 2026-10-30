import SwiftUI
import UIKit

/// Photos of the shop's work. Tap one to see it full screen.
struct GalleryView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPhoto: GalleryPhoto?

    /// Two columns, or one at the largest text sizes so the page reads as a list.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Work from the barbers at \(AppData.shop.name). Tap a photo to see it up close.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
                grid
                actions
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            // Room for the last button to clear the tab bar.
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationTitle("Fresh Cuts")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(startingAt: photo)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(GalleryPhoto.allCases) { photo in
                Button {
                    selectedPhoto = photo
                } label: {
                    GalleryPhotoTile(photo: photo)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(photo.caption)
                .accessibilityHint("Opens the photo full screen")
                .accessibilityIdentifier("photo-\(photo.rawValue)")
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                router.startBooking()
            } label: {
                Label("Book an Appointment", systemImage: Symbol.book)
            }
            // The gallery has no red: the Book button in the tab bar is one tap away.
            .buttonStyle(.secondary)
            .accessibilityIdentifier("galleryBookButton")

            Link(destination: AppData.shop.instagramURL) {
                Label("More cuts on Instagram", systemImage: Symbol.instagram)
            }
            .buttonStyle(.tertiary)
            .accessibilityLabel("More cuts on \(AppData.shop.name)'s Instagram")
            .accessibilityIdentifier("galleryInstagramButton")
        }
    }
}

/// A photo in the grid: rounded, with a hairline and a soft shadow.
private struct GalleryPhotoTile: View {
    let photo: GalleryPhoto
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        FillImage(name: photo.assetName)
            .aspectRatio(0.8, contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.line))
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
            .contentShape(shape)
    }
}

/// Swipe between photos; pinch or double-tap to zoom.
///
/// Photos read best on black, so this stays dark in the light app.
struct PhotoViewer: View {
    @State private var current: GalleryPhoto
    @Environment(\.dismiss) private var dismiss

    init(startingAt photo: GalleryPhoto) {
        _current = State(initialValue: photo)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $current) {
                ForEach(GalleryPhoto.allCases) { photo in
                    PhotoViewerPage(photo: photo)
                        .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            closeButton
        }
        .overlay(alignment: .topLeading) {
            counter
        }
        .overlay(alignment: .bottom) {
            caption
        }
        // Dark status bar text would vanish on black; the photo gets the whole screen.
        .statusBarHidden()
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: Symbol.close)
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                .contentShape(Circle())
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("closePhoto")
        .padding(.trailing, 16)
        .padding(.top, 8)
    }

    /// "2 of 6". VoiceOver hears the page position from the page control.
    private var counter: some View {
        Text("\(position) of \(GalleryPhoto.allCases.count)")
            .font(.footnote.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.55), in: Capsule())
            .padding(.leading, 16)
            .padding(.top, 14)
            .accessibilityHidden(true)
    }

    /// The photo's description; VoiceOver reads it on the photo itself.
    private var caption: some View {
        Text(current.caption)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 48)
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
            ZoomableImage(image: image, accessibilityLabel: photo.caption)
        } else {
            Image(systemName: Symbol.gallery)
                .font(.largeTitle)
                .foregroundStyle(Color.white.opacity(0.6))
                .accessibilityLabel(photo.caption)
        }
    }
}
