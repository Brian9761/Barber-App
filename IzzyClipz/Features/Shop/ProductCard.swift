import SwiftUI

/// A Bravo product in the Shop: its photo on white, name, size and price.
///
/// The price is Bravo's current one once the store has answered, otherwise
/// the one bundled with the app. Give it the full height of its grid row so
/// cards side by side line up.
struct ProductCard: View {
    let product: Product
    /// Shows the category ("HAIR GELS") above the name, for mixed lists.
    var showsCategory = false

    @Environment(BravoStore.self) private var bravo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            photo
            details
            Spacer(minLength: 0)
            priceRow
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card(padding: 12)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var photo: some View {
        ProductPhoto(product: product, cornerRadius: 14, inset: 6)
            .overlay(alignment: .topLeading) {
                if bravo.isSoldOut(product) {
                    ProductSoldOutBadge()
                        .padding(6)
                }
            }
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showsCategory {
                Text(product.category.title.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.red)
            }
            Text(product.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let size = product.size {
                Text(size)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The price with a "more" arrow, or the price alone when there's no room.
    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                price
                Spacer(minLength: 4)
                arrow
            }
            price
        }
    }

    private var price: some View {
        Text(bravo.price(for: product).label)
            .font(.title3.weight(.heavy))
            .foregroundStyle(Theme.red)
    }

    private var arrow: some View {
        Image(systemName: Symbol.chevron)
            .font(.caption.weight(.heavy))
            .foregroundStyle(Theme.blue)
            .frame(width: 28, height: 28)
            .background(Theme.tint, in: Circle())
            .accessibilityHidden(true)
    }

    /// What VoiceOver reads for a product: "Blue Hair Gel, 16 oz, $17.99, sold out".
    static func accessibilityText(for product: Product, price: Price, isSoldOut: Bool) -> String {
        var parts = [product.name]
        if let size = product.size {
            parts.append(size)
        }
        parts.append(price.label)
        if isSoldOut {
            parts.append("sold out")
        }
        return parts.joined(separator: ", ")
    }
}

/// A product's photo on white, kept square whatever the image's shape.
struct ProductPhoto: View {
    let product: Product
    var cornerRadius: CGFloat = 14
    /// White space between the photo and the edge.
    var inset: CGFloat = 6

    var body: some View {
        Theme.surface
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(product.imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(inset)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// "Sold out", laid over a product's photo. Hidden from VoiceOver: the
/// product's label or a note next to it says so instead.
struct ProductSoldOutBadge: View {
    var body: some View {
        Text("Sold out")
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.85), in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Wording and assets shared by the Shop screens.
enum BravoShopCopy {
    /// Bravo's wordmark. A template image, so it can be tinted white.
    static let logoAsset = "BravoLogo"

    /// The store's address as people know it: "bravohairgel.com".
    static var storeHost: String {
        let host = AppData.products.sponsor.storeURL.host ?? "bravohairgel.com"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Why the shop carries Bravo, in the same words as the Home banner.
    static var partnerLine: String {
        let shop = AppData.shop.name
        let sponsor = AppData.products.sponsor.name
        return "\(shop) is proud to partner with \(sponsor): the gels, clay and pomade we trust in the chair."
    }

    /// Who sells the products and where the prices come from.
    static var finePrint: String {
        let sponsor = AppData.products.sponsor.name
        return "Sold and shipped by \(sponsor). Prices from \(storeHost); you'll see the final price at checkout."
    }
}
