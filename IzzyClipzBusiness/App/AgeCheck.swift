import Foundation

/// Apple's Declared Age Range check at launch, which California's Digital Age Assurance Act (AB 1043,
/// as amended by AB 1856) asks of every app from January 1, 2027 (docs/legal/research.md §4.2 and
/// §18 item 18).
///
/// On iOS 26 and later the app asks iOS whether age rules apply to the person using this iPhone
/// (`AgeRangeService.isEligibleForAgeFeatures`, iOS 26.2 and later: where a law requires the signal),
/// and only then for their age range against one age gate, 13. AB 1856 bars asking where no law
/// requires it, so outside those places nothing is asked. iOS shows its own sheet the first time,
/// and remembers the answer.
///
/// Only an answer that puts the person under 13 changes anything, by the same rule as the customer
/// app (`IzzyClipz/App/AgeCheck.swift`): the app shows `UnderAgeView` (the app is for the shop's
/// team; a parent or guardian books for a child) and takes no details. Nothing is stored: the answer
/// lives in memory for this launch, and every other answer (13 or older, declined, unclear, an
/// error, an older iOS) just carries on.
enum AgeCheck {
    enum Outcome: Equatable, Sendable {
        /// Not asked: an older iOS, a build without the check, or no law requires it here.
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

    /// What iOS's shared range means, from its bounds, as in the customer app: under 13 when its
    /// highest age is below 13, 13 or older when its lowest age is at least 13 (`nil` bounds are
    /// open: below the lowest gate, or at or above the highest), and otherwise unclear.
    static func outcome(lowerBound: Int?, upperBound: Int?) -> Outcome {
        if let upperBound, upperBound < ageGate { return .under13 }
        if let lowerBound, lowerBound >= ageGate { return .thirteenOrOlder }
        return .unclear
    }

    /// Only an under-13 answer shows the screen for children instead of the app.
    static func showsUnderAgeScreen(_ outcome: Outcome) -> Bool {
        outcome == .under13
    }

    /// What the screen for children says.
    static let title = "Izzy Clipz Business is for the shop's team"
    static let message = "This app is for the barbers at Izzy Clipz Barbershop. To book a haircut, ask a parent or guardian to book for you in the Izzy Clipz app, or call the shop."
}
