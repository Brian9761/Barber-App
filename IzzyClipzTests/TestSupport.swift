import Foundation
import XCTest
@testable import IzzyClipz

/// A `ShopAPI` whose answers each test scripts, and that records what it was asked.
@MainActor
final class ScriptedShopAPI: ShopAPI {
    var healthHandler: () throws -> IzzyAPI.Health = { IzzyAPI.Health(version: "test") }
    var availabilityHandler: (IzzyAPI.AvailabilityQuery) throws -> IzzyAPI.AvailabilityResponse = { query in
        ScriptedShopAPI.emptyAvailability(for: query)
    }
    var bookHandler: (IzzyAPI.NewAppointment) throws -> IzzyAPI.BookingConfirmation = { _ in throw APIError.offline }
    var appointmentHandler: (String, String) throws -> IzzyAPI.Appointment = { _, _ in throw APIError.offline }
    var cancelHandler: (String, String) throws -> IzzyAPI.Appointment = { _, _ in throw APIError.offline }
    var reviewsHandler: () throws -> IzzyAPI.ReviewsResponse = { throw APIError.offline }
    var productsHandler: () throws -> [IzzyAPI.Product] = { [] }

    private(set) var availabilityQueries: [IzzyAPI.AvailabilityQuery] = []
    private(set) var bookings: [IzzyAPI.NewAppointment] = []
    private(set) var lookups: [(id: String, token: String)] = []
    private(set) var cancellations: [(id: String, token: String)] = []
    private(set) var reviewRequests = 0
    private(set) var productRequests = 0

    func health() async throws -> IzzyAPI.Health { try healthHandler() }

    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        availabilityQueries.append(query)
        return try availabilityHandler(query)
    }

    func book(_ appointment: IzzyAPI.NewAppointment) async throws -> IzzyAPI.BookingConfirmation {
        bookings.append(appointment)
        return try bookHandler(appointment)
    }

    func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        lookups.append((id, manageToken))
        return try appointmentHandler(id, manageToken)
    }

    func cancelAppointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        cancellations.append((id, manageToken))
        return try cancelHandler(id, manageToken)
    }

    func reviews() async throws -> IzzyAPI.ReviewsResponse {
        reviewRequests += 1
        return try reviewsHandler()
    }

    func products() async throws -> [IzzyAPI.Product] {
        productRequests += 1
        return try productsHandler()
    }

    /// Every day asked for, with no openings.
    nonisolated static func emptyAvailability(for query: IzzyAPI.AvailabilityQuery) -> IzzyAPI.AvailabilityResponse {
        IzzyAPI.AvailabilityResponse(
            timeZone: "America/Los_Angeles",
            days: (0..<query.days).map { IzzyAPI.DaySlots(date: query.from.adding(days: $0), slots: []) }
        )
    }
}

/// Dates and data the tests share. Times are in Oceanside (Pacific).
enum TestData {
    /// Wednesday, October 28, 2026, noon.
    static let now = Date(timeIntervalSince1970: 1_793_214_000)
    /// Friday, October 30, 2026, 2:30 PM.
    static let friday = Date(timeIntervalSince1970: 1_793_395_800)
    /// Today at 12:45 PM: too soon for a day-before or an hour-before reminder.
    static let soon = Date(timeIntervalSince1970: 1_793_216_700)
    /// Monday, October 26, 2026, 10 AM: already over.
    static let monday = Date(timeIntervalSince1970: 1_793_034_000)
    /// Tuesday, September 15, 2026, 10 AM: over a month ago.
    static let september = Date(timeIntervalSince1970: 1_789_491_600)

    static let carlosHaircutID = "carlos-rafael/9343fc67-b196-4604-987e-a4a9b6b4cc41"

    static func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "IzzyClipzTests-\(name)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// A haircut with Carlos as the server describes it.
    static func appointment(
        id: String = "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b",
        start: Date = friday,
        status: IzzyAPI.AppointmentStatus = .booked,
        cancelledBy: IzzyAPI.CancelledBy? = nil
    ) -> IzzyAPI.Appointment {
        IzzyAPI.Appointment(
            id: id,
            offeringId: carlosHaircutID,
            serviceId: "haircut",
            serviceName: "Haircut",
            barberId: "carlos-rafael",
            barberName: "Carlos",
            start: start,
            end: start.addingTimeInterval(45 * 60),
            durationMinutes: 45,
            priceLabel: "$45",
            status: status,
            cancelledBy: cancelledBy,
            customer: IzzyAPI.Customer(name: "Alex", phone: "+14425550123"),
            createdAt: now
        )
    }

    static func confirmation(id: String = "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b", start: Date = friday, token: String = "token-1") -> IzzyAPI.BookingConfirmation {
        IzzyAPI.BookingConfirmation(appointment: appointment(id: id, start: start), manageToken: token)
    }

    /// The shop's calendar at a fixed moment.
    static func calendarDay(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
        LocalDate(year: year, month: month, day: day)!
    }
}
