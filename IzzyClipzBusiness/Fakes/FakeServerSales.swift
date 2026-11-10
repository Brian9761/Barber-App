import Foundation
import IzzyClipzKit

// The sample server's checkout, answering like the server (`server/src/sales.ts`,
// `server/src/payments.ts`): cash and other sales with an Idempotency-Key, card sales recorded
// once their payment goes through, today's sales, voiding, and the receipt emailed after a card
// payment (never kept).

extension FakeServer {
    /// A ticket as the server checks and fills it in: who gets credit, the names and prices, the total.
    struct SaleDraft: Equatable {
        var barberId: String
        var appointmentId: String?
        var customerName: String?
        var items: [IzzyAPI.SaleItem]

        var totalCents: Int { items.reduce(0) { $0 + $1.totalCents } }
    }

    /// The server's words when an app sends a receipt email with the payment.
    static let receiptAfterPaymentMessage = "Take the card payment without an email. Once it goes through, you can email the client a receipt."
    /// The server's words when a card sale is sent as a cash sale.
    static let cardSaleMessage = "Take card payments with Tap to Pay in the app. The sale is saved when the payment goes through."

    /// Whether card payments can be taken now: Stripe is on, and the shop's account is connected.
    var takesCardPayments: Bool {
        options.stripeConfigured && options.stripeAccount == .active
    }

    // MARK: Checking a ticket

    private func badRequest(_ message: String) -> APIError {
        APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: message, status: 400)
    }

    /// Checks a ticket and fills it in, the same way for cash, other and card sales (the server's
    /// `draftTicket`): the appointment can be checked out, the barber is on the team, each item is
    /// known and priced, and the total is at most $10,000.
    func draftSale(barberId: String?, appointmentId: String?, customerName: String?, items: [IzzyAPI.NewSaleItem]) throws -> SaleDraft {
        guard !items.isEmpty else { throw badRequest("Add at least one item.") }
        guard items.count <= IzzyAPI.NewSale.itemCountRange.upperBound else { throw badRequest("A sale can have at most 20 items.") }
        var appointment: IzzyAPI.Appointment?
        if let id = appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil {
            guard let found = appointments.first(where: { $0.id == id }) else {
                throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that appointment.", status: 404)
            }
            if let problem = Self.checkoutProblem(found) { throw problem }
            appointment = found
        }
        let name = customerName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        if let name, name.count > IzzyAPI.NewSale.maxCustomerNameLength {
            throw badRequest("Keep the name to 60 characters or fewer.")
        }
        guard let barberId = barberId?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil ?? appointment?.barberId else {
            throw badRequest("Pick the barber who gets credit for this sale.")
        }
        guard let barber = catalog.barber(withID: barberId) else {
            throw badRequest("That barber isn't on the team. Pick who did the service.")
        }
        let filled = try items.map { item -> IzzyAPI.SaleItem in
            guard IzzyAPI.NewSaleItem.quantityRange.contains(item.quantity) else {
                throw badRequest("The quantity must be a whole number from 1 to 99.")
            }
            if let cents = item.unitCents, !IzzyAPI.NewSaleItem.unitCentsRange.contains(cents) {
                throw badRequest("Prices must be whole cents, from $0 to $10,000.")
            }
            switch item.kind {
            case .service:
                let serviceId = item.serviceId ?? ""
                let own = appointment.map { $0.serviceId == serviceId } ?? false
                guard let name = catalog.service(withID: serviceId)?.name ?? (own ? appointment?.serviceName : nil) else {
                    throw badRequest("That service isn't on the menu. Pick another, or add it as a custom item.")
                }
                let price = try item.unitCents ?? (own ? appointmentPriceCents(appointment) : menuPrice(barber: barber, serviceId: serviceId, serviceName: name))
                return IzzyAPI.SaleItem(kind: .service, serviceId: serviceId, name: name, quantity: item.quantity, unitCents: price)
            case .product:
                guard let product = products.first(where: { $0.id == item.productId }) else {
                    throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that product. It may have been deleted.", status: 404)
                }
                guard let price = item.unitCents ?? product.priceCents else {
                    throw badRequest("\(product.name) has no price. Enter the price.")
                }
                return IzzyAPI.SaleItem(kind: .product, productId: product.id, name: product.name, quantity: item.quantity, unitCents: price)
            case .custom:
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { throw badRequest("Give the item a name, like Gift card.") }
                guard name.count <= IzzyAPI.NewSaleItem.maxNameLength else { throw badRequest("Keep the item name to 80 characters or fewer.") }
                guard let price = item.unitCents else { throw badRequest("Enter the price of each custom item.") }
                return IzzyAPI.SaleItem(kind: .custom, name: name, quantity: item.quantity, unitCents: price)
            }
        }
        let draft = SaleDraft(barberId: barber.id, appointmentId: appointment?.id, customerName: name ?? appointment?.customer.name, items: filled)
        guard draft.totalCents <= IzzyAPI.NewSale.maxTotalCents else {
            throw badRequest("A sale can be at most $10,000. Split it into two sales.")
        }
        return draft
    }

    /// Why an appointment can't be checked out, as the server says it (409), or `nil`.
    static func checkoutProblem(_ appointment: IzzyAPI.Appointment) -> APIError? {
        switch appointment.status {
        case .cancelled:
            return APIError.server(
                code: IzzyAPI.ErrorCode.notCheckoutable,
                message: "This appointment was cancelled, so it can't be checked out. Reopen it first, or check out without the appointment.",
                status: 409
            )
        case .noShow:
            return APIError.server(
                code: IzzyAPI.ErrorCode.notCheckoutable,
                message: "This appointment was marked a no-show, so it can't be checked out. Reopen it first, or check out without the appointment.",
                status: 409
            )
        case .booked, .completed:
            guard appointment.sale == nil else {
                return APIError.server(code: IzzyAPI.ErrorCode.alreadyCheckedOut, message: "This appointment was already checked out.", status: 409)
            }
            return nil
        }
    }

    /// The price the appointment was booked at: its offering's price on the menu.
    private func appointmentPriceCents(_ appointment: IzzyAPI.Appointment?) -> Int {
        guard let appointment else { return 0 }
        return catalog.offering(withID: appointment.offeringId)?.price.cents ?? 0
    }

    /// The barber's one price for a service on the menu, or the server's 400 asking for the price.
    private func menuPrice(barber: Barber, serviceId: String, serviceName: String) throws -> Int {
        let prices = Set(catalog.offerings.filter { $0.barberID == barber.id && $0.serviceID == serviceId }.map(\.price.cents))
        if prices.count == 1, let price = prices.first { return price }
        if prices.isEmpty { throw badRequest("\(barber.name) doesn't offer \(serviceName). Enter the price.") }
        throw badRequest("\(barber.name) has more than one price for \(serviceName). Enter the price.")
    }

    // MARK: Cash and other sales

    /// `POST /api/owner/sales`: with a key it already recorded and the same sale (Record again after
    /// a lost answer), that sale as it is now; with that key and another sale, a 400; otherwise a
    /// new sale, which checks out its appointment.
    func recordSale(_ request: IzzyAPI.NewSale, idempotencyKey: IzzyAPI.IdempotencyKey?) throws -> IzzyAPI.Sale {
        guard request.method != .card else { throw badRequest(Self.cardSaleMessage) }
        if let idempotencyKey, let earlier = saleKeys[idempotencyKey] {
            guard earlier.request.retryKey == request.retryKey, let sale = sales.first(where: { $0.id == earlier.id }) else {
                throw badRequest("That sale key was already used for another sale.")
            }
            return sale
        }
        let draft = try draftSale(barberId: request.barberId, appointmentId: request.appointmentId, customerName: request.customerName, items: request.items)
        let sale = insertSale(draft, method: request.method, paymentIntentId: nil, soldAt: now())
        if let idempotencyKey { saleKeys[idempotencyKey] = (sale.id, request) }
        if options.loseNextSaleAnswer {
            // Recorded, but the answer never reaches the phone.
            options.loseNextSaleAnswer = false
            throw APIError.offline
        }
        return sale
    }

    /// Records a sale and checks out its appointment: completed, with the sale, and paid with the
    /// sale's total unless card payments taken for it already paid it (those numbers stay).
    @discardableResult
    func insertSale(_ draft: SaleDraft, method: IzzyAPI.SaleMethod, paymentIntentId: String?, soldAt: Date) -> IzzyAPI.Sale {
        shopCounter += 1
        let digits = String(shopCounter)
        let sale = IzzyAPI.Sale(
            id: "00000000-0000-4000-9000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits,
            barberId: draft.barberId,
            barberName: catalog.barber(withID: draft.barberId)?.name ?? draft.barberId,
            appointmentId: draft.appointmentId,
            customerName: draft.customerName,
            method: method,
            paymentIntentId: paymentIntentId,
            items: draft.items,
            soldAt: soldAt
        )
        sales.append(sale)
        if let id = draft.appointmentId, let index = appointments.firstIndex(where: { $0.id == id }) {
            var appointment = appointments[index]
            appointment.status = .completed
            appointment.cancelledBy = nil
            appointment.sale = IzzyAPI.AppointmentSale(sale: sale)
            if !paidByCard(id) {
                appointment.payment = IzzyAPI.AppointmentPayment(status: .paid, amountCents: sale.totalCents, paidAt: soldAt)
            }
            everCompleted.insert(id)
            Self.refreshFeeReason(&appointment)
            appointments[index] = appointment
        }
        return sale
    }

    /// Whether card payments taken in the shop for this appointment went through.
    private func paidByCard(_ appointmentId: String) -> Bool {
        payments.contains { $0.payment.appointmentId == appointmentId && $0.payment.isSucceeded && $0.payment.kind == .inPerson }
    }

    /// `GET /api/owner/sales?date=`: newest first, voided ones too; the totals leave voided ones out.
    func salesDay(_ day: LocalDate) -> IzzyAPI.SalesDay {
        let start = shopTime.startOfDay(day)
        let end = shopTime.startOfDay(day.adding(days: 1))
        let onDay = sales.filter { $0.soldAt >= start && $0.soldAt < end }
            .sorted { $0.soldAt != $1.soldAt ? $0.soldAt > $1.soldAt : $0.id > $1.id }
        return IzzyAPI.SalesDay(date: day, sales: onDay)
    }

    /// `POST /api/owner/sales/:id/void`: the sale stops counting (again: the same answer). Its
    /// appointment stays completed and can be checked out again; it's unpaid again unless card
    /// payments paid it. Voiding a card sale doesn't refund the card.
    func voidSale(id: String, reason: String?) throws -> IzzyAPI.VoidedSale {
        guard let index = sales.firstIndex(where: { $0.id == id.lowercased() }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that sale.", status: 404)
        }
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        if let trimmed, trimmed.count > 200 { throw badRequest("Keep the reason to 200 characters or fewer.") }
        let sale = sales[index]
        guard !sale.isVoided else { return IzzyAPI.VoidedSale(sale: sale) }
        let voided = sale.voided(at: now(), reason: trimmed)
        sales[index] = voided
        if let appointmentId = sale.appointmentId, let at = appointments.firstIndex(where: { $0.id == appointmentId }),
           appointments[at].sale?.id == sale.id {
            appointments[at].sale = nil
            if !paidByCard(appointmentId) {
                appointments[at].payment = .unpaid
            }
        }
        return IzzyAPI.VoidedSale(sale: voided)
    }

    // MARK: Card sales

    /// A card checkout's ticket (`NewPayment.sale`), checked like a cash sale's. The payment's
    /// appointment, if it names one, must be the ticket's, and its amount must be the total.
    func cardSaleDraft(_ ticket: IzzyAPI.NewSale, for payment: IzzyAPI.NewPayment) throws -> SaleDraft {
        let topLevel = payment.appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmptyOrNil
        let appointmentId = ticket.appointmentId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nonEmptyOrNil ?? topLevel
        if let topLevel, appointmentId != topLevel {
            throw badRequest("The appointment doesn't match the sale's appointment.")
        }
        let draft = try draftSale(barberId: ticket.barberId, appointmentId: appointmentId, customerName: ticket.customerName, items: ticket.items)
        guard draft.totalCents == payment.amountCents else {
            throw APIError.server(code: IzzyAPI.ErrorCode.amountMismatch, message: "The amount doesn't match the items.", status: 400)
        }
        return draft
    }

    /// Records the card sale of a payment that went through, once. If its appointment can't take it
    /// any more (checked out another way meanwhile, cancelled or a no-show), the sale is recorded
    /// without it, so the money still counts, and the payment lets go of the appointment too.
    func recordCardSale(paymentIndex index: Int) {
        let stored = payments[index].payment
        guard stored.isSucceeded, stored.kind == .inPerson, stored.saleId == nil, var draft = saleDrafts[stored.id] else { return }
        if let id = draft.appointmentId {
            let appointment = appointments.first { $0.id == id }
            if appointment.map({ Self.checkoutProblem($0) != nil }) ?? true {
                draft.appointmentId = nil
                payments[index].payment.appointmentId = nil
            }
        }
        let sale = insertSale(draft, method: .card, paymentIntentId: stored.id, soldAt: now())
        payments[index].payment.saleId = sale.id
    }

    // MARK: Receipts

    /// `POST /api/owner/payments/:id/receipt`: Stripe emails the receipt of a card payment that went
    /// through. The address goes to Stripe only: it isn't kept, here or on the server.
    func sendReceipt(paymentId: String, email: String) throws -> IzzyAPI.Payment {
        guard options.stripeConfigured else { throw APIError.notConfigured(APIError.Feature.stripe) }
        guard let payment = payments.first(where: { $0.payment.id == paymentId })?.payment else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that payment.", status: 404)
        }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw badRequest("Enter the client's email address.") }
        guard address.count <= 254, Self.isEmail(address) else { throw badRequest("Enter a valid email address.") }
        guard payment.kind == .inPerson else { throw badRequest("Receipts are sent only for card payments taken at the shop.") }
        guard payment.isSucceeded else { throw badRequest("This payment hasn't gone through, so there's no receipt to send yet.") }
        receiptsSent += 1
        return payment
    }

    /// Roughly the server's check: something@something.something, no spaces.
    private static func isEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !text.contains(where: \.isWhitespace) else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    // MARK: Sample sales

    /// Today's sample sale: Diego, who came at 10:30, checked out in cash with a haircut and the
    /// sample pomade. Checkouts and Today's sales have something to show.
    func seedSales() {
        guard let diego = appointments.first(where: { $0.customer.name == "Diego Sample" }),
              let pomade = products.first(where: { $0.name == "Sample pomade" }),
              let draft = try? draftSale(
                  barberId: diego.barberId, appointmentId: diego.id, customerName: nil,
                  items: [.service(diego.serviceId), .product(pomade.id)]
              )
        else { return }
        let paidAt = shopTime.date(on: shopTime.day(containing: diego.start), hour: 11, minute: 0) ?? diego.end
        insertSale(draft, method: .cash, paymentIntentId: nil, soldAt: min(paidAt, now()))
    }
}
