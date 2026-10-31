import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to the Izzy Clipz server over HTTPS.
///
/// A small value type: make one per base URL and owner key. The owner app
/// verifies a pasted key with `withOwnerKey(_:)` and `ownerStatus()` before
/// keeping it.
///
/// Responses are never served from a cache (availability and reviews must be
/// live), no cookies are kept, and redirects are never followed, so the owner
/// key, a manage token or a customer's details can't be sent on to another
/// address.
public struct IzzyAPIClient: ShopAPI, OwnerAPI, Sendable, CustomStringConvertible {
    public let baseURL: URL
    public let session: URLSession
    private let ownerKey: String?

    /// - Parameters:
    ///   - baseURL: e.g. `https://izzy-clipz-api.vercel.app` (a path prefix is kept).
    ///   - session: `IzzyAPIClient.defaultSession` unless given; inject one
    ///     with a stub `URLProtocol` in tests.
    ///   - ownerKey: the owner key for owner calls; surrounding spaces and line
    ///     breaks from pasting are dropped. Without one, owner calls throw
    ///     `APIError.unauthorized` without contacting the server.
    public init(baseURL: URL, session: URLSession = IzzyAPIClient.defaultSession, ownerKey: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.ownerKey = ownerKey?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// A session that keeps nothing on disk: no URL cache (so customers'
    /// names and phone numbers never land in the app's caches) and no cookies.
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // `waitsForConnectivity` is already false, so being offline fails fast.
        return URLSession(configuration: configuration)
    }()

    /// The same client with a different owner key (`nil` signs out).
    public func withOwnerKey(_ ownerKey: String?) -> IzzyAPIClient {
        IzzyAPIClient(baseURL: baseURL, session: session, ownerKey: ownerKey)
    }

    public var hasOwnerKey: Bool { ownerKey != nil }

    /// Leaves the owner key out, so it never ends up in a log.
    public var description: String {
        "IzzyAPIClient(baseURL: \(baseURL.absoluteString), ownerKey: \(ownerKey == nil ? "none" : "<redacted>"))"
    }

    /// Sends `endpoint` and decodes its response.
    ///
    /// - Throws: `APIError` for every failure (`offline`, the contract's error
    ///   codes, `decoding`), or `CancellationError` if the task was cancelled.
    public func send<Response: Decodable>(_ endpoint: IzzyAPI.Endpoint<Response>) async throws -> Response {
        let request = try endpoint.urlRequest(baseURL: baseURL, ownerKey: ownerKey)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        } catch {
            throw APIError.fromTransport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(code: APIError.networkErrorCode, message: "", status: 0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.fromResponse(status: http.statusCode, body: data)
        }
        if Response.self == IzzyAPI.NoContent.self, let nothing = IzzyAPI.NoContent() as? Response {
            return nothing
        }
        do {
            return try IzzyAPI.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(APIError.describe(error))
        }
    }

    // MARK: ShopAPI

    public func health() async throws -> IzzyAPI.Health {
        try await send(IzzyAPI.Endpoints.health())
    }

    public func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        try await send(IzzyAPI.Endpoints.availability(query))
    }

    /// Answers 201 for a new booking and 200 for a retry the server recognized; both decode the
    /// same way.
    public func book(_ appointment: IzzyAPI.NewAppointment, token: IzzyAPI.ManageToken) async throws -> IzzyAPI.BookingConfirmation {
        try await send(try encoded { try IzzyAPI.Endpoints.book(appointment, token: token) })
    }

    public func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        try await send(IzzyAPI.Endpoints.appointment(id: id, manageToken: manageToken)).appointment
    }

    public func cancelAppointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        try await send(IzzyAPI.Endpoints.cancelAppointment(id: id, manageToken: manageToken)).appointment
    }

    public func reviews() async throws -> IzzyAPI.ReviewsResponse {
        try await send(IzzyAPI.Endpoints.reviews())
    }

    public func products() async throws -> [IzzyAPI.Product] {
        try await send(IzzyAPI.Endpoints.products()).products
    }

    // MARK: OwnerAPI

    public func ownerStatus() async throws -> IzzyAPI.OwnerStatus {
        try await send(IzzyAPI.Endpoints.ownerStatus())
    }

    public func ownerAvailability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse {
        try await send(IzzyAPI.Endpoints.ownerAvailability(query))
    }

    public func appointments(on date: LocalDate) async throws -> [IzzyAPI.Appointment] {
        try await send(IzzyAPI.Endpoints.ownerAppointments(on: date)).appointments
    }

    public func appointments(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.Appointment] {
        try await send(IzzyAPI.Endpoints.ownerAppointments(from: from, to: to)).appointments
    }

    public func createAppointment(_ appointment: IzzyAPI.NewAppointment) async throws -> IzzyAPI.Appointment {
        try await send(try encoded { try IzzyAPI.Endpoints.createOwnerAppointment(appointment) }).appointment
    }

    public func setStatus(_ status: IzzyAPI.AppointmentStatus, ofAppointment id: String) async throws -> IzzyAPI.Appointment {
        try await send(try encoded { try IzzyAPI.Endpoints.setAppointmentStatus(id: id, to: status) }).appointment
    }

    public func timeOff(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.TimeOff] {
        try await send(IzzyAPI.Endpoints.timeOff(from: from, to: to)).timeOff
    }

    public func createTimeOff(_ timeOff: IzzyAPI.NewTimeOff) async throws -> IzzyAPI.TimeOff {
        try await send(try encoded { try IzzyAPI.Endpoints.createTimeOff(timeOff) }).timeOff
    }

    public func deleteTimeOff(id: String) async throws {
        _ = try await send(IzzyAPI.Endpoints.deleteTimeOff(id: id))
    }

    public func allProducts() async throws -> [IzzyAPI.Product] {
        try await send(IzzyAPI.Endpoints.ownerProducts()).products
    }

    public func createProduct(_ product: IzzyAPI.NewProduct) async throws -> IzzyAPI.Product {
        try await send(try encoded { try IzzyAPI.Endpoints.createProduct(product) }).product
    }

    public func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) async throws -> IzzyAPI.Product {
        try await send(try encoded { try IzzyAPI.Endpoints.updateProduct(id: id, update) }).product
    }

    public func deleteProduct(id: String) async throws {
        _ = try await send(IzzyAPI.Endpoints.deleteProduct(id: id))
    }

    /// Photos over `IzzyAPI.maxPhotoBytes` are turned down here, with the
    /// same message the server's limit gives, without uploading them.
    public func uploadProductPhoto(id: String, jpegData: Data) async throws -> IzzyAPI.Product {
        guard jpegData.count <= IzzyAPI.maxPhotoBytes else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: APIError.tooLargeMessage, status: 0)
        }
        return try await send(IzzyAPI.Endpoints.uploadProductPhoto(id: id, jpegData: jpegData)).product
    }

    public func connectionToken() async throws -> String {
        try await send(IzzyAPI.Endpoints.connectionToken()).secret
    }

    public func createPayment(_ payment: IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated {
        try await send(try encoded { try IzzyAPI.Endpoints.createPayment(payment) })
    }

    public func completePayment(id: String) async throws -> IzzyAPI.Payment {
        try await send(IzzyAPI.Endpoints.completePayment(id: id)).payment
    }

    public func payments(on date: LocalDate) async throws -> [IzzyAPI.Payment] {
        try await send(IzzyAPI.Endpoints.payments(on: date)).payments
    }

    /// Builds an endpoint whose body is encoded JSON; an encoding failure
    /// (which the request types never produce) is reported as `APIError`.
    private func encoded<Response>(_ build: () throws -> IzzyAPI.Endpoint<Response>) throws -> IzzyAPI.Endpoint<Response> {
        do {
            return try build()
        } catch {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "", status: 0)
        }
    }
}

/// Turns down every redirect: the API never redirects, so one means a
/// misconfigured base URL or a server that's been tampered with. The redirect
/// response itself is returned and becomes an `APIError`.
final class RedirectRefuser: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RedirectRefuser()

    #if canImport(FoundationNetworking)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
    #else
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
    #endif
}
