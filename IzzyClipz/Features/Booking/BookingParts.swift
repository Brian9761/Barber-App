import SwiftUI

// Pieces the booking steps share: the step header ("Step 2 of 5" over a thin bar, then the
// step's question), the navigation bar with "Start over", section labels and summary rows.

// MARK: - Step chrome

extension View {
    /// A booking step's navigation bar: its short name as the title (what the next step's back
    /// button and VoiceOver's screen change use), and on steps 2–5 a "Start over" button that goes
    /// back to step 1. The bar stays native, so the back button and swipe-back work as everywhere.
    func bookingStepChrome(title: String, showsStartOver: Bool = true) -> some View {
        modifier(BookingStepChrome(title: title, showsStartOver: showsStartOver))
    }
}

private struct BookingStepChrome: ViewModifier {
    let title: String
    let showsStartOver: Bool

    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsStartOver {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Start over") {
                            router.finishBooking()
                        }
                        .accessibilityHint("Goes back to picking a service")
                        .accessibilityIdentifier("bookingStartOver")
                    }
                }
            }
    }
}

/// The top of a booking step: "Step 2 of 5" and a thin bar showing how far along it is, the step's
/// question in a title, and a line under it.
struct BookingStepHeader: View {
    let step: Int
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Step \(step) of \(BookingStep.count)")
                    .textRole(.label)
                    .foregroundStyle(Theme.smoke)
                StepProgressBar(step: step, total: BookingStep.count)
                    .frame(maxWidth: 160)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step) of \(BookingStep.count)")
            .accessibilityIdentifier("bookingStep")

            Text(title)
                .textRole(.displayL)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label over a group of rows, "Haircuts", with its symbol.
struct BookingSectionLabel: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.smoke)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(.headline)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Summary

/// A label and a value on one line ("Barber  Carlos"), or stacked when they don't fit, with an
/// optional "Change" button.
struct SummaryRow: View {
    let label: String
    let value: String
    var detail: String?
    var changeLabel: String?
    var onChange: (() -> Void)?
    var identifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .textRole(.label)
                    .foregroundStyle(Theme.smoke)
                Text(value)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let onChange {
                Button(changeLabel ?? "Change", action: onChange)
                    .buttonStyle(.textLink(color: Theme.electric))
                    .accessibilityLabel("\(changeLabel ?? "Change") \(label.lowercased())")
                    .accessibilityIdentifier(identifier.map { "change-\($0)" } ?? "change")
            }
        }
        .padding(.vertical, Theme.Space.xs)
    }
}

/// A hairline between summary rows. Decoration only.
struct SummaryDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Wording

/// Wording the booking screens share.
enum BookingFlowCopy {
    /// "with Carlos", or "with any barber".
    static func withBarber(_ choice: BookingChoice) -> String {
        choice.barberID == nil ? "with any barber" : "with \(choice.barberName)"
    }

    /// "Flowxbori, Cristian or Julian".
    static func list(_ names: [String], conjunction: String = "or") -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " \(conjunction) " + (names.last ?? "")
        }
    }

    /// "Times are in Oceanside time (Pacific).", but only when this iPhone is set to another time
    /// zone, where shop times could pass for local ones.
    static func timeZoneNote(at date: Date, deviceTimeZone: TimeZone = .current) -> String? {
        let shopOffset = AppData.shop.timeZone.secondsFromGMT(for: date)
        guard deviceTimeZone.secondsFromGMT(for: date) != shopOffset else { return nil }
        return "Times are in Oceanside time (Pacific), where the shop is."
    }

    /// "Pay at the shop with a credit card or gift card."
    static var payAtShop: String {
        let methods = AppData.shop.paymentMethods.map { $0.lowercased() }
        return "Pay at the shop with a \(list(methods))."
    }
}
