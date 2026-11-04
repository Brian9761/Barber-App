import Foundation

/// What the customer app needs from the server. `IzzyAPIClient` talks to the
/// real one; UI tests and previews use an in-memory fake.
///
/// Every method throws `APIError`, or `CancellationError` when its task is
/// cancelled.
public protocol ShopAPI: Sendable {
    /// `GET /api/health`.
    func health() async throws -> IzzyAPI.Health

    /// `GET /api/availability`: open start times, by shop day.
    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse

    /// `POST /api/appointments`, sending `token` as the appointment's manage
    /// token (`X-Manage-Token`). Make one token per booking (`ManageToken.generate()`)
    /// and send the same one with every retry of that same booking: if an
    /// earlier try went through but its answer was lost, the server answers
    /// with that appointment (200) instead of booking twice. "The same
    /// booking" is what the server compares, `NewAppointment.retryKey` (the
    /// target, start and phone number): a retry with the name or note edited
    /// is still that booking, and gets it back as it was first made. A new
    /// token only for a booking with another key.
    ///
    /// Keep the confirmation's manage token (the one sent, from a server that
    /// takes it): it's the only way to look up or cancel the appointment later.
    func book(_ appointment: IzzyAPI.NewAppointment, token: IzzyAPI.ManageToken) async throws -> IzzyAPI.BookingConfirmation

    /// `GET /api/appointments/:id`: the appointment as it is now (the shop may
    /// have cancelled or completed it).
    func appointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment

    /// `POST /api/appointments/:id/cancel`.
    ///
    /// Inside the late-cancellation window of a booking with a card on file, the server asks first:
    /// without `acceptLateCancelFee` it throws `APIError.lateCancelFee(message:)` and changes
    /// nothing. Show that message ("Cancelling now, less than 1 hour before your appointment, may be
    /// charged $35, the full service price.") with "Cancel appointment" and "Keep appointment", and
    /// call again with `acceptLateCancelFee: true` to cancel anyway. Send `true` only after the
    /// client saw a warning: the server decides by its own clock, so the phone's may be off.
    func cancelAppointment(id: String, manageToken: String, acceptLateCancelFee: Bool) async throws -> IzzyAPI.Appointment

    /// `GET /api/reviews`: live, never stored.
    func reviews() async throws -> IzzyAPI.ReviewsResponse

    /// `GET /api/products`: the products on show, in the shop's order.
    func products() async throws -> [IzzyAPI.Product]

    // MARK: No-show protection

    /// `GET /api/no-show-policy`: whether booking `target` needs a saved card, the fee (a range
    /// for "any barber" when the barbers' fees differ), the late-cancellation window, the policy to
    /// agree to and the warning to show while booking. Not required when Stripe isn't set up, the
    /// shop hasn't turned protection on, or the item has no fee.
    func noShowPolicy(for target: IzzyAPI.BookingTarget) async throws -> IzzyAPI.NoShowPolicy

    /// `POST /api/cards/checkout`: Stripe's card page for saving a card under `token` (a new
    /// `CardToken.generate()` for each "Add a card"). Open its `url` in
    /// `ASWebAuthenticationSession` with `CardCheckout.callbackScheme`, then read the callback
    /// with `CardCheckoutResult(callbackURL:)`.
    func startCardCheckout(for target: IzzyAPI.BookingTarget, token: IzzyAPI.CardToken) async throws -> IzzyAPI.CardCheckout

    /// `POST /api/cards`: saves the card from a completed Checkout Session under `token` (the
    /// one the checkout was started with). Safe to call again after a lost answer.
    func saveCard(sessionId: String, token: IzzyAPI.CardToken) async throws -> IzzyAPI.SavedCard
}

extension ShopAPI {
    /// `cancelAppointment(id:manageToken:acceptLateCancelFee:)` before any warning: a cancellation
    /// inside the late-cancellation window comes back as `APIError.lateCancelFee`.
    public func cancelAppointment(id: String, manageToken: String) async throws -> IzzyAPI.Appointment {
        try await cancelAppointment(id: id, manageToken: manageToken, acceptLateCancelFee: false)
    }
}

/// What the owner app needs from the server. Every call but `health` and
/// `availability` carries the owner key.
///
/// Every method throws `APIError`, or `CancellationError` when its task is
/// cancelled.
public protocol OwnerAPI: Sendable {
    /// `GET /api/health`.
    func health() async throws -> IzzyAPI.Health

    /// `GET /api/availability`, as customers see it.
    func availability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse

    /// `GET /api/owner/me`: checks the owner key and reports Stripe's status.
    func ownerStatus() async throws -> IzzyAPI.OwnerStatus

    /// `GET /api/owner/availability`: open start times without the lead time (for walk-ins).
    func ownerAvailability(_ query: IzzyAPI.AvailabilityQuery) async throws -> IzzyAPI.AvailabilityResponse

    /// `GET /api/owner/appointments?date=`: one shop day, every status.
    func appointments(on date: LocalDate) async throws -> [IzzyAPI.Appointment]

    /// `GET /api/owner/appointments?from=&to=`.
    func appointments(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.Appointment]

    /// `POST /api/owner/appointments`: walk-ins and phone bookings. No lead
    /// time and no phone needed, but still no overlaps and inside hours.
    ///
    /// Sends `idempotencyKey` as `Idempotency-Key`. Make one per booking
    /// (`IdempotencyKey.generate()`) and send the same one when booking it
    /// again after an error that leaves the outcome unknown (offline, a lost
    /// answer): if the earlier try went through, the server answers with that
    /// appointment, as it is now, instead of booking twice. A new key for a
    /// booking that changed, and for the next one.
    func createAppointment(_ appointment: IzzyAPI.NewAppointment, idempotencyKey: IzzyAPI.IdempotencyKey) async throws -> IzzyAPI.Appointment

    /// `PATCH /api/owner/appointments/:id`. Cancelling here records the shop
    /// as the one who cancelled.
    func setStatus(_ status: IzzyAPI.AppointmentStatus, ofAppointment id: String) async throws -> IzzyAPI.Appointment

    /// `POST /api/owner/appointments/:id/no-show-fee`: charges the fee agreed at booking to the
    /// card on file, for a no-show whose start has passed or a late cancellation by the client
    /// (`Appointment.chargeableFee(at:)`; `noShowFee.reason` says which it was charged for).
    /// Returns the appointment as it is now: its `noShowFee.status` says whether it was charged,
    /// declined (`message` says why), needs the client, or is still pending. Charged at most once:
    /// calling again after a lost answer or a pending charge never charges twice.
    func chargeNoShowFee(appointmentId: String) async throws -> IzzyAPI.Appointment

    /// `GET /api/owner/no-show-settings`.
    func noShowSettings() async throws -> IzzyAPI.NoShowSettings

    /// `PATCH /api/owner/no-show-settings`: changes only the fields that are set.
    func updateNoShowSettings(_ update: IzzyAPI.NoShowSettingsUpdate) async throws -> IzzyAPI.NoShowSettings

    /// `GET /api/owner/time-off?from=&to=`.
    func timeOff(from: LocalDate, to: LocalDate) async throws -> [IzzyAPI.TimeOff]

    /// `POST /api/owner/time-off`.
    func createTimeOff(_ timeOff: IzzyAPI.NewTimeOff) async throws -> IzzyAPI.TimeOff

    /// `DELETE /api/owner/time-off/:id`.
    func deleteTimeOff(id: String) async throws

    /// `GET /api/owner/products`: every product, hidden ones too.
    func allProducts() async throws -> [IzzyAPI.Product]

    /// `POST /api/owner/products`.
    func createProduct(_ product: IzzyAPI.NewProduct) async throws -> IzzyAPI.Product

    /// `PATCH /api/owner/products/:id`.
    func updateProduct(id: String, _ update: IzzyAPI.ProductUpdate) async throws -> IzzyAPI.Product

    /// `DELETE /api/owner/products/:id`.
    func deleteProduct(id: String) async throws

    /// `POST /api/owner/products/:id/photo` with a JPEG of at most
    /// `IzzyAPI.maxPhotoBytes`.
    func uploadProductPhoto(id: String, jpegData: Data) async throws -> IzzyAPI.Product

    /// `POST /api/owner/terminal/connection-token`: the secret Stripe
    /// Terminal's `ConnectionTokenProvider` hands to the SDK. Never cache it.
    func connectionToken() async throws -> String

    /// `POST /api/owner/payments`: the server creates the PaymentIntent, so
    /// the app can't change the amount afterwards.
    func createPayment(_ payment: IzzyAPI.NewPayment) async throws -> IzzyAPI.PaymentIntentCreated

    /// `POST /api/owner/payments/:id/complete`, after Tap to Pay succeeds:
    /// the server checks with Stripe and marks the appointment paid.
    func completePayment(id: String) async throws -> IzzyAPI.Payment

    /// `GET /api/owner/payments?date=`.
    func payments(on date: LocalDate) async throws -> [IzzyAPI.Payment]
}
