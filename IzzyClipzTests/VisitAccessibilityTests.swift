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

    /// The line about getting in offers email too once the shop has an address (docs/legal/
    /// OWNER-CHECKLIST.md §3 item 21), and nothing until then: no address is made up.
    func testTheEmailSentenceOnlyOnceTheShopHasAnEmail() {
        XCTAssertEqual(AppData.shop.email, "")
        XCTAssertNil(VisitAccessibility.emailLine())
        XCTAssertNil(VisitAccessibility.emailURL())

        let withEmail = Self.shop(email: "hello@izzyclipz.example")
        XCTAssertEqual(VisitAccessibility.emailLine(for: withEmail), "Or email us at hello@izzyclipz.example.")
        XCTAssertEqual(VisitAccessibility.emailURL(for: withEmail)?.absoluteString, "mailto:hello@izzyclipz.example")
        // As the website says it: the call line, then the email sentence.
        XCTAssertEqual(
            "\(VisitAccessibility.callLine) \(VisitAccessibility.emailLine(for: withEmail)!)",
            "Questions about getting in or around the shop? Call (442) 341-3053 (relay calls welcome: dial 711) and we'll help. Or email us at hello@izzyclipz.example."
        )
        XCTAssertNil(VisitAccessibility.emailLine(for: Self.shop(email: "  ")))
    }

    /// The shop's data with an email address given.
    static func shop(email: String) -> ShopInfo {
        let shop = AppData.shop
        return ShopInfo(
            name: shop.name, fullName: shop.fullName, tagline: shop.tagline, about: shop.about, address: shop.address,
            coordinate: shop.coordinate, phone: shop.phone, timeZoneIdentifier: shop.timeZoneIdentifier, schedule: shop.schedule,
            instagramHandle: shop.instagramHandle, websiteURL: shop.websiteURL, paymentMethods: shop.paymentMethods,
            highlights: shop.highlights, accessibility: shop.accessibility, googlePlaceID: shop.googlePlaceID,
            legalName: shop.legalName, email: email
        )
    }
}
