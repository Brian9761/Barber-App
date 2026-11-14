import Foundation
import IzzyClipzKit
import XCTest
@testable import IzzyClipzBusiness

/// What the legal documents ask of the owner app: the four policies on the shop's website
/// (IZZY_WEBSITE_URL), and Apple's age range at launch where a law requires it.
@MainActor
final class LegalTests: XCTestCase {
    // MARK: The website's legal pages

    func testTheLegalPagesAreOnTheWebsite() async {
        let base = URL(string: "https://izzy-clipz.vercel.app")!
        XCTAssertEqual(Website.LegalPage.allCases.map(\.title), [
            "Privacy Policy", "Terms of Service", "Cancellation & No-Show Policy", "Accessibility",
        ])
        XCTAssertEqual(Website.LegalPage.allCases.map { $0.url(on: base).absoluteString }, [
            "https://izzy-clipz.vercel.app/privacy",
            "https://izzy-clipz.vercel.app/terms",
            "https://izzy-clipz.vercel.app/cancellation-policy",
            "https://izzy-clipz.vercel.app/accessibility",
        ])
        XCTAssertEqual(Website.LegalPage.cancellationPolicy.identifier, "legal-cancellation-policy")
    }

    func testTheWebsiteAddressComesFromTheBuildSetting() async {
        XCTAssertEqual(Website.baseURL(from: "https://www.izzyclipz.com").absoluteString, "https://www.izzyclipz.com")
        XCTAssertEqual(Website.baseURL(from: " https://www.izzyclipz.com/ \n").absoluteString, "https://www.izzyclipz.com", "Spaces and the slash at the end go")
        XCTAssertEqual(
            Website.LegalPage.terms.url(on: Website.baseURL(from: "https://www.izzyclipz.com/")).absoluteString,
            "https://www.izzyclipz.com/terms"
        )
        // Anything unusable is the current public site.
        for value: Any? in [nil, "", "$(IZZY_WEBSITE_URL)", "http://izzyclipz.com", "izzyclipz.com", "https://", 42] {
            XCTAssertEqual(Website.baseURL(from: value), Website.fallback, "\(String(describing: value))")
        }
        XCTAssertEqual(Website.fallback.absoluteString, "https://izzy-clipz.vercel.app")
        XCTAssertEqual(Website.baseURL(bundle: Bundle(for: LegalTests.self)), Website.fallback, "A bundle without the key")
    }

    // MARK: Apple's age range

    /// The customer app's rule (IzzyClipzTests/AgeCheckTests.swift): one gate, 13. Under it, the
    /// range's highest age is 12 or less (its lowest is open); at or over it, the lowest age is 13
    /// or more. Anything else isn't known to be under 13, so the app carries on.
    func testWhatIOSsAnswerMeans() async {
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

    func testOnlyUnder13ShowsTheScreenForChildren() async {
        XCTAssertTrue(AgeCheck.showsUnderAgeScreen(.under13))
        for outcome: AgeCheck.Outcome in [.notAsked, .declined, .thirteenOrOlder, .unclear, .failed] {
            XCTAssertFalse(AgeCheck.showsUnderAgeScreen(outcome), "\(outcome) carries on")
        }
        XCTAssertTrue(AgeCheck.message.contains("parent or guardian"))
        XCTAssertTrue(AgeCheck.message.contains("call the shop"))
    }

    func testTheAppAndTheDemoAskButTestsNever() async {
        XCTAssertFalse(AppEnvironment.sample().asksForAgeRange, "UI tests and previews: no iOS sheet")
        XCTAssertFalse(AppEnvironment.sample(arguments: [LaunchArgument.uiTesting, LaunchArgument.signedIn]).asksForAgeRange)
        XCTAssertTrue(DemoMode.environment().asksForAgeRange, "The demo, like the real app")
    }

    // MARK: Tap to Pay's location question

    func testTheLocationQuestionGivesStripesReason() async throws {
        // The committed Info.plist, as the app ships it.
        let url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("IzzyClipzBusiness/Info.plist")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("The repository isn't next to the test bundle here.")
        }
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(
            plist["NSLocationWhenInUseUsageDescription"] as? String,
            "Stripe needs to know where card payments are taken, to reduce fraud and disputes, so it checks this iPhone's location while you take a payment with Tap to Pay on iPhone. Without it, Tap to Pay is turned off."
        )
        XCTAssertEqual(plist["IzzyWebsiteURL"] as? String, "$(IZZY_WEBSITE_URL)")
    }
}
