import SwiftUI

struct ServicesView: View {
    @State private var query = ""
    private let catalog = AppData.catalog

    private var results: [Service] {
        catalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(catalog.categories) { category in
                    let services = results.filter { $0.category == category }
                    if !services.isEmpty {
                        Section {
                            ForEach(services) { service in
                                NavigationLink(value: service) {
                                    ServiceRow(service: service)
                                }
                                .listRowBackground(Theme.surface)
                                .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                                .accessibilityIdentifier("service-\(service.id)")
                            }
                        } header: {
                            Label(category.title, systemImage: category.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }

                if !results.isEmpty {
                    Section {
                        Text("Prices are from the shop's booking menu and may vary by barber. You'll see the final price before you confirm.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Search services")
            .navigationTitle("Services")
            .navigationDestination(for: Service.self) { ServiceDetailView(service: $0) }
            .navigationDestination(for: Barber.self) { BarberDetailView(barber: $0) }
        }
    }
}

struct ServiceRow: View {
    let service: Service

    var body: some View {
        HStack(spacing: 14) {
            ServiceIcon(symbol: service.symbol, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(AppData.catalog.durationSummary(forService: service.id))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Text(AppData.catalog.priceSummary(forService: service.id))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    static func accessibilityText(for service: Service) -> String {
        "\(service.name), \(AppData.catalog.priceSummary(forService: service.id)), \(AppData.catalog.durationSummary(forService: service.id))"
    }
}
