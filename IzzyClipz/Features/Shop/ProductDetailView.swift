import SwiftUI

/// One of the shop's products: a big photo, the name, the price (or a note to ask), the full
/// description, and where to get it, with Call and Directions.
struct ProductDetailView: View {
    let product: IzzyAPI.Product

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                ProductPhoto(url: product.imageUrl, name: product.name)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(product.name)
                        .textRole(.displayL)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("productDetail")
                    Text(product.priceLabel ?? "Ask at the shop for the price")
                        .textRole(product.priceLabel == nil ? .body : .priceL)
                        .foregroundStyle(product.priceLabel == nil ? Theme.smoke : Theme.bone)
                        .accessibilityIdentifier("productPrice")
                }

                if let description = product.description, !description.isEmpty {
                    Text(description)
                        .textRole(.body)
                        .foregroundStyle(Theme.bone)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProductAvailabilityCard()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)
        }
        .screenBackground()
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Available at the shop — ask at the counter", with Call and Directions.
private struct ProductAvailabilityCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.location)
                    .font(.title3)
                    .foregroundStyle(Theme.electric)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Available at the shop")
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    Text("Ask at the counter. Pay at the shop: \(AppData.shop.paymentMethods.joined(separator: " or ").lowercased()).")
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppData.shop.address.singleLine)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Theme.Space.m) {
                CallButton {
                    Label("Call", systemImage: Symbol.call)
                }
                .buttonStyle(.tertiary)
                DirectionsButton {
                    Label("Directions", systemImage: Symbol.directions)
                }
                .buttonStyle(.tertiary)
            }
        }
        .card(padding: Theme.Space.xl)
    }
}
