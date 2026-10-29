import SwiftUI

/// The Shop tab: Bravo, the shop's product partner, and the products it
/// sells on bravohairgel.com, by category.
struct ShopView: View {
    private let catalog = AppData.products

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    ShopPartnerHeader()
                        .padding(.horizontal, Theme.gutter)
                    if !catalog.featured.isEmpty {
                        ShopFeaturedSection(products: catalog.featured)
                    }
                    ForEach(catalog.categories) { category in
                        ShopCategorySection(category: category, products: catalog.products(in: category))
                    }
                    ShopAboutSponsor()
                    footnote
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .screenBackground()
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Product.self) { product in
                ProductDetailView(product: product)
            }
        }
    }

    private var footnote: some View {
        Text(BravoShopCopy.finePrint)
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Partner header

/// Royal blue to navy card: "Proud Bravo partner", Bravo's logo and tagline,
/// why the shop uses it, shipping, and a link to the whole store.
private struct ShopPartnerHeader: View {
    @Environment(AppRouter.self) private var router
    private let sponsor = AppData.products.sponsor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            partnerLabel
            logo
            copy
            shippingNote
            shopAllButton
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { backdrop }
        .overlay(alignment: .top) {
            StripeBand(stripeWidth: 8)
                .frame(height: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: Theme.blueDeep.opacity(0.28), radius: 16, y: 8)
    }

    private var partnerLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: Symbol.partner)
                .font(.subheadline.weight(.bold))
            Text("PROUD \(sponsor.name.uppercased()) PARTNER")
                .font(.caption.weight(.heavy))
                .tracking(1.6)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.red, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proud \(sponsor.name) partner")
    }

    private var logo: some View {
        Image(BravoShopCopy.logoAsset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.white)
            .frame(maxWidth: 230, alignment: .leading)
            .accessibilityLabel("\(sponsor.name) Professional Grooming")
            .accessibilityAddTraits(.isHeader)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sponsor.tagline)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(BravoShopCopy.partnerLine)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shippingNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Symbol.shipping)
                .font(.subheadline.weight(.semibold))
                .accessibilityHidden(true)
            Text(sponsor.shippingNote)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var shopAllButton: some View {
        Button {
            router.openWeb(AppData.products.storeURL)
        } label: {
            HStack(spacing: 8) {
                Text("Shop all \(sponsor.name)")
                Image(systemName: Symbol.external)
                    .font(.subheadline.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.secondary)
        .accessibilityHint("Opens \(BravoShopCopy.storeHost)")
        .accessibilityIdentifier("shopAllBravo")
    }

    private var backdrop: some View {
        ZStack {
            Theme.heroGradient
            StripeTexture(opacity: 0.08)
        }
    }
}

// MARK: - Featured

/// "Barbershop favorites": the featured products in a row that scrolls
/// sideways, snapping to each card.
private struct ShopFeaturedSection: View {
    let products: [Product]
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader("Barbershop favorites")
                .padding(.horizontal, Theme.gutter)
            ScrollView(.horizontal) {
                cards
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(products) { product in
                ShopProductLink(product: product, identifier: "featured-\(product.id)", showsCategory: true)
                    .frame(width: min(cardWidth, 290))
            }
        }
        .scrollTargetLayout()
        // Every card as tall as the tallest one.
        .fixedSize(horizontal: false, vertical: true)
        // Room for the cards' shadows.
        .padding(.vertical, 14)
    }
}

// MARK: - Categories

/// One category's products in a two-column grid (one column at the largest
/// text sizes).
private struct ShopCategorySection: View {
    let category: ProductCategory
    let products: [Product]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    var body: some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(category.title)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(products) { product in
                        ShopProductLink(product: product, identifier: "product-\(product.id)")
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

/// A product card that opens the product's page.
private struct ShopProductLink: View {
    let product: Product
    let identifier: String
    var showsCategory = false

    @Environment(BravoStore.self) private var bravo

    var body: some View {
        NavigationLink(value: product) {
            ProductCard(product: product, showsCategory: showsCategory)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows details and where to buy")
        .accessibilityIdentifier(identifier)
    }

    private var accessibilityText: String {
        ProductCard.accessibilityText(
            for: product,
            price: bravo.price(for: product),
            isSoldOut: bravo.isSoldOut(product)
        )
    }
}

// MARK: - About

/// Bravo in its own words: who runs it and how its products are made.
private struct ShopAboutSponsor: View {
    private let sponsor = AppData.products.sponsor

    var body: some View {
        if !sponsor.about.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("About \(sponsor.name)")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sponsor.about.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}
