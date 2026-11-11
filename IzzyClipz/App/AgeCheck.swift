import Foundation

/// Apple's Declared Age Range check at launch, which California's Digital Age Assurance Act (AB 1043,
/// as amended by AB 1856) asks of every app from January 1, 2027 (docs/legal/research.md §4.2 and
/// §18 item 18).
///
/// On iOS 26 and later the app asks iOS whether age rules apply to the person using this iPhone
/// (`AgeRangeService.isEligibleForAgeFeatures`, iOS 26.2 and later: where a law requires the signal),
/// and only then for their age range, against one age gate, 13. AB 1856 bars asking where no law
/// requires it, so elsewhere nothing is asked. iOS shows its own sheet the first time and remembers
/// the answer.
///
/// Only an answer that puts the person under 13 changes anything: the app shows a calm screen asking
/// a parent or guardian to book, with the shop's number, and takes no details (the Privacy Policy's
/// "Children": a parent or guardian books for a child). Nothing is stored: the answer lives in
/// memory for this launch. Every other answer (13 or older, declined, unclear, an error, an older
/// iOS) just carries on.
enum AgeCheck {
    enum Outcome: Equatable, Sendable {
        /// Not asked: an older iOS, UI tests, or no law requires it here.
        case notAsked
        /// The person chose not to share (possible where sharing isn't required).
        case declined
        case thirteenOrOlder
        case under13
        /// A range that reaches both sides of 13 (a region's own age gates can differ from the
        /// app's), or none: the app carries on, since it doesn't know the person is under 13.
        case unclear
        /// iOS couldn't answer (the app isn't entitled, say): the app carries on.
        case failed
    }

    /// The one age gate: 13, under which a parent or guardian books.
    static let ageGate = 13

    /// What iOS's shared range means, from its bounds: under 13 when its highest age is below 13,
    /// 13 or older when its lowest age is at least 13 (`nil` bounds are open: below the lowest gate,
    /// or at or above the highest).
    static func outcome(lowerBound: Int?, upperBound: Int?) -> Outcome {
        if let upperBound, upperBound < ageGate { return .under13 }
        if let lowerBound, lowerBound >= ageGate { return .thirteenOrOlder }
        return .unclear
    }

    /// Only someone under 13 sees the screen for a parent or guardian instead of the app.
    static func showsParentScreen(_ outcome: Outcome) -> Bool {
        outcome == .under13
    }

    /// `-fakeUnder13` (UI tests only): start as if iOS had said the person is under 13, to check the
    /// screen without iOS's sheet.
    static let fakeUnder13Argument = "-fakeUnder13"

    /// What a launch starts with: under 13 for that UI test, otherwise not asked yet.
    static func launchOutcome(arguments: [String], isUITesting: Bool) -> Outcome {
        isUITesting && arguments.contains(fakeUnder13Argument) ? .under13 : .notAsked
    }

    /// Whether to ask iOS at all: the real app and the demo version, never UI tests (iOS's sheet
    /// would get in their way, and they start from their own answer).
    static func asks(isUITesting: Bool) -> Bool {
        !isUITesting
    }

    /// What the screen for a parent or guardian says.
    static let title = "Please ask a parent or guardian to book"
    static let message = "Someone under 13 can't book in this app. Ask a parent or guardian to book for you, on their own phone or by calling the shop."
}
