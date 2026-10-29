import SwiftUI

/// The Book tab. Booking takes four steps: a service, a barber, a day and
/// time on the app's calendar, then a review that hands off to Squire, the
/// shop's booking system, to confirm the real slot.
struct BookView: View {
    @Environment(AppRouter.self) private var router

    private static let topID = "bookTop"

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.bookingPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Re-checked every minute, so an appointment that's over drops off.
                    TimelineView(.everyMinute) { context in
                        BookStartContent(now: context.date)
                    }
                    .id(Self.topID)
                }
                .onChange(of: router.finishedBookings) {
                    // Just saved: the new appointment is at the top.
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
            .screenBackground()
            .navigationTitle("Book")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: BookingStep.self) { step in
                BookStepDestination(step: step)
            }
        }
    }
}

/// Step 1: saved appointments first, then the menu.
private struct BookStartContent: View {
    let now: Date

    @Environment(AppointmentStore.self) private var appointments
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            let upcoming = appointments.upcoming.filter { $0.isUpcoming(at: now) }
            if !upcoming.isEmpty {
                BookAppointmentsSection(appointments: upcoming)
            }

            StepHeader(
                step: 1,
                of: 4,
                title: "Pick a service",
                subtitle: "Prices and lengths come straight from the shop's booking menu."
            )

            ForEach(catalog.categories) { category in
                BookCategorySection(category: category)
            }

            BookOtherWays()
        }
        .padding(Theme.gutter)
    }
}

/// The screen for each step pushed onto the Book tab.
private struct BookStepDestination: View {
    let step: BookingStep
    private let catalog = AppData.catalog

    var body: some View {
        switch step {
        case .chooseBarber(let serviceID):
            if let service = catalog.service(withID: serviceID) {
                ChooseBarberView(service: service)
            } else {
                BookStepUnavailableView(title: "Service unavailable")
            }
        case .chooseService(let barberID):
            if let barber = catalog.barber(withID: barberID) {
                ChooseServiceView(barber: barber)
            } else {
                BookStepUnavailableView(title: "Barber unavailable")
            }
        case .chooseTime(let choice):
            if catalog.service(withID: choice.serviceID) != nil {
                ChooseTimeView(choice: choice)
            } else {
                BookStepUnavailableView(title: "Service unavailable")
            }
        case .review(let plan):
            if catalog.service(withID: plan.choice.serviceID) != nil {
                BookingReviewView(plan: plan)
            } else {
                BookStepUnavailableView(title: "Service unavailable")
            }
        }
    }
}

/// Shown if a link points at a service or barber that's no longer on the menu.
private struct BookStepUnavailableView: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: Symbol.info,
            description: Text("It may have changed since you last opened the app. Go back and pick again, or call the shop at \(AppData.shop.phone.display).")
        )
        .screenBackground()
    }
}

/// "Your appointments": everything saved that hasn't happened yet.
private struct BookAppointmentsSection: View {
    let appointments: [Appointment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your appointments")
            ForEach(appointments) { appointment in
                UpcomingAppointmentCard(
                    appointment: appointment,
                    isNext: appointment.id == appointments.first?.id
                )
            }
        }
    }
}

/// One category of the menu, e.g. "Haircuts", with a row per service.
private struct BookCategorySection: View {
    let category: ServiceCategory
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(category.title) {
                Image(systemName: category.symbol)
                    .foregroundStyle(Theme.blue)
                    .accessibilityHidden(true)
            }
            ForEach(catalog.services(in: category)) { service in
                NavigationLink(value: BookingStep.chooseBarber(serviceID: service.id)) {
                    ServiceRow(service: service)
                        .card(padding: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                .accessibilityHint("Next, pick your barber")
                .accessibilityIdentifier("bookService-\(service.id)")
            }
        }
    }
}

/// Squire's full booking page and the phone, for anything the menu above
/// doesn't cover.
private struct BookOtherWays: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Looking for something else?")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)

            Button {
                router.openSquire(.anything, plan: nil)
            } label: {
                Label("Browse everything on Squire", systemImage: Symbol.external)
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Opens Squire, the shop's booking system")
            .accessibilityIdentifier("browseSquireButton")

            CallButton {
                Label("Prefer to call? \(AppData.shop.phone.display)", systemImage: Symbol.call)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("bookCallButton")
        }
        .padding(.top, 4)
    }
}
