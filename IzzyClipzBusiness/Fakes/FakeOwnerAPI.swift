import Foundation
import IzzyClipzKit

/// `OwnerAPI` over the in-memory `FakeServer`, with an owner key like the real
/// client: every owner call checks it.
struct FakeOwnerAPI: OwnerAPI {
    let server: FakeServer
    let ownerKey: String?

    func health() async throws -> IzzyAPI.Health {
        try await server.begin("health", key: ownerKey, ownerOnly: false)
        return IzzyAPI.Health(version: "sample")
    }

    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        try await server.begin("availability", key: ownerKey, ownerOnly: false)
        return try await server.availability(query, leadTimeMinutes: 30)
    }

    func ownerStatus() async throws -> IzzyAPI.OwnerStatus {
        try await server.begin("ownerStatus", key: ownerKey)
        return await server.ownerStatus()
    }

    func ownerAvailability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        try await server.begin("ownerAvailability", key: ownerKey)
        return try await server.availability(query, leadTimeMinutes: 0)
    }

    func appointments(on date: LocalDate) async throws -> [IzzyAPI.Appointment] {
        try await server.begin("appointments", key: ownerKey)
        return await server.appointments(from: date, to: date)
    }

    func appointments(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.Appointment] {
        try await server.begin("appointments", key: ownerKey)
        return await server.appointments(from: from, to: to)
    }

    func createAppointment(_ appointment: IzzyAPI.NewAppointment) async throws -> IzzyAPI.Appointment {
        try await server.begin("createAppointment", key: ownerKey)
        return try await server.createAppointment(appointment)
    }

    func setStatus(_ status: IzzyAPI.AppointmentStatus, ofAppointment id: String) async throws -> IzzyAPI.Appointment {
        try await server.begin("setStatus", key: ownerKey)
        return try await server.setStatus(status, of: id)
    }

    func timeOff(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.TimeOff] {
        try await server.begin("timeOff", key: ownerKey)
        return await server.timeOff(from: from, to: to)
    }

    func createTimeOff(_ timeOff: IzzyAPI.NewTimeOff) async throws -> IzzyAPI.TimeOff {
        try await server.begin("createTimeOff", key: ownerKey)
        return try await server.createTimeOff(timeOff)
    }

    func deleteTimeOff(id: String) async throws {
        try await server.begin("deleteTimeOff", key: ownerKey)
        try await server.deleteTimeOff(id: id)
    }

    func allProducts() async throws -> [IzzyAPI.Product] {
        try await server.begin("allProducts", key: ownerKey)
        return await server.products
    }

    func createProduct(_ product: IzzyAPI.NewProduct) async throws -> IzzyAPI.Product {
        try await server.begin("createProduct", key: ownerKey)
        return try await server.createProduct(product)
    }

    func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) async throws -> IzzyAPI.Product {
        try await server.begin("updateProduct", key: ownerKey)
        return try await server.updateProduct(id: id, update)
    }

    func deleteProduct(id: String) async throws {
        try await server.begin("deleteProduct", key: ownerKey)
        try await server.deleteProduct(id: id)
    }

    func uploadProductPhoto(id: String, jpegData: Data) async throws -> IzzyAPI.Product {
        try await server.begin("uploadProductPhoto", key: ownerKey)
        return try await server.uploadPhoto(id: id, jpegData: jpegData)
    }

    func connectionToken() async throws -> String {
        try await server.begin("connectionToken", key: ownerKey)
        guard await server.options.stripeConfigured else { throw APIError.notConfigured(APIError.Feature.stripe) }
        return "pst_sample_connection_token"
    }

    func createPayment(_ payment: IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated {
        try await server.begin("createPayment", key: ownerKey)
        return try await server.createPayment(payment)
    }

    func completePayment(id: String) async throws -> IzzyAPI.Payment {
        try await server.begin("completePayment", key: ownerKey)
        return try await server.completePayment(id: id)
    }

    func payments(on date: LocalDate) async throws -> [IzzyAPI.Payment] {
        try await server.begin("payments", key: ownerKey)
        return await server.payments(on: date)
    }
}
