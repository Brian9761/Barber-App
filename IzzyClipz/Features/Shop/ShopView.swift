import SwiftUI

/// The Shop tab: products sold only at the shop. Until the shop adds its own, it says they're
/// coming and points to the counter.
struct ShopView: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                title: "Shop exclusives",
                symbol: Symbol.shop,
                message: "New products are coming soon. Ask at the shop what's in stock."
            )
            .screenBackground()
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
