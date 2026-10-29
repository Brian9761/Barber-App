import SwiftUI

/// One month of the booking calendar: the month's name with previous and next
/// buttons, the weekday initials, and a Sunday-first grid of days.
///
/// Only days that can be booked are tappable. Today has a royal blue ring and
/// the selected day is filled red.
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
        VStack(spacing: 10) {
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
        .padding(.vertical, 6)
        .card(padding: 8)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(page.title)
                .font(.display(.title2))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendarMonthTitle")
            Spacer(minLength: 8)
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
        .padding(.leading, 8)
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: Self.weekdayInitials[index])
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
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

/// A round previous/next month button.
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
                .foregroundStyle(isEnabled ? Theme.blue : Theme.tertiaryText)
                .frame(width: 44, height: 44)
                .background(isEnabled ? Theme.tint : Theme.ink.opacity(0.04), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// One day on the grid.
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
                .font(.body.weight(isSelected || isToday ? .bold : .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background { selectionCircle }
                .overlay { todayRing }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!isBookable)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("day-\(day.id)")
    }

    private var textColor: Color {
        if isSelected { return .white }
        if !isBookable { return Theme.tertiaryText }
        return isToday ? Theme.blue : Theme.ink
    }

    @ViewBuilder private var selectionCircle: some View {
        if isSelected {
            Circle()
                .fill(Theme.red)
                .padding(1)
                .shadow(color: Theme.red.opacity(0.32), radius: 6, y: 3)
                .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    @ViewBuilder private var todayRing: some View {
        if isToday && !isSelected {
            Circle()
                .strokeBorder(Theme.blue, lineWidth: 2)
                .padding(2)
        }
    }
}
