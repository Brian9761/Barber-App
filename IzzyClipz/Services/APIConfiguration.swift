import Foundation
import SwiftUI

/// Where the shop's server is, and which `ShopAPI` the app talks to.
enum APIConfiguration {
    /// The Info.plist key with the server's base URL, e.g. `https://izzy-clipz-api.vercel.app`.
    static let baseURLKey = "IzzyAPIBaseURL"

    /// The server from Info.plist, or `nil` if it's missing or not an https address.
    static var baseURL: URL? {
        baseURL(from: Bundle.main.object(forInfoDictionaryKey: baseURLKey))
    }

    /// Only https is accepted (the shop's customers' names and numbers travel to it), plus plain
    /// http to this machine for a local test server.
    static func baseURL(from value: Any?) -> URL? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty
        else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1"].contains(host.lowercased()) { return url }
        return nil
    }

    /// The server the app talks to: an in-memory fake while UI testing (never the network),
    /// otherwise the shop's server from Info.plist.
    @MainActor
    static func makeAPI() -> any ShopAPI {
        if LaunchOptions.isUITesting {
            return FakeShopAPI(options: FakeShopAPI.Options(arguments: ProcessInfo.processInfo.arguments))
        }
        guard let baseURL else { return UnconfiguredShopAPI() }
        return IzzyAPIClient(baseURL: baseURL)
    }
}

/// Stands in when Info.plist has no usable server address: every call explains that the app isn't
/// connected yet, so screens show their error state with "Call the shop" instead of crashing.
struct UnconfiguredShopAPI: ShopAPI {
    private var error: APIError { .notConfigured(APIError.Feature.server) }

    func health() async throws -> IzzyAPI.Health { throw error }
    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse { throw error }
    func book(_ appointment: IzzyAPI.NewAppointment, token: IzzyAPI.ManageToken) async throws -> IzzyAPI.BookingConfirmation { throw error }
    func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment { throw error }
    func cancelAppointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment { throw error }
    func reviews() async throws -> IzzyAPI.ReviewsResponse { throw error }
    func products() async throws -> [IzzyAPI.Product] { throw error }
}

extension Error {
    /// The error as the app shows it: an `APIError`, with anything unexpected treated as a server
    /// problem (still worded for people, with a way forward).
    var asAPIError: APIError {
        (self as? APIError) ?? .server(code: IzzyAPI.ErrorCode.serverError, message: "", status: 0)
    }

    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

private struct ShopAPIKey: EnvironmentKey {
    static let defaultValue: any ShopAPI = UnconfiguredShopAPI()
}

extension EnvironmentValues {
    /// The shop's server, for views that make their own requests (the booking steps).
    var shopAPI: any ShopAPI {
        get { self[ShopAPIKey.self] }
        set { self[ShopAPIKey.self] = newValue }
    }
}
