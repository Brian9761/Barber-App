import SwiftUI

// Pieces the four booking steps and the "Did you book it?" sheet share: the step indicator in the
// navigation bar, the step title, the mono section labels and the bone ticket.

// MARK: - Step chrome

extension View {
    /// A booking step's navigation bar: "STEP 3 / 4 · TIME" over the pole progress bar where the
    /// title would be, and on steps 2–4 an ✕ that goes back to step 1. The bar stays native, so
    /// the back button and swipe-back work as everywhere else; `title` is what the next step's back
    /// button and VoiceOver's screen change use.
    func bookingStepChrome(step: Int, name: String, title: String) -> some View {
        modifier(BookingStepChrome(step: step, name: name, title: title))
    }
}

private struct BookingStepChrome: ViewModifier {
    let step: Int
    let name: String
    let title: String

    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BookingStepIndicator(step: step, name: name)
                }
                if step > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        // A plain symbol: on iOS 26 the bar draws its own glass circle around it.
                        Button {
                            router.bookingPath = []
                        } label: {
                            Image(systemName: Symbol.close)
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Start over")
                        .accessibilityHint("Goes back to picking a service")
                        .accessibilityIdentifier("bookingStartOver")
                    }
                }
            }
    }
}

/// "STEP 3 / 4 · TIME" over the pole progress bar (finished steps striped, the current one spins
/// once as it arrives). It lives in the navigation bar, which has a fixed height, so it stops
/// growing at xLarge; `BookingStepTitle` repeats the tag in the content at accessibility sizes.
struct BookingStepIndicator: View {
    static let totalSteps = 4

    let step: Int
    /// The step's short name: "Service", "Barber", "Time", "Review".
    let name: String

    var body: some View {
        VStack(spacing: 5) {
            Text(Self.tag(step: step, name: name))
                .textRole(.monoTag)
                .foregroundStyle(Theme.smoke)
                .lineLimit(1)
                .fixedSize()
            PoleProgressBar(step: step, total: Self.totalSteps)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(Self.totalSteps): \(name)")
    }

    /// "Step 3 / 4 · Time" (set in capitals).
    static func tag(step: Int, name: String) -> String {
        "Step \(step) / \(totalSteps) · \(name)"
    }
}

// MARK: - Titles and labels

/// A step's title in Display L ("PICK A TIME"), with an optional line under it.
struct BookingStepTitle: View {
    let step: Int
    let name: String
    let title: String
    var subtitle: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if dynamicTypeSize.isAccessibilitySize {
                // The navigation bar's tag stops at xLarge; here it grows with the text.
                // VoiceOver already heard it from the bar.
                Kicker(BookingStepIndicator.tag(step: step, name: name))
                    .accessibilityHidden(true)
            }
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

/// A mono label over a group of rows, with a hairline running to the edge: "✂ HAIRCUTS ———".
/// The hairline is decoration only.
struct BookingSectionLabel: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.smoke)
                    .accessibilityHidden(true)
            }
            Text(title)
                .textRole(.monoTag)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Rectangle()
                .fill(Theme.line)
                .frame(minWidth: 12, maxWidth: .infinity)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .padding(.top, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Ticket

/// A booking on a bone ticket: the day and the time on two lines in Display M, "Haircut with
/// Carlos" under them, and a stub with the price and length behind a perforated rule with two
/// notches. At accessibility sizes the stub moves under the date. VoiceOver reads it as one line.
///
/// It never shows the time in red (red is for actions) and claims no more than the app knows: the
/// tag is "Your pick" before Squire, "Saved on this iPhone" after.
struct BookingTicket: View {
    /// A short mono tag above the date, e.g. "Your pick".
    var kicker: String?
    let start: Date
    let serviceName: String
    /// "with Carlos", or "with whoever's free first".
    let withBarber: String
    let priceLabel: String
    let durationMinutes: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Wide enough for "$55–$60" or "From $80" on two lines.
    @ScaledMetric(relativeTo: .title2) private var stubWidth: CGFloat = 104
    private let calendar = AppData.bookingCalendar

    /// The perforation's notches.
    private static let notchDiameter: CGFloat = 18

    var body: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        layout {
            details
            stub(isStacked: isStacked)
                .overlay(alignment: isStacked ? .top : .leading) {
                    perforation(isStacked: isStacked)
                }
        }
        // Equal-height columns, so the stub (and its rule) runs the ticket's full height.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.ink)
        .environment(\.surfaceTone, .bone)
        .background(Theme.bone, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        // The notches cut through the bone (`destinationOut`) within this group only.
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let kicker {
                Kicker(kicker)
            }
            // The day over the time, never on one line: "WED, NOV 25 · 12:30 PM" overflows.
            VStack(alignment: .leading, spacing: 0) {
                Text(dayLine)
                    .fixedSize(horizontal: false, vertical: true)
                Text(calendar.timeLabel(for: start))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .textRole(.displayM)
            Text("\(serviceName) \(withBarber)")
                .textRole(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func stub(isStacked: Bool) -> some View {
        let content = VStack(alignment: isStacked ? .leading : .center, spacing: Theme.Space.xxs) {
            Text(priceLabel)
                .textRole(.priceL)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(isStacked ? .leading : .center)
            Text(DurationText.short(minutes: durationMinutes))
                .textRole(.monoNumber)
                .foregroundStyle(Theme.smokeDark)
                .multilineTextAlignment(isStacked ? .leading : .center)
        }
        .padding(isStacked ? 18 : 12)
        if isStacked {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
                .frame(width: stubWidth)
                .frame(maxHeight: .infinity)
        }
    }

    /// The dashed rule between the ticket and its stub, with a notch where it meets each edge.
    @ViewBuilder private func perforation(isStacked: Bool) -> some View {
        let d = Self.notchDiameter
        let dash = StrokeStyle(lineWidth: 2, dash: [5, 4])
        if isStacked {
            HStack(spacing: 0) {
                notch.offset(x: -d / 2)
                TicketRule(isVertical: false)
                    .stroke(Theme.ink.opacity(0.25), style: dash)
                    .frame(height: 2)
                    .padding(.horizontal, 4)
                notch.offset(x: d / 2)
            }
            .frame(height: d)
            .offset(y: -d / 2)
        } else {
            VStack(spacing: 0) {
                notch.offset(y: -d / 2)
                TicketRule(isVertical: true)
                    .stroke(Theme.ink.opacity(0.25), style: dash)
                    .frame(width: 2)
                    .padding(.vertical, 4)
                notch.offset(y: d / 2)
            }
            .frame(width: d)
            .offset(x: -d / 2)
        }
    }

    private var notch: some View {
        Circle()
            .frame(width: Self.notchDiameter, height: Self.notchDiameter)
            .blendMode(.destinationOut)
    }

    /// "Thu, Oct 30", with "Oct 30" held together so a long date breaks after the comma.
    private var dayLine: String {
        calendar.shortLabel(for: calendar.day(containing: start))
            .replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: ",\u{00A0}", with: ", ")
    }

    private var accessibilityText: String {
        [
            kicker,
            "\(serviceName) \(withBarber)",
            calendar.dateTimeLabel(for: start),
            priceLabel.spokenRanges,
            DurationText.spoken(minutes: durationMinutes),
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// A straight line down the middle of its frame, for the ticket's dashed rule.
private struct TicketRule: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
