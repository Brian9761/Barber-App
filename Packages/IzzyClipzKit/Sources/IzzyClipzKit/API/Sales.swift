import Foundation

// Sales: what the shop sells at checkout, for the barber who gets credit, with or without an
// appointment. A sale has one or more items (a catalog service, one of the shop's products, or a
// custom item such as a gift card) and is paid by card with Tap to Pay, in cash, or another way
// the shop only records (Squire, Zelle, Cash App…). Cash and other sales are recorded with
// `recordSale`; a card sale's ticket goes with its payment (`NewPayment.sale`) and is recorded
// when the payment goes through. A sale is never edited: a mistake is voided. Models field for
// field as the server writes them (server/README.md, "Sales and analytics").

// MARK: - Sales

extension IzzyAPI {
    /// How a sale was paid.
    public enum SaleMethod: String, Codable, CaseIterable, Hashable, Sendable {
        /// Tap to Pay in the Business app, through Stripe.
        case card
        case cash
        /// Another way the shop only records: Squire, Zelle, Cash App…
        case other

        /// "Card", "Cash", "Other".
        public var title: String {
            switch self {
            case .card: return "Card"
            case .cash: return "Cash"
            case .other: return "Other"
            }
        }

        /// A method this version doesn't know reads as `other`: money recorded, not taken in the app.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = SaleMethod(rawValue: raw) ?? .other
        }
    }

    /// What a sale's item is.
    public enum SaleItemKind: String, Codable, CaseIterable, Hashable, Sendable {
        /// A service on the menu, e.g. a haircut.
        case service
        /// One of the shop's own products.
        case product
        /// Anything else with a name and a price, e.g. a gift card.
        case custom

        /// A kind this version doesn't know reads as `custom`: an item with a name and a price.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = SaleItemKind(rawValue: raw) ?? .custom
        }
    }

    /// One item of a sale, as it was sold: `{ kind, serviceId, productId, name, quantity, unitCents, totalCents }`.
    /// Names and prices are copied when it's sold, so changing the menu or a product later never changes it.
    public struct SaleItem: Codable, Hashable, Sendable {
        public var kind: SaleItemKind
        /// The catalog service, for a service.
        public var serviceId: String?
        /// The product, for a product; `nil` once the product is deleted (its name stays).
        public var productId: String?
        public var name: String
        public var quantity: Int
        /// The price of one, in cents.
        public var unitCents: Int
        /// `quantity` × `unitCents`.
        public var totalCents: Int

        /// `totalCents` defaults to `quantity` × `unitCents`, as the server works it out.
        public init(
            kind: SaleItemKind,
            serviceId: String? = nil,
            productId: String? = nil,
            name: String,
            quantity: Int = 1,
            unitCents: Int,
            totalCents: Int? = nil
        ) {
            self.kind = kind
            self.serviceId = serviceId
            self.productId = productId
            self.name = name
            self.quantity = quantity
            self.unitCents = unitCents
            self.totalCents = totalCents ?? quantity * unitCents
        }

        /// "$40", "2 × $18".
        public var priceLabel: String {
            quantity == 1 ? Price.currencyString(cents: unitCents) : "\(quantity) × " + Price.currencyString(cents: unitCents)
        }

        private enum CodingKeys: String, CodingKey {
            case kind, serviceId, productId, name, quantity, unitCents, totalCents
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(serviceId, forKey: .serviceId)
            try container.encode(productId, forKey: .productId)
            try container.encode(name, forKey: .name)
            try container.encode(quantity, forKey: .quantity)
            try container.encode(unitCents, forKey: .unitCents)
            try container.encode(totalCents, forKey: .totalCents)
        }
    }

    /// A sale: `{ id, barberId, barberName, appointmentId, customerName, method, paymentIntentId,
    /// totalCents, items, soldAt, voidedAt, voidReason }`.
    public struct Sale: Codable, Hashable, Identifiable, Sendable {
        public var id: String
        /// The barber who gets credit.
        public var barberId: String
        public var barberName: String
        /// The appointment it checked out, if any.
        public var appointmentId: String?
        public var customerName: String?
        public var method: SaleMethod
        /// A card sale's Tap to Pay payment ("pi_…"); `nil` for cash and other sales.
        public var paymentIntentId: String?
        public var totalCents: Int
        /// In the order they were rung up.
        public var items: [SaleItem]
        public var soldAt: Date
        /// When it was voided; a voided sale no longer counts anywhere.
        public var voidedAt: Date?
        public var voidReason: String?

        public init(
            id: String,
            barberId: String,
            barberName: String,
            appointmentId: String? = nil,
            customerName: String? = nil,
            method: SaleMethod,
            paymentIntentId: String? = nil,
            totalCents: Int? = nil,
            items: [SaleItem],
            soldAt: Date,
            voidedAt: Date? = nil,
            voidReason: String? = nil
        ) {
            self.id = id
            self.barberId = barberId
            self.barberName = barberName
            self.appointmentId = appointmentId
            self.customerName = customerName
            self.method = method
            self.paymentIntentId = paymentIntentId
            self.totalCents = totalCents ?? items.reduce(0) { $0 + $1.totalCents }
            self.items = items
            self.soldAt = soldAt
            self.voidedAt = voidedAt
            self.voidReason = voidReason
        }

        public var isVoided: Bool { voidedAt != nil }

        /// "$60", "$7.50".
        public var totalLabel: String { Price.currencyString(cents: totalCents) }

        /// What the receipt and Today's sales say: "Sold $60 · Cash · Izzy".
        public var receiptLine: String {
            "Sold \(totalLabel) · \(method.title) · \(barberName)"
        }

        /// The sale as voiding leaves it (the server's way, for fakes): voided once, at the first time.
        public func voided(at date: Date, reason: String? = nil) -> Sale {
            guard voidedAt == nil else { return self }
            var sale = self
            sale.voidedAt = date
            sale.voidReason = reason?.trimmed.nonEmpty
            return sale
        }

        private enum CodingKeys: String, CodingKey {
            case id, barberId, barberName, appointmentId, customerName, method, paymentIntentId, totalCents, items, soldAt, voidedAt, voidReason
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            barberId = try container.decode(String.self, forKey: .barberId)
            barberName = try container.decode(String.self, forKey: .barberName)
            appointmentId = try container.decodeIfPresent(String.self, forKey: .appointmentId)
            customerName = try container.decodeIfPresent(String.self, forKey: .customerName)
            method = try container.decode(SaleMethod.self, forKey: .method)
            paymentIntentId = try container.decodeIfPresent(String.self, forKey: .paymentIntentId)
            totalCents = try container.decode(Int.self, forKey: .totalCents)
            items = try container.decode([SaleItem].self, forKey: .items)
            soldAt = try container.decode(Date.self, forKey: .soldAt)
            voidedAt = try container.decodeIfPresent(Date.self, forKey: .voidedAt)
            voidReason = try container.decodeIfPresent(String.self, forKey: .voidReason)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(barberId, forKey: .barberId)
            try container.encode(barberName, forKey: .barberName)
            try container.encode(appointmentId, forKey: .appointmentId)
            try container.encode(customerName, forKey: .customerName)
            try container.encode(method, forKey: .method)
            try container.encode(paymentIntentId, forKey: .paymentIntentId)
            try container.encode(totalCents, forKey: .totalCents)
            try container.encode(items, forKey: .items)
            try container.encode(soldAt, forKey: .soldAt)
            try container.encode(voidedAt, forKey: .voidedAt)
            try container.encode(voidReason, forKey: .voidReason)
        }
    }

    /// An owner appointment's checkout: its live (not voided) sale, `{ id, totalCents, method }`. Only
    /// the shop sees it; the client's own view of an appointment doesn't have it.
    public struct AppointmentSale: Codable, Hashable, Sendable {
        /// The sale's id (`Sale.id`), e.g. for "Void sale".
        public var id: String
        public var totalCents: Int
        public var method: SaleMethod

        public init(id: String, totalCents: Int, method: SaleMethod) {
            self.id = id
            self.totalCents = totalCents
            self.method = method
        }

        /// The appointment's copy of `sale`, as the server keeps it.
        public init(sale: Sale) {
            self.init(id: sale.id, totalCents: sale.totalCents, method: sale.method)
        }

        /// "Paid $60 · Cash".
        public var paidLabel: String {
            "Paid " + Price.currencyString(cents: totalCents) + " · " + method.title
        }
    }

    /// `POST /api/owner/sales` → 201 `{ sale }` (200 with the same for a retry with the same key).
    public struct SaleResponse: Codable, Hashable, Sendable {
        public var sale: Sale

        public init(sale: Sale) {
            self.sale = sale
        }
    }

    /// `POST /api/owner/sales/:id/void` → `{ sale, message }`. Voiding again answers the same.
    public struct VoidedSale: Codable, Hashable, Sendable {
        public var sale: Sale
        /// What to tell the owner. For a card sale it says the card isn't refunded: refunds are made
        /// in the Stripe Dashboard.
        public var message: String

        public init(sale: Sale, message: String? = nil) {
            self.sale = sale
            self.message = message ?? VoidedSale.message(for: sale.method)
        }

        /// What the server says after voiding a sale paid `method`.
        public static func message(for method: SaleMethod) -> String {
            let voided = "The sale was voided, so it no longer counts in your sales."
            return method == .card ? voided + " Voiding doesn't refund the card: refunds are made in the Stripe Dashboard." : voided
        }
    }

    /// `GET /api/owner/sales?date=YYYY-MM-DD` → `{ date, sales, totals }`: one shop day's sales, newest
    /// first, voided ones too.
    public struct SalesDay: Codable, Hashable, Sendable {
        /// `{ totalCents, count }` of the live sales: voided sales don't count.
        public struct Totals: Codable, Hashable, Sendable {
            public var totalCents: Int
            public var count: Int

            public init(totalCents: Int, count: Int) {
                self.totalCents = totalCents
                self.count = count
            }

            /// "$184".
            public var totalLabel: String { Price.currencyString(cents: totalCents) }
        }

        public var date: LocalDate
        public var sales: [Sale]
        public var totals: Totals

        public init(date: LocalDate, sales: [Sale], totals: Totals) {
            self.date = date
            self.sales = sales
            self.totals = totals
        }

        /// The day as the server answers it: the totals of the sales that aren't voided.
        public init(date: LocalDate, sales: [Sale]) {
            let live = sales.filter { !$0.isVoided }
            self.init(date: date, sales: sales, totals: Totals(totalCents: live.reduce(0) { $0 + $1.totalCents }, count: live.count))
        }
    }
}

// MARK: - Checking out an appointment

extension IzzyAPI.Appointment {
    /// Whether the shop checked it out: it has a live sale (`sale`, in the shop's view).
    public var isCheckedOut: Bool { sale != nil }

    /// Whether the shop can check it out now, by the server's rule: booked or completed, and not
    /// checked out yet. A cancelled or no-show appointment has to be reopened first (409
    /// `not_checkoutable`); a checked-out one stays completed until its sale is voided.
    public var canCheckOut: Bool {
        (status == .booked || status == .completed) && sale == nil
    }
}

// MARK: - Recording a sale

extension IzzyAPI {
    /// One item of a checkout's ticket, as it's sent: a catalog service, one of the shop's products,
    /// or a custom item. Make one with `service(_:unitCents:quantity:)`, `product(_:unitCents:quantity:)`
    /// or `custom(name:unitCents:quantity:)`.
    public struct NewSaleItem: Encodable, Hashable, Sendable {
        public let kind: SaleItemKind
        /// A service's catalog id.
        public let serviceId: String?
        /// A product's id (a hidden product works too).
        public let productId: String?
        /// A custom item's name, like "Gift card".
        public let name: String?
        /// The price of one in cents, or `nil` for the server's price: the appointment's booked price
        /// for its own service, the barber's menu price for another service, the product's price. A
        /// custom item always has one; so must a service the barber doesn't offer (or offers at more
        /// than one price) and a product without a price.
        public var unitCents: Int?
        /// 1 to 99 (`quantityRange`).
        public var quantity: Int

        private init(kind: SaleItemKind, serviceId: String? = nil, productId: String? = nil, name: String? = nil, unitCents: Int?, quantity: Int) {
            self.kind = kind
            self.serviceId = serviceId
            self.productId = productId
            self.name = name
            self.unitCents = unitCents
            self.quantity = quantity
        }

        public static func service(_ serviceId: String, unitCents: Int? = nil, quantity: Int = 1) -> NewSaleItem {
            NewSaleItem(kind: .service, serviceId: serviceId, unitCents: unitCents, quantity: quantity)
        }

        public static func product(_ productId: String, unitCents: Int? = nil, quantity: Int = 1) -> NewSaleItem {
            NewSaleItem(kind: .product, productId: productId, unitCents: unitCents, quantity: quantity)
        }

        public static func custom(name: String, unitCents: Int, quantity: Int = 1) -> NewSaleItem {
            NewSaleItem(kind: .custom, name: name, unitCents: unitCents, quantity: quantity)
        }

        /// What the server takes for a quantity.
        public static let quantityRange: ClosedRange<Int> = 1...99
        /// What the server takes for a price, in cents: $0 to $10,000.
        public static let unitCentsRange: ClosedRange<Int> = 0...1_000_000
        /// The longest custom item name.
        public static let maxNameLength = 80

        /// `quantity` × `unitCents`, or `nil` when the price is left to the server.
        public var totalCents: Int? {
            unitCents.map { $0 * quantity }
        }

        /// Whether the server will take it as it is (it still checks the service or product exists).
        public var isValid: Bool {
            guard Self.quantityRange.contains(quantity), unitCents.map(Self.unitCentsRange.contains) ?? true else { return false }
            switch kind {
            case .service: return serviceId?.trimmed.nonEmpty != nil
            case .product: return productId?.trimmed.nonEmpty != nil
            case .custom:
                let text = name?.trimmed ?? ""
                // Counted like the server: in Unicode code points.
                return !text.isEmpty && text.unicodeScalars.count <= Self.maxNameLength && unitCents != nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind, serviceId, productId, name, unitCents, quantity
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            switch kind {
            case .service: try container.encode(serviceId ?? "", forKey: .serviceId)
            case .product: try container.encode(productId ?? "", forKey: .productId)
            case .custom: try container.encode(name?.trimmed ?? "", forKey: .name)
            }
            try container.encodeIfPresent(unitCents, forKey: .unitCents)
            try container.encode(quantity, forKey: .quantity)
        }

        /// The item as the server compares it on a retry: what it is, how many, and its price when given.
        var retryKey: String {
            let what: String
            switch kind {
            case .service: what = "service:" + (serviceId ?? "")
            case .product: what = "product:" + (productId ?? "")
            case .custom: what = "custom:" + (name?.trimmed ?? "")
            }
            return what + "x\(quantity)" + (unitCents.map { "@\($0)" } ?? "")
        }
    }

    /// A checkout's ticket: `{ barberId?, appointmentId?, customerName?, method, items }`.
    ///
    /// Paid in cash or another way (`method` `.cash` or `.other`), it's recorded with
    /// `recordSale(_:idempotencyKey:)`. Paid by card (`.card`), it goes with the Tap to Pay payment
    /// as `NewPayment.sale` (without the method), and the server records it when the payment goes
    /// through.
    public struct NewSale: Encodable, Hashable, Sendable {
        public var method: SaleMethod
        /// The barber who gets credit; `nil`: the appointment's barber.
        public var barberId: String?
        /// The appointment it checks out: it must be booked or completed and not checked out yet.
        public var appointmentId: String?
        /// The client's name; `nil` (or blank): the appointment's client, or none.
        public var customerName: String?
        /// 1 to 20 items (`itemCountRange`).
        public var items: [NewSaleItem]

        public init(method: SaleMethod, barberId: String? = nil, appointmentId: String? = nil, customerName: String? = nil, items: [NewSaleItem]) {
            self.method = method
            self.barberId = barberId
            self.appointmentId = appointmentId
            self.customerName = customerName
            self.items = items
        }

        /// How many items a sale can have.
        public static let itemCountRange: ClosedRange<Int> = 1...20
        /// The largest sale, in cents: $10,000.
        public static let maxTotalCents = 1_000_000
        /// The longest client name.
        public static let maxCustomerNameLength = 60

        /// The sum of the items, or `nil` while an item's price is left to the server. A card payment's
        /// amount must be exactly the ticket's total (400 `amount_mismatch` otherwise).
        public var totalCents: Int? {
            var total = 0
            for item in items {
                guard let cents = item.totalCents else { return nil }
                total += cents
            }
            return total
        }

        /// Whether the server will take it as it is (it still checks the barber, appointment, services
        /// and products exist). Card sales are recorded with their payment, never with `recordSale`.
        public var isValid: Bool {
            Self.itemCountRange.contains(items.count)
                && items.allSatisfy(\.isValid)
                && (totalCents.map { $0 <= Self.maxTotalCents } ?? true)
                && (customerName?.trimmed.unicodeScalars.count ?? 0) <= Self.maxCustomerNameLength
        }

        /// What the server compares when the same `Idempotency-Key` comes back: the method, the
        /// appointment, the barber and client when given, and each item. Keep the key while this stays
        /// the same (Save again after a lost answer); make a new one when it changes.
        public var retryKey: String {
            [
                method.rawValue,
                appointmentId?.trimmed.lowercased() ?? "",
                barberId?.trimmed ?? "",
                customerName?.trimmed ?? "",
                items.map(\.retryKey).joined(separator: ","),
            ].joined(separator: "|")
        }

        /// The ticket alone (no method), as `sale` with a card payment.
        var ticket: SaleTicket { SaleTicket(sale: self) }

        /// Every field but `method`, as `SaleTicket` sends it.
        enum CodingKeys: String, CodingKey {
            case method, barberId, appointmentId, customerName, items
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(method, forKey: .method)
            try encodeTicket(into: &container)
        }

        /// The ticket's fields: empty text is left out, and text is trimmed.
        func encodeTicket(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
            try container.encodeIfPresent(barberId?.trimmed.nonEmpty, forKey: .barberId)
            try container.encodeIfPresent(appointmentId?.trimmed.nonEmpty, forKey: .appointmentId)
            try container.encodeIfPresent(customerName?.trimmed.nonEmpty, forKey: .customerName)
            try container.encode(items, forKey: .items)
        }
    }

    /// `NewPayment.sale`: a ticket's fields without its method (a payment's ticket is a card sale).
    struct SaleTicket: Encodable, Hashable, Sendable {
        var sale: NewSale

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: NewSale.CodingKeys.self)
            try sale.encodeTicket(into: &container)
        }
    }

    /// `POST /api/owner/sales/:id/void` body `{ reason? }`.
    struct VoidSaleBody: Encodable, Hashable, Sendable {
        var reason: String?

        private enum CodingKeys: String, CodingKey {
            case reason
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(reason?.trimmed.nonEmpty, forKey: .reason)
        }
    }
}
