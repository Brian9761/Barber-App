import Foundation
import IzzyClipzKit

/// An in-memory stand-in for the shop's server, for UI tests, previews and
/// unit tests. It follows the server's rules closely enough that the app can't
/// tell the difference: owner key checks, availability from the shop's hours
/// minus bookings and time off, overlaps refused as `slot_taken`, payments
/// that are only "succeeded" once the (simulated) card was approved.
///
/// Its data is clearly sample data ("Sample" surnames, "Sample" products):
/// it's never shown outside tests and previews.
@MainActor
final class FakeServer {
    /// The owner key the fake accepts (at least 32 characters, like the real one).
    static let ownerKey = "izzy-clipz-demo-owner-key-0123456789"

    /// Ways to make the fake misbehave, from launch arguments or tests.
    struct Options: Equatable {
        /// Every call fails as if the phone were offline.
        var offline = false
        /// `GET /api/owner/me` answers 503 `owner_not_configured`.
        var ownerNotConfigured = false
        /// Stripe's status on the server.
        var stripeConfigured = true
        var stripeMode: IzzyAPI.StripeMode = .test
        var locationId: String? = "tml_sample_location"
        /// The next booking fails with `slot_taken` because someone booked
        /// that time on the phone a moment earlier (the fake adds that booking).
        var takeNextSlot = false
        /// The next booking goes through, but its answer is lost on the way
        /// back and the app sees it as offline. Book again with the same
        /// `Idempotency-Key` gets it.
        var loseNextBookingAnswer = false
        /// `completePayment` reports this status instead of Stripe's real one,
        /// e.g. "processing" or "requires_payment_method".
        var completeStatusOverride: String?
        /// Start with nothing booked, no time off and no products.
        var empty = false
        /// How long each call takes, so loading states are visible.
        var latency: Duration = .zero
    }

    var options: Options
    let catalog: Catalog
    let shopTime: ShopTime
    let now: () -> Date

    private(set) var appointments: [IzzyAPI.Appointment] = []
    private(set) var timeOff: [IzzyAPI.TimeOff] = []
    private(set) var products: [IzzyAPI.Product] = []
    private(set) var payments: [StoredPayment] = []
    /// Every call, in order ("ownerStatus", "createPayment", …), for tests.
    private(set) var calls: [String] = []
    /// Every `Idempotency-Key` a booking came with, in order, for tests.
    private(set) var bookingKeys: [IzzyAPI.IdempotencyKey] = []
    /// What each key booked: the appointment's ID and the request, to recognize Book again.
    private var keyed: [IzzyAPI.IdempotencyKey: (id: String, request: IzzyAPI.NewAppointment)] = [:]

    struct StoredPayment: Equatable {
        var payment: IzzyAPI.Payment
        var clientSecret: String
        var receiptEmail: String?
    }

    private var counter = 0

    init(options: Options = Options(), catalog: Catalog = .izzyClipz, shopTime: ShopTime = ShopTime(), now: @escaping () -> Date) {
        self.options = options
        self.catalog = catalog
        self.shopTime = shopTime
        self.now = now
        if !options.empty {
            seed()
        }
    }

    /// An `OwnerAPI` talking to this fake with `ownerKey`.
    func api(ownerKey: String?) -> FakeOwnerAPI {
        FakeOwnerAPI(server: self, ownerKey: ownerKey)
    }

    // MARK: Requests

    /// Checks the network and the owner key, like every owner endpoint.
    func begin(_ name: String, key: String?, ownerOnly: Bool = true) async throws {
        calls.append(name)
        if options.latency > .zero {
            try await Task.sleep(for: options.latency)
        }
        if options.offline { throw APIError.offline }
        guard ownerOnly else { return }
        if options.ownerNotConfigured { throw APIError.notConfigured(APIError.Feature.owner) }
        guard key?.trimmingCharacters(in: .whitespacesAndNewlines) == FakeServer.ownerKey else { throw APIError.unauthorized }
    }

    func ownerStatus() -> IzzyAPI.OwnerStatus {
        let configured = options.stripeConfigured
        return IzzyAPI.OwnerStatus(stripe: IzzyAPI.StripeStatus(
            configured: configured,
            mode: configured ? options.stripeMode : nil,
            locationId: configured ? options.locationId : nil
        ))
    }

    // MARK: Availability

    /// The offerings a booking target can use, in team order.
    func offerings(for target: IzzyAPI.BookingTarget) throws -> [Offering] {
        switch target {
        case .offering(let id):
            guard let offering = catalog.offering(withID: id) else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That service isn't on the menu.", status: 400)
            }
            return [offering]
        case .anyBarber(let serviceId):
            let ids = CatalogExport.document(catalog: catalog, shop: shopTime.shop).firstAvailable
                .first { $0.serviceId == serviceId }?.offeringIds ?? []
            let offerings = ids.compactMap { catalog.offering(withID: $0) }
            guard !offerings.isEmpty else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Pick a barber for this service.", status: 400)
            }
            return offerings
        }
    }

    func availability(_ query: IzzyAPI.AvailabilityQuery, leadTimeMinutes: Int) throws -> IzzyAPI.AvailabilityResponse {
        guard IzzyAPI.availabilityDaysRange.contains(query.days) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "days must be 1 to 31.", status: 400)
        }
        let offerings = try offerings(for: query.target)
        let calendar = BookingCalendar(clock: shopTime.shop.clock, leadTimeMinutes: leadTimeMinutes)
        let current = now()
        let days = (0..<query.days).map { offset -> IzzyAPI.DaySlots in
            let day = query.from.adding(days: offset)
            var byStart: [Date: [String]] = [:]
            for offering in offerings {
                for slot in calendar.slots(on: day.calendarDay, durationMinutes: offering.durationMinutes, now: current) {
                    let end = slot.start.addingTimeInterval(TimeInterval(offering.durationMinutes * 60))
                    if isFree(barberID: offering.barberID, from: slot.start, to: end) {
                        byStart[slot.start, default: []].append(offering.barberID)
                    }
                }
            }
            let slots = byStart.keys.sorted().map { IzzyAPI.Slot(start: $0, barberIds: byStart[$0] ?? []) }
            return IzzyAPI.DaySlots(date: day, slots: slots)
        }
        return IzzyAPI.AvailabilityResponse(timeZone: shopTime.shop.timeZoneIdentifier, days: days)
    }

    /// No booked or completed appointment and no time off for the barber (or
    /// the whole shop) overlaps `[start, end)`.
    func isFree(barberID: String, from start: Date, to end: Date, ignoring appointmentID: String? = nil) -> Bool {
        let busy = appointments.contains { appointment in
            appointment.id != appointmentID
                && appointment.barberId == barberID
                && (appointment.status == .booked || appointment.status == .completed)
                && appointment.start < end && start < appointment.end
        }
        let blocked = timeOff.contains { block in
            (block.barberId == nil || block.barberId == barberID) && block.start < end && start < block.end
        }
        return !busy && !blocked
    }

    // MARK: Appointments

    func appointments(from: LocalDate, to: LocalDate) -> [IzzyAPI.Appointment] {
        let start = shopTime.startOfDay(from)
        let end = shopTime.startOfDay(to.adding(days: 1))
        return appointments.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
    }

    /// Books like the server: with a key it already booked and the same booking (Book again
    /// after a lost answer), the appointment as it is now; with that key and another booking, a
    /// 400; otherwise a new appointment, kept under the key.
    func createAppointment(_ request: IzzyAPI.NewAppointment, idempotencyKey: IzzyAPI.IdempotencyKey? = nil) throws -> IzzyAPI.Appointment {
        if let idempotencyKey { bookingKeys.append(idempotencyKey) }
        let start = request.start
        let name = request.customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Enter your name.", status: 400)
        }
        // The phone is optional, but one that's given must be a US number (as on the server).
        var phone: String?
        if let typed = request.customer.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil {
            guard let number = PhoneNumber(parsing: typed) else {
                throw APIError.server(
                    code: IzzyAPI.ErrorCode.invalidRequest,
                    message: "Enter a US mobile number, like (442) 341-3053, or leave it empty.",
                    status: 400
                )
            }
            phone = number.e164
        }
        // Book again: answered before the time rules, as on the server.
        if let idempotencyKey, let earlier = keyed[idempotencyKey] {
            guard Self.isSameBooking(earlier.request, request),
                  let appointment = appointments.first(where: { $0.id == earlier.id })
            else {
                throw APIError.server(
                    code: IzzyAPI.ErrorCode.invalidRequest, message: "That booking key was already used for another booking.", status: 400
                )
            }
            return appointment
        }
        let candidates = try offerings(for: request.target)
        let day = shopTime.day(containing: start)
        guard let open = shopTime.openInterval(on: day) else { throw APIError.outsideHours }

        if options.takeNextSlot {
            options.takeNextSlot = false
            // Someone booked this time on the phone a moment ago.
            if let offering = candidates.first {
                appointments.append(makeAppointment(
                    offering: offering, start: start, customer: IzzyAPI.Customer(name: "Phone Sample", phone: "+14425550100"),
                    status: .booked
                ))
            }
            throw APIError.slotTaken
        }

        // "Any barber": the free barber with the fewest bookings that day.
        let free = candidates.filter { offering in
            let end = start.addingTimeInterval(TimeInterval(offering.durationMinutes * 60))
            return start >= open.start && end <= open.end && isFree(barberID: offering.barberID, from: start, to: end)
        }
        guard let offering = free.min(by: { bookings(of: $0.barberID, on: day) < bookings(of: $1.barberID, on: day) }) else {
            let fits = candidates.contains { start >= open.start && start.addingTimeInterval(TimeInterval($0.durationMinutes * 60)) <= open.end }
            throw fits ? APIError.slotTaken : APIError.outsideHours
        }
        let appointment = makeAppointment(
            offering: offering, start: start,
            customer: IzzyAPI.Customer(name: name, phone: phone, email: request.customer.email),
            note: request.note
        )
        appointments.append(appointment)
        if let idempotencyKey {
            keyed[idempotencyKey] = (appointment.id, request)
        }
        if options.loseNextBookingAnswer {
            // Booked, but the answer never reaches the phone.
            options.loseNextBookingAnswer = false
            throw APIError.offline
        }
        return appointment
    }

    /// The server's rule for Book again: the same target asked for the same way, the same start,
    /// and the same client name and phone number (or none). The email and note may differ.
    private static func isSameBooking(_ earlier: IzzyAPI.NewAppointment, _ retry: IzzyAPI.NewAppointment) -> Bool {
        func name(_ request: IzzyAPI.NewAppointment) -> String {
            request.customer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func phone(_ request: IzzyAPI.NewAppointment) -> String? {
            request.customer.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil.map { PhoneNumber(parsing: $0)?.e164 ?? $0 }
        }
        return earlier.target == retry.target && earlier.start == retry.start
            && name(earlier) == name(retry) && phone(earlier) == phone(retry)
    }

    private func bookings(of barberID: String, on day: LocalDate) -> Int {
        appointments(from: day, to: day).filter { $0.barberId == barberID && $0.status == .booked }.count
    }

    func setStatus(_ status: IzzyAPI.AppointmentStatus, of id: String) throws -> IzzyAPI.Appointment {
        guard let index = appointments.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that appointment.", status: 404)
        }
        var appointment = appointments[index]
        if (status == .booked || status == .completed),
           appointment.status == .cancelled || appointment.status == .noShow,
           !isFree(barberID: appointment.barberId, from: appointment.start, to: appointment.end, ignoring: id) {
            throw APIError.slotTaken
        }
        let previous = appointment.status
        appointment.status = status
        if status == .cancelled {
            // Cancelling here is the shop cancelling; an earlier cancellation keeps who did it.
            appointment.cancelledBy = previous == .cancelled ? appointment.cancelledBy : .shop
        } else {
            appointment.cancelledBy = nil
        }
        appointments[index] = appointment
        return appointment
    }

    // MARK: Time off

    func timeOff(from: LocalDate, to: LocalDate) -> [IzzyAPI.TimeOff] {
        let start = shopTime.startOfDay(from)
        let end = shopTime.startOfDay(to.adding(days: 1))
        return timeOff.filter { $0.start < end && start < $0.end }.sorted { $0.start < $1.start }
    }

    func createTimeOff(_ request: IzzyAPI.NewTimeOff) throws -> IzzyAPI.TimeOff {
        if let barberId = request.barberId, catalog.barber(withID: barberId) == nil {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That barber isn't on the team.", status: 400)
        }
        guard request.end > request.start else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "The end has to be after the start.", status: 400)
        }
        let block = IzzyAPI.TimeOff(
            id: nextUUID(), barberId: request.barberId, start: request.start, end: request.end,
            reason: request.reason?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        )
        timeOff.append(block)
        return block
    }

    func deleteTimeOff(id: String) throws {
        guard let index = timeOff.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that time off. It may already be removed.", status: 404)
        }
        timeOff.remove(at: index)
    }

    // MARK: Products

    func createProduct(_ request: IzzyAPI.NewProduct) throws -> IzzyAPI.Product {
        let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Give the product a name.", status: 400)
        }
        let product = IzzyAPI.Product(
            id: nextUUID(), name: name,
            description: request.description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
            priceCents: request.priceCents, imageUrl: nil, visible: request.visible ?? true
        )
        products.append(product)
        return product
    }

    func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) throws -> IzzyAPI.Product {
        guard let index = products.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that product.", status: 404)
        }
        var product = products[index]
        if let name = update.name?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !name.isEmpty else {
                throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "Give the product a name.", status: 400)
            }
            product.name = name
        }
        switch update.description {
        case .unchanged: break
        case .set(let text): product.description = text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
        case .clear: product.description = nil
        }
        switch update.priceCents {
        case .unchanged: break
        case .set(let cents): product.priceCents = cents
        case .clear: product.priceCents = nil
        }
        if let visible = update.visible { product.visible = visible }
        products[index] = product
        return product
    }

    func deleteProduct(id: String) throws {
        guard let index = products.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that product.", status: 404)
        }
        products.remove(at: index)
    }

    /// The uploaded photos, by product.
    private(set) var photos: [String: Data] = [:]

    func uploadPhoto(id: String, jpegData: Data) throws -> IzzyAPI.Product {
        guard jpegData.count <= IzzyAPI.maxPhotoBytes else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "That photo is too big to upload. Pick a smaller one, or take it again.", status: 413)
        }
        guard jpegData.starts(with: [0xFF, 0xD8, 0xFF]) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: "The photo must be a JPEG.", status: 415)
        }
        guard let index = products.firstIndex(where: { $0.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that product.", status: 404)
        }
        photos[id] = jpegData
        counter += 1
        products[index].imageUrl = URL(string: "https://example.invalid/products/\(id)-\(counter).jpg")
        return products[index]
    }

    // MARK: Payments

    func createPayment(_ request: IzzyAPI.NewPayment) throws -> IzzyAPI.PaymentIntentCreated {
        guard options.stripeConfigured else { throw APIError.notConfigured(APIError.Feature.stripe) }
        guard request.isAmountAllowed else {
            throw APIError.server(code: IzzyAPI.ErrorCode.invalidRequest, message: Money.allowedRangeText, status: 400)
        }
        if let appointmentId = request.appointmentId, !appointments.contains(where: { $0.id == appointmentId }) {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that appointment.", status: 404)
        }
        counter += 1
        let id = "pi_sample_\(counter)"
        let payment = IzzyAPI.Payment(
            id: id, amountCents: request.amountCents,
            description: request.description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
            appointmentId: request.appointmentId, status: "requires_payment_method", createdAt: now()
        )
        let secret = "\(id)_secret_sample"
        payments.append(StoredPayment(payment: payment, clientSecret: secret, receiptEmail: request.receiptEmail))
        return IzzyAPI.PaymentIntentCreated(paymentIntentId: id, clientSecret: secret)
    }

    /// What Stripe would learn when the simulated card is approved.
    func cardApproved(clientSecret: String) {
        guard let index = payments.firstIndex(where: { $0.clientSecret == clientSecret }) else { return }
        if payments[index].payment.status != "canceled" {
            payments[index].payment.status = "succeeded"
        }
    }

    func completePayment(id: String) throws -> IzzyAPI.Payment {
        guard let index = payments.firstIndex(where: { $0.payment.id == id }) else {
            throw APIError.server(code: IzzyAPI.ErrorCode.notFound, message: "We couldn't find that payment.", status: 404)
        }
        // What the server reports: Stripe's status, or the test's override
        // (which leaves the real status alone, like a slow Stripe would).
        var reported = payments[index].payment
        if let override = options.completeStatusOverride {
            reported.status = override
        }
        if reported.isSucceeded, let appointmentId = reported.appointmentId,
           let appointmentIndex = appointments.firstIndex(where: { $0.id == appointmentId }) {
            let total = payments.filter { $0.payment.appointmentId == appointmentId && $0.payment.isSucceeded }
                .reduce(0) { $0 + $1.payment.amountCents }
            appointments[appointmentIndex].payment = IzzyAPI.AppointmentPayment(
                status: .paid, amountCents: total,
                paidAt: appointments[appointmentIndex].payment.paidAt ?? now()
            )
        }
        return reported
    }

    func payments(on day: LocalDate) -> [IzzyAPI.Payment] {
        let start = shopTime.startOfDay(day)
        let end = shopTime.startOfDay(day.adding(days: 1))
        return payments.map(\.payment).filter { $0.createdAt >= start && $0.createdAt < end }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Sample data

    /// UUID-shaped, like the server's IDs, and the same on every run.
    private func nextUUID() -> String {
        counter += 1
        let digits = String(counter)
        return "00000000-0000-4000-8000-" + String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    }

    func makeAppointment(
        offering: Offering,
        start: Date,
        customer: IzzyAPI.Customer,
        status: IzzyAPI.AppointmentStatus = .booked,
        cancelledBy: IzzyAPI.CancelledBy? = nil,
        payment: IzzyAPI.AppointmentPayment = .unpaid,
        note: String? = nil
    ) -> IzzyAPI.Appointment {
        IzzyAPI.Appointment(
            id: nextUUID(),
            offeringId: offering.id,
            serviceId: offering.serviceID,
            serviceName: catalog.service(withID: offering.serviceID)?.name ?? offering.serviceID,
            barberId: offering.barberID,
            barberName: catalog.barber(withID: offering.barberID)?.name ?? offering.barberID,
            start: start,
            end: start.addingTimeInterval(TimeInterval(offering.durationMinutes * 60)),
            durationMinutes: offering.durationMinutes,
            priceLabel: offering.price.label,
            status: status,
            cancelledBy: cancelledBy,
            payment: payment,
            customer: customer,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
            createdAt: now().addingTimeInterval(-86_400)
        )
    }

    /// A believable day in the shop, built around today: a few appointments
    /// across barbers in every status, a lunch break, and two sample products.
    private func seed() {
        let today = shopTime.day(containing: now())
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            shopTime.date(on: today, hour: hour, minute: minute) ?? shopTime.noon(on: today)
        }
        func offering(_ serviceID: String, _ barberID: String) -> Offering? {
            catalog.offerings.first { $0.serviceID == serviceID && $0.barberID == barberID }
        }
        let samples: [(String, String, Int, Int, String, String?, IzzyAPI.AppointmentStatus, IzzyAPI.CancelledBy?, Bool, String?)] = [
            ("haircut", "israel-flores", 10, 0, "Marcus Sample", "+14425550101", .completed, nil, true, nil),
            ("haircut", "cristian-ceja", 10, 0, "Jay Sample", "+14425550102", .noShow, nil, false, nil),
            ("haircut", "carlos-rafael", 10, 30, "Diego Sample", "+14425550103", .completed, nil, false, nil),
            ("haircut-and-beard", "israel-flores", 11, 30, "Andre Sample", "+14425550104", .booked, nil, false, "Likes a low fade"),
            ("military-haircut", "julian-ramos", 12, 0, "Luis Sample", "+14425550105", .booked, nil, false, nil),
            ("haircut", "cristian-ceja", 13, 0, "Sam Sample", "+14425550106", .cancelled, .customer, false, nil),
            ("haircut", "carlos-rafael", 14, 0, "Chris Sample", nil, .booked, nil, false, nil),
            ("vip", "israel-flores", 15, 30, "Tony Sample", "+14425550107", .booked, nil, false, nil),
        ]
        for sample in samples {
            guard let offering = offering(sample.0, sample.1) else { continue }
            let payment = sample.8
                ? IzzyAPI.AppointmentPayment(status: .paid, amountCents: offering.price.cents, paidAt: at(10, 50))
                : .unpaid
            appointments.append(makeAppointment(
                offering: offering, start: at(sample.2, sample.3),
                customer: IzzyAPI.Customer(name: sample.4, phone: sample.5),
                status: sample.6, cancelledBy: sample.7, payment: payment, note: sample.9
            ))
        }
        timeOff.append(IzzyAPI.TimeOff(id: nextUUID(), barberId: "flowxbori", start: at(13), end: at(14), reason: "Lunch"))
        products = [
            IzzyAPI.Product(id: nextUUID(), name: "Sample pomade", description: "Medium hold, sample product for testing.", priceCents: 1800, imageUrl: nil, visible: true),
            IzzyAPI.Product(id: nextUUID(), name: "Sample beard oil", description: nil, priceCents: nil, imageUrl: nil, visible: false),
        ]
        if let paid = appointments.first(where: { $0.payment.status == .paid }) {
            counter += 1
            payments.append(StoredPayment(
                payment: IzzyAPI.Payment(
                    id: "pi_sample_\(counter)", amountCents: paid.payment.amountCents ?? 0,
                    description: "\(paid.serviceName) with \(paid.barberName)", appointmentId: paid.id,
                    status: "succeeded", createdAt: at(10, 50)
                ),
                clientSecret: "pi_sample_\(counter)_secret_sample", receiptEmail: nil
            ))
        }
    }
}

extension String {
    /// `nil` for an empty string.
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
