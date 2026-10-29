import Foundation
import Observation
import SwiftUI

enum AppTab: Hashable {
    case home
    case services
    case book
    case shop
    case visit
}

/// Screens pushed from Home that aren't a service or a barber.
enum HomeRoute: Hashable {
    case gallery
    case team
    case reviews
}

/// Screens in the Book tab's step-by-step flow.
enum BookingStep: Hashable {
    /// Step 2 when the service was picked first.
    case chooseBarber(serviceID: String)
    /// Step 2 when the barber was picked first (from their profile or Home).
    case chooseService(barberID: String)
    /// Step 3: the day and time, on the app's calendar.
    case chooseTime(BookingChoice)
    /// Step 4: check everything, then confirm on Squire.
    case review(BookingPlan)
}

/// Who the client picked for a service.
enum BookingChoice: Hashable {
    case firstAvailable(FirstAvailableOption)
    case offering(Offering)

    var request: BookingRequest {
        switch self {
        case .firstAvailable(let option): return .firstAvailable(option)
        case .offering(let offering): return .offering(offering)
        }
    }

    var serviceID: String {
        switch self {
        case .firstAvailable(let option): return option.serviceID
        case .offering(let offering): return offering.serviceID
        }
    }

    /// The barber's ID, or `nil` for whoever is free first.
    var barberID: String? {
        switch self {
        case .firstAvailable: return nil
        case .offering(let offering): return offering.barberID
        }
    }

    var serviceName: String {
        AppData.catalog.service(withID: serviceID)?.name ?? "Appointment"
    }

    /// "Carlos", or "First available".
    var barberName: String {
        guard let barberID else { return "First available" }
        return AppData.catalog.barber(withID: barberID)?.name ?? "Your barber"
    }

    var priceLabel: String {
        switch self {
        case .firstAvailable(let option): return option.priceLabel
        case .offering(let offering): return offering.price.label
        }
    }

    /// How long to plan for. With "first available" the barbers' lengths can
    /// differ, so this is the longest, which every barber can fit.
    var durationMinutes: Int {
        switch self {
        case .offering(let offering):
            return offering.durationMinutes
        case .firstAvailable(let option):
            let lengths = AppData.catalog.offerings
                .filter { $0.squireServiceID == option.squireServiceID && option.barberIDs.contains($0.barberID) }
                .map(\.durationMinutes)
            return lengths.max() ?? 60
        }
    }

    var durationLabel: String {
        switch self {
        case .firstAvailable(let option): return option.durationLabel
        case .offering(let offering): return offering.durationLabel
        }
    }

    /// A barber-specific note, e.g. what's included in their version.
    var note: String? {
        if case .offering(let offering) = self { return offering.note }
        return nil
    }
}

/// A choice plus the day and time the client picked on the app's calendar.
struct BookingPlan: Hashable {
    let choice: BookingChoice
    let start: Date

    /// The appointment to save once the client has booked it on Squire.
    func appointment(at start: Date? = nil, createdAt: Date = Date()) -> Appointment {
        Appointment(
            id: UUID(),
            serviceID: choice.serviceID,
            serviceName: choice.serviceName,
            barberID: choice.barberID,
            barberName: choice.barberName,
            start: start ?? self.start,
            durationMinutes: choice.durationMinutes,
            priceLabel: choice.priceLabel,
            createdAt: createdAt
        )
    }
}

/// Opening the shop's Squire booking page, and the plan it confirms (if any).
struct SquireHandoff: Hashable {
    let request: BookingRequest
    /// The day and time picked in the app. `nil` when browsing Squire directly.
    let plan: BookingPlan?

    var url: URL { AppData.bookingURL(for: request) }
}

/// Modal screens. They're all presented from the root, one at a time, so a
/// sheet can never be asked to appear on top of another one and silently fail.
enum AppSheet: Identifiable, Hashable {
    case squire(SquireHandoff)
    case confirmBooking(BookingPlan)
    case web(URL)
    case reminders
    case addToCalendar(Appointment)

    var id: String {
        switch self {
        case .squire(let handoff):
            return "squire/\(handoff.url.absoluteString)"
        case .confirmBooking(let plan):
            return "confirm/\(plan.choice.request.barberID ?? "any")/\(plan.choice.serviceID)/\(plan.start.timeIntervalSince1970)"
        case .web(let url):
            return "web/\(url.absoluteString)"
        case .reminders:
            return "reminders"
        case .addToCalendar(let appointment):
            return "calendar/\(appointment.id.uuidString)"
        }
    }
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    /// Home pushes services, barbers and `HomeRoute`s, so its path holds any of them.
    var homePath = NavigationPath()
    var bookingPath: [BookingStep] = []
    /// The sheet on screen. Set it through `present(_:)` so dismissal knows
    /// what was showing; SwiftUI sets it back to `nil` when it goes away.
    var sheet: AppSheet?

    /// What was presented last, so its dismissal can lead somewhere.
    @ObservationIgnored private var lastPresentedSheet: AppSheet?

    /// Switches to the Book tab at step 1.
    func startBooking() {
        closeSheet()
        bookingPath = []
        selectedTab = .book
    }

    /// Switches to the Book tab with a service already chosen.
    func startBooking(serviceID: String) {
        closeSheet()
        bookingPath = [.chooseBarber(serviceID: serviceID)]
        selectedTab = .book
    }

    /// Switches to the Book tab with the service and barber chosen, at the calendar.
    func startBooking(choice: BookingChoice) {
        closeSheet()
        bookingPath = [.chooseBarber(serviceID: choice.serviceID), .chooseTime(choice)]
        selectedTab = .book
    }

    /// Switches to the Book tab with a barber chosen, to pick one of their services.
    func startBooking(barberID: String) {
        closeSheet()
        bookingPath = [.chooseService(barberID: barberID)]
        selectedTab = .book
    }

    /// Opens Squire to confirm a booking. With a plan, the client is asked
    /// afterwards whether they booked it, so it can be saved in the app.
    func openSquire(_ request: BookingRequest, plan: BookingPlan?) {
        present(.squire(SquireHandoff(request: request, plan: plan)))
    }

    /// Opens a web page in the in-app browser.
    func openWeb(_ url: URL) {
        present(.web(url))
    }

    func showReminders() {
        present(.reminders)
    }

    func addToCalendar(_ appointment: Appointment) {
        present(.addToCalendar(appointment))
    }

    func present(_ sheet: AppSheet) {
        lastPresentedSheet = sheet
        self.sheet = sheet
    }

    /// Closes whatever sheet is up without anything following it.
    func closeSheet() {
        lastPresentedSheet = nil
        sheet = nil
    }

    /// Called by the root view whenever a sheet finishes dismissing.
    func sheetDidDismiss() {
        // When one sheet replaces another, the new one is already set; leave it.
        guard sheet == nil else { return }
        let dismissed = lastPresentedSheet
        lastPresentedSheet = nil
        if case .squire(let handoff)? = dismissed, let plan = handoff.plan {
            present(.confirmBooking(plan))
        }
    }

    /// After an appointment is saved: back to the start of the Book tab.
    func finishBooking() {
        bookingPath = []
    }
}
