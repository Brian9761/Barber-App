import SwiftUI

/// The Services tab: the whole menu by category, searchable, with each
/// service's price range and length.
struct ServicesView: View {
    @State private var query = ""
    private let catalog = AppData.catalog

    private var results: [Service] {
        catalog.search(query)
    }

    /// Whether the client has typed something to search for. Spaces alone
    /// still show the whole menu.
    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !isSearching {
                        ServicesHero()
                    }
                    ForEach(catalog.categories) { category in
                        ServiceCategorySection(
                            category: category,
                            services: results.filter { $0.category == category }
                        )
                    }
                    if !results.isEmpty {
                        footnote
                    }
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search services")
            .navigationTitle("Services")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Service.self) { ServiceDetailView(service: $0) }
            .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0) }
        }
    }

    private var footnote: some View {
        Text("Prices are from the shop's booking menu and can differ by barber. Squire shows your barber's price before you confirm.")
            .font(.footnote)
            .foregroundStyle(Theme.smoke)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Every cut, every price".
private struct ServicesHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EVERY CUT, EVERY PRICE")
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Prices straight from the shop's booking menu. Pick one to see each barber's price.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .card(padding: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every cut, every price. Prices straight from the shop's booking menu. Pick one to see each barber's price.")
    }
}

/// One category's services, under a title with the category's icon.
private struct ServiceCategorySection: View {
    let category: ServiceCategory
    let services: [Service]

    var body: some View {
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ServiceCategoryHeader(category: category)
                VStack(spacing: 10) {
                    ForEach(services) { service in
                        ServiceLink(service: service)
                    }
                }
            }
        }
    }
}

/// The section title look (heavy condensed caps) with the category's icon.
private struct ServiceCategoryHeader: View {
    let category: ServiceCategory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.smoke)
            Text(category.title.uppercased())
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A service card that opens the service's page.
private struct ServiceLink: View {
    let service: Service

    var body: some View {
        NavigationLink(value: service) {
            ServiceRow(service: service)
                .card(padding: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(ServiceRow.accessibilityText(for: service))
        .accessibilityHint("Shows each barber's price")
        .accessibilityIdentifier("service-\(service.id)")
    }
}
