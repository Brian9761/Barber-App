import Foundation

// Request bodies and queries. Unlike responses, optional fields that are
// empty are left out of request bodies (never sent as `null` unless the
// contract asks for it), and text is trimmed, so a blank note or email never
// fails the server's validation.

extension IzzyAPI {
    /// Who to book with: one barber's offering, or the first available barber
    /// for a service.
    public enum BookingTarget: Hashable, Sendable {
        /// A specific barber's offering: the Kit's `Offering.id`.
        case offering(id: String)
        /// Whoever is free first among the catalog's `firstAvailable` offerings.
        case anyBarber(serviceId: String)

        public static func offering(_ offering: Offering) -> BookingTarget {
            .offering(id: offering.id)
        }

        /// The fields this target adds to a query or a body, in order.
        var fields: [(name: String, value: String)] {
            switch self {
            case .offering(let id):
                return [("offeringId", id)]
            case .anyBarber(let serviceId):
                return [("serviceId", serviceId), ("barberId", IzzyAPI.anyBarberID)]
            }
        }
    }

    /// `GET /api/availability?offeringId=…|serviceId=…&barberId=any&from=YYYY-MM-DD&days=1..31`.
    public struct AvailabilityQuery: Hashable, Sendable {
        public var target: BookingTarget
        /// The first shop day to list.
        public var from: LocalDate
        /// How many days to list, 1 to 31.
        public var days: Int

        public init(target: BookingTarget, from: LocalDate, days: Int = 1) {
            self.target = target
            self.from = from
            self.days = days
        }
    }

    /// The customer part of a new appointment: `{ name, phone, email? }`.
    /// The public endpoint needs a phone; the owner's walk-ins don't.
    public struct NewCustomer: Encodable, Hashable, Sendable {
        public var name: String
        /// Sent in E.164, e.g. "+14423413053": a US number typed any common
        /// way ("(442) 341-3053") is converted; anything else is sent as typed
        /// for the server to turn down.
        public var phone: String?
        public var email: String?

        public init(name: String, phone: String? = nil, email: String? = nil) {
            self.name = name
            self.phone = phone
            self.email = email
        }

        private enum CodingKeys: String, CodingKey {
            case name, phone, email
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name.trimmed, forKey: .name)
            if let typed = phone?.trimmed.nonEmpty {
                try container.encode(PhoneNumber(parsing: typed)?.e164 ?? typed, forKey: .phone)
            }
            try container.encodeIfPresent(email?.trimmed.nonEmpty, forKey: .email)
        }
    }

    /// `POST /api/appointments` and `POST /api/owner/appointments`:
    /// `{ offeringId? | (serviceId + barberId: "any"), start, customer, note? }`.
    public struct NewAppointment: Encodable, Hashable, Sendable {
        public var target: BookingTarget
        /// A slot's `start`, exactly as the server listed it.
        public var start: Date
        public var customer: NewCustomer
        public var note: String?

        public init(target: BookingTarget, start: Date, customer: NewCustomer, note: String? = nil) {
            self.target = target
            self.start = start
            self.customer = customer
            self.note = note
        }

        private struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(_ string: String) { stringValue = string }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for field in target.fields {
                try container.encode(field.value, forKey: Key(field.name))
            }
            try container.encode(start, forKey: Key("start"))
            try container.encode(customer, forKey: Key("customer"))
            try container.encodeIfPresent(note?.trimmed.nonEmpty, forKey: Key("note"))
        }

        /// What the server compares when the same manage token comes back
        /// (`ShopAPI.book(_:token:)`): the target, asked for the same way, the
        /// start as it's sent, and the phone number as it's sent (E.164). The
        /// name, email and note aren't part of it, so two requests with the
        /// same key are one booking to the server, even with those edited.
        public var retryKey: String {
            let target = target.fields.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
            let phone = customer.phone?.trimmed.nonEmpty.map { PhoneNumber(parsing: $0)?.e164 ?? $0 } ?? ""
            return [target, Timestamp.string(from: start), phone].joined(separator: "|")
        }
    }

    /// `PATCH /api/owner/appointments/:id` body `{ status }`.
    public struct StatusChange: Encodable, Hashable, Sendable {
        public var status: AppointmentStatus

        public init(status: AppointmentStatus) {
            self.status = status
        }
    }

    /// `POST /api/owner/time-off` body `{ barberId|null, start, end, reason? }`.
    public struct NewTimeOff: Encodable, Hashable, Sendable {
        /// `nil` blocks the whole shop; it's sent as an explicit `null`.
        public var barberId: String?
        public var start: Date
        public var end: Date
        public var reason: String?

        public init(barberId: String?, start: Date, end: Date, reason: String? = nil) {
            self.barberId = barberId
            self.start = start
            self.end = end
            self.reason = reason
        }

        private enum CodingKeys: String, CodingKey {
            case barberId, start, end, reason
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let barberId {
                try container.encode(barberId, forKey: .barberId)
            } else {
                try container.encodeNil(forKey: .barberId)
            }
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
            try container.encodeIfPresent(reason?.trimmed.nonEmpty, forKey: .reason)
        }
    }

    /// `POST /api/owner/products` body `{ name, description?, priceCents?, visible? }`.
    public struct NewProduct: Encodable, Hashable, Sendable {
        public var name: String
        public var description: String?
        public var priceCents: Int?
        /// `nil` lets the server decide (it shows new products by default).
        public var visible: Bool?

        public init(name: String, description: String? = nil, priceCents: Int? = nil, visible: Bool? = nil) {
            self.name = name
            self.description = description
            self.priceCents = priceCents
            self.visible = visible
        }

        private enum CodingKeys: String, CodingKey {
            case name, description, priceCents, visible
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name.trimmed, forKey: .name)
            try container.encodeIfPresent(description?.trimmed.nonEmpty, forKey: .description)
            try container.encodeIfPresent(priceCents, forKey: .priceCents)
            try container.encodeIfPresent(visible, forKey: .visible)
        }
    }

    /// A field in a partial update: leave it, set it, or clear it to `null`.
    public enum FieldUpdate<Value: Hashable & Sendable>: Hashable, Sendable {
        case unchanged
        case set(Value)
        case clear
    }

    /// `PATCH /api/owner/products/:id` (partial): only the fields that change
    /// are sent. Clearing the description or the price sends `null`; so does
    /// setting a blank description.
    public struct ProductUpdate: Encodable, Hashable, Sendable {
        /// `nil` leaves the name as it is.
        public var name: String?
        public var description: FieldUpdate<String>
        public var priceCents: FieldUpdate<Int>
        /// `nil` leaves it as it is.
        public var visible: Bool?

        public init(
            name: String? = nil,
            description: FieldUpdate<String> = .unchanged,
            priceCents: FieldUpdate<Int> = .unchanged,
            visible: Bool? = nil
        ) {
            self.name = name
            self.description = description
            self.priceCents = priceCents
            self.visible = visible
        }

        /// Everything the product editor shows, from its current values: an
        /// empty description or a missing price is sent as a clear.
        public static func replacing(name: String, description: String?, priceCents: Int?, visible: Bool) -> ProductUpdate {
            ProductUpdate(
                name: name,
                description: description?.trimmed.nonEmpty.map { .set($0) } ?? .clear,
                priceCents: priceCents.map { .set($0) } ?? .clear,
                visible: visible
            )
        }

        public var isEmpty: Bool {
            name == nil && description == .unchanged && priceCents == .unchanged && visible == nil
        }

        private enum CodingKeys: String, CodingKey {
            case name, description, priceCents, visible
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name?.trimmed, forKey: .name)
            switch description {
            case .unchanged: break
            case .set(let value):
                if let text = value.trimmed.nonEmpty {
                    try container.encode(text, forKey: .description)
                } else {
                    try container.encodeNil(forKey: .description)
                }
            case .clear: try container.encodeNil(forKey: .description)
            }
            switch priceCents {
            case .unchanged: break
            case .set(let value): try container.encode(value, forKey: .priceCents)
            case .clear: try container.encodeNil(forKey: .priceCents)
            }
            try container.encodeIfPresent(visible, forKey: .visible)
        }
    }

    /// `POST /api/owner/payments` body `{ amountCents, description?, appointmentId?, receiptEmail? }`.
    public struct NewPayment: Encodable, Hashable, Sendable {
        /// 50 to 100,000 (`IzzyAPI.paymentAmountRange`).
        public var amountCents: Int
        public var description: String?
        public var appointmentId: String?
        /// Stripe emails the receipt here.
        public var receiptEmail: String?

        public init(amountCents: Int, description: String? = nil, appointmentId: String? = nil, receiptEmail: String? = nil) {
            self.amountCents = amountCents
            self.description = description
            self.appointmentId = appointmentId
            self.receiptEmail = receiptEmail
        }

        /// Whether the server will take the amount.
        public var isAmountAllowed: Bool { IzzyAPI.paymentAmountRange.contains(amountCents) }

        private enum CodingKeys: String, CodingKey {
            case amountCents, description, appointmentId, receiptEmail
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(amountCents, forKey: .amountCents)
            try container.encodeIfPresent(description?.trimmed.nonEmpty, forKey: .description)
            try container.encodeIfPresent(appointmentId?.trimmed.nonEmpty, forKey: .appointmentId)
            try container.encodeIfPresent(receiptEmail?.trimmed.nonEmpty, forKey: .receiptEmail)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
