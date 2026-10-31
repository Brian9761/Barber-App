import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension IzzyAPI {
    public enum HTTPMethod: String, Hashable, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    /// The secret a request carries, if any.
    public enum Credential: Hashable, Sendable {
        case none
        /// `X-Manage-Token`: the customer's token for one appointment.
        case manageToken(String)
        /// `Authorization: Bearer <owner key>`, filled in by the client.
        case ownerKey
    }

    public struct QueryItem: Hashable, Sendable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    /// One API call, described without sending it: what `IzzyAPIClient`
    /// sends, and what tests and fakes can inspect.
    public struct Endpoint<Response: Decodable>: Sendable {
        public let method: HTTPMethod
        /// Below the base URL, percent-encoded, e.g. "/api/appointments/abc/cancel".
        public let path: String
        public let query: [QueryItem]
        public let body: Data?
        public let contentType: String?
        public let credential: Credential
        public let timeout: TimeInterval

        init(
            _ method: HTTPMethod,
            _ path: String,
            query: [QueryItem] = [],
            body: Data? = nil,
            contentType: String? = nil,
            credential: Credential = .none,
            timeout: TimeInterval = 30
        ) {
            // A POST always has a body, `{}` if nothing else, so servers that
            // read JSON from every POST never trip over an empty one.
            let body = body ?? (method == .post ? Data("{}".utf8) : nil)
            self.method = method
            self.path = path
            self.query = query
            self.body = body
            self.contentType = contentType ?? (body == nil ? nil : "application/json")
            self.credential = credential
            self.timeout = timeout
        }

        /// The request to send to the server at `baseURL`.
        ///
        /// - Throws: `APIError.notConfigured("server")` for a base URL that
        ///   isn't https with a host (plain http only for this computer, for a
        ///   local server in development); `APIError.unauthorized` for an
        ///   owner call without a usable owner key, or a manage token that
        ///   can't be sent, so a secret is never sent malformed or empty.
        public func urlRequest(baseURL: URL, ownerKey: String?) throws -> URLRequest {
            guard let scheme = baseURL.scheme?.lowercased(),
                  var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
                  let host = components.host?.lowercased(), !host.isEmpty,
                  scheme == "https" || (scheme == "http" && Endpoints.isLoopback(host))
            else { throw APIError.notConfigured(APIError.Feature.server) }

            var basePath = components.percentEncodedPath
            while basePath.hasSuffix("/") { basePath.removeLast() }
            components.percentEncodedPath = basePath + path
            components.percentEncodedQuery = query.isEmpty
                ? nil
                : query.map { Endpoints.escape($0.name) + "=" + Endpoints.escape($0.value) }.joined(separator: "&")
            components.fragment = nil
            guard let url = components.url else { throw APIError.notConfigured(APIError.Feature.server) }

            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
            request.httpMethod = method.rawValue
            request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
            }
            switch credential {
            case .none:
                break
            case .manageToken(let token):
                guard Endpoints.isHeaderSafe(token) else { throw APIError.unauthorized }
                request.setValue(token, forHTTPHeaderField: "X-Manage-Token")
            case .ownerKey:
                guard let ownerKey, Endpoints.isHeaderSafe(ownerKey) else { throw APIError.unauthorized }
                request.setValue("Bearer " + ownerKey, forHTTPHeaderField: "Authorization")
            }
            return request
        }
    }

    /// Every endpoint in the v1 contract.
    public enum Endpoints {
        // MARK: Public

        /// `GET /api/health` → `{ ok, version }`.
        public static func health() -> Endpoint<Health> {
            Endpoint(.get, "/api/health")
        }

        /// `GET /api/availability` → `{ timeZone, days }`.
        public static func availability(_ query: AvailabilityQuery) -> Endpoint<AvailabilityResponse> {
            let target = query.target.fields.map { QueryItem($0.name, $0.value) }
            return Endpoint(.get, "/api/availability", query: target + [
                QueryItem("from", query.from.description),
                QueryItem("days", String(query.days)),
            ])
        }

        /// `POST /api/appointments` with the app's own `X-Manage-Token` → 201 `{ appointment,
        /// manageToken }`, or 200 with the same when this token already booked this appointment
        /// (a retry after a lost answer).
        public static func book(_ appointment: NewAppointment, token: ManageToken) throws -> Endpoint<BookingConfirmation> {
            Endpoint(.post, "/api/appointments", body: try json(appointment), credential: .manageToken(token.rawValue))
        }

        /// `GET /api/appointments/:id` with `X-Manage-Token` → `{ appointment }`.
        public static func appointment(id: String, manageToken: String) -> Endpoint<AppointmentResponse> {
            Endpoint(.get, "/api/appointments/" + segment(id), credential: .manageToken(manageToken))
        }

        /// `POST /api/appointments/:id/cancel` with `X-Manage-Token` → `{ appointment }`.
        public static func cancelAppointment(id: String, manageToken: String) -> Endpoint<AppointmentResponse> {
            Endpoint(.post, "/api/appointments/" + segment(id) + "/cancel", credential: .manageToken(manageToken))
        }

        /// `GET /api/reviews` → `{ google, yelp }`.
        public static func reviews() -> Endpoint<ReviewsResponse> {
            Endpoint(.get, "/api/reviews")
        }

        /// `GET /api/products` → `{ products }`: visible ones, in the shop's order.
        public static func products() -> Endpoint<ProductsResponse> {
            Endpoint(.get, "/api/products")
        }

        // MARK: Owner

        /// `GET /api/owner/me` → `{ ok, stripe }`.
        public static func ownerStatus() -> Endpoint<OwnerStatus> {
            Endpoint(.get, "/api/owner/me", credential: .ownerKey)
        }

        /// `GET /api/owner/availability` → `{ timeZone, days }`: like `availability`, without the
        /// lead time, so a walk-in can take the next slot that hasn't started yet.
        public static func ownerAvailability(_ query: AvailabilityQuery) -> Endpoint<AvailabilityResponse> {
            let target = query.target.fields.map { QueryItem($0.name, $0.value) }
            return Endpoint(.get, "/api/owner/availability", query: target + [
                QueryItem("from", query.from.description),
                QueryItem("days", String(query.days)),
            ], credential: .ownerKey)
        }

        /// `GET /api/owner/appointments?date=YYYY-MM-DD` → `{ appointments }`.
        public static func ownerAppointments(on date: LocalDate) -> Endpoint<AppointmentsResponse> {
            Endpoint(.get, "/api/owner/appointments", query: [QueryItem("date", date.description)], credential: .ownerKey)
        }

        /// `GET /api/owner/appointments?from=YYYY-MM-DD&to=YYYY-MM-DD` → `{ appointments }`.
        public static func ownerAppointments(from: LocalDate, to: LocalDate) -> Endpoint<AppointmentsResponse> {
            Endpoint(
                .get, "/api/owner/appointments",
                query: [QueryItem("from", from.description), QueryItem("to", to.description)],
                credential: .ownerKey
            )
        }

        /// `POST /api/owner/appointments` → 201 `{ appointment }`.
        public static func createOwnerAppointment(_ appointment: NewAppointment) throws -> Endpoint<AppointmentResponse> {
            Endpoint(.post, "/api/owner/appointments", body: try json(appointment), credential: .ownerKey)
        }

        /// `PATCH /api/owner/appointments/:id` `{ status }` → `{ appointment }`.
        public static func setAppointmentStatus(id: String, to status: AppointmentStatus) throws -> Endpoint<AppointmentResponse> {
            Endpoint(.patch, "/api/owner/appointments/" + segment(id), body: try json(StatusChange(status: status)), credential: .ownerKey)
        }

        /// `GET /api/owner/time-off?from=YYYY-MM-DD&to=YYYY-MM-DD` → `{ timeOff: [TimeOff] }`.
        public static func timeOff(from: LocalDate, to: LocalDate) -> Endpoint<TimeOffListResponse> {
            Endpoint(
                .get, "/api/owner/time-off",
                query: [QueryItem("from", from.description), QueryItem("to", to.description)],
                credential: .ownerKey
            )
        }

        /// `POST /api/owner/time-off` → 201 `{ timeOff }`.
        public static func createTimeOff(_ timeOff: NewTimeOff) throws -> Endpoint<TimeOffResponse> {
            Endpoint(.post, "/api/owner/time-off", body: try json(timeOff), credential: .ownerKey)
        }

        /// `DELETE /api/owner/time-off/:id` → 204.
        public static func deleteTimeOff(id: String) -> Endpoint<NoContent> {
            Endpoint(.delete, "/api/owner/time-off/" + segment(id), credential: .ownerKey)
        }

        /// `GET /api/owner/products` → `{ products }`, hidden ones included.
        public static func ownerProducts() -> Endpoint<ProductsResponse> {
            Endpoint(.get, "/api/owner/products", credential: .ownerKey)
        }

        /// `POST /api/owner/products` → 201 `{ product }`.
        public static func createProduct(_ product: NewProduct) throws -> Endpoint<ProductResponse> {
            Endpoint(.post, "/api/owner/products", body: try json(product), credential: .ownerKey)
        }

        /// `PATCH /api/owner/products/:id` (partial) → `{ product }`.
        public static func updateProduct(id: String, _ update: ProductUpdate) throws -> Endpoint<ProductResponse> {
            Endpoint(.patch, "/api/owner/products/" + segment(id), body: try json(update), credential: .ownerKey)
        }

        /// `DELETE /api/owner/products/:id` → 204.
        public static func deleteProduct(id: String) -> Endpoint<NoContent> {
            Endpoint(.delete, "/api/owner/products/" + segment(id), credential: .ownerKey)
        }

        /// `POST /api/owner/products/:id/photo`, the JPEG itself as the body
        /// (`Content-Type: image/jpeg`, at most `maxPhotoBytes`) → `{ product }`.
        public static func uploadProductPhoto(id: String, jpegData: Data) -> Endpoint<ProductResponse> {
            Endpoint(
                .post, "/api/owner/products/" + segment(id) + "/photo",
                body: jpegData, contentType: "image/jpeg", credential: .ownerKey, timeout: 60
            )
        }

        /// `POST /api/owner/terminal/connection-token` → `{ secret }`.
        public static func connectionToken() -> Endpoint<ConnectionToken> {
            Endpoint(.post, "/api/owner/terminal/connection-token", credential: .ownerKey)
        }

        /// `POST /api/owner/payments` → 201 `{ paymentIntentId, clientSecret }`.
        public static func createPayment(_ payment: NewPayment) throws -> Endpoint<PaymentIntentCreated> {
            Endpoint(.post, "/api/owner/payments", body: try json(payment), credential: .ownerKey)
        }

        /// `POST /api/owner/payments/:id/complete` → `{ payment }`.
        public static func completePayment(id: String) -> Endpoint<PaymentResponse> {
            Endpoint(.post, "/api/owner/payments/" + segment(id) + "/complete", credential: .ownerKey)
        }

        /// `GET /api/owner/payments?date=YYYY-MM-DD` → `{ payments }`.
        public static func payments(on date: LocalDate) -> Endpoint<PaymentsResponse> {
            Endpoint(.get, "/api/owner/payments", query: [QueryItem("date", date.description)], credential: .ownerKey)
        }

        // MARK: Encoding

        static func json<Body: Encodable>(_ body: Body) throws -> Data {
            try IzzyAPI.makeEncoder().encode(body)
        }

        /// Percent-encodes everything but letters, digits and `-._~`, so
        /// `/`, `?`, `#`, `&`, `+` and spaces in a value can't change the URL.
        static func escape(_ string: String) -> String {
            var result = ""
            for byte in string.utf8 {
                switch byte {
                case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                     UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."),
                     UInt8(ascii: "_"), UInt8(ascii: "~"):
                    result.append(Character(Unicode.Scalar(byte)))
                default:
                    let hex = String(byte, radix: 16, uppercase: true)
                    result += byte < 16 ? "%0" + hex : "%" + hex
                }
            }
            return result
        }

        /// One escaped path segment. "." and ".." are escaped too, so an ID can
        /// never walk up the path, and an empty ID becomes a space, which the
        /// server answers with an error instead of the route one level up.
        static func segment(_ id: String) -> String {
            if id.isEmpty { return "%20" }
            if id == "." || id == ".." { return String(repeating: "%2E", count: id.count) }
            return escape(id)
        }

        /// This computer, where plain http can't be overheard.
        static func isLoopback(_ host: String) -> Bool {
            host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
        }

        /// Not empty, and no control characters (a line break would split the
        /// header); only visible ASCII and spaces.
        static func isHeaderSafe(_ value: String) -> Bool {
            !value.isEmpty && value.utf8.allSatisfy { (0x20...0x7E).contains($0) }
        }
    }
}
