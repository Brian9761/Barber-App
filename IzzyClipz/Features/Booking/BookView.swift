import SwiftUI

/// Book in three steps: service, barber, review. The last step hands off to
/// Squire, where the client picks a time and confirms.
struct BookView: View {
    @Environment(AppRouter.self) private var router
    private let catalog = AppData.catalog

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.bookingPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    StepHeader(step: 1, title: "Pick a service", subtitle: "Prices and times come straight from the shop's booking menu.")

                    ForEach(catalog.categories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.title, systemImage: category.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.secondaryText)
                            ForEach(catalog.services(in: category)) { service in
                                NavigationLink(value: BookingStep.chooseBarber(serviceID: service.id)) {
                                    ServiceRow(service: service)
                                        .card(padding: 14)
                                }
                                .buttonStyle(.pressable)
                                .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                                .accessibilityIdentifier("bookService-\(service.id)")
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            router.book(.anything)
                        } label: {
                            Label("Browse everything on Squire", systemImage: Symbol.external)
                        }
                        .buttonStyle(.secondary)

                        CallButton {
                            Label("Prefer to call? \(AppData.shop.phone.display)", systemImage: Symbol.call)
                        }
                        .buttonStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("Book")
            .navigationDestination(for: BookingStep.self) { step in
                switch step {
                case .chooseBarber(let serviceID):
                    if let service = catalog.service(withID: serviceID) {
                        ChooseBarberView(service: service)
                    } else {
                        ContentUnavailableView("Service unavailable", systemImage: Symbol.info)
                    }
                case .review(let choice):
                    BookingReviewView(choice: choice)
                }
            }
        }
    }
}

private struct StepHeader: View {
    let step: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEP \(step) OF 3")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.red)
            Text(title.uppercased())
                .font(.display(.title))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ChooseBarberView: View {
    let service: Service
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StepHeader(step: 2, title: "Pick your barber", subtitle: "\(service.name) · \(catalog.durationSummary(forService: service.id))")

                if let option = catalog.firstAvailableOption(forService: service.id) {
                    NavigationLink(value: BookingStep.review(.firstAvailable(option))) {
                        FirstAvailableRow(option: option)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(FirstAvailableRow.accessibilityText(for: option))
                    .accessibilityIdentifier("chooseFirstAvailable")
                }

                ForEach(offerings) { offering in
                    if let barber = catalog.barber(withID: offering.barberID) {
                        let isFavorite = favorites.isFavorite(barber.id)
                        NavigationLink(value: BookingStep.review(.offering(offering))) {
                            OfferingRow(offering: offering, barber: barber, isFavorite: isFavorite)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(OfferingRow.accessibilityText(offering: offering, barber: barber, isFavorite: isFavorite))
                        .accessibilityIdentifier("choose-\(offering.id)")
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The client's favorite barber first, then cheapest first.
    private var offerings: [Offering] {
        let all = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return all }
        return all.filter { $0.barberID == favorite } + all.filter { $0.barberID != favorite }
    }
}

private struct BookingReviewView: View {
    let choice: BookingChoice
    @Environment(AppRouter.self) private var router
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(step: 3, title: "Review & book", subtitle: "Next, you'll choose a time and confirm your details on Squire, the shop's booking system.")

                VStack(alignment: .leading, spacing: 14) {
                    if let service {
                        summaryRow(title: "Service", value: service.name)
                    }
                    summaryRow(title: "Barber", value: barberText)
                    summaryRow(title: "Price", value: priceText)
                    summaryRow(title: "Length", value: durationText)
                    if case .offering(let offering) = choice, let note = offering.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()

                Button {
                    router.book(choice.request)
                } label: {
                    Label("Choose a Time", systemImage: Symbol.calendar)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("chooseTimeButton")

                Text("Squire shows your barber's open times and any extras they offer before you confirm.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var service: Service? {
        catalog.service(withID: choice.serviceID)
    }

    private var barberText: String {
        switch choice {
        case .firstAvailable:
            return "First available"
        case .offering(let offering):
            return catalog.barber(withID: offering.barberID)?.name ?? "Your barber"
        }
    }

    private var priceText: String {
        switch choice {
        case .firstAvailable(let option): return option.priceLabel
        case .offering(let offering): return offering.price.label
        }
    }

    private var durationText: String {
        switch choice {
        case .firstAvailable(let option): return option.durationLabel
        case .offering(let offering): return offering.durationLabel
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}
