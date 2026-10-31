import XCTest
@testable import IzzyClipzKit

/// Decoding the Kit's own fixtures field by field, and encoding the way the
/// contract writes things.
final class ResponseDecodingTests: XCTestCase {
    private let decoder = IzzyAPI.makeDecoder()

    func testBookingConfirmation() throws {
        let confirmation = try decoder.decode(IzzyAPI.BookingConfirmation.self, from: try kitFixture("booking-confirmation.json"))
        XCTAssertEqual(confirmation.manageToken, "dGVzdC1tYW5hZ2UtdG9rZW4tZm9yLWZpeHR1cmVzLTAx")
        let appointment = confirmation.appointment
        XCTAssertEqual(appointment.id, "5b8f2c1e-3d4a-4e6f-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(appointment.offeringId, "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a")
        XCTAssertEqual(appointment.serviceId, "haircut")
        XCTAssertEqual(appointment.serviceName, "Haircut")
        XCTAssertEqual(appointment.barberId, "flowxbori")
        XCTAssertEqual(appointment.barberName, "Flowxbori")
        XCTAssertEqual(appointment.start, utc(2026, 11, 2, 18))
        XCTAssertEqual(appointment.end, utc(2026, 11, 2, 18, 45))
        XCTAssertEqual(appointment.durationMinutes, 45)
        XCTAssertEqual(appointment.priceLabel, "$35")
        XCTAssertEqual(appointment.status, .booked)
        XCTAssertNil(appointment.cancelledBy)
        XCTAssertEqual(appointment.payment, .unpaid)
        XCTAssertEqual(appointment.customer, IzzyAPI.Customer(name: "Test Customer", phone: "+14425550123"))
        XCTAssertNil(appointment.note)
        XCTAssertEqual(appointment.createdAt, utc(2026, 10, 31, 17, 5, 9))
        // The token never shows up in logs.
        XCTAssertFalse(String(describing: confirmation).contains(confirmation.manageToken))
    }

    func testAppointmentStatusesPaymentsAndWalkIns() throws {
        let list = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json")).appointments
        XCTAssertEqual(list.map(\.status), [.completed, .noShow, .cancelled])
        XCTAssertEqual(list[0].payment, IzzyAPI.AppointmentPayment(status: .paid, amountCents: 8000, paidAt: utc(2026, 11, 2, 19, 20, 31)))
        XCTAssertNil(list[0].customer.phone)
        XCTAssertEqual(list[2].cancelledBy, .shop)
        XCTAssertEqual(list[2].priceLabel, "From $80")
        XCTAssertEqual(list[2].note, "First time with lightener.")

        let single = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("appointment.json")).appointment
        XCTAssertEqual(single.status, .cancelled)
        XCTAssertEqual(single.cancelledBy, .customer)
        XCTAssertEqual(single.customer.email, "test.customer@example.com")
    }

    func testAppointmentHelpers() throws {
        var appointment = try decoder.decode(IzzyAPI.AppointmentResponse.self, from: try kitFixture("booking-confirmation.json")).appointment
        XCTAssertTrue(appointment.isCancellable(at: utc(2026, 11, 2, 17, 59)))
        XCTAssertFalse(appointment.isCancellable(at: utc(2026, 11, 2, 18)))
        XCTAssertTrue(appointment.isUpcoming(at: utc(2026, 11, 2, 18, 44)))
        XCTAssertFalse(appointment.isUpcoming(at: utc(2026, 11, 2, 18, 45)))
        XCTAssertEqual(appointment.durationLabel, "45 min")
        appointment.status = .cancelled
        XCTAssertFalse(appointment.isCancellable(at: utc(2026, 11, 1)))
        appointment.durationMinutes = 0
        XCTAssertEqual(appointment.durationLabel, "")
        XCTAssertEqual(IzzyAPI.AppointmentStatus.allCases.map(\.title), ["Booked", "Cancelled", "Completed", "No-show"])
        XCTAssertEqual(IzzyAPI.AppointmentStatus.noShow.rawValue, "noShow")
    }

    func testAppointmentsAreStrict() throws {
        let fixture = String(decoding: try kitFixture("appointment.json"), as: UTF8.self)
        for (from, to) in [
            (#""status": "cancelled""#, #""status": "no_show""#),
            (#""status": "cancelled""#, #""status": "pending""#),
            (#""start": "2026-11-02T18:00:00Z""#, #""start": "2026-11-02 18:00""#),
            (#""durationMinutes": 45"#, #""durationMinutes": "45""#),
            (#""cancelledBy": "customer""#, #""cancelledBy": "barber""#),
            (#""durationMinutes": 45"#, #""durationMinutes": 0"#),
            (#""durationMinutes": 45"#, #""durationMinutes": -15"#),
        ] {
            XCTAssertThrowsError(try decodeAPI(IzzyAPI.AppointmentResponse.self, fixture.replacingOccurrences(of: from, with: to)), to)
        }
    }

    func testAvailability() throws {
        let availability = try decoder.decode(IzzyAPI.AvailabilityResponse.self, from: try kitFixture("availability.json"))
        XCTAssertEqual(availability.timeZone, "America/Los_Angeles")
        XCTAssertEqual(availability.shopTimeZone, pacific)
        XCTAssertEqual(availability.days.map(\.date.description), ["2026-11-02", "2026-11-03"])
        let monday = availability.slots(on: LocalDate("2026-11-02")!)
        XCTAssertEqual(monday.map(\.start), [utc(2026, 11, 2, 18), utc(2026, 11, 2, 18, 30), utc(2026, 11, 3, 2)])
        XCTAssertEqual(monday[0].barberIds, ["flowxbori", "cristian-ceja", "julian-ramos"])
        // 6 PM in the shop is already the next day in UTC; it still belongs to Monday.
        XCTAssertEqual(ShopInfo.izzyClipz.bookingCalendar.timeLabel(for: monday[2].start), "6 PM")
        XCTAssertEqual(availability.slots(on: LocalDate("2026-11-03")!), [])
        XCTAssertEqual(availability.slots(on: LocalDate("2026-12-25")!), [])
    }

    func testReviews() throws {
        let reviews = try decoder.decode(IzzyAPI.ReviewsResponse.self, from: try kitFixture("reviews.json"))
        XCTAssertTrue(reviews.google.available)
        XCTAssertEqual(reviews.google.rating, 4.9)
        XCTAssertEqual(reviews.google.count, 61)
        XCTAssertEqual(reviews.google.fetchedAt, utc(2026, 10, 31, 17))
        XCTAssertEqual(reviews.google.summary?.averageLabel, "4.9")
        XCTAssertEqual(reviews.google.summary?.countLabel, "61 reviews")
        XCTAssertEqual(reviews.google.reviews.count, 2)
        let first = reviews.google.reviews[0]
        XCTAssertEqual(first.author, "Sample Reviewer")
        XCTAssertEqual(first.rating, 5)
        XCTAssertEqual(first.relativeTime, "2 weeks ago")
        XCTAssertEqual(first.publishedAt, utc(2026, 10, 14, 20, 11, 42))
        XCTAssertEqual(first.authorPhotoUrl?.host, "lh3.googleusercontent.com")
        XCTAssertEqual(first.url?.host, "www.google.com")
        let second = reviews.google.reviews[1]
        XCTAssertNil(second.authorPhotoUrl)
        XCTAssertNil(second.url)
        XCTAssertEqual(second.text, "")

        XCTAssertFalse(reviews.yelp.available)
        XCTAssertNil(reviews.yelp.summary)
        XCTAssertNil(reviews.yelp.rating)
        XCTAssertNil(reviews.yelp.count)
        XCTAssertEqual(reviews.yelp.url.absoluteString, "https://www.yelp.com/biz/izzy-clipz-barbershop-oceanside")
        XCTAssertEqual(reviews.yelp.reviews, [])

        let yelp = try decoder.decode(IzzyAPI.ReviewsResponse.self, from: try kitFixture("reviews-yelp.json")).yelp
        XCTAssertEqual(yelp.rating, 4.5)
        // Yelp's tracking parameters must stay exactly as Yelp sent them.
        XCTAssertTrue(yelp.reviews[0].url!.absoluteString.hasSuffix("utm_source=SAMPLE"))
    }

    func testReviewsAreLenientAboutThirdPartyExtras() throws {
        let source = try decodeAPI(IzzyAPI.ReviewSource.self, """
        {"available": true, "rating": 5, "count": 3, "url": "https://www.google.com/maps/search/?api=1",
         "reviews": [
           {"author": "Links", "authorPhotoUrl": "javascript:alert(1)", "authorUrl": "tel:+15555550100", "rating": 4.0,
            "text": "Fine", "relativeTime": 7, "publishedAt": "last week", "url": "not a link"},
           {"author": "No text", "rating": 4.6},
           {"rating": 5, "text": "No author, skipped"},
           {"author": "Bad rating", "rating": "five", "text": "Skipped"},
           {"author": "Kept", "rating": 3, "text": "Kept", "publishedAt": "2026-10-14T20:11:42.123456789Z"}
         ],
         "fetchedAt": "yesterday"}
        """)
        XCTAssertEqual(source.reviews.map(\.author), ["Links", "No text", "Kept"])
        let links = source.reviews[0]
        XCTAssertNil(links.authorPhotoUrl)
        XCTAssertNil(links.authorUrl)
        XCTAssertNil(links.url)
        XCTAssertNil(links.relativeTime)
        XCTAssertNil(links.publishedAt)
        XCTAssertEqual(links.rating, 4)
        XCTAssertEqual(source.reviews[1].rating, 5)
        XCTAssertEqual(source.reviews[1].text, "")
        XCTAssertEqual(source.reviews[2].publishedAt?.timeIntervalSince(utc(2026, 10, 14, 20, 11, 42)) ?? -1, 0.123_456_789, accuracy: 0.000_001)
        XCTAssertNil(source.fetchedAt)
        XCTAssertEqual(source.rating, 5)
        // The shop's own page link is required and must be a web link.
        XCTAssertThrowsError(try decodeAPI(IzzyAPI.ReviewSource.self, #"{"available": false, "url": "javascript:alert(1)", "reviews": []}"#))
        XCTAssertThrowsError(try decodeAPI(IzzyAPI.ReviewSource.self, #"{"available": false, "reviews": []}"#))
        // A link with a raw space still works.
        let spaced = try decodeAPI(IzzyAPI.ReviewSource.self,
                                   #"{"available": false, "url": "https://www.google.com/maps/search/?api=1&query=Izzy Clipz Barbershop"}"#)
        XCTAssertEqual(spaced.url.absoluteString, "https://www.google.com/maps/search/?api=1&query=Izzy%20Clipz%20Barbershop")
        // An already escaped one is left alone.
        let escaped = try decodeAPI(IzzyAPI.ReviewSource.self, #"{"available": false, "url": "https://www.google.com/maps/search/?query=Izzy%20Clipz"}"#)
        XCTAssertEqual(escaped.url.absoluteString, "https://www.google.com/maps/search/?query=Izzy%20Clipz")
        // A missing review list is an empty one.
        XCTAssertEqual(try decodeAPI(IzzyAPI.ReviewSource.self, #"{"available": false, "url": "https://www.yelp.com/biz/x"}"#).reviews, [])
    }

    func testNumbersThatWouldBreakAStarRowAreTamed() throws {
        let source = try decodeAPI(IzzyAPI.ReviewSource.self, """
        {"available": true, "rating": 7.5, "count": -3, "url": "https://www.yelp.com/biz/x", "reviews": [
          {"author": "Huge", "rating": 1e300, "text": ""},
          {"author": "Negative", "rating": -2, "text": ""},
          {"author": "Too many", "rating": 9, "text": ""},
          {"author": "Half", "rating": 3.5, "text": ""}
        ]}
        """)
        XCTAssertEqual(source.reviews.map(\.rating), [5, 0, 5, 4])
        XCTAssertNil(source.rating)
        XCTAssertNil(source.count)
        XCTAssertNil(source.summary)
        let partial = try decodeAPI(IzzyAPI.ReviewSource.self, #"{"available": true, "rating": 4.5, "count": null, "url": "https://www.yelp.com/biz/x"}"#)
        XCTAssertNil(partial.summary, "no count, no summary")
        XCTAssertNil(IzzyAPI.Product(id: "p", name: "Odd", priceCents: -100).priceLabel)
    }

    func testProducts() throws {
        let products = try decoder.decode(IzzyAPI.ProductsResponse.self, from: try kitFixture("products.json")).products
        XCTAssertEqual(products.map(\.name), ["Sample pomade", "Sample comb"])
        XCTAssertEqual(products[0].priceCents, 1800)
        XCTAssertEqual(products[0].priceLabel, "$18")
        XCTAssertEqual(products[0].imageUrl?.host, "sample.public.blob.vercel-storage.com")
        XCTAssertNil(products[1].priceLabel)
        XCTAssertNil(products[1].description)
        XCTAssertNil(products[1].imageUrl)
        XCTAssertTrue(products.allSatisfy(\.visible))

        let hidden = try decoder.decode(IzzyAPI.ProductsResponse.self, from: try kitFixture("owner-products.json")).products[0]
        XCTAssertFalse(hidden.visible)
        XCTAssertEqual(hidden.priceLabel, "$7.50")

        let one = try decoder.decode(IzzyAPI.ProductResponse.self, from: try kitFixture("product.json")).product
        XCTAssertEqual(one, products[0])
    }

    func testOneBadProductDoesntHideTheRest() throws {
        let products = try decodeAPI(IzzyAPI.ProductsResponse.self, """
        {"products": [
          {"id": "a", "name": "Good", "description": null, "priceCents": 500, "imageUrl": null, "visible": true},
          {"id": "b", "name": "Bad price", "priceCents": "five", "visible": true},
          {"id": "c", "name": "No visible flag"},
          {"id": "d", "name": "Odd image link", "imageUrl": "file:///etc/passwd", "visible": true}
        ]}
        """).products
        XCTAssertEqual(products.map(\.id), ["a", "d"])
        XCTAssertNil(products[1].imageUrl)
        XCTAssertThrowsError(try decodeAPI(IzzyAPI.ProductsResponse.self, #"{"items": []}"#))
    }

    func testOwnerResponses() throws {
        let me = try decoder.decode(IzzyAPI.OwnerStatus.self, from: try kitFixture("owner-me.json"))
        XCTAssertEqual(me, IzzyAPI.OwnerStatus(ok: true, stripe: IzzyAPI.StripeStatus(configured: true, mode: .test, locationId: "tml_FixtureLocation")))
        let unconfigured = try decoder.decode(IzzyAPI.OwnerStatus.self, from: try kitFixture("owner-me-unconfigured.json"))
        XCTAssertEqual(unconfigured.stripe, IzzyAPI.StripeStatus(configured: false, mode: nil))

        let health = try decoder.decode(IzzyAPI.Health.self, from: try kitFixture("health.json"))
        XCTAssertEqual(health, IzzyAPI.Health(ok: true, version: "1.0.0"))

        let timeOff = try decoder.decode(IzzyAPI.TimeOffListResponse.self, from: try kitFixture("time-off-list.json")).timeOff
        XCTAssertEqual(timeOff.map(\.barberId), ["carlos-rafael", nil])
        XCTAssertEqual(timeOff.map(\.isWholeShop), [false, true])
        XCTAssertEqual(timeOff[0].reason, "Dentist")
        XCTAssertNil(timeOff[1].reason)
        XCTAssertEqual(timeOff[1].start, utc(2026, 11, 26, 8))
        let created = try decoder.decode(IzzyAPI.TimeOffResponse.self, from: try kitFixture("time-off.json")).timeOff
        XCTAssertEqual(created, timeOff[0])

        let token = try decoder.decode(IzzyAPI.ConnectionToken.self, from: try kitFixture("connection-token.json"))
        XCTAssertTrue(token.secret.hasPrefix("pst_test_"))
        XCTAssertFalse(String(describing: token).contains(token.secret))

        let intent = try decoder.decode(IzzyAPI.PaymentIntentCreated.self, from: try kitFixture("payment-intent.json"))
        XCTAssertEqual(intent.paymentIntentId, "pi_3SampleSampleSample01")
        XCTAssertFalse(String(describing: intent).contains(intent.clientSecret))

        let payment = try decoder.decode(IzzyAPI.PaymentResponse.self, from: try kitFixture("payment.json")).payment
        XCTAssertTrue(payment.isSucceeded)
        XCTAssertEqual(payment.amountLabel, "$80")
        XCTAssertEqual(payment.appointmentId, "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
        let payments = try decoder.decode(IzzyAPI.PaymentsResponse.self, from: try kitFixture("payments.json")).payments
        XCTAssertEqual(payments.map(\.isSucceeded), [true, false])
        XCTAssertNil(payments[1].description)
        XCTAssertEqual(payments[1].amountLabel, "$25")
    }

    func testErrorEnvelope() throws {
        let envelope = try decoder.decode(IzzyAPI.ErrorEnvelope.self, from: try kitFixture("error-slot-taken.json"))
        XCTAssertEqual(envelope.error.code, "slot_taken")
        XCTAssertEqual(envelope.error.message, "Someone just booked that time. Pick another.")
        XCTAssertEqual(try decodeAPI(IzzyAPI.ErrorEnvelope.self, #"{"error":{"code":"server_error"}}"#).error.message, "")
    }
}

final class ResponseEncodingTests: XCTestCase {
    func testOptionalFieldsAreWrittenAsNull() throws {
        let appointment = IzzyAPI.Appointment(
            id: "a1", offeringId: "flowxbori/x", serviceId: "haircut", serviceName: "Haircut",
            barberId: "flowxbori", barberName: "Flowxbori", start: utc(2026, 11, 2, 18), end: utc(2026, 11, 2, 18, 45),
            durationMinutes: 45, priceLabel: "$35", customer: IzzyAPI.Customer(name: "Test"), createdAt: utc(2026, 10, 31)
        )
        let json = try encodeAPI(appointment)
        XCTAssertEqual(json["cancelledBy"], .null)
        XCTAssertEqual(json["note"], .null)
        XCTAssertEqual(json["payment"], .object(["status": .string("unpaid"), "amountCents": .null, "paidAt": .null]))
        XCTAssertEqual(json["customer"], .object(["name": .string("Test"), "phone": .null, "email": .null]))
        XCTAssertEqual(json["start"], .string("2026-11-02T18:00:00Z"))
        XCTAssertEqual(json["status"], .string("booked"))
        XCTAssertEqual(json.keys.count, 16)

        let product = try encodeAPI(IzzyAPI.Product(id: "p", name: "Comb"))
        XCTAssertEqual(product, .object([
            "id": .string("p"), "name": .string("Comb"), "description": .null, "priceCents": .null,
            "imageUrl": .null, "visible": .bool(true),
        ]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.StripeStatus(configured: false)), .object(["configured": .bool(false), "mode": .null, "locationId": .null]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.TimeOff(id: "t", barberId: nil, start: utc(2026, 1, 1), end: utc(2026, 1, 2)))["barberId"], .null)
    }

    func testModelsRoundTrip() throws {
        let decoder = IzzyAPI.makeDecoder()
        let encoder = IzzyAPI.makeEncoder()
        let reviews = try decoder.decode(IzzyAPI.ReviewsResponse.self, from: try kitFixture("reviews.json"))
        XCTAssertEqual(try decoder.decode(IzzyAPI.ReviewsResponse.self, from: try encoder.encode(reviews)), reviews)
        let list = try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try kitFixture("owner-appointments.json"))
        XCTAssertEqual(try decoder.decode(IzzyAPI.AppointmentsResponse.self, from: try encoder.encode(list)), list)
        let availability = try decoder.decode(IzzyAPI.AvailabilityResponse.self, from: try kitFixture("availability.json"))
        XCTAssertEqual(try decoder.decode(IzzyAPI.AvailabilityResponse.self, from: try encoder.encode(availability)), availability)
    }
}

final class RequestEncodingTests: XCTestCase {
    func testNewAppointmentWithABarbersOffering() throws {
        let body = IzzyAPI.NewAppointment(
            target: .offering(id: "flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"),
            start: utc(2026, 11, 2, 18),
            customer: IzzyAPI.NewCustomer(name: "  Test Customer \n", phone: "+14425550123", email: "  "),
            note: "   "
        )
        XCTAssertEqual(try encodeAPI(body), .object([
            "offeringId": .string("flowxbori/bbb0c294-87a6-465d-9f55-6f579dcb399a"),
            "start": .string("2026-11-02T18:00:00Z"),
            "customer": .object(["name": .string("Test Customer"), "phone": .string("+14425550123")]),
        ]))
        let raw = String(decoding: try IzzyAPI.makeEncoder().encode(body), as: UTF8.self)
        XCTAssertFalse(raw.contains("\\/"), raw)
    }

    func testCustomerPhonesAreSentInE164() throws {
        func phone(_ typed: String?) throws -> JSONValue? {
            try encodeAPI(IzzyAPI.NewCustomer(name: "T", phone: typed))["phone"]
        }
        XCTAssertEqual(try phone("(442) 555-0123"), .string("+14425550123"))
        XCTAssertEqual(try phone("442.555.0123 "), .string("+14425550123"))
        XCTAssertEqual(try phone("+14425550123"), .string("+14425550123"))
        // Not a US number: sent as typed, for the server to explain.
        XCTAssertEqual(try phone(" +44 20 7946 0958 "), .string("+44 20 7946 0958"))
        XCTAssertNil(try phone("  "))
        XCTAssertNil(try phone(nil))
    }

    func testNewAppointmentWithAnyBarber() throws {
        let body = IzzyAPI.NewAppointment(
            target: .anyBarber(serviceId: "haircut"),
            start: utc(2026, 11, 2, 18, 30),
            customer: IzzyAPI.NewCustomer(name: "Walk-in"),
            note: " Fade, please "
        )
        XCTAssertEqual(try encodeAPI(body), .object([
            "serviceId": .string("haircut"),
            "barberId": .string("any"),
            "start": .string("2026-11-02T18:30:00Z"),
            "customer": .object(["name": .string("Walk-in")]),
            "note": .string("Fade, please"),
        ]))
        let offering = Catalog.izzyClipz.offerings[0]
        XCTAssertEqual(IzzyAPI.BookingTarget.offering(offering), .offering(id: offering.id))
    }

    func testStatusChange() throws {
        XCTAssertEqual(try encodeAPI(IzzyAPI.StatusChange(status: .noShow)), .object(["status": .string("noShow")]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.StatusChange(status: .cancelled)), .object(["status": .string("cancelled")]))
    }

    func testNewTimeOffSendsAnExplicitNullForTheWholeShop() throws {
        let shop = IzzyAPI.NewTimeOff(barberId: nil, start: utc(2026, 11, 26, 8), end: utc(2026, 11, 27, 8), reason: "  ")
        XCTAssertEqual(try encodeAPI(shop), .object([
            "barberId": .null, "start": .string("2026-11-26T08:00:00Z"), "end": .string("2026-11-27T08:00:00Z"),
        ]))
        let carlos = IzzyAPI.NewTimeOff(barberId: "carlos-rafael", start: utc(2026, 11, 5, 18), end: utc(2026, 11, 5, 21), reason: "Dentist")
        XCTAssertEqual(try encodeAPI(carlos)["barberId"], .string("carlos-rafael"))
        XCTAssertEqual(try encodeAPI(carlos)["reason"], .string("Dentist"))
    }

    func testNewProductLeavesOutWhatIsntSet() throws {
        XCTAssertEqual(try encodeAPI(IzzyAPI.NewProduct(name: " Comb ")), .object(["name": .string("Comb")]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.NewProduct(name: "Pomade", description: "Strong hold", priceCents: 1800, visible: false)), .object([
            "name": .string("Pomade"), "description": .string("Strong hold"), "priceCents": .number(1800), "visible": .bool(false),
        ]))
    }

    func testProductUpdateSendsOnlyChangesAndNullToClear() throws {
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate()), .object([:]))
        XCTAssertTrue(IzzyAPI.ProductUpdate().isEmpty)
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate(visible: false)), .object(["visible": .bool(false)]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate(description: .clear, priceCents: .clear)), .object([
            "description": .null, "priceCents": .null,
        ]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate(name: "Comb", description: .set("  "), priceCents: .set(750))), .object([
            "name": .string("Comb"), "description": .null, "priceCents": .number(750),
        ]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate.replacing(name: "Comb", description: "", priceCents: nil, visible: true)), .object([
            "name": .string("Comb"), "description": .null, "priceCents": .null, "visible": .bool(true),
        ]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.ProductUpdate.replacing(name: "Comb", description: " Wide tooth ", priceCents: 750, visible: false)), .object([
            "name": .string("Comb"), "description": .string("Wide tooth"), "priceCents": .number(750), "visible": .bool(false),
        ]))
    }

    func testNewPayment() throws {
        XCTAssertEqual(try encodeAPI(IzzyAPI.NewPayment(amountCents: 4500)), .object(["amountCents": .number(4500)]))
        let full = IzzyAPI.NewPayment(amountCents: 8000, description: "VIP with Izzy", appointmentId: "a1", receiptEmail: " client@example.com ")
        XCTAssertEqual(try encodeAPI(full), .object([
            "amountCents": .number(8000), "description": .string("VIP with Izzy"),
            "appointmentId": .string("a1"), "receiptEmail": .string("client@example.com"),
        ]))
        XCTAssertEqual(try encodeAPI(IzzyAPI.NewPayment(amountCents: 100, receiptEmail: "")), .object(["amountCents": .number(100)]))
        XCTAssertFalse(IzzyAPI.NewPayment(amountCents: 49).isAmountAllowed)
        XCTAssertTrue(IzzyAPI.NewPayment(amountCents: 50).isAmountAllowed)
        XCTAssertTrue(IzzyAPI.NewPayment(amountCents: 100_000).isAmountAllowed)
        XCTAssertFalse(IzzyAPI.NewPayment(amountCents: 100_001).isAmountAllowed)
    }
}

final class PhoneNumberParsingTests: XCTestCase {
    func testReadsWhatPeopleType() {
        for input in ["(442) 341-3053", "442-341-3053", "442.341.3053", "4423413053", "+1 442 341 3053",
                      "1 (442) 341-3053", "14423413053", "+14423413053", " 442 341 3053 \n"] {
            XCTAssertEqual(PhoneNumber(parsing: input)?.e164, "+14423413053", input)
        }
    }

    func testRejectsWhatIsntAUSNumber() {
        for input in ["", "341-3053", "442-341-305", "442-341-30533", "+44 20 7946 0958", "+4423413053",
                      "042-341-3053", "142-341-3053", "442-041-3053", "442-141-3053", "1-800-FLOWERS",
                      "442-341-3053 ext 5", "442-341-3053#", "4423+413053", "٤٤٢٣٤١٣٠٥٣", "4̃423413053", "24423413053"] {
            XCTAssertNil(PhoneNumber(parsing: input), input)
        }
    }

    /// N11 codes (211, 411, 911…) are never area codes or exchanges; the server turns them
    /// down, so the details step must too, not the last step of booking.
    func testRejectsN11AreaCodesAndExchanges() {
        for input in ["(442) 911-3053", "211-555-0123", "(911) 555-0100", "442-411-0100", "+1 (811) 555-0100", "1 442 611 3053"] {
            XCTAssertNil(PhoneNumber(parsing: input), input)
        }
        // Only both of the last two digits being 1 makes an N11 code.
        XCTAssertEqual(PhoneNumber(parsing: "(212) 555-0100")?.e164, "+12125550100")
        XCTAssertEqual(PhoneNumber(parsing: "442-210-3053")?.e164, "+14422103053")
        XCTAssertNil(PhoneNumber(parsing: "442-121-3053"), "an exchange can't start with 1")
    }

    /// Spaces count as the server counts them: tabs and no-break spaces are fine, a zero-width
    /// space or a next-line character isn't.
    func testSpacesAreTheServersSpaces() {
        XCTAssertEqual(PhoneNumber(parsing: "442\t341\t3053")?.e164, "+14423413053")
        XCTAssertEqual(PhoneNumber(parsing: "\u{FEFF}442\u{2009}341\u{00A0}3053\u{3000}")?.e164, "+14423413053")
        XCTAssertNil(PhoneNumber(parsing: "442\u{200B}341 3053"))
        XCTAssertNil(PhoneNumber(parsing: "4423413053\u{85}"))
    }

    /// The server's own list (`server/test/fixtures/phone-numbers.json`), which its tests check
    /// against `normalizeUSPhone`: the Kit must accept and reject exactly the same numbers.
    func testAgreesWithTheServerOnEveryNumberInTheSharedList() throws {
        struct Cases: Decodable {
            let accepted: [[String]]
            let rejected: [String]
        }
        let url = TestPaths.repository.appendingPathComponent("server/test/fixtures/phone-numbers.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("No server phone fixtures at \(url.path).")
        }
        let cases = try JSONDecoder().decode(Cases.self, from: data)
        XCTAssertGreaterThan(cases.accepted.count, 10)
        XCTAssertGreaterThan(cases.rejected.count, 10)
        for pair in cases.accepted {
            XCTAssertEqual(pair.count, 2)
            XCTAssertEqual(PhoneNumber(parsing: pair[0])?.e164, pair[1], "accepted by the server: \(pair[0].debugDescription)")
        }
        for input in cases.rejected {
            XCTAssertNil(PhoneNumber(parsing: input), "rejected by the server: \(input.debugDescription)")
        }
    }

    func testFormsAgree() {
        let number = PhoneNumber(parsing: "(760) 555-0188")
        XCTAssertEqual(number?.digits, "7605550188")
        XCTAssertEqual(number?.display, "(760) 555-0188")
        XCTAssertEqual(ShopInfo.izzyClipz.phone.e164, "+14423413053")
    }
}
