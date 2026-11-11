import Foundation
import IzzyClipzKit

/// The checkout's ticket on Take payment: who it's for (an appointment, or a walk-in with an
/// optional name), who sold it (the barber who gets credit), and what was sold (services at the
/// barber's prices, the shop's products, and amounts with a name), with the total.
///
/// It becomes a sale: recorded right away for cash or another way (`newSale(method:)` with
/// `OwnerAPI.recordSale`), or sent with the Tap to Pay payment for a card, which the server records
/// once the payment goes through. Every item carries its price, so the total the owner sees is the
/// total the server records (a card payment's amount must be exactly that).
struct CheckoutTicket: Equatable {
    /// One line on the ticket.
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable {
            /// A service on the menu (its catalog id).
            case service(id: String)
            /// One of the shop's products.
            case product(id: String)
            /// An amount with a name: "Other", "Tip", "Gift card".
            case custom
        }

        let id: Int
        let kind: Kind
        var name: String
        /// The price of one, in cents.
        var unitCents: Int
        var quantity: Int
        /// The menu says "From $80": the price is where it starts, so the owner checks it.
        var startsAtThisPrice = false

        var totalCents: Int { unitCents * quantity }

        var isProduct: Bool {
            if case .product = kind { return true }
            return false
        }

        /// "$40", or "2 × $18".
        var priceLabel: String {
            quantity == 1 ? Money.amount(unitCents) : "\(quantity) × \(Money.amount(unitCents))"
        }

        /// The item as it's sent, always with its price.
        var saleItem: IzzyAPI.NewSaleItem {
            switch kind {
            case .service(let id): return .service(id, unitCents: unitCents, quantity: quantity)
            case .product(let id): return .product(id, unitCents: unitCents, quantity: quantity)
            case .custom: return .custom(name: name, unitCents: unitCents, quantity: quantity)
            }
        }
    }

    /// The appointment a checkout started from (Schedule → appointment → Check out).
    struct AppointmentLink: Equatable {
        let id: String
        let clientName: String
        let serviceName: String
        let barberId: String
        let barberName: String
        /// "Today at 11:30 AM".
        let when: String
        /// What it was booked at: "$55", "From $80".
        let priceLabel: String
        /// What was already paid for it by card, so it isn't taken again.
        let alreadyPaidCents: Int?
    }

    /// The appointment it checks out, if it started from one.
    private(set) var appointment: AppointmentLink?
    /// A walk-in's name (optional), when it isn't for an appointment.
    var walkInName = ""
    /// The barber who gets credit for the sale.
    var barberId: String?
    private(set) var items: [Item] = []
    private var lastItemID = 0

    /// A walk-in, sold by `barberId` (the last barber chosen on this iPhone), with nothing on it yet.
    init(barberId: String? = nil) {
        self.barberId = barberId
    }

    /// Checking out an appointment: its client, sold by its barber, with its service at the price
    /// it was booked at (its menu price; a "From" price is where it starts, and can be changed).
    init(appointment: IzzyAPI.Appointment, catalog: Catalog, shopTime: ShopTime, now: Date) {
        let offering = catalog.offering(withID: appointment.offeringId)
        let day = shopTime.relativeDay(shopTime.day(containing: appointment.start), today: shopTime.day(containing: now))
        self.appointment = AppointmentLink(
            id: appointment.id,
            clientName: appointment.customer.name,
            serviceName: appointment.serviceName,
            barberId: appointment.barberId,
            barberName: appointment.barberName,
            when: "\(day) at \(shopTime.time(appointment.start))",
            priceLabel: offering?.price.label ?? appointment.priceLabel,
            alreadyPaidCents: appointment.payment.status == .paid ? appointment.payment.amountCents : nil
        )
        barberId = appointment.barberId
        let price = offering?.price
        add(Item(
            id: 0, kind: .service(id: appointment.serviceId), name: appointment.serviceName,
            unitCents: price?.cents ?? 0, quantity: 1, startsAtThisPrice: price?.kind == .startingAt
        ))
    }

    // MARK: What's on it

    var totalCents: Int { items.reduce(0) { $0 + $1.totalCents } }

    var isEmpty: Bool { items.isEmpty }

    var appointmentId: String? { appointment?.id }

    /// The client's name on the sale: the appointment's, or the walk-in's when one was typed.
    var customerName: String? {
        if let appointment { return appointment.clientName }
        let name = walkInName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    func item(withID id: Int) -> Item? {
        items.first { $0.id == id }
    }

    // MARK: Changing it

    /// "+ Service": a service at the barber's price for it (`price`, from the menu).
    mutating func addService(id serviceId: String, name: String, price: Price) {
        add(Item(id: 0, kind: .service(id: serviceId), name: name, unitCents: price.cents, quantity: 1, startsAtThisPrice: price.kind == .startingAt))
    }

    /// "+ Product": one more of a product already on the ticket, or a new line at `unitCents`
    /// (its price, or the one the owner typed for a product without one).
    mutating func addProduct(_ product: IzzyAPI.Product, unitCents: Int) {
        if let index = items.firstIndex(where: { $0.kind == .product(id: product.id) && $0.unitCents == unitCents }) {
            items[index].quantity = min(items[index].quantity + 1, IzzyAPI.NewSaleItem.quantityRange.upperBound)
            return
        }
        add(Item(id: 0, kind: .product(id: product.id), name: product.name, unitCents: unitCents, quantity: 1))
    }

    /// "+ Amount": an amount with the name typed, or "Other".
    mutating func addAmount(_ cents: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        add(Item(id: 0, kind: .custom, name: trimmed.isEmpty ? Self.otherName : String(trimmed.prefix(IzzyAPI.NewSaleItem.maxNameLength)), unitCents: cents, quantity: 1))
    }

    /// The name an amount gets when none is typed.
    static let otherName = "Other"

    mutating func remove(_ id: Int) {
        items.removeAll { $0.id == id }
    }

    /// The quantity (1 to 99), for products.
    mutating func setQuantity(_ quantity: Int, of id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].quantity = min(max(quantity, IzzyAPI.NewSaleItem.quantityRange.lowerBound), IzzyAPI.NewSaleItem.quantityRange.upperBound)
    }

    /// A new price for one (a "From" price that came out higher, say).
    mutating func setPrice(_ cents: Int, of id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].unitCents = min(max(cents, 0), IzzyAPI.NewSaleItem.unitCentsRange.upperBound)
        items[index].startsAtThisPrice = false
    }

    /// "Not for this appointment": a walk-in for the same client, with what's on the ticket.
    mutating func forgetAppointment() {
        guard let appointment else { return }
        walkInName = appointment.clientName
        self.appointment = nil
    }

    private mutating func add(_ item: Item) {
        lastItemID += 1
        var item = item
        item = Item(id: lastItemID, kind: item.kind, name: item.name, unitCents: item.unitCents, quantity: item.quantity, startsAtThisPrice: item.startsAtThisPrice)
        items.append(item)
    }

    // MARK: Recording it

    /// What has to change before it can be paid `method`, in plain words; `nil` when it's ready.
    func problem(for method: IzzyAPI.SaleMethod) -> String? {
        if items.isEmpty { return Self.emptyMessage }
        if barberId == nil { return Self.noBarberMessage }
        if items.count > IzzyAPI.NewSale.itemCountRange.upperBound { return "A sale can have at most 20 items. Split it into two sales." }
        if totalCents > IzzyAPI.NewSale.maxTotalCents { return "A sale can be at most $10,000. Split it into two sales." }
        if (customerName?.unicodeScalars.count ?? 0) > IzzyAPI.NewSale.maxCustomerNameLength {
            return "Keep the client's name to 60 characters or fewer."
        }
        if method == .card, !IzzyAPI.paymentAmountRange.contains(totalCents) {
            return Money.cardRangeText
        }
        return nil
    }

    static let emptyMessage = "Add a service, a product or an amount first."
    static let noBarberMessage = "Pick who gets credit for this sale, under Sold by."

    /// The sale as it's sent: with the appointment, the barber, the client's name and every item
    /// with its price.
    func newSale(method: IzzyAPI.SaleMethod) -> IzzyAPI.NewSale {
        IzzyAPI.NewSale(
            method: method,
            barberId: barberId,
            appointmentId: appointment?.id,
            customerName: customerName,
            items: items.map(\.saleItem)
        )
    }

    /// The card payment's description at Stripe: what was sold and who sold it, "Haircut & Beard with
    /// Izzy", never the client's name. A note the owner types goes instead, as typed.
    func paymentDescription(barberName: String?) -> String {
        let names = items.map(\.name)
        var what: String
        switch names.count {
        case 0: what = "Sale"
        case 1, 2, 3: what = names.joined(separator: ", ")
        default: what = names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
        }
        if let barberName { what += " with \(barberName)" }
        return String(what.prefix(200))
    }
}

/// What the success screen shows for a sale: "Sold $60 · Cash · Izzy" and each item.
struct SaleReceipt: Equatable {
    struct Line: Equatable {
        let name: String
        /// "$40", "2 × $18".
        let price: String
        let total: String
    }

    let method: IzzyAPI.SaleMethod
    let totalCents: Int
    /// "Sold $60 · Cash · Izzy".
    let summary: String
    let lines: [Line]
    let clientName: String?

    /// A sale as the server recorded it.
    init(sale: IzzyAPI.Sale) {
        method = sale.method
        totalCents = sale.totalCents
        summary = Self.summary(totalCents: sale.totalCents, method: sale.method, barberName: sale.barberName)
        lines = sale.items.map { item in
            Line(
                name: item.name,
                price: item.quantity == 1 ? Money.amount(item.unitCents) : "\(item.quantity) × \(Money.amount(item.unitCents))",
                total: Money.amount(item.totalCents)
            )
        }
        clientName = sale.customerName
    }

    /// A card sale, from the ticket that went with the payment (the server records it as it was sent).
    init(ticket: CheckoutTicket, method: IzzyAPI.SaleMethod, barberName: String) {
        self.method = method
        totalCents = ticket.totalCents
        summary = Self.summary(totalCents: ticket.totalCents, method: method, barberName: barberName)
        lines = ticket.items.map { Line(name: $0.name, price: $0.priceLabel, total: Money.amount($0.totalCents)) }
        clientName = ticket.customerName
    }

    /// "Sold $60 · Cash · Izzy", as the Kit says it for a sale.
    static func summary(totalCents: Int, method: IzzyAPI.SaleMethod, barberName: String) -> String {
        "Sold \(Price.currencyString(cents: totalCents)) · \(method.title) · \(barberName)"
    }
}

extension Money {
    /// The card payments the server takes, for the ticket's message.
    static var cardRangeText: String {
        "Card payments can be from \(amount(IzzyAPI.paymentAmountRange.lowerBound)) to \(amount(IzzyAPI.paymentAmountRange.upperBound)). Take cash or another way for other amounts."
    }
}
