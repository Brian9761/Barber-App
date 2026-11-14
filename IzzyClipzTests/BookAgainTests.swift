import XCTest
@testable import IzzyClipz

/// "Book again" on a past or cancelled appointment, and on "You're booked": the same service with
/// the same barber, straight to the day and time, or a step back when that isn't on the menu.
final class BookAgainTests: XCTestCase {
    private let flowxboriHourHaircut = "flowxbori/0d069a9e-c5ea-4cca-ae34-3f38bf668940"

    /// The appointment as the server describes it, for `offeringId` (and the barber in it).
    private func appointment(offeringId: String, serviceId: String = "haircut", barberId: String? = nil) -> IzzyAPI.Appointment {
        var appointment = TestData.appointment()
        appointment.offeringId = offeringId
        appointment.serviceId = serviceId
        appointment.barberId = barberId ?? String(offeringId.split(separator: "/").first ?? "")
        return appointment
    }

    /// Carlos's haircut: Carlos's haircut again, at the times.
    func testTheSameServiceWithTheSameBarber() throws {
        let carlos = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        XCTAssertEqual(BookAgain.restart(for: TestData.appointment()), .times(.offering(carlos)))
    }

    /// Flowxbori has two haircuts: the hour-long one stays the hour-long one.
    func testTheExactItemBooked() throws {
        let hour = try XCTUnwrap(AppData.catalog.offering(withID: flowxboriHourHaircut))
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: flowxboriHourHaircut)), .times(.offering(hour)))
        XCTAssertEqual(hour.durationMinutes, 60)
    }

    /// An item that's gone from the menu: the barber's version of the service when there's just
    /// one, otherwise "Pick a barber" for the service.
    func testAnItemNoLongerOnTheMenu() throws {
        let carlos = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: "carlos-rafael/gone", barberId: "carlos-rafael")), .times(.offering(carlos)))
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: "flowxbori/gone", barberId: "flowxbori")), .barbers(serviceID: "haircut"))
    }

    /// A barber who left, or a booking without one (from the previous version's Squire bookings):
    /// "Pick a barber" for the service. A service that's gone: pick a service.
    func testABarberOrServiceThatsGone() {
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: "someone-who-left/x", barberId: "someone-who-left")), .barbers(serviceID: "haircut"))
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: "", barberId: "")), .barbers(serviceID: "haircut"))
        XCTAssertEqual(BookAgain.restart(for: appointment(offeringId: "carlos-rafael/x", serviceId: "gone", barberId: "carlos-rafael")), .services)
    }

    /// An appointment saved by the previous version, after booking on Squire, books like any other.
    func testAnAppointmentFromThePreviousVersion() throws {
        let old = Appointment(serviceID: "haircut", serviceName: "Haircut", barberID: "carlos-rafael", barberName: "Carlos", start: TestData.friday, durationMinutes: 45, priceLabel: "$45")
        let saved = SavedAppointment(squire: old, remind: false)
        let carlos = try XCTUnwrap(AppData.catalog.offering(withID: TestData.carlosHaircutID))
        XCTAssertEqual(BookAgain.restart(for: saved.snapshot), .times(.offering(carlos)))
    }
}
