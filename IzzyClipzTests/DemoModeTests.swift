import Foundation
import XCTest
@testable import IzzyClipz

/// The demo version (built with IZZY_DEMO_MODE=YES): the in-memory server with the real clock, and
/// settings that start empty every launch. Every other build is the real app (see also
/// `AppResourcesTests.testOnlyTheDemoVersionUsesTheInMemoryServer`).
@MainActor
final class DemoModeTests: XCTestCase {
    func testOnlyYesOneOrTrueTurnItOn() {
        for value: Any in ["YES", "yes", "Yes", " YES\n", "1", "true", "TRUE", true, 1] {
            XCTAssertTrue(DemoMode.isEnabled(value), "\(value)")
        }
        for value: Any in ["NO", "no", "0", "false", "", " ", "$(IZZY_DEMO_MODE)", "Y", "on", "YES please", false, 0, 2, ["YES"]] {
            XCTAssertFalse(DemoMode.isEnabled(value), "\(value)")
        }
        XCTAssertFalse(DemoMode.isEnabled(nil), "No Info.plist key is the real app")
    }

    func testTheAppAndItsTestsAreNotTheDemoVersion() {
        XCTAssertFalse(DemoMode.isOn)
        XCTAssertFalse(DemoMode.isEnabled(in: .main))
    }

    /// The demo's server answers from memory like the UI tests' fake, but with today's open times
    /// and none of their switches: no failures on purpose, the sample reviews and products, and a
    /// booking that goes straight through.
    func testTheDemoServerIsInMemoryWithTheRealClock() async throws {
        let api = DemoMode.makeShopAPI()
        XCTAssertTrue(api is FakeShopAPI, "Never the network")
        let health = try await api.health()
        XCTAssertEqual(health.version, "fake")

        let calendar = AppData.bookingCalendar
        let today = LocalDate(calendar.day(containing: Date()))
        let target = IzzyAPI.BookingTarget.anyBarber(serviceId: "haircut")
        let availability = try await api.availability(IzzyAPI.AvailabilityQuery(target: target, from: today, days: 14))
        let slots = availability.days.flatMap(\.slots)
        let first = try XCTUnwrap(slots.first, "The coming two weeks have open times")
        XCTAssertGreaterThan(first.start, Date(), "Times from the real clock, not a test date")
        XCTAssertLessThan(first.start, Date().addingTimeInterval(15 * 24 * 60 * 60))

        let reviews = try await api.reviews()
        XCTAssertTrue(reviews.google.available)
        XCTAssertFalse(reviews.google.reviews.isEmpty)
        let products = try await api.products()
        XCTAssertFalse(products.isEmpty)

        let request = IzzyAPI.NewAppointment(target: target, start: first.start, customer: IzzyAPI.NewCustomer(name: "Demo tester", phone: "4425550123"))
        let confirmation = try await api.book(request, token: .generate())
        XCTAssertEqual(confirmation.appointment.start, first.start)
        let found = try await api.appointment(id: confirmation.appointment.id, manageToken: confirmation.manageToken)
        XCTAssertEqual(found.status, .booked)
    }

    func testTheDemoStartsWithEmptySettingsEveryLaunch() {
        let key = "demo-mode-tests-name"
        let first = DemoMode.startFresh()
        first.set("Alex", forKey: key)
        XCTAssertEqual(first.string(forKey: key), "Alex")
        XCTAssertNil(UserDefaults.standard.string(forKey: key), "Not the real app's settings")

        let next = DemoMode.startFresh()
        XCTAssertNil(next.string(forKey: key), "The next launch starts empty")
        next.removePersistentDomain(forName: DemoMode.defaultsSuite)
    }
}
