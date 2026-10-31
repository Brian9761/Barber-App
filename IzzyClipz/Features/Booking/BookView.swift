import SwiftUI

/// The Book tab: booking in five steps, with no payment up front.
///
/// 1. A service (this screen, under the client's appointments).
/// 2. A barber, or "Any barber" when several share the service.
/// 3. A day and time from the shop's live calendar.
/// 4. The client's name and mobile number, remembered for next time.
/// 5. A review that says payment happens at the shop, and "Book appointment".
///
/// Then the confirmation, with Add to Calendar and reminders. Steps 1 and 2 move on as soon as
/// something is tapped.
struct BookView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.bookingPath) {
            BookStartScreen()
                .navigationTitle("Book")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: BookingStep.self) { step in
                    BookStepDestination(step: step)
                }
        }
    }
}

/// Step 1: the client's appointments first, then the menu by category, then other ways to book.
private struct BookStartScreen: View {
    @Environment(AppointmentStore.self) private var appointments
    private let catalog = AppData.catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                // Re-checked every minute, so an appointment that's over moves out of the list.
                TimelineView(.everyMinute) { context in
                    BookAppointmentsSection(now: context.date)
                }

                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    BookingStepHeader(
                        step: 1,
                        title: "Pick a service",
                        subtitle: "No payment needed to book. You pay at the shop."
                    )
                    BookCustomerDetailsRow()
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
        .screenBackground()
        .refreshable {
            await appointments.refresh(force: true)
        }
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
        case .details(let plan):
            BookingDetailsView(plan: plan)
        case .review(let draft):
            BookingReviewView(draft: draft)
        case .booked(let appointmentID):
            BookedView(appointmentID: appointmentID)
        }
    }
}

/// Shown if a link points at a service or barber that's no longer on the menu.
private struct BookStepUnavailableView: View {
    let title: String

    var body: some View {
        ScrollView {
            ErrorStateView(
                title: title,
                message: "It may have changed since you last opened the app. Go back and pick again, or call the shop."
            )
            .padding(Theme.gutter)
        }
        .screenBackground()
        .bookingStepChrome(title: title)
    }
}

/// "Your appointments": everything that hasn't ended yet, soonest first.
private struct BookAppointmentsSection: View {
    let now: Date
    @Environment(AppointmentStore.self) private var store

    var body: some View {
        let upcoming = store.upcoming.filter { $0.isUpcoming(at: now) }
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.cardGap) {
                SectionHeader("Your appointments")
                ForEach(upcoming) { saved in
                    AppointmentSummaryCard(appointment: saved)
                }
            }
        }
    }
}

/// "Booking as Alex · (442) 555-0123", with "Change", once the client's details are remembered.
private struct BookCustomerDetailsRow: View {
    @Environment(CustomerDetailsStore.self) private var details
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let saved = details.saved {
            HStack(spacing: Theme.Space.l) {
                Image(systemName: Symbol.person)
                    .foregroundStyle(Theme.smoke)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Booking as \(saved.name)")
                        .textRole(.callout)
                        .foregroundStyle(Theme.bone)
                    Text(saved.displayPhone)
                        .textRole(.detail)
                        .foregroundStyle(Theme.smoke)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button("Change") {
                    router.editCustomerDetails()
                }
                .buttonStyle(.textLink(color: Theme.electric))
                .accessibilityLabel("Change your details")
                .accessibilityIdentifier("changeCustomerDetails")
            }
            .card()
            .accessibilityIdentifier("customerDetailsRow")
        }
    }
}

/// One category of the menu, e.g. "Haircuts", with a row per service. Each row goes to step 2.
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

/// The phone, for anything the menu doesn't cover.
private struct BookOtherWays: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Prefer to call, or need something else?")
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            CallButton {
                Label("Call \(AppData.shop.phone.display)", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
            .accessibilityIdentifier("bookCallButton")
            Text("Walk-ins are welcome too.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
        }
    }
}
