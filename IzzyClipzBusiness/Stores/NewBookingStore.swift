import Foundation
import IzzyClipzKit
import Observation

/// New booking: walk-ins and phone bookings. The owner picks a service, a
/// barber (or anyone free), a time from the owner's availability (no lead
/// time, so a walk-in can take the next slot that hasn't started) or "Now"
/// for a walk-in who's in the chair, and the client's name with an optional
/// phone number.
@MainActor
@Observable
final class NewBookingStore {
    /// Who does it: a specific barber's offering, or anyone free.
    enum Choice: Hashable {
        case anyBarber
        case offering(String)
    }

    enum SlotsState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var serviceID: String?
    private(set) var choice: Choice?
    private(set) var day: LocalDate
    private(set) var slots: [IzzyAPI.Slot] = []
    private(set) var slotsState: SlotsState = .idle
    /// Bumped whenever the times are cleared, so the screen loads them again
    /// even when the service, barber and day stay the same (after a booking).
    private(set) var slotsVersion = 0
    var selectedSlot: IzzyAPI.Slot?
    var clientName = ""
    var clientPhone = ""
    var note = ""

    private(set) var isFindingNextSlot = false
    private(set) var isBooking = false
    /// A problem to show above the Book button.
    var formError: String?
    /// The appointment just booked, for the confirmation.
    private(set) var booked: IzzyAPI.Appointment?

    let shopTime: ShopTime
    let catalog: Catalog
    @ObservationIgnored private let api: any OwnerAPI
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var generation = 0
    /// The booking last sent (as sent) and its `Idempotency-Key`. Book again with the same
    /// booking, after an offline error or an answer that never arrived, sends the same key, so
    /// the server answers with the appointment that went through instead of booking a second
    /// barber or saying the shop's own time was taken. Anything that changes what's sent gets a
    /// new key, and so does the next booking once this one is made.
    @ObservationIgnored private var attempt: (body: Data, key: IzzyAPI.IdempotencyKey)?
    @ObservationIgnored var onBooked: ((IzzyAPI.Appointment) -> Void)?

    /// How far "Next open slot" looks ahead.
    static let nextSlotSearchDays = 14

    init(api: any OwnerAPI, shopTime: ShopTime, catalog: Catalog, clock: @escaping () -> Date) {
        self.api = api
        self.shopTime = shopTime
        self.catalog = catalog
        self.clock = clock
        self.day = shopTime.day(containing: clock())
    }

    var today: LocalDate { shopTime.day(containing: clock()) }

    // MARK: Choices

    /// Picks a service; "Any barber" is chosen when the service offers it.
    func selectService(_ id: String?) {
        guard id != serviceID else { return }
        serviceID = id
        if let id, catalog.firstAvailableOption(forService: id) != nil {
            choice = .anyBarber
        } else {
            choice = offerings.first.map { .offering($0.id) }
        }
        clearSlots()
    }

    func selectChoice(_ choice: Choice?) {
        guard choice != self.choice else { return }
        self.choice = choice
        clearSlots()
    }

    var services: [Service] { catalog.services }

    var service: Service? { serviceID.flatMap { catalog.service(withID: $0) } }

    /// Every barber's version of the chosen service.
    var offerings: [Offering] {
        guard let serviceID else { return [] }
        return catalog.offerings(forService: serviceID)
    }

    var offersAnyBarber: Bool {
        guard let serviceID else { return false }
        return catalog.firstAvailableOption(forService: serviceID) != nil
    }

    var target: IzzyAPI.BookingTarget? {
        switch choice {
        case .anyBarber?: return serviceID.map { .anyBarber(serviceId: $0) }
        case .offering(let id)?: return .offering(id: id)
        case nil: return nil
        }
    }

    /// "Izzy · 1 hr · $40".
    func label(for offering: Offering) -> String {
        let name = catalog.barber(withID: offering.barberID)?.name ?? offering.barberID
        return "\(name) · \(offering.durationLabel) · \(offering.price.label)"
    }

    func barberNames(for slot: IzzyAPI.Slot) -> String {
        slot.barberIds.compactMap { catalog.barber(withID: $0)?.name }.joined(separator: ", ")
    }

    /// The menu items the booking can go to: the barber's, or with "Any barber" each
    /// barber's version that the server picks from (catalog.json's `firstAvailable`).
    private var targetOfferings: [Offering] {
        switch choice {
        case .offering(let id)?:
            return catalog.offering(withID: id).map { [$0] } ?? []
        case .anyBarber?:
            guard let serviceID, let option = catalog.firstAvailableOption(forService: serviceID) else { return [] }
            return offerings.filter { option.barberIDs.contains($0.barberID) && $0.squireServiceID == option.squireServiceID }
        case nil:
            return []
        }
    }

    // MARK: Days and times

    var dayAsDate: Date {
        get { shopTime.noon(on: day) }
        set { select(day: shopTime.day(containing: newValue)) }
    }

    func select(day: LocalDate) {
        guard day != self.day else { return }
        self.day = day
        clearSlots()
    }

    /// The start "Now" books: this minute on the shop's clock. It's offered when the day on
    /// screen is today, the shop is open, and the service (with at least one of the barbers,
    /// for Any barber) ends by closing. The server takes any whole minute inside opening hours
    /// from the shop, so a walk-in who's in the chair isn't recorded at the next half hour.
    var nowStart: Date? {
        guard day == today, let open = shopTime.openInterval(on: day) else { return nil }
        let start = Date(timeIntervalSince1970: (clock().timeIntervalSince1970 / 60).rounded(.down) * 60)
        guard start >= open.start else { return nil }
        let fits = targetOfferings.contains { start.addingTimeInterval(TimeInterval($0.durationMinutes * 60)) <= open.end }
        return fits ? start : nil
    }

    /// Picks "Now". The minute is kept from here on, so Book again after a lost answer sends
    /// the same booking.
    func selectNow() {
        guard let start = nowStart else { return }
        selectedSlot = IzzyAPI.Slot(start: start, barberIds: [])
    }

    /// Whether `slot` is "Now" rather than one of the listed times (those always name the
    /// barbers who are free then).
    static func isNow(_ slot: IzzyAPI.Slot) -> Bool { slot.barberIds.isEmpty }

    var isNowSelected: Bool { selectedSlot.map(Self.isNow) ?? false }

    private func clearSlots() {
        generation += 1
        slotsVersion += 1
        slots = []
        selectedSlot = nil
        slotsState = .idle
    }

    /// Open start times on the chosen day (`GET /api/owner/availability`).
    /// `keepingTheTimes` refreshes the times already on screen without
    /// swapping them for a spinner, so the form doesn't jump while the owner
    /// reads why their booking didn't go through.
    func loadSlots(keepingTheTimes: Bool = false) async {
        guard let target else {
            clearSlots()
            return
        }
        generation += 1
        let requested = generation
        let day = self.day
        if !(keepingTheTimes && slotsState == .loaded) {
            slotsState = .loading
        }
        do {
            let response = try await api.ownerAvailability(IzzyAPI.AvailabilityQuery(target: target, from: day, days: 1))
            guard requested == generation else { return }
            let now = clock()
            // The owner can book a slot that hasn't started yet; the server
            // decides, but hide ones already past on this phone's clock.
            slots = response.slots(on: day).filter { $0.start >= now.addingTimeInterval(-60) }
            // "Now" isn't one of the listed times; it stays picked.
            if let selected = selectedSlot, !Self.isNow(selected), !slots.contains(where: { $0.start == selected.start }) {
                selectedSlot = nil
            }
            slotsState = .loaded
        } catch is CancellationError {
            if requested == generation { slotsState = .idle }
        } catch {
            guard requested == generation else { return }
            slotsState = .failed(ErrorText.message(for: error))
        }
    }

    /// The walk-in shortcut: the earliest open slot from now, today or on the
    /// next days.
    func findNextOpenSlot() async {
        guard let target else {
            formError = "Pick a service first."
            return
        }
        guard !isFindingNextSlot else { return }
        isFindingNextSlot = true
        defer { isFindingNextSlot = false }
        formError = nil
        let today = self.today
        do {
            let response = try await api.ownerAvailability(
                IzzyAPI.AvailabilityQuery(target: target, from: today, days: Self.nextSlotSearchDays)
            )
            let now = clock()
            let first = response.days.sorted { $0.date < $1.date }
                .lazy
                .compactMap { day in day.slots.sorted { $0.start < $1.start }.first { $0.start >= now.addingTimeInterval(-60) }.map { (day.date, $0) } }
                .first
            guard let (date, slot) = first else {
                formError = "No open times in the next \(Self.nextSlotSearchDays) days for this choice. Try another barber."
                return
            }
            if date != day {
                day = date
            }
            generation += 1
            slots = response.slots(on: date).filter { $0.start >= now.addingTimeInterval(-60) }
            slotsState = .loaded
            selectedSlot = slot
        } catch is CancellationError {
            return
        } catch {
            formError = ErrorText.message(for: error)
        }
    }

    // MARK: Booking

    var phoneIsValid: Bool {
        let typed = clientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty || PhoneNumber(parsing: typed) != nil
    }

    /// What's still missing, in the order the form asks for it.
    var missing: String? {
        if serviceID == nil { return "Pick a service." }
        if choice == nil { return "Pick a barber." }
        if selectedSlot == nil { return "Pick a time." }
        let name = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter the client's name." }
        if name.count > 60 { return "Keep the name to 60 characters or fewer." }
        if !phoneIsValid { return "Check the phone number: it should be a US number like (442) 555-0123, or leave it empty." }
        if note.count > 300 { return "Keep the note to 300 characters or fewer." }
        return nil
    }

    /// The key to send `request` with: the last one if this is the same booking again.
    func idempotencyKey(for request: IzzyAPI.NewAppointment) -> IzzyAPI.IdempotencyKey {
        // What's sent decides (names are trimmed and numbers put in E.164 on the way).
        let body = (try? IzzyAPI.makeEncoder().encode(request)) ?? Data(UUID().uuidString.utf8)
        if let attempt, attempt.body == body { return attempt.key }
        let key = IzzyAPI.IdempotencyKey.generate()
        attempt = (body, key)
        return key
    }

    /// `POST /api/owner/appointments`, with the same key as the last try when
    /// it's the same booking (see `idempotencyKey(for:)`). On "slot taken" the
    /// times are loaded again so the owner can pick another one.
    func book() async {
        guard !isBooking else { return }
        if let missing {
            formError = missing
            return
        }
        guard let target, let slot = selectedSlot else { return }
        isBooking = true
        defer { isBooking = false }
        formError = nil
        let phone = clientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = IzzyAPI.NewAppointment(
            target: target,
            start: slot.start,
            customer: IzzyAPI.NewCustomer(name: clientName, phone: phone.isEmpty ? nil : phone),
            note: note
        )
        let key = idempotencyKey(for: request)
        do {
            let appointment = try await api.createAppointment(request, idempotencyKey: key)
            attempt = nil
            guard appointment.status == .booked else {
                // An earlier try went through, but it has been cancelled (or closed) since.
                onBooked?(appointment)
                formError = "Your first try went through, but that appointment isn't booked any more. Book again to add it back."
                return
            }
            booked = appointment
            onBooked?(appointment)
        } catch APIError.slotTaken {
            formError = Self.isNow(slot) ? notFreeNowMessage : "Someone just took that time. Pick another one."
            selectedSlot = nil
            await loadSlots(keepingTheTimes: true)
        } catch APIError.outsideHours {
            formError = "That time is outside the shop's hours. Pick another one."
            selectedSlot = nil
            await loadSlots(keepingTheTimes: true)
        } catch is CancellationError {
            return
        } catch {
            formError = ErrorText.message(for: error)
        }
    }

    /// "Now" was turned down: the barber (or every barber, for Any barber) is busy now, or has
    /// a client before the service would end.
    private var notFreeNowMessage: String {
        if case .offering(let id)? = choice, let offering = catalog.offering(withID: id),
           let barber = catalog.barber(withID: offering.barberID) {
            return "\(barber.name) can't fit this in right now. Pick another time."
        }
        return "No barber can fit this in right now. Pick another time."
    }

    /// After the confirmation: ready for the next walk-in, same service.
    func startOver() {
        attempt = nil
        booked = nil
        clientName = ""
        clientPhone = ""
        note = ""
        formError = nil
        selectedSlot = nil
        day = today
        clearSlots()
    }

    /// "Haircut with Izzy, today at 2:30 PM".
    func summary(of appointment: IzzyAPI.Appointment) -> String {
        let dayText = shopTime.relativeDay(shopTime.day(containing: appointment.start), today: today)
        return "\(appointment.serviceName) with \(appointment.barberName), \(dayText.lowercasedFirstIfRelative) at \(shopTime.time(appointment.start))"
    }
}

private extension String {
    /// "today", "tomorrow" read better mid-sentence; dates stay as they are.
    var lowercasedFirstIfRelative: String {
        ["Today", "Tomorrow", "Yesterday"].contains(self) ? lowercased() : self
    }
}
