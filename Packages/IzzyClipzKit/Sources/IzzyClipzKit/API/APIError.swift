import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything that can go wrong talking to the server, typed so the apps can
/// offer the right way forward (pick another time, retry, call the shop).
///
/// Task cancellation is not an `APIError`: it's thrown as `CancellationError`.
public enum APIError: Error, Hashable, Sendable {
    /// The server couldn't be reached: no connection, the connection dropped,
    /// the host wasn't found or the request timed out.
    case offline
    /// Any other error the server reported, with its contract code
    /// (`invalid_request`, `not_found`, `server_error`, …), its message and
    /// the HTTP status. Status 0 means the request never got a response.
    case server(code: String, message: String, status: Int)
    /// 409 `slot_taken`: someone else booked that time first.
    case slotTaken
    /// 409 `not_cancellable`: it's not booked any more, or it already started.
    case notCancellable
    /// 429 `rate_limited`.
    case rateLimited
    /// 401 `unauthorized`: a missing or wrong owner key or manage token.
    case unauthorized
    /// 503 `stripe_not_configured` (`"stripe"`), `owner_not_configured`
    /// (`"owner"`), or a base URL the app can't use (`"server"`).
    case notConfigured(String)
    /// 422 `outside_hours`.
    case outsideHours
    /// 422 `too_soon`: inside the lead time.
    case tooSoon
    /// 422 `too_far`: past the booking window.
    case tooFar
    /// The response wasn't what the contract says; the text says where.
    case decoding(String)

    /// The features `notConfigured` names.
    public enum Feature {
        public static let stripe = "stripe"
        public static let owner = "owner"
        public static let server = "server"
    }

    /// The error for a contract error code.
    public init(code: String, message: String, status: Int) {
        switch code {
        case IzzyAPI.ErrorCode.slotTaken: self = .slotTaken
        case IzzyAPI.ErrorCode.notCancellable: self = .notCancellable
        case IzzyAPI.ErrorCode.rateLimited: self = .rateLimited
        case IzzyAPI.ErrorCode.unauthorized: self = .unauthorized
        case IzzyAPI.ErrorCode.stripeNotConfigured: self = .notConfigured(Feature.stripe)
        case IzzyAPI.ErrorCode.ownerNotConfigured: self = .notConfigured(Feature.owner)
        case IzzyAPI.ErrorCode.outsideHours: self = .outsideHours
        case IzzyAPI.ErrorCode.tooSoon: self = .tooSoon
        case IzzyAPI.ErrorCode.tooFar: self = .tooFar
        default: self = .server(code: code, message: message, status: status)
        }
    }

    /// The contract error code, when there is one.
    public var code: String? {
        switch self {
        case .offline, .decoding: return nil
        case .server(let code, _, _): return code
        case .slotTaken: return IzzyAPI.ErrorCode.slotTaken
        case .notCancellable: return IzzyAPI.ErrorCode.notCancellable
        case .rateLimited: return IzzyAPI.ErrorCode.rateLimited
        case .unauthorized: return IzzyAPI.ErrorCode.unauthorized
        case .notConfigured(let feature):
            switch feature {
            case Feature.stripe: return IzzyAPI.ErrorCode.stripeNotConfigured
            case Feature.owner: return IzzyAPI.ErrorCode.ownerNotConfigured
            default: return nil
            }
        case .outsideHours: return IzzyAPI.ErrorCode.outsideHours
        case .tooSoon: return IzzyAPI.ErrorCode.tooSoon
        case .tooFar: return IzzyAPI.ErrorCode.tooFar
        }
    }

    /// Whether trying the same request again later might work.
    public var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited: return true
        case .server(_, _, let status): return status == 0 || status >= 500
        default: return false
        }
    }

    /// A plain, friendly sentence to show the person, with a way forward.
    public var userMessage: String {
        switch self {
        case .offline:
            return "We couldn't reach the shop. Check your internet connection and try again."
        case .server(let code, let message, _):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
            switch code {
            case IzzyAPI.ErrorCode.invalidRequest:
                return "Something in that request wasn't right. Check the details and try again."
            case IzzyAPI.ErrorCode.notFound:
                return "We couldn't find that. It may have been removed."
            case APIError.networkErrorCode:
                return "We couldn't reach the shop's server. Try again in a moment, or call the shop."
            default:
                return "Something went wrong on our side. Try again in a moment, or call the shop."
            }
        case .slotTaken:
            return "Someone just booked that time. Pick another one."
        case .notCancellable:
            return "This appointment can't be cancelled anymore. Call the shop if you need to change it."
        case .rateLimited:
            return "That's a lot of tries in a short time. Wait a little and try again, or call the shop."
        case .unauthorized:
            return "We couldn't confirm it's you. Sign in again, or call the shop if this keeps happening."
        case .notConfigured(let feature):
            switch feature {
            case Feature.stripe:
                return "Card payments aren't set up yet. Add the shop's Stripe account on the server to take payments."
            case Feature.owner:
                return "The owner key isn't set up on the server yet."
            default:
                return "The app isn't connected to the shop's server yet. Call the shop to book."
            }
        case .outsideHours:
            return "That time is outside the shop's hours. Pick another time."
        case .tooSoon:
            return "That time is too soon to book. Pick a later time."
        case .tooFar:
            return "That day is too far ahead to book. Pick an earlier day."
        case .decoding:
            return "Something went wrong reading the shop's reply. Try again in a moment."
        }
    }

    // MARK: Mapping

    /// The code `server` uses for a connection problem that isn't simply
    /// being offline, such as a failed secure connection.
    public static let networkErrorCode = "network_error"

    /// URL loading errors that mean the server couldn't be reached.
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotFindHost,
        .cannotConnectToHost,
        .dnsLookupFailed,
        .timedOut,
        .internationalRoamingOff,
        .dataNotAllowed,
        .callIsActive,
        .cannotLoadFromNetwork,
    ]

    /// What a failed `URLSession` call becomes. Cancellation turns into
    /// `CancellationError` so callers can ignore it in one place.
    static func fromTransport(_ error: Error) -> Error {
        if error is CancellationError || error is APIError { return error }
        let code: URLError.Code?
        if let urlError = error as? URLError {
            code = urlError.code
        } else {
            let nsError = error as NSError
            code = nsError.domain == NSURLErrorDomain ? URLError.Code(rawValue: nsError.code) : nil
        }
        guard let code else {
            return APIError.server(code: networkErrorCode, message: "", status: 0)
        }
        if code == .cancelled { return CancellationError() }
        if offlineCodes.contains(code) { return APIError.offline }
        return APIError.server(code: networkErrorCode, message: "", status: 0)
    }

    /// What a response with a non-2xx status becomes: the contract's error
    /// envelope when there is one, otherwise a guess from the status.
    static func fromResponse(status: Int, body: Data) -> APIError {
        if let envelope = try? IzzyAPI.makeDecoder().decode(IzzyAPI.ErrorEnvelope.self, from: body) {
            // The message is shown to people; keep a runaway one short.
            let message = String(envelope.error.message.prefix(300))
            return APIError(code: envelope.error.code, message: message, status: status)
        }
        switch status {
        case 401: return .unauthorized
        case 404: return .server(code: IzzyAPI.ErrorCode.notFound, message: "", status: status)
        case 429: return .rateLimited
        // 400, and others such as 413 when a photo is over the platform's limit.
        case 400..<500: return .server(code: IzzyAPI.ErrorCode.invalidRequest, message: "", status: status)
        default: return .server(code: IzzyAPI.ErrorCode.serverError, message: "", status: status)
        }
    }

    /// A short "where and what" for a decoding failure, for logs and bug reports.
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return String(describing: error) }
        func path(_ context: DecodingError.Context, _ key: CodingKey? = nil) -> String {
            let keys = context.codingPath + (key.map { [$0] } ?? [])
            let text = keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return text.isEmpty ? "response" : "response" + text
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "\(path(context, key)) is missing"
        case .valueNotFound(_, let context):
            return "\(path(context)) is null: \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            return "\(path(context)) isn't \(type): \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "\(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: decodingError)
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { userMessage }
}
