import Foundation
import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// Monday, November 2, 2026 at 11:05 AM in the shop (the day after daylight
/// saving time ended), the same "now" the UI tests use.
@MainActor
enum TestClock {
    static let shopTime = ShopTime()
    static let now = AppEnvironment.uiTestNow(shopTime: shopTime)
    static var today: LocalDate { shopTime.day(containing: now) }

    static func at(_ hour: Int, _ minute: Int = 0, on day: LocalDate? = nil) -> Date {
        shopTime.date(on: day ?? today, hour: hour, minute: minute)!
    }
}

/// A sample server, and an API signed in to it.
@MainActor
struct Harness {
    let server: FakeServer
    let api: FakeOwnerAPI

    init(options: FakeServer.Options = FakeServer.Options(), now: Date? = nil) {
        let moment = now ?? TestClock.now
        server = FakeServer(options: options, shopTime: TestClock.shopTime, now: { moment })
        api = server.api(ownerKey: FakeServer.ownerKey)
    }

    func appointment(named name: String) -> IzzyAPI.Appointment? {
        server.appointments.first { $0.customer.name == name }
    }
}

/// An `OwnerAPI` whose answers each test scripts, wrapping a sample server
/// for everything else.
@MainActor
final class ScriptedAPI: OwnerAPI {
    let base: FakeOwnerAPI
    var appointmentsHandler: ((LocalDate) async throws -> [IzzyAPI.Appointment])?
    var completeHandler: ((String) async throws -> IzzyAPI.Payment)?
    var createPaymentHandler: ((IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated)?
    var uploadHandler: ((String, Data) async throws -> IzzyAPI.Product)?
    private(set) var createdPayments = 0

    init(base: FakeOwnerAPI) {
        self.base = base
    }

    func health() async throws -> IzzyAPI.Health { try await base.health() }
    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { try await base.availability(query) }
    func ownerStatus() async throws -> IzzyAPI.OwnerStatus { try await base.ownerStatus() }
    func ownerAvailability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { try await base.ownerAvailability(query) }
    func appointments(on date: LocalDate) async throws -> [IzzyAPI.Appointment] {
        if let appointmentsHandler { return try await appointmentsHandler(date) }
        return try await base.appointments(on: date)
    }
    func appointments(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.Appointment] { try await base.appointments(from: from, to: to) }
    func createAppointment(_ appointment: IzzyAPI.NewAppointment) async throws -> IzzyAPI.Appointment { try await base.createAppointment(appointment) }
    func setStatus(_ status: IzzyAPI.AppointmentStatus, ofAppointment id: String) async throws -> IzzyAPI.Appointment {
        try await base.setStatus(status, ofAppointment: id)
    }
    func timeOff(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.TimeOff] { try await base.timeOff(from: from, to: to) }
    func createTimeOff(_ timeOff: IzzyAPI.NewTimeOff) async throws -> IzzyAPI.TimeOff { try await base.createTimeOff(timeOff) }
    func deleteTimeOff(id: String) async throws { try await base.deleteTimeOff(id: id) }
    func allProducts() async throws -> [IzzyAPI.Product] { try await base.allProducts() }
    func createProduct(_ product: IzzyAPI.NewProduct) async throws -> IzzyAPI.Product { try await base.createProduct(product) }
    func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) async throws -> IzzyAPI.Product { try await base.updateProduct(id: id, update) }
    func deleteProduct(id: String) async throws { try await base.deleteProduct(id: id) }
    func uploadProductPhoto(id: String, jpegData: Data) async throws -> IzzyAPI.Product {
        if let uploadHandler { return try await uploadHandler(id, jpegData) }
        return try await base.uploadProductPhoto(id: id, jpegData: jpegData)
    }
    func connectionToken() async throws -> String { try await base.connectionToken() }
    func createPayment(_ payment: IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated {
        createdPayments += 1
        if let createPaymentHandler { return try await createPaymentHandler(payment) }
        return try await base.createPayment(payment)
    }
    func completePayment(id: String) async throws -> IzzyAPI.Payment {
        if let completeHandler { return try await completeHandler(id) }
        return try await base.completePayment(id: id)
    }
    func payments(on date: LocalDate) async throws -> [IzzyAPI.Payment] { try await base.payments(on: date) }
}

/// A fresh, empty UserDefaults for one test.
func makeDefaults(_ function: String = #function) -> UserDefaults {
    let name = "IzzyClipzBusinessTests.\(function).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Waits (up to `timeout`) for a condition that's set by work on the main actor.
@MainActor
func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
