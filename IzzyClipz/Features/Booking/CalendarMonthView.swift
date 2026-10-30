import SwiftUI

/// One month of the booking calendar on an `ink2` card with a hairline: "OCTOBER 2026" with
/// previous and next buttons, the weekday initials, and a Sunday-first grid of days.
///
/// Only days that can be booked are tappable; the rest are bone at 40% (still findable). Today has
/// a bone ring. The selected day is a bone disc with ink, bold digits, never red (red is for the
/// Continue button). There are no "has openings" dots: the app knows the shop's hours, not the
/// barbers' calendars.
struct CalendarMonthView: View {
    let page: MonthPage
    let calendar: BookingCalendar
    /// The appointment's length, which decides whether a day still has room.
    let durationMinutes: Int
    let now: Date
    let today: CalendarDay
    let selectedDay: CalendarDay?
    let canShowPrevious: Bool
    let canShowNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSelect: (CalendarDay) -> Void

    private static let weekdayInitials = ["S", "M", "T", "W", "T", "F", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: Theme.Space.xxs) {
            header
            weekdayRow
            // A new identity per month, so changing months cross-fades the
            // whole grid in place instead of shuffling cells.
            ZStack {
                dayGrid
                    .id(page.id)
                    .transition(AnyTransition.opacity)
            }
        }
        .padding(6)
        .background(Theme.ink2, in: shape)
        .overlay(shape.strokeBorder(Theme.line))
    }

    private var header: some View {
        HStack(spacing: 0) {
            title
                .textRole(.displayM)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendarMonthTitle")
            Spacer(minLength: Theme.Space.s)
            CalendarMonthArrowButton(
                symbol: Symbol.back,
                label: "Previous month",
                identifier: "calendarPrevMonth",
                isEnabled: canShowPrevious,
                action: onPrevious
            )
            CalendarMonthArrowButton(
                symbol: Symbol.chevron,
                label: "Next month",
                identifier: "calendarNextMonth",
                isEnabled: canShowNext,
                action: onNext
            )
        }
        .padding(.leading, 10)
    }

    /// "OCTOBER" in bone and "2026" in smoke.
    private var title: Text {
        let year = String(page.year)
        let suffix = " \(year)"
        guard page.title.hasSuffix(suffix) else {
            return Text(page.title).foregroundStyle(Theme.bone)
        }
        let month = String(page.title.dropLast(suffix.count))
        return Text("\(Text(month).foregroundStyle(Theme.bone)) \(Text(year).foregroundStyle(Theme.smoke))")
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: Self.weekdayInitials[index])
                    .textRole(.monoTag)
                    .foregroundStyle(Theme.smoke)
                    .frame(maxWidth: .infinity, minHeight: 18)
            }
        }
        .accessibilityHidden(true)
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<page.leadingBlanks, id: \.self) { _ in
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            ForEach(page.days) { day in
                cell(for: day)
            }
        }
    }

    private func cell(for day: CalendarDay) -> CalendarMonthDayCell {
        let availability = calendar.availability(of: day, durationMinutes: durationMinutes, now: now)
        let isToday = day == today
        return CalendarMonthDayCell(
            day: day,
            isBookable: availability.isBookable,
            isToday: isToday,
            isSelected: day == selectedDay,
            accessibilityText: Self.accessibilityText(for: day, availability: availability, isToday: isToday, calendar: calendar),
            action: { onSelect(day) }
        )
    }

    /// "Thursday, October 30, today, available".
    static func accessibilityText(
        for day: CalendarDay,
        availability: DayAvailability,
        isToday: Bool,
        calendar: BookingCalendar
    ) -> String {
        var parts = [calendar.longLabel(for: day)]
        if isToday { parts.append("today") }
        parts.append(statusText(for: availability))
        return parts.joined(separator: ", ")
    }

    static func statusText(for availability: DayAvailability) -> String {
        switch availability {
        case .open: return "available"
        case .closed: return "closed"
        case .past: return "past"
        case .noTimesLeft: return "no times left"
        case .outsideWindow: return "not open for booking yet"
        }
    }
}

/// A previous/next month chevron: bone, or bone at 40% when there's no month that way. 44 pt.
private struct CalendarMonthArrowButton: View {
    let symbol: String
    let label: String
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(isEnabled ? Theme.bone : Theme.boneDisabled)
                .frame(minWidth: Theme.minimumTapSize, minHeight: Theme.minimumTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// One day on the grid: at least 44 pt tall, as wide as a seventh of the card.
private struct CalendarMonthDayCell: View {
    let day: CalendarDay
    let isBookable: Bool
    let isToday: Bool
    let isSelected: Bool
    let accessibilityText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: String(day.day))
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(textColor)
                .padding(.vertical, Theme.Space.xxs)
                .frame(maxWidth: .infinity, minHeight: Theme.minimumTapSize)
                // A circle inscribed in the cell, about 40 pt at the default size.
                .background { selectionDisc }
                .overlay { todayRing }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isBookable)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("day-\(day.id)")
    }

    /// Tabular digits, so the columns line up; bold for today and the selected day.
    private var font: Font {
        let face: BrandFont = isSelected || isToday ? .bold : (isBookable ? .semiBold : .medium)
        return face.font(size: 16, relativeTo: .body).monospacedDigit()
    }

    /// Selection is bone with ink, never red. Days that can't be booked are bone at 40%.
    private var textColor: Color {
        if isSelected { return Theme.ink }
        if !isBookable { return Theme.boneDisabled }
        return Theme.bone
    }

    @ViewBuilder private var selectionDisc: some View {
        if isSelected {
            Circle()
                .fill(Theme.bone)
                .padding(2)
                .transition(AnyTransition.opacity)
        }
    }

    @ViewBuilder private var todayRing: some View {
        if isToday && !isSelected {
            Circle()
                .strokeBorder(Theme.bone, lineWidth: 2)
                .padding(2)
        }
    }
}
