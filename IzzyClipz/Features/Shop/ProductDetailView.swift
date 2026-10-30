import SwiftUI

/// One Bravo product: its photo, price, what it does, and a link to buy it
/// on Bravo's store. Pushed from the Shop tab.
struct ProductDetailView: View {
    let product: Product

    @Environment(AppRouter.self) private var router
    @Environment(BravoStore.self) private var bravo

    private let catalog = AppData.products

    private var isSoldOut: Bool {
        bravo.isSoldOut(product)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                photo
                ProductDetailHeading(product: product, price: bravo.price(for: product), isSoldOut: isSoldOut)
                summary
                actions
                InfoCallout(title: "Shipping", message: catalog.sponsor.shippingNote, symbol: Symbol.shipping)
                ProductHighlights(highlights: product.highlights)
                finePrint
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photo: some View {
        ProductPhoto(product: product, cornerRadius: 16, inset: 8)
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .card(padding: 12)
            .overlay(alignment: .topLeading) {
                if isSoldOut {
                    ProductSoldOutBadge()
                        .padding(14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo of \(product.name)")
            .accessibilityAddTraits(.isImage)
    }

    private var summary: some View {
        Text(product.summary)
            .font(.body)
            .foregroundStyle(Theme.bone)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                router.openWeb(catalog.url(for: product))
            } label: {
                Text(buyTitle)
            }
            .buttonStyle(.primary(trailingSymbol: Symbol.external))
            .accessibilityHint("Opens \(product.name) on \(BravoShopCopy.storeHost)")
            .accessibilityIdentifier("buyProductButton")

            Button {
                router.openWeb(catalog.storeURL)
            } label: {
                HStack(spacing: 8) {
                    Text("Shop all \(catalog.sponsor.name) products")
                    Image(systemName: Symbol.external)
                        .font(.subheadline.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.tertiary)
            .accessibilityHint("Opens \(BravoShopCopy.storeHost)")
            .accessibilityIdentifier("productShopAllBravo")
        }
    }

    /// "Buy on bravohairgel.com", or a softer wording while it's sold out.
    private var buyTitle: String {
        let host = BravoShopCopy.storeHost
        return isSoldOut ? "See it on \(host)" : "Buy on \(host)"
    }

    private var finePrint: some View {
        Text(BravoShopCopy.finePrint)
            .font(.footnote)
            .foregroundStyle(Theme.smoke)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "BRAVO · HAIR GELS", the name, the price and size, and a sold-out note.
private struct ProductDetailHeading: View {
    let product: Product
    let price: Price
    let isSoldOut: Bool

    private let sponsor = AppData.products.sponsor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(sponsor.name.uppercased()) · \(product.category.title.uppercased())")
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(Theme.bone)
                .accessibilityLabel("\(sponsor.name), \(product.category.title)")
            Text(product.name.uppercased())
                .textRole(.displayL)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(product.name)
                .accessibilityAddTraits(.isHeader)
            priceLine
            if isSoldOut {
                soldOutNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceLine: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(price.label)
                .textRole(.displayM)
                .foregroundStyle(Theme.bone)
            if let size = product.size {
                Chip(text: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(priceAccessibilityText)
    }

    private var priceAccessibilityText: String {
        guard let size = product.size else { return "Price \(price.label)" }
        return "Price \(price.label), \(size)"
    }

    private var soldOutNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Symbol.info)
                .accessibilityHidden(true)
            Text("\(sponsor.name)'s store shows this as sold out right now.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.bone)
        .accessibilityElement(children: .combine)
    }
}

/// The product's selling points, from Bravo's description, with check marks.
private struct ProductHighlights: View {
    let highlights: [String]

    var body: some View {
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Highlights")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { item in
                        row(item.element)
                    }
                }
                .card()
            }
        }
    }

    private func row(_ highlight: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: Symbol.included)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.electric)
                .accessibilityHidden(true)
            Text(highlight)
                .font(.body)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
