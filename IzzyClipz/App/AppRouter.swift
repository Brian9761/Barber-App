import Foundation
import Observation

enum AppTab: Hashable {
    case home
    case services
    case book
    case team
    case visit
}

/// Screens in the Book tab's step-by-step flow.
enum BookingStep: Hashable {
    case chooseBarber(serviceID: String)
    case review(BookingChoice)
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
}

/// Modal screens. They're all presented from the root, one at a time, so a
/// sheet can never be asked to appear on top of another one and silently fail.
enum AppSheet: Identifiable, Hashable {
    case booking(BookingRequest)
    case reminders

    var id: String {
        switch self {
        case .booking(let request):
            return "booking/\(request.barberID ?? "any")/\(request.squireServiceID ?? "none")"
        case .reminders:
            return "reminders"
        }
    }
}

/// App-wide navigation state.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var bookingPath: [BookingStep] = []
    var sheet: AppSheet?

    /// Opens the shop's booking page for a request.
    func book(_ request: BookingRequest) {
        sheet = .booking(request)
    }

    /// Switches to the Book tab, optionally starting with a service already chosen.
    func startBooking(serviceID: String? = nil) {
        sheet = nil
        bookingPath = serviceID.map { [.chooseBarber(serviceID: $0)] } ?? []
        selectedTab = .book
    }

    func showReminders() {
        sheet = .reminders
    }
}
