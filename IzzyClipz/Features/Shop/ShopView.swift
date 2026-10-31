import SwiftUI

/// The Shop tab: the shop's own products, sold only at the shop. It's a showcase, not a store:
/// there's no cart and no checkout, and every product says it's available at the shop.
///
/// Products come live from the shop's server (the owner adds them in the Izzy Clipz Business app).
/// Pull to refresh. Loading, empty and error states each say what's going on and what to do.
struct ShopView: View {
    @State private var path: [IzzyAPI.Product] = []

    var body: some View {
        NavigationStack(path: $path) {
            ShopScreen()
                .navigationTitle("Shop")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: IzzyAPI.Product.self) { product in
                    ProductDetailView(product: product)
                }
        }
    }
}

private struct ShopScreen: View {
    @Environment(ProductsStore.self) private var products

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                intro
                content
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .refreshable {
            await products.refresh()
        }
        .task {
            await products.load(maxAge: 5 * 60)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Only at \(AppData.shop.name)")
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .accessibilityAddTraits(.isHeader)
            Text("Products you can pick up at the shop. Ask at the counter.")
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        if let list = products.value {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let error = products.error {
                    StaleDataNote(text: "Couldn't refresh the products. \(error.userMessage)")
                }
                if list.isEmpty {
                    ShopEmptyState()
                } else {
                    ProductGrid(products: list)
                }
            }
        } else if let error = products.error {
            ErrorStateView(
                title: "Couldn't load the products",
                message: error.userMessage,
                onRetry: { Task { await products.refresh() } },
                isRetrying: products.isLoading
            )
            .accessibilityIdentifier("shopError")
        } else {
            LoadingStateView(text: "Loading the shop's products…")
                .accessibilityIdentifier("shopLoading")
        }
    }
}

/// No products yet: "New products are coming soon", with a way to ask the shop.
private struct ShopEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.shop)
                    .font(.title2)
                    .foregroundStyle(Theme.bone)
                    .frame(width: 52, height: 52)
                    .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Nothing on the shelf yet")
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    Text("New products are coming soon. Ask at the shop what's in stock.")
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shopEmpty")
            CallButton {
                Label("Call the shop", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
        }
        .card(padding: Theme.Space.xl)
    }
}

/// Two columns of product tiles, one at the largest text sizes.
private struct ProductGrid: View {
    let products: [IzzyAPI.Product]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.l, alignment: .top), count: count),
            spacing: Theme.Space.l
        ) {
            ForEach(products) { product in
                NavigationLink(value: product) {
                    ProductTile(product: product)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ProductTile.accessibilityText(for: product))
                .accessibilityHint("Shows the product")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("product-\(product.id)")
            }
        }
    }
}

/// A product on an `ink3` card: its photo (or a placeholder), name, price when the shop lists one,
/// a short description and "Available at the shop".
private struct ProductTile: View {
    let product: IzzyAPI.Product

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ProductPhoto(url: product.imageUrl, name: product.name)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            Text(product.name)
                .textRole(.headline)
                .foregroundStyle(Theme.bone)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let price = product.priceLabel {
                Text(price)
                    .textRole(.price)
                    .foregroundStyle(Theme.bone)
            }
            if let description = product.description, !description.isEmpty {
                Text(description)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Label("Available at the shop", systemImage: Symbol.location)
                .textRole(.label)
                .foregroundStyle(Theme.smoke)
                .labelStyle(.titleAndIcon)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// "Sample pomade, $18, available at the shop".
    static func accessibilityText(for product: IzzyAPI.Product) -> String {
        [product.name, product.priceLabel, "available at the shop"].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A product's photo from the shop's server, filling its frame. Until it loads there's a spinner
/// on the placeholder; without a photo, or if it can't load, a plain placeholder with the bag
/// symbol (and, for a failed load, a note saying so).
struct ProductPhoto: View {
    let url: URL?
    let name: String

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .accessibilityLabel("Photo of \(name)")
                        case .failure:
                            placeholder(note: "Photo unavailable")
                        case .empty:
                            placeholder(note: nil, isLoading: true)
                        @unknown default:
                            placeholder(note: nil)
                        }
                    }
                } else {
                    placeholder(note: nil)
                }
            }
            .clipped()
    }

    private func placeholder(note: String?, isLoading: Bool = false) -> some View {
        ZStack {
            Theme.ink4
            VStack(spacing: Theme.Space.s) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.bone)
                } else {
                    Image(systemName: note == nil ? Symbol.shop : Symbol.photoUnavailable)
                        .font(.title)
                        .foregroundStyle(Theme.smoke)
                }
                if let note {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                }
            }
            .padding(Theme.Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note ?? (isLoading ? "Loading photo" : "No photo yet"))
    }
}
