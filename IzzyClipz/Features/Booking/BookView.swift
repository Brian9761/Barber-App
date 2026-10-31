import SwiftUI

/// The Book tab. Booking takes four steps: a service, a barber, a day and
/// time on the app's calendar, then a review that hands off to Squire, the
/// shop's booking system, to confirm the real slot.
///
/// Step 1 (this screen): the client's saved appointments, then the menu.
/// Steps 1 and 2 move on as soon as something is tapped; only the calendar
/// has a Continue button, because only there is the choice in two parts.
/// No red here: the tab bar's Book button is the screen's one red.
struct BookView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .bookingStepChrome(step: 1, name: "Service", title: "Book")
            .navigationDestination(for: BookingStep.self) { step in
                BookStepDestination(step: step)
                    
                    
            }
        }
    }
}

/// Step 1: saved appointments first, then the menu by category, then other ways to book.
private struct BookStartContent: View {
    let now: Date

    @Environment(AppointmentStore.self) private var appointments
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            let upcoming = appointments.upcoming.filter { $0.isUpcoming(at: now) }
            if !upcoming.isEmpty {
                BookAppointmentsSection(appointments: upcoming)
            }

            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BookingStepTitle(
                    step: 1,
                    name: "Service",
                    title: "Pick a service",
                    subtitle: "Prices and lengths come straight from the shop's booking menu."
                )
                ForEach(catalog.categories) { category in
                    BookCategorySection(category: category)
                }
            }

            BookOtherWays()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xxl)
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
                BookStepUnavailableView(title: "Service unavailable", step: 2, name: "Barber")
            }
        case .chooseService(let barberID):
            if let barber = catalog.barber(withID: barberID) {
                ChooseServiceView(barber: barber)
            } else {
                BookStepUnavailableView(title: "Barber unavailable", step: 2, name: "Service")
            }
        case .chooseTime(let choice):
            if catalog.service(withID: choice.serviceID) != nil {
                ChooseTimeView(choice: choice)
            } else {
                BookStepUnavailableView(title: "Service unavailable", step: 3, name: "Time")
            }
        case .review(let plan):
            if catalog.service(withID: plan.choice.serviceID) != nil {
                BookingReviewView(plan: plan)
            } else {
                BookStepUnavailableView(title: "Service unavailable", step: 4, name: "Review")
            }
        }
    }
}

/// Shown if a link points at a service or barber that's no longer on the menu.
private struct BookStepUnavailableView: View {
    let title: String
    let step: Int
    let name: String

    var body: some View {
        EmptyStateView(
            title: title,
            symbol: Symbol.info,
            message: "It may have changed since you last opened the app. Go back and pick again, or call the shop."
        ) {
            CallButton {
                Text("Call \(AppData.shop.phone.display)")
            }
            .buttonStyle(.secondary)
        }
        .screenBackground()
        .bookingStepChrome(step: step, name: name, title: title)
    }
}

/// "Your appointments": everything saved that hasn't happened yet, as tickets. The soonest one is
/// the "Next appointment".
private struct BookAppointmentsSection: View {
    let appointments: [Appointment]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
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

/// One category of the menu, e.g. "Haircuts", with a row per service. Each row goes straight to
/// step 2.
private struct BookCategorySection: View {
    let category: ServiceCategory
    private let catalog = AppData.catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            BookingSectionLabel(title: category.title, symbol: category.symbol)
            ForEach(catalog.services(in: category)) { service in
                NavigationLink(value: BookingStep.chooseBarber(serviceID: service.id)) {
                    ServiceRow(service: service)
                        .card(padding: Theme.Space.cardPadding)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(ServiceRow.accessibilityText(for: service))
                .accessibilityHint("Next, pick your barber")
                .accessibilityIdentifier("bookService-\(service.id)")
            }
        }
    }
}

/// Squire's full booking page and the phone, for anything the menu above doesn't cover.
private struct BookOtherWays: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Looking for something else?")
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Button {
                router.openSquire(.anything, plan: nil)
            } label: {
                Label("Browse all on Squire", systemImage: Symbol.external)
                    .labelStyle(BookTrailingIconLabelStyle())
            }
            .buttonStyle(.tertiary)
            .accessibilityLabel("Browse all on Squire")
            .accessibilityHint("Opens Squire, the shop's booking system")
            .accessibilityIdentifier("browseSquireButton")

            CallButton {
                Label("Call \(AppData.shop.phone.display)", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("bookCallButton")
        }
    }
}

/// The title, then its symbol ("BROWSE ALL ON SQUIRE ↗"): the arrow says where the button goes.
private struct BookTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.s) {
            configuration.title
            configuration.icon
                .accessibilityHidden(true)
        }
    }
}
