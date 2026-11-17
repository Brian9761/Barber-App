import XCTest
@testable import IzzyClipz

/// The Visit tab's "Accessibility": only the lines the owner checked and confirmed, then always the
/// invitation to call, since the entrance isn't confirmed step-free.
final class VisitAccessibilityTests: XCTestCase {
    func testOnlyTheLinesTheOwnerConfirmed() {
        XCTAssertEqual(VisitAccessibility.lines, [
            "Room for a wheelchair inside, at the chairs and the counter",
            "Disabled parking space near the entrance",
        ])
        for line in VisitAccessibility.lines {
            XCTAssertNil(line.range(of: "ADA"), line)
            XCTAssertNil(line.range(of: "step-free", options: .caseInsensitive), line)
            XCTAssertNotEqual(line, "Wheelchair accessible")
            // "Accessible parking" reads as a claim the space meets ADA standards, which nobody inspected.
            XCTAssertNil(line.range(of: "Accessible parking", options: .caseInsensitive), line)
        }
    }

    func testTheCallLineIsAlwaysThereWithTheShopsNumber() {
        XCTAssertEqual(
            VisitAccessibility.callLine,
            "Questions about getting in or around the shop? Call (442) 341-3053 (relay calls welcome: dial 711) and we'll help."
        )
        XCTAssertTrue(VisitAccessibility.callLine.contains(AppData.shop.phone.display))
        XCTAssertEqual(AppData.shop.phone.callURL.absoluteString, "tel:+14423413053")
    }
}
