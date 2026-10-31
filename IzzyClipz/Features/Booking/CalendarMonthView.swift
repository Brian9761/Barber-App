import SwiftUI

/// One month of the booking calendar on an `ink2` card: the month with previous and next buttons,
/// the weekday initials, and a Sunday-first grid of days.
///
/// Days come from the shop's live calendar: a day with open times is bone with a dot under it and
/// can be picked; days without openings, closed days, past days and days not checked yet are bone
/// at 40% and can't be. Today has a ring. The picked day is a bone disc with ink digits, never
/// red (red is for the Continue button).
struct CalendarMonthView: View {
    let page: MonthPage
    let today: CalendarDay
    let selectedDay: CalendarDay?
    let status: (CalendarDay) -> AvailabilityLoader.DayStatus
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
            dayGrid
        }
        .padding(6)
        .background(Theme.ink2, in: shape)
        .overlay(shape.strokeBorder(Theme.line))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(page.title)
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
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

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: Self.weekdayInitials[index])
                    .textRole(.label)
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
        let dayStatus = status(day)
        let isToday = day == today
        return CalendarMonthDayCell(
            day: day,
            isBookable: dayStatus.isBookable,
            isToday: isToday,
            isSelected: day == selectedDay,
            accessibilityText: Self.accessibilityText(for: day, status: dayStatus, isToday: isToday),
            action: { onSelect(day) }
        )
    }

    /// "Thursday, October 30, today, open times".
    static func accessibilityText(for day: CalendarDay, status: AvailabilityLoader.DayStatus, isToday: Bool) -> String {
        var parts = [AppData.bookingCalendar.longLabel(for: day)]
        if isToday { parts.append("today") }
        parts.append(statusText(for: status))
        return parts.joined(separator: ", ")
    }

    static func statusText(for status: AvailabilityLoader.DayStatus) -> String {
        switch status {
        case .open(let slots): return slots.count == 1 ? "1 open time" : "\(slots.count) open times"
        case .noOpenings: return "no openings"
        case .closed: return "closed"
        case .past: return "past"
        case .tooFar: return "not open for booking yet"
        case .notLoaded: return "checking"
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
            VStack(spacing: 2) {
                Text(verbatim: String(day.day))
                    .font(font)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(textColor)
                // Says "this day has times", with more than color alone.
                Circle()
                    .fill(isSelected ? Theme.ink : Theme.electric)
                    .frame(width: 4, height: 4)
                    .opacity(isBookable ? 1 : 0)
            }
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
        let weight: Font.Weight = isSelected || isToday ? .bold : (isBookable ? .semibold : .regular)
        return Font.system(.body, design: .default, weight: weight).monospacedDigit()
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
