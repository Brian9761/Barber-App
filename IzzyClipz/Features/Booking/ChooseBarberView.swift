import SwiftUI

/// Step 2 when the service was picked first: who does it. "First available"
/// comes first when several barbers share the service, then each barber's
/// version, the client's favorite barber at the top.
struct ChooseBarberView: View {
    let service: Service
    @Environment(Favorites.self) private var favorites
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StepHeader(step: 2, of: 4, title: "Pick your barber", subtitle: subtitle)
                    .padding(.bottom, 4)

                if let option = catalog.firstAvailableOption(forService: service.id) {
                    ChooseBarberFirstAvailableLink(option: option)
                    Text("Or choose your barber")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(offerings) { offering in
                    if let barber = catalog.barber(withID: offering.barberID) {
                        ChooseBarberOfferingLink(
                            offering: offering,
                            barber: barber,
                            isFavorite: favorites.isFavorite(barber.id)
                        )
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Haircut · $35–$45 · 45 min – 1 hr".
    private var subtitle: String {
        [
            service.name,
            catalog.priceSummary(forService: service.id),
            catalog.durationSummary(forService: service.id),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    /// The client's favorite barber first, then cheapest first.
    private var offerings: [Offering] {
        let all = catalog.offerings(forService: service.id)
        guard let favorite = favorites.barberID else { return all }
        return all.filter { $0.barberID == favorite } + all.filter { $0.barberID != favorite }
    }
}

/// Book the service with whoever is free first.
private struct ChooseBarberFirstAvailableLink: View {
    let option: FirstAvailableOption

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.firstAvailable(option))) {
            FirstAvailableRow(option: option)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(FirstAvailableRow.accessibilityText(for: option))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("chooseFirstAvailable")
    }
}

/// One barber's version of the service.
private struct ChooseBarberOfferingLink: View {
    let offering: Offering
    let barber: Barber
    let isFavorite: Bool

    var body: some View {
        NavigationLink(value: BookingStep.chooseTime(.offering(offering))) {
            OfferingRow(offering: offering, barber: barber, isFavorite: isFavorite, actionLabel: "Select")
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(OfferingRow.accessibilityText(offering: offering, barber: barber, isFavorite: isFavorite, verb: "Choose"))
        .accessibilityHint("Next, pick a day and time")
        .accessibilityIdentifier("choose-\(offering.id)")
    }
}
