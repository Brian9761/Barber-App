import Foundation
import IzzyClipzKit

// The owner routes that came with Settings' Stripe connection and computer sign-in, and with the
// checkout (sales and receipts), on the sample server. Each checks the network and the owner key
// like every owner route.

extension FakeOwnerAPI {
    // MARK: The shop's Stripe account

    func stripeConnection() async throws -> IzzyAPI.StripeConnection {
        try await server.begin("stripeConnection", key: ownerKey)
        return await server.stripeConnection()
    }

    func connectStripe() async throws -> IzzyAPI.StripeConnectLink {
        try await server.begin("connectStripe", key: ownerKey)
        return try await server.connectStripe()
    }

    func disconnectStripe() async throws -> IzzyAPI.StripeConnection {
        try await server.begin("disconnectStripe", key: ownerKey)
        return try await server.disconnectStripe()
    }

    // MARK: Computers

    func createComputerCode() async throws -> IzzyAPI.ComputerCode {
        try await server.begin("createComputerCode", key: ownerKey)
        return await server.createComputerCode()
    }

    func computerSessions() async throws -> [IzzyAPI.ComputerSession] {
        try await server.begin("computerSessions", key: ownerKey)
        return await server.signedInComputers()
    }

    func signOutComputer(id: String) async throws {
        try await server.begin("signOutComputer", key: ownerKey)
        try await server.signOutComputer(id: id)
    }

    func signOutAllComputers() async throws {
        try await server.begin("signOutAllComputers", key: ownerKey)
        await server.signOutAllComputers()
    }

    // MARK: Sales

    func recordSale(_ sale: IzzyAPI.NewSale, idempotencyKey: IzzyAPI.IdempotencyKey) async throws -> IzzyAPI.Sale {
        try await server.begin("recordSale", key: ownerKey)
        return try await server.recordSale(sale, idempotencyKey: idempotencyKey)
    }

    func sales(on date: LocalDate) async throws -> IzzyAPI.SalesDay {
        try await server.begin("sales", key: ownerKey)
        return await server.salesDay(date)
    }

    func voidSale(id: String, reason: String?) async throws -> IzzyAPI.VoidedSale {
        try await server.begin("voidSale", key: ownerKey)
        return try await server.voidSale(id: id, reason: reason)
    }

    // MARK: Receipts

    func sendReceipt(paymentId: String, email: String) async throws -> IzzyAPI.Payment {
        try await server.begin("sendReceipt", key: ownerKey)
        return try await server.sendReceipt(paymentId: paymentId, email: email)
    }
}
