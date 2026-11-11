import XCTest
@testable import IzzyClipz

/// Apple's age range at launch: only someone iOS says is under 13 sees the screen asking a parent
/// or guardian to book; every other answer carries on, and nothing is kept.
final class AgeCheckTests: XCTestCase {
    /// One gate, 13: under it, the range's highest age is 12 (its lowest is open); at or over it,
    /// the lowest age is 13 or more.
    func testWhatIOSsAnswerMeans() {
        XCTAssertEqual(AgeCheck.ageGate, 13)
        XCTAssertEqual(AgeCheck.outcome(lowerBound: nil, upperBound: 12), .under13)
        XCTAssertEqual(AgeCheck.outcome(lowerBound: 13, upperBound: nil), .thirteenOrOlder)
        XCTAssertEqual(AgeCheck.outcome(lowerBound: 18, upperBound: nil), .thirteenOrOlder)
        XCTAssertEqual(AgeCheck.outcome(lowerBound: 13, upperBound: 15), .thirteenOrOlder)
        // A region's own gates: under 12 is under 13 too.
        XCTAssertEqual(AgeCheck.outcome(lowerBound: nil, upperBound: 11), .under13)
        // A range on both sides of 13 (a region's lowest gate at 16), or none: not known to be under 13.
        XCTAssertEqual(AgeCheck.outcome(lowerBound: nil, upperBound: 15), .unclear)
        XCTAssertEqual(AgeCheck.outcome(lowerBound: nil, upperBound: nil), .unclear)
    }

    func testOnlySomeoneUnder13SeesTheParentScreen() {
        XCTAssertTrue(AgeCheck.showsParentScreen(.under13))
        for outcome: AgeCheck.Outcome in [.notAsked, .declined, .thirteenOrOlder, .unclear, .failed] {
            XCTAssertFalse(AgeCheck.showsParentScreen(outcome), "\(outcome) carries on")
        }
    }

    /// The real app and the demo ask iOS; UI tests never do, and can start under 13 to see the screen.
    func testWhenItAsks() {
        XCTAssertTrue(AgeCheck.asks(isUITesting: false))
        XCTAssertFalse(AgeCheck.asks(isUITesting: true))
        XCTAssertEqual(AgeCheck.launchOutcome(arguments: [], isUITesting: false), .notAsked)
        XCTAssertEqual(AgeCheck.launchOutcome(arguments: ["-fakeUnder13"], isUITesting: true), .under13)
        XCTAssertEqual(AgeCheck.launchOutcome(arguments: ["-fakeUnder13"], isUITesting: false), .notAsked, "Only UI tests")
    }

    func testWhatTheScreenSays() {
        XCTAssertEqual(AgeCheck.title, "Please ask a parent or guardian to book")
        XCTAssertTrue(AgeCheck.message.contains("parent or guardian"))
        XCTAssertTrue(AgeCheck.message.contains("calling the shop"))
    }
}
