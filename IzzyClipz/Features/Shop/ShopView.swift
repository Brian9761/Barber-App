import SwiftUI

/// The Shop tab: Bravo, the shop's product partner, and the products it sells on bravohairgel.com.
///
/// Top to bottom: "THE SHOP" with the bag button (its red count badge is this screen's one red),
/// Bravo's logo and "PROUD BRAVO PARTNER", a still bone band with Bravo's free-shipping line, one
/// featured card (Blue Hair Gel 16 oz) in the promo gradient with the gel drip, then every other
/// item in a two-column grid with a "+" to add it to the bag. An item that comes in several sizes
/// has one tile; the size is picked on its page. Last, Bravo in its own words and a link to its
/// whole store.
///
/// Once the big title has scrolled under the navigation bar, the bar shows "Shop" and a bag button
/// (bone, no badge), so the bag stays one tap away from anywhere on the page.
struct ShopView: View {
    private let catalog = AppData.products
    /// Popped back to the shop when the Shop tab is tapped again.
    @State private var path = NavigationPath()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "shopTop"

    /// The one featured card: the first featured product (Blue Hair Gel 16 oz), as its item's lead size.
    private var featured: Product? {
        catalog.featured.first.map { catalog.lead(for: $0) }
    }

    /// Every other item once, the other featured ones first, in catalog order.
    private var gridProducts: [Product] {
        let others = catalog.leadProducts.filter { $0.id != featured?.id }
        return others.filter(\.isFeatured) + others.filter { !$0.isFeatured }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ShopHeader()
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Theme.Space.xs)
                            .id(Self.topID)
                        ShopShippingBand()
                            .padding(.top, Theme.Space.l)
                        if let featured {
                            ShopFeaturedCard(product: featured)
                                .padding(.horizontal, Theme.gutter)
                                .padding(.top, Theme.Space.s)
                        }
                        ShopProductGrid(products: gridProducts)
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Theme.Space.xl)
                        ShopAboutSponsor()
                            .padding(.horizontal, Theme.gutter)
                            .padding(.top, Theme.Space.section + Theme.Space.s)
                    }
                    .padding(.bottom, Theme.Space.section)
                }
                .screenBackground()
                .tabScreen()
                .modifier(ShopRootBar())
                .navigationDestination(for: Product.self) { product in
                    ProductDetailView(product: product)
                        .barberPolePushRide()
                        .tabScreen()
                }
                .onTabReselect {
                    if path.isEmpty {
                        withAnimation(reduceMotion ? nil : .smooth) {
                            scroller.scrollTo(Self.topID, anchor: .top)
                        }
                    } else {
                        path = NavigationPath()
                    }
                }
            }
        }
    }
}

/// The Shop's navigation bar: inline and empty while "THE SHOP" is on screen (so "Shop" never sits
/// right above "THE SHOP"), then "Shop" and the bag once it has scrolled under. The bar stays native;
/// "Shop" is also the back button's title on a product page.
/// The Shop's navigation bar: no title (THE SHOP is the page's own title) and the bag button,
/// always within reach. The bag's count is the Shop's one red, on the button.
///
/// The bag used to sit next to the page title and move into the bar once the title scrolled away,
/// but that depended on measuring where the bar ends, which iOS 26 reports differently: the bar
/// showed a second bag and a second title at rest.
private struct ShopRootBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Names the bar for VoiceOver and the back button on product pages.
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Hides the inline title, which would repeat THE SHOP right under it.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShopToolbarBagButton(identifier: "shopBagButton")
                }
            }
    }
}

// MARK: - Header

/// "THE SHOP", and Bravo's logo with "PROUD BRAVO PARTNER" under it.
private struct ShopHeader: View {

    private let sponsor = AppData.products.sponsor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ScreenHeader(title: "The shop")
            partnerLine
        }
    }

    /// Bravo's logo | PROUD BRAVO PARTNER.
    private var partnerLine: some View {
        HStack(spacing: Theme.Space.m) {
            Image(BravoShopCopy.logoAsset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 20)
                .foregroundStyle(Theme.bone)
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1, height: 16)
            Text("Proud \(sponsor.name) partner")
                .textRole(.monoTag)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proud \(sponsor.name) partner")
    }
}

// MARK: - Free shipping

/// Bravo's free-shipping line on a still bone band, full bleed and tilted 2° like a strip of tape.
/// It doesn't move: a ticker that can't be paused fails WCAG 2.2.2 and runs the battery down.
private struct ShopShippingBand: View {
    private let note = AppData.products.sponsor.shippingNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: Symbol.shipping)
                .font(.system(size: 13, weight: .bold))
                .accessibilityHidden(true)
            Text(note)
                .textRole(.monoNumber)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background {
            // Wider than the screen, so the tilt never shows a corner.
            Theme.bone
                .padding(.horizontal, -32)
        }
        .rotationEffect(.degrees(-2))
        // Room for the tilt above and below.
        .padding(.vertical, Theme.Space.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note)
    }
}

// MARK: - Featured

/// The featured product in the promo gradient: the electric gel drip along the top, "FEATURED ·
/// BRAVO", the name, the sizes, the price, a bone "+ ADD" and the jar in a white disc that bleeds
/// off the right edge. At accessibility text sizes the disc moves above the text.
///
/// The card is a link to the product, and "+ ADD" is a sibling button laid over it (never inside
/// the link's label). To put the button exactly where the card leaves room for it at every text
/// size, a second, invisible copy of the card's text is laid over the first with only the button
/// showing.
private struct ShopFeaturedCard: View {
    let product: Product

    @Environment(BravoStore.self) private var bravo
    @Environment(BagStore.self) private var bag
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var justAdded = false
    @State private var addCount = 0

    private let sponsor = AppData.products.sponsor
    private static let discSize: CGFloat = 170
    /// How much of the disc hangs off the card's right edge.
    private static let discBleed: CGFloat = 34
    /// The room the text leaves for the disc.
    private static let discReserve: CGFloat = discSize - discBleed + 10
    /// Clears the longest drip and its droplet.
    private static let topInset: CGFloat = DripEdge.depth(of: DripEdge.gelCard, band: 5) + 8

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }
    private var isSoldOut: Bool { bravo.isSoldOut(product) }
    private var otherSizes: [String] { BravoShopCopy.otherSizes(of: product) }

    var body: some View {
        ZStack {
            NavigationLink(value: product) {
                face(isGhost: false)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Featured: " + ProductCard.accessibilityText(
                for: product,
                price: bravo.price(for: product),
                isSoldOut: isSoldOut,
                otherSizes: otherSizes
            ))
            .accessibilityHint(otherSizes.isEmpty ? "Shows details" : "Shows details and sizes")
            .accessibilityIdentifier("product-\(product.id)")

            face(isGhost: true)
        }
        .sensoryFeedback(.success, trigger: addCount)
        .task(id: addCount) {
            guard addCount > 0 else { return }
            do {
                try await Task.sleep(for: .seconds(1.2))
                justAdded = false
            } catch {
                // Tapped again: the newer tap's task resets it.
            }
        }
        .onDisappear { justAdded = false }
    }

    /// The card's text column. `isGhost` hides everything but the add button, which only the ghost shows.
    private func face(isGhost: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLargeText {
                disc(side: 120)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, Theme.Space.l)
                    .shopGhost(isGhost)
            }
            HStack(spacing: Theme.Space.s) {
                Text("Featured · \(sponsor.name)")
                    .textRole(.monoTag)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                if isSoldOut {
                    MonoTag(text: "Sold out", style: .bone)
                }
            }
            .shopGhost(isGhost)
            Text(product.name)
                .textRole(.displayM)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xs)
                .shopGhost(isGhost)
            if let sizeLine {
                Text(sizeLine)
                    .textRole(.monoNumber)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.xs)
                    .shopGhost(isGhost)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Theme.Space.l) {
                    price.shopGhost(isGhost)
                    addButton.shopGhost(!isGhost)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    price.shopGhost(isGhost)
                    addButton.shopGhost(!isGhost)
                }
            }
            .padding(.top, Theme.Space.l)
        }
        .padding(.leading, 20)
        .padding(.trailing, isLargeText ? 20 : Self.discReserve)
        .padding(.top, Self.topInset)
        .padding(.bottom, Theme.Space.xl)
        .frame(maxWidth: .infinity, minHeight: 186, alignment: .topLeading)
        .background {
            if !isGhost {
                background
            }
        }
    }

    /// "16 OZ · ALSO IN 4 OZ".
    private var sizeLine: String? {
        let parts = [product.size, otherSizes.isEmpty ? nil : "also in \(otherSizes.joined(separator: ", "))"]
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    private var price: some View {
        Text(bravo.price(for: product).label)
            .textRole(.priceL)
            .foregroundStyle(Color.white)
            .lineLimit(1)
    }

    private var addButton: some View {
        Button {
            guard bag.add(product) else { return }
            ShopBagFeedback.announceAdded(product)
            addCount += 1
            justAdded = true
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: justAdded ? Symbol.checkmark : Symbol.add)
                    .font(.system(size: 13, weight: .heavy))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(justAdded ? "Added" : "Add")
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: justAdded)
        }
        .buttonStyle(.compact)
        .disabled(!bag.canAdd(product) && !justAdded)
        .accessibilityLabel("Add \(product.name) to bag")
        .accessibilityValue(otherSizes.isEmpty ? "" : (product.size ?? ""))
        .accessibilityIdentifier("quickAdd-\(product.id)")
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return Theme.promoGradient
            .overlay(alignment: .trailing) {
                if !isLargeText {
                    disc(side: Self.discSize)
                        .offset(x: Self.discBleed, y: Theme.Space.s)
                }
            }
            .overlay(alignment: .top) {
                DripEdge(drips: DripEdge.gelCard, band: 5)
                    .fill(Theme.electric)
                    .frame(height: DripEdge.depth(of: DripEdge.gelCard, band: 5))
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
    }

    /// The jar in a white disc, tilted like a sticker.
    private func disc(side: CGFloat) -> some View {
        Image(product.imageName)
            .resizable()
            .scaledToFit()
            .padding(side * 0.04)
            .frame(width: side, height: side)
            .background(Color.white)
            .clipShape(Circle())
            .rotationEffect(.degrees(-8))
            .shadow(color: .black.opacity(0.35), radius: 13, x: -12, y: 10)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// In the ghost copy of a card (laid over the real card to place its button), takes the same
    /// room but shows nothing, lets taps through to the card and stays out of VoiceOver.
    @ViewBuilder
    func shopGhost(_ isGhost: Bool) -> some View {
        if isGhost {
            hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            self
        }
    }
}

// MARK: - Grid

/// Every other item in two columns (one at accessibility text sizes), cards in a row as tall as the
/// tallest so their prices line up.
private struct ShopProductGrid: View {
    let products: [Product]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    private var rows: [[Product]] {
        stride(from: 0, to: products.count, by: columns).map { start in
            Array(products[start..<min(start + columns, products.count)])
        }
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl + Theme.Space.xxs) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    ForEach(row) { product in
                        ShopProductTile(product: product)
                            .frame(maxWidth: .infinity)
                    }
                    if row.count < columns {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                // Each card as tall as the tallest in its row.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A product card that opens the product's page, with the "+" laid over its photo as a sibling.
private struct ShopProductTile: View {
    let product: Product

    @Environment(BravoStore.self) private var bravo

    private var otherSizes: [String] { BravoShopCopy.otherSizes(of: product) }

    var body: some View {
        NavigationLink(value: product) {
            ProductCard(product: product, sizeCount: otherSizes.count + 1)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(ProductCard.accessibilityText(
            for: product,
            price: bravo.price(for: product),
            isSoldOut: bravo.isSoldOut(product),
            otherSizes: otherSizes
        ))
        .accessibilityHint(otherSizes.isEmpty ? "Shows details" : "Shows details and sizes")
        .accessibilityIdentifier("product-\(product.id)")
        .overlay(alignment: .top) {
            // The photo's frame (full width, the same shape, at the top), so the "+" lands on its corner.
            Color.clear
                .aspectRatio(ProductCard.photoAspectRatio, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    ShopQuickAddButton(product: product)
                        .padding(Theme.Space.xxs)
                }
        }
    }
}

// MARK: - About

/// Bravo in its own words, a link to its whole store, and who sells and ships.
private struct ShopAboutSponsor: View {
    @Environment(AppRouter.self) private var router
    private let catalog = AppData.products

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
            SectionHeader("About \(catalog.sponsor.name)")
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(catalog.sponsor.tagline)
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(catalog.sponsor.about.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: Theme.Space.xl)
            Button {
                router.openWeb(catalog.storeURL)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    // "SHOP ALL ON BRAVOHAIRGEL.COM" would wrap at 375 and 393 pt; the hint names the site.
                    Text("Shop all \(catalog.sponsor.name) products")
                    Image(systemName: Symbol.external)
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Opens \(BravoShopCopy.storeHost)")
            .accessibilityIdentifier("shopAllBravo")
            Text(BravoShopCopy.finePrint)
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
