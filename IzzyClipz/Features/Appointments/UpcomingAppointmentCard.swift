import SwiftUI
import UIKit

/// A saved appointment as a bone ticket: the day and the time on two lines, the service and the
/// barber, and a stub with the price and the length, torn off along a dashed line between two
/// notches. Tapping the ticket opens its options (Add to Calendar, Directions, Call the shop, Remove
/// from this iPhone), and "Add to Calendar" also sits under it.
///
/// It's the client's own note of a Squire booking, so "Remove" only takes it out of the app;
/// changes and cancellations go through the shop. No check-in barcode and no "set" badge: the app
/// only knows the client said they booked it.
struct UpcomingAppointmentCard: View {
    let appointment: Appointment
    /// The soonest one reads "Next appointment"; later ones "Upcoming".
    var isNext = true

    @Environment(AppRouter.self) private var router
    @Environment(AppointmentStore.self) private var appointments
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingRemoval = false
    @State private var isChoosingMaps = false
    @State private var showsNumber = false
    private let calendar = AppData.bookingCalendar
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            optionsMenu
                .confirmationDialog("Directions to \(shop.name)", isPresented: $isChoosingMaps, titleVisibility: .visible) {
                    Button("Apple Maps") { openURL(shop.appleMapsDirectionsURL) }
                    Button("Google Maps") { openURL(shop.googleMapsDirectionsURL) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(shop.address.singleLine)
                }
            addToCalendarLink
                .alert("Call \(shop.name)", isPresented: $showsNumber) {
                    Button("Copy Number") {
                        UIPasteboard.general.string = shop.phone.display
                    }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("This device can't make calls. Reach the shop at \(shop.phone.display).")
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upcomingAppointment")
        .confirmationDialog("Remove this appointment?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                withAnimation(reduceMotion ? nil : .snappy) {
                    appointments.remove(appointment.id)
                }
            }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("This only removes it from the app. To change or cancel the booking, call the shop at \(shop.phone.display).")
        }
    }

    // MARK: Parts

    /// The ticket itself, as the button that opens the appointment's options.
    private var optionsMenu: some View {
        Menu {
            Section {
                Button {
                    router.addToCalendar(appointment)
                } label: {
                    Label("Add to Calendar", systemImage: Symbol.calendarAdd)
                }
                Button {
                    isChoosingMaps = true
                } label: {
                    Label("Directions", systemImage: Symbol.directions)
                }
                .accessibilityIdentifier("appointmentDirections")
            }
            Section("To change or cancel") {
                Button {
                    openURL(shop.phone.callURL) { accepted in
                        if !accepted { showsNumber = true }
                    }
                } label: {
                    Label("Call the shop", systemImage: Symbol.call)
                }
            }
            Section {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Label("Remove from this iPhone", systemImage: Symbol.remove)
                }
                .accessibilityIdentifier("removeAppointmentButton")
            }
        } label: {
            AppointmentTicket(
                tag: isNext ? "Next appointment" : "Upcoming",
                day: dayLine,
                time: calendar.timeLabel(for: appointment.start),
                withLine: withLine,
                price: appointment.priceLabel,
                duration: appointment.durationLabel
            )
        }
        .menuStyle(.button)
        .buttonStyle(.pressable)
        .menuOrder(.fixed)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Shows options: add to Calendar, directions, call the shop, or remove it from this iPhone")
        .accessibilityIdentifier("appointmentMoreButton")
    }

    /// The one follow-up most people want after saving: put it in their calendar.
    private var addToCalendarLink: some View {
        Button {
            router.addToCalendar(appointment)
        } label: {
            Label("Add to Calendar", systemImage: Symbol.calendarAdd)
        }
        .buttonStyle(.textLink(color: Theme.bone))
        .padding(.leading, 4)
        // Several tickets can be stacked (Book step 1): say which one this is for.
        .accessibilityHint("\(withLine), \(longDay)")
        .accessibilityIdentifier("appointmentAddToCalendar")
    }

    // MARK: Text

    /// "Fri, Oct 30", with "Oct 30" held together so a long date breaks after the comma.
    private var dayLine: String {
        calendar.shortLabel(for: calendar.day(containing: appointment.start))
            .replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: ",\u{00A0}", with: ", ")
    }

    /// "Haircut with Carlos", or "Haircut with the first available barber".
    private var withLine: String {
        let who = appointment.barberID == nil ? "the first available barber" : appointment.barberName
        return "\(appointment.serviceName) with \(who)"
    }

    /// "Friday, October 30 at 2:30 PM".
    private var longDay: String {
        let day = calendar.longLabel(for: calendar.day(containing: appointment.start))
        return "\(day) at \(calendar.timeLabel(for: appointment.start))"
    }

    /// "Next appointment, Friday, October 30 at 2:30 PM, Haircut with Carlos, $45, 45 minutes".
    private var accessibilitySummary: String {
        [
            isNext ? "Next appointment" : "Upcoming appointment",
            longDay,
            withLine,
            appointment.priceLabel.spokenRanges,
            DurationText.spoken(minutes: appointment.durationMinutes),
        ].joined(separator: ", ")
    }
}

// MARK: - The ticket

/// The bone ticket: a column with the details, a dashed perforation between two half-circle
/// notches, and a stub with the price and the length. From xxxLarge text the stub moves under the
/// details and the perforation turns horizontal, with the notches on the sides.
private struct AppointmentTicket: View {
    let tag: String
    /// "Fri, Oct 30".
    let day: String
    /// "2:30 PM".
    let time: String
    /// "Haircut with Carlos".
    let withLine: String
    /// "$45", or a range like "$35–$40".
    let price: String
    /// "45 min".
    let duration: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The stub is never narrower than this, so short prices still look like a stub.
    private static let stubMinimumWidth: CGFloat = 96

    var body: some View {
        let isStacked = dynamicTypeSize >= .xxxLarge
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        layout {
            details
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .anchorPreference(key: TicketDetailsBounds.self, value: .bounds) { $0 }
            stub(isStacked: isStacked)
        }
        // Both columns as tall as the taller one, so the stub's perforation runs the full height.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.ink)
        .backgroundPreferenceValue(TicketDetailsBounds.self) { anchor in
            GeometryReader { proxy in
                let perforation = anchor.map { bounds -> TicketShape.Perforation in
                    let frame = proxy[bounds]
                    return isStacked ? .horizontal(y: frame.maxY) : .vertical(x: frame.maxX)
                }
                ZStack {
                    TicketShape(perforation: perforation).fill(Theme.bone)
                    if let perforation {
                        TicketPerforation(perforation: perforation)
                            .stroke(Theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Text(tag)
                    .textRole(.label)
                    .foregroundStyle(Theme.smokeDark)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Says the ticket has options; the whole ticket is the button.
                Image(systemName: Symbol.more)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            // The day over the time, both in Display M. Tighter than the font's own line height,
            // like the spec's 30/27.
            VStack(alignment: .leading, spacing: -5) {
                Text(day)
                    .fixedSize(horizontal: false, vertical: true)
                Text(time)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .textRole(.displayM)
            .padding(.top, Theme.Space.xxs)
            Text(withLine)
                .textRole(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xs)
        }
        .multilineTextAlignment(.leading)
        .padding(.leading, Theme.Space.xl)
        .padding(.trailing, Theme.Space.l)
        .padding(.vertical, Theme.Space.l + 2)
    }

    @ViewBuilder private func stub(isStacked: Bool) -> some View {
        if isStacked {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                    priceText
                    Spacer(minLength: 0)
                    durationText
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    priceText
                    durationText
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                priceText
                durationText
            }
            // As wide as the price or the length needs, never clipped or shrunk.
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Space.l)
            .frame(minWidth: Self.stubMinimumWidth, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var priceText: some View {
        Text(price)
            .textRole(.priceL)
            .foregroundStyle(Theme.ink)
    }

    private var durationText: some View {
        Text(duration)
            .textRole(.detail)
            .foregroundStyle(Theme.smokeDark)
    }
}

/// Where the details column ends, so the ticket knows where to cut its notches.
private struct TicketDetailsBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A rounded ticket with a half-circle notch bitten out of each end of its perforation.
private struct TicketShape: Shape {
    enum Perforation {
        /// A vertical tear line at `x`: notches in the top and bottom edges.
        case vertical(x: CGFloat)
        /// A horizontal tear line at `y`: notches in the left and right edges.
        case horizontal(y: CGFloat)
    }

    /// `nil` until the layout is known: a plain rounded ticket.
    var perforation: Perforation?
    var cornerRadius: CGFloat = Theme.Radius.tile
    var notchRadius: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let ticket = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        guard let perforation else { return ticket }
        let r = notchRadius
        let centres: [CGPoint]
        switch perforation {
        case .vertical(let x):
            centres = [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)]
        case .horizontal(let y):
            centres = [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)]
        }
        var notches = Path()
        for centre in centres {
            notches.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
        }
        return ticket.subtracting(notches)
    }
}

/// The dashed tear line between the notches.
private struct TicketPerforation: Shape {
    let perforation: TicketShape.Perforation
    /// Clear of the notches.
    var inset: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch perforation {
        case .vertical(let x):
            path.move(to: CGPoint(x: x, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: x, y: rect.maxY - inset))
        case .horizontal(let y):
            path.move(to: CGPoint(x: rect.minX + inset, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: y))
        }
        return path
    }
}
