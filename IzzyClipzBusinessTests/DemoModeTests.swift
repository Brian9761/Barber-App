import Foundation
import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// The demo version (built with IZZY_DEMO_MODE=YES): signed in on the sample server with the real
/// clock, taking payments with the simulated reader. Every other build is the real app.
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

    func testTheDemoIsSignedInOnTheSampleServerWithTheRealClock() async throws {
        let environment = DemoMode.environment()
        guard case .sample(let server) = environment.backend else {
            return XCTFail("The demo never talks to the shop's server")
        }
        XCTAssertTrue(environment.startsSignedIn)
        XCTAssertEqual(try environment.secrets.read(), FakeServer.ownerKey)
        XCTAssertTrue(environment.terminal.isSimulated, "No real reader and no money")
        XCTAssertTrue(environment.practiceTerminal.isSimulated)
        XCTAssertFalse(environment.canShowAppleEducation)
        XCTAssertEqual(server.options.latency, DemoMode.serverLatency, "Loading states show for a moment")
        XCTAssertFalse(server.options.offline)
        XCTAssertTrue(server.options.stripeConfigured)
        XCTAssertNil(server.options.completeStatusOverride)

        // The real clock, not the UI tests' Monday morning: today's sample bookings are today.
        XCTAssertEqual(environment.clock().timeIntervalSinceNow, 0, accuracy: 60)
        let today = environment.shopTime.day(containing: environment.clock())
        XCTAssertFalse(server.appointments.isEmpty)
        for appointment in server.appointments {
            XCTAssertEqual(environment.shopTime.day(containing: appointment.start), today, appointment.customer.name)
        }

        // The sample owner key opens the workspace straight away (here without the pauses).
        server.options.latency = .zero
        (environment.terminal as? SimulatedPaymentTerminal)?.stepDelay = .zero
        let model = AppModel(environment: environment)
        await model.start()
        let workspace = try XCTUnwrap(model.workspace, "The demo starts signed in")
        XCTAssertEqual(workspace.ownerKey, FakeServer.ownerKey)
        XCTAssertEqual(workspace.checkout.mode, .sampleServer(locationId: "tml_sample_location"))
    }
}
