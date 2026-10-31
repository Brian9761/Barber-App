import Foundation
import Observation
import SwiftUI
import UIKit

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

/// Screens in the Book tab's step-by-step flow. Step 1, the service, is the tab's first screen.
enum BookingStep: Hashable {
    /// Step 2 when the service was picked first.
    case chooseBarber(serviceID: String)
    /// Step 2 when the barber was picked first (from their profile or Home).
    case chooseService(barberID: String)
    /// Step 3: the day and time, from the shop's live calendar.
    case chooseTime(BookingChoice)
    /// Step 4: the client's name, mobile number and an optional note.
    case details(BookingPlan)
    /// Step 5: check everything, then book.
    case review(BookingDraft)
    /// Done: the appointment as the shop booked it.
    case booked(appointmentID: String)

    /// The step's number in "Step 2 of 5", or `nil` after booking.
    var number: Int? {
        switch self {
        case .chooseBarber, .chooseService: return 2
        case .chooseTime: return 3
        case .details: return 4
        case .review: return 5
        case .booked: return nil
        }
    }

    /// How many steps there are before an appointment is booked.
    static let count = 5
}

/// Who the client picked for a service.
enum BookingChoice: Hashable {
    /// Whoever is free first among the barbers who share the service's "first available" item.
    case anyBarber(FirstAvailableOption)
    /// One barber's version of the service.
    case offering(Offering)

    /// What the server books.
    var target: IzzyAPI.BookingTarget {
        switch self {
        case .anyBarber(let option): return .anyBarber(serviceId: option.serviceID)
        case .offering(let offering): return .offering(offering)
        }
    }

    var serviceID: String {
        switch self {
        case .anyBarber(let option): return option.serviceID
        case .offering(let offering): return offering.serviceID
        }
    }

    /// The barber's ID, or `nil` for any barber.
    var barberID: String? {
        switch self {
        case .anyBarber: return nil
        case .offering(let offering): return offering.barberID
        }
    }

    var serviceName: String {
        AppData.catalog.service(withID: serviceID)?.name ?? "Appointment"
    }

    /// "Carlos", or "Any barber".
    var barberName: String {
        guard let barberID else { return "Any barber" }
        return AppData.catalog.barber(withID: barberID)?.name ?? "Your barber"
    }

    var priceLabel: String {
        switch self {
        case .anyBarber(let option): return option.priceLabel
        case .offering(let offering): return offering.price.label
        }
    }

    var durationLabel: String {
        switch self {
        case .anyBarber(let option): return option.durationLabel
        case .offering(let offering): return offering.durationLabel
        }
    }

    /// A barber-specific note, e.g. what's included in their version.
    var note: String? {
        if case .offering(let offering) = self { return offering.note }
        return nil
    }

    /// The barbers "Any barber" picks from, by name.
    var anyBarberNames: [String] {
        guard case .anyBarber(let option) = self else { return [] }
        return option.barberIDs.compactMap { AppData.catalog.barber(withID: $0)?.name }
    }
}

/// A choice plus the start time the client picked from the shop's live calendar. `start` is the
/// slot's start exactly as the server listed it, and goes back to it unchanged.
struct BookingPlan: Hashable {
    let choice: BookingChoice
    let start: Date
}

/// Everything step 5 books: the plan, who it's for and an optional note for the barber.
struct BookingDraft: Hashable {
    let plan: BookingPlan
    let customer: CustomerDetails
    let note: String
}

/// What the client has typed on the details step, kept while they're booking: going back to the
/// times (a time that was taken, "Change", or the back button) and forward again brings it back,
/// the note and "Remember me" too, and the name and number even when they aren't remembered.
struct BookingDetailsInProgress: Hashable {
    var customer: CustomerDetails
    var note: String
    var remember: Bool

    /// What the details step starts with: what was typed earlier in this booking, or else the
    /// name and number remembered from last time, with no note and "Remember me" on.
    static func start(kept: BookingDetailsInProgress?, saved: CustomerDetails?) -> BookingDetailsInProgress {
        kept ?? BookingDetailsInProgress(customer: saved ?? CustomerDetails(name: "", phone: ""), note: "", remember: true)
    }

    /// The same booking after the client changed the remembered name and number in "Your
    /// details" (`saved`), or forgot them (`nil`): those are the ones it fills in now, with
    /// "Remember me" on, and the note stays. Otherwise Continue would remember the old ones again.
    func remembering(_ saved: CustomerDetails?) -> BookingDetailsInProgress {
        BookingDetailsInProgress(customer: saved ?? CustomerDetails(name: "", phone: ""), note: note, remember: true)
    }
}

/// What the time step is told when the client is sent back to it: reload, and say why (e.g.
/// someone else booked the time first).
struct TimeStepNotice: Equatable {
    let id = UUID()
    /// `nil` when the client went back on purpose, to change the time.
    let message: String?
    /// The time that's gone, so it's no longer shown as picked.
    let droppedStart: Date?
}

/// Modal screens. They're all presented from the root, one at a time, so a sheet can never be
/// asked to appear on top of another one and silently fail.
enum AppSheet: Identifiable, Hashable {
    case web(URL)
    case reminders
    case addToCalendar(CalendarEvent)
    /// The name and number remembered for booking.
    case customerDetails

    var id: String {
        switch self {
        case .web(let url): return "web/\(url.absoluteString)"
        case .reminders: return "reminders"
        case .addToCalendar(let event): return "calendar/\(event.id)"
        case .customerDetails: return "customerDetails"
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
    var bookingPath: [BookingStep] = [] {
        didSet {
            // Back at step 1 (the back button, the Book tab tapped again, Start over): that
            // booking was left, so what was typed for it doesn't fill in the next one.
            if bookingPath.isEmpty, !oldValue.isEmpty { detailsInProgress = nil }
        }
    }
    /// Set when the client is sent back to the times; the time step shows it and refreshes.
    private(set) var timeStepNotice: TimeStepNotice?
    /// Goes up by one each time an appointment is booked.
    private(set) var finishedBookings = 0
    /// What the client has typed on the details step in this booking. Kept until it's booked,
    /// the client goes back to step 1 or starts over, or a new booking starts from elsewhere in
    /// the app. Changing the service from the review keeps it.
    var detailsInProgress: BookingDetailsInProgress?
    /// The sheet on screen. Set it through `present(_:)` so dismissal knows what was showing;
    /// SwiftUI sets it back to `nil` when it goes away.
    var sheet: AppSheet?

    /// A sheet waiting for the one on screen to finish closing.
    @ObservationIgnored private var queuedSheet: AppSheet?

    // MARK: Booking

    /// Switches to the Book tab at step 1. `keepingDetails` when the client is changing the
    /// service of the booking they're making (from its review), so what they typed stays.
    func startBooking(keepingDetails: Bool = false) {
        closeSheet()
        let kept = keepingDetails ? detailsInProgress : nil
        bookingPath = []
        // Back at step 1 drops them (see `bookingPath`), but this is still the same booking.
        detailsInProgress = kept
        selectedTab = .book
    }

    /// Switches to the Book tab with a service already chosen. `keepingDetails` when the client
    /// is changing the barber of the booking they're making (from its review).
    func startBooking(serviceID: String, keepingDetails: Bool = false) {
        closeSheet()
        if !keepingDetails { detailsInProgress = nil }
        bookingPath = [.chooseBarber(serviceID: serviceID)]
        selectedTab = .book
    }

    /// Switches to the Book tab with the service and barber chosen, at the calendar.
    func startBooking(choice: BookingChoice) {
        closeSheet()
        detailsInProgress = nil
        bookingPath = [.chooseBarber(serviceID: choice.serviceID), .chooseTime(choice)]
        selectedTab = .book
    }

    /// Switches to the Book tab with a barber chosen, to pick one of their services.
    func startBooking(barberID: String) {
        closeSheet()
        detailsInProgress = nil
        bookingPath = [.chooseService(barberID: barberID)]
        selectedTab = .book
    }

    /// Switches to the Book tab at the calendar for a service on a barber's own menu. Going back
    /// shows that barber's services, the way the client came, not "Pick a barber".
    func startBooking(fromBarberMenu offering: Offering) {
        closeSheet()
        detailsInProgress = nil
        bookingPath = [.chooseService(barberID: offering.barberID), .chooseTime(.offering(offering))]
        selectedTab = .book
    }

    /// Back to the times (step 3), which reload and show `message`: when the picked time was
    /// taken or can no longer be booked, or (with no message) when the client wants another time.
    /// What they typed on the details step comes back when they continue.
    func returnToTimes(message: String?, droppedStart: Date?) {
        if let index = bookingPath.lastIndex(where: { if case .chooseTime = $0 { return true } else { return false } }) {
            bookingPath = Array(bookingPath.prefix(through: index))
        }
        timeStepNotice = TimeStepNotice(message: message, droppedStart: droppedStart)
    }

    /// The time step has shown the notice.
    func clearTimeStepNotice() {
        timeStepNotice = nil
    }

    /// Back to the details (step 4), to fix the name or number.
    func returnToDetails() {
        if let index = bookingPath.lastIndex(where: { if case .details = $0 { return true } else { return false } }) {
            bookingPath = Array(bookingPath.prefix(through: index))
        }
    }

    /// Whether `step` is the booking step on screen. A booking's answer can arrive after the
    /// client has left its review for another booking; it mustn't move that one.
    func isShowing(_ step: BookingStep) -> Bool {
        bookingPath.last == step
    }

    /// Booked: the flow is replaced by the confirmation, so going back can't book it twice.
    func showBooked(appointmentID: String) {
        bookingPath = [.booked(appointmentID: appointmentID)]
        detailsInProgress = nil
        finishedBookings += 1
    }

    /// Back to the start of the Book tab, with nothing kept from this booking.
    func finishBooking() {
        bookingPath = []
        detailsInProgress = nil
        timeStepNotice = nil
    }

    // MARK: Pages and sheets

    /// Opens a web page in the in-app browser.
    func openWeb(_ url: URL) {
        present(.web(url))
    }

    /// Opens a page outside the app: in Safari, or in the site's own app (Google Maps for Google
    /// reviews, Instagram), where the client is already signed in. UI tests get the in-app preview
    /// instead, so they never leave the app.
    func openOutside(_ url: URL) {
        if LaunchOptions.isUITesting {
            present(.web(url))
        } else {
            UIApplication.shared.open(url)
        }
    }

    func showReminders() {
        present(.reminders)
    }

    func addToCalendar(_ event: CalendarEvent) {
        present(.addToCalendar(event))
    }

    func editCustomerDetails() {
        present(.customerDetails)
    }

    /// The client changed the remembered name and number in "Your details", or forgot them
    /// (`nil`). The booking they're making fills in those too, so its details step doesn't bring
    /// back the old ones and remember them again.
    func rememberedDetailsChanged(to saved: CustomerDetails?) {
        detailsInProgress = detailsInProgress?.remembering(saved)
    }

    /// Shows a sheet. If another one is up, that one closes first and the new one opens once it
    /// has gone: swapping sheets mid-presentation is unreliable on some iOS versions.
    func present(_ sheet: AppSheet) {
        // A second tap while the sheet it replaces is still closing: it's already on its way.
        if sheet == queuedSheet { return }
        if let current = self.sheet, current != sheet {
            queuedSheet = sheet
            self.sheet = nil
            return
        }
        self.sheet = sheet
    }

    /// Closes whatever sheet is up without anything following it.
    func closeSheet() {
        queuedSheet = nil
        sheet = nil
    }

    /// Called by the root view whenever a sheet finishes dismissing.
    func sheetDidDismiss() {
        // Something already put a new sheet up; leave it.
        guard sheet == nil else { return }
        if let next = queuedSheet {
            queuedSheet = nil
            present(next)
        }
    }
}
