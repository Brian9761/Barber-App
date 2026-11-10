import Foundation
import IzzyClipzKit

// The sample server's Stripe connection and computer sign-in, answering like the server
// (`server/src/stripeconnect.ts`, `server/src/computers.ts`). With Stripe on, it's a Stripe
// Connect server: the shop's own account is connected (the usual) or not yet, and "Connect
// Stripe" goes through a stand-in for Stripe's window (`FakeStripeConnector`).

extension FakeServer {
    /// The shop's own Stripe account on the sample server.
    enum StripeAccount: Equatable, Sendable {
        /// Not connected yet: Settings offers Connect Stripe.
        case none
        /// Made, but Stripe still needs details: Settings offers Finish setting up.
        case needsInfo
        /// Connected and taking card payments.
        case active
    }

    /// The sample account's id and name, as Stripe would report them.
    static let sampleAccountId = "acct_sample_shop"
    static let sampleBusinessName = "Izzy Clipz Barbershop"

    // MARK: Stripe

    /// `GET /api/owner/stripe`, in the server's words.
    func stripeConnection() -> IzzyAPI.StripeConnection {
        guard options.stripeConfigured else { return IzzyAPI.StripeConnection(mode: .off, status: .off) }
        switch options.stripeAccount {
        case .none:
            return IzzyAPI.StripeConnection(mode: .connect, status: .notConnected)
        case .needsInfo:
            return IzzyAPI.StripeConnection(
                mode: .connect, status: .needsInfo, accountId: Self.sampleAccountId, businessName: Self.sampleBusinessName,
                livemode: options.stripeMode == .live, requirementsDue: 3, checkedAt: now()
            )
        case .active:
            return IzzyAPI.StripeConnection(
                mode: .connect, status: .active, accountId: Self.sampleAccountId, businessName: Self.sampleBusinessName,
                livemode: options.stripeMode == .live, chargesEnabled: true, payoutsEnabled: true, detailsSubmitted: true,
                checkedAt: now()
            )
        }
    }

    /// `POST /api/owner/stripe/connect`: makes the shop's account the first time (Stripe then needs
    /// its details), and a link to Stripe's pages, which works for 5 minutes.
    func connectStripe() throws -> IzzyAPI.StripeConnectLink {
        guard options.stripeConfigured else { throw Self.connectOff("connect") }
        if options.stripeAccount == .none { options.stripeAccount = .needsInfo }
        shopCounter += 1
        return IzzyAPI.StripeConnectLink(
            url: URL(string: "https://connect.stripe.com/setup/s/\(Self.sampleAccountId)/sample\(shopCounter)")!,
            expiresAt: now().addingTimeInterval(300)
        )
    }

    /// What the owner did on Stripe's pages: finished (the account takes card payments) or left
    /// details missing. Returns the status the way back reports (`izzyclipzbusiness://stripe-connected?status=`).
    @discardableResult
    func finishStripeSetup(detailsSubmitted: Bool) -> IzzyAPI.StripeConnection.Status {
        guard options.stripeConfigured else { return .off }
        options.stripeAccount = detailsSubmitted ? .active : .needsInfo
        return stripeConnection().status
    }

    /// `DELETE /api/owner/stripe/connect`: forgets the shop's account (it stays open at Stripe).
    func disconnectStripe() throws -> IzzyAPI.StripeConnection {
        guard options.stripeConfigured else { throw Self.connectOff("disconnect") }
        options.stripeAccount = .none
        var connection = stripeConnection()
        connection.message = IzzyAPI.StripeConnection.disconnectedMessage
        return connection
    }

    /// The server's 409 `stripe_connect_off` without Stripe on the server.
    private static func connectOff(_ what: String) -> APIError {
        APIError.server(
            code: IzzyAPI.ErrorCode.stripeConnectOff, message: "Stripe isn't set up on the server yet, so there's nothing to \(what).", status: 409
        )
    }

    // MARK: Computers

    /// The sample codes, in turn: the same on every run, so UI tests can read them.
    static let sampleCodes = ["483920", "271846", "905173", "638254"]

    /// `POST /api/owner/computer-codes`: a new 6-digit code for 10 minutes, replacing the one before.
    func createComputerCode() -> IzzyAPI.ComputerCode {
        shopCounter += 1
        let code = Self.sampleCodes[(shopCounter - 1) % Self.sampleCodes.count]
        let made = IzzyAPI.ComputerCode(code: code, expiresAt: now().addingTimeInterval(600), expiresInSeconds: 600)
        computerCode = made
        return made
    }

    /// `GET /api/owner/computer-sessions`: the computers signed in now, most recently used first.
    func signedInComputers() -> [IzzyAPI.ComputerSession] {
        computerSessions.filter { $0.expiresAt > now() }.sorted {
            $0.lastUsedAt != $1.lastUsedAt ? $0.lastUsedAt > $1.lastUsedAt : $0.id < $1.id
        }
    }

    /// `DELETE /api/owner/computer-sessions/:id`.
    func signOutComputer(id: String) throws {
        guard let index = computerSessions.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that computer.", status: 404)
        }
        computerSessions.remove(at: index)
    }

    /// `DELETE /api/owner/computer-sessions`.
    func signOutAllComputers() {
        computerSessions.removeAll()
    }

    /// Two sample computers signed in to the website's Business area: the shop's Mac, used this
    /// morning, and an iPad, used yesterday.
    func seedComputers() {
        let current = now()
        func session(_ name: String, signedIn: TimeInterval, used: TimeInterval) -> IzzyAPI.ComputerSession {
            shopCounter += 1
            let digits = String(shopCounter)
            let created = current.addingTimeInterval(-signedIn)
            return IzzyAPI.ComputerSession(
                id: "00000000-0000-4000-a000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits,
                name: name, createdAt: created, lastUsedAt: current.addingTimeInterval(-used),
                expiresAt: created.addingTimeInterval(30 * 86_400)
            )
        }
        computerSessions = [
            session("Chrome on Mac", signedIn: 3 * 86_400, used: 20 * 60),
            session("Safari on iPad", signedIn: 9 * 86_400, used: 86_400),
        ]
    }
}
