import SwiftUI

/// The shop's Instagram (@izzy_clipz_barbershop_) as a card, opened outside the app: Instagram's
/// app if it's installed (through its universal link), Safari otherwise.
///
/// Honest by design: the app can't load posts or follow anyone, so the card never shows photos as
/// if they were the account's posts. Bundled photos appear only labeled "FROM THE SHOP".
///
/// - `.home`: one big tap target (`instagramButton`) with the handle, the logo sticker on its
///   corner and, optionally, up to three of the shop's photos.
/// - `.visit`: the handle with two actions, "Open in Instagram ↗" (`visitInstagramLink`) and
///   "Message us ↗" (`visitInstagramMessage`, an Instagram DM).
struct InstagramCard: View {
    enum Variant {
        case home
        case visit
    }

    var variant: Variant = .home
    /// Up to three bundled photos for the Home card, labeled "FROM THE SHOP".
    var photos: [GalleryPhoto] = []

    @Environment(AppRouter.self) private var router
    private let shop = AppData.shop

    /// Opens a direct-message thread with the shop in Instagram.
    static var messageURL: URL {
        URL(string: "https://ig.me/m/\(AppData.shop.instagramHandle)") ?? AppData.shop.instagramURL
    }

    var body: some View {
        switch variant {
        case .home: homeCard
        case .visit: visitCard
        }
    }

    // MARK: Home

    private var homeCard: some View {
        Button {
            router.openOutside(shop.instagramURL)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    header
                    handle
                    Text("Follow the shop on Instagram")
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                }
                // Clear of the logo sticker on the corner.
                .padding(.trailing, Self.stickerRoom)
                if !photos.isEmpty {
                    photoStrip
                }
            }
            .card()
            .overlay(alignment: .topTrailing) {
                LogoSticker(width: 76, rotation: .degrees(7))
                    .offset(x: -6, y: -12)
                    .accessibilityHidden(true)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(shop.name) on Instagram, @\(shop.instagramHandle)")
        .accessibilityHint("Opens Instagram")
        .accessibilityIdentifier("instagramButton")
    }

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Kicker("From the shop")
            HStack(spacing: Theme.Space.xs) {
                ForEach(photos.prefix(3)) { photo in
                    FillImage(name: photo.assetName, anchor: FillImage.editorial)
                        .frame(height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: Visit

    private var visitCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                handle
            }
            .padding(.trailing, Self.stickerRoom)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.s) { visitActions }
                VStack(alignment: .leading, spacing: Theme.Space.s) { visitActions }
            }
        }
        .card()
        .overlay(alignment: .topTrailing) {
            LogoSticker(width: 76, rotation: .degrees(7))
                .offset(x: -6, y: -12)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var visitActions: some View {
        Button {
            router.openOutside(shop.instagramURL)
        } label: {
            Label("Open in Instagram", systemImage: Symbol.external)
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.compact)
        .accessibilityLabel("Open @\(shop.instagramHandle) in Instagram")
        .accessibilityIdentifier("visitInstagramLink")

        Button {
            router.openOutside(Self.messageURL)
        } label: {
            Label("Message us", systemImage: Symbol.external)
                .labelStyle(TrailingIconLabelStyle())
        }
        .buttonStyle(.compact)
        .accessibilityLabel("Message \(shop.name) on Instagram")
        .accessibilityIdentifier("visitInstagramMessage")
    }

    // MARK: Shared

    /// Room kept free for the logo sticker on the card's top-right corner.
    private static let stickerRoom: CGFloat = 72

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: Symbol.instagram)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(Theme.bone, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Kicker("Instagram")
        }
    }

    private var handle: some View {
        Text("@\(shop.instagramHandle)")
            .font(BrandFont.condensedExtraBold.font(size: 21, relativeTo: .title3))
            .foregroundStyle(Theme.bone)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// A label with its icon after the title: "Open in Instagram ↗".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon
                .font(.system(size: 11, weight: .heavy))
        }
    }
}
