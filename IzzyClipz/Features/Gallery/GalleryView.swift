import SwiftUI
import UIKit

struct GalleryView: View {
    @State private var selectedPhoto: GalleryPhoto?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(GalleryPhoto.allCases) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            FillImage(name: photo.assetName)
                                .aspectRatio(0.75, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(photo.caption)
                        .accessibilityHint("Opens the photo full screen")
                        .accessibilityIdentifier("photo-\(photo.rawValue)")
                    }
                }

                Link(destination: AppData.shop.instagramURL) {
                    Label("More cuts on Instagram", systemImage: Symbol.instagram)
                }
                .buttonStyle(.secondary)
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("Fresh Cuts")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(startingAt: photo)
        }
    }
}

/// Swipe between photos; pinch or double-tap to zoom.
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
                    PhotoPage(photo: photo)
                        .tag(photo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: Symbol.close)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("closePhoto")
        }
        .overlay(alignment: .bottom) {
            Text(current.caption)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 48)
                .accessibilityHidden(true)
        }
    }
}

private struct PhotoPage: View {
    let photo: GalleryPhoto

    var body: some View {
        if let image = UIImage(named: photo.assetName) {
            ZoomableImage(image: image, accessibilityLabel: photo.caption)
        } else {
            Image(systemName: Symbol.gallery)
                .font(.largeTitle)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityLabel(photo.caption)
        }
    }
}
