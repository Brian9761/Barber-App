import SwiftUI

/// Step 3: the day and start time, on the app's own calendar.
///
/// The calendar knows the shop's hours, not each barber's bookings, so it
/// offers every start time that fits before closing. Squire confirms the
/// real opening in the last step. Everything is in the shop's time zone.
struct ChooseTimeView: View {
    let choice: BookingChoice

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var now: Date
    @State private var selectedDay: CalendarDay?
    @State private var selectedSlot: TimeSlot?
    /// The month on screen, as `MonthPage.id` ("2026-10").
    @State private var displayedMonthID: String
    /// Counts the client's own day taps, so the app moving the day on by
    /// itself doesn't make the phone tick.
    @State private var dayPickCount = 0
    /// Why the picked time went away, when the clock took it.
    @State private var expiredNote: String?

    private let calendar = AppData.bookingCalendar

    init(choice: BookingChoice) {
        self.choice = choice
        let calendar = AppData.bookingCalendar
        let now = Date()
        let first = calendar.firstBookableDay(durationMinutes: choice.durationMinutes, now: now)
        _now = State(initialValue: now)
        _selectedDay = State(initialValue: first)
        _selectedSlot = State(initialValue: nil)
        _displayedMonthID = State(initialValue: Self.monthID(for: first ?? calendar.day(containing: now)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StepHeader(
                    step: 3,
                    of: 4,
                    title: "Pick a day & time",
                    subtitle: "Choose a day, then a start time that suits you."
                )
                BookingChoiceCard(choice: choice)
                monthCalendar
                ChooseTimeDayCard(
                    calendar: calendar,
                    notice: expiredNote,
                    day: selectedDay,
                    today: today,
                    durationMinutes: durationMinutes,
                    now: now,
                    selectedSlot: selectedSlot,
                    onSelect: selectSlot
                )
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.gutter)
        }
        .screenBackground()
        .navigationTitle("Day & Time")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            ChooseTimeContinueBar(
                subtitle: selectedSlot.map { calendar.dateTimeLabel(for: $0.start) },
                onContinue: continueToReview
            )
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        // Keeps today's times honest while the client lingers on the calendar.
        .task {
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                refresh()
            }
        }
        .sensoryFeedback(.selection, trigger: dayPickCount)
        .sensoryFeedback(.selection, trigger: selectedSlot) { _, newValue in
            newValue != nil
        }
    }

    // MARK: Calendar

    @ViewBuilder private var monthCalendar: some View {
        let pages = months
        if let index = displayedIndex(in: pages) {
            CalendarMonthView(
                page: pages[index],
                calendar: calendar,
                durationMinutes: durationMinutes,
                now: now,
                today: today,
                selectedDay: selectedDay,
                canShowPrevious: index > 0,
                canShowNext: index < pages.count - 1,
                onPrevious: { showMonth(at: index - 1, in: pages) },
                onNext: { showMonth(at: index + 1, in: pages) },
                onSelect: selectDay
            )
        }
    }

    private var durationMinutes: Int {
        choice.durationMinutes
    }

    private var today: CalendarDay {
        calendar.day(containing: now)
    }

    private var months: [MonthPage] {
        calendar.months(now: now)
    }

    /// Where the displayed month is in `pages`, or the first month if it's gone.
    private func displayedIndex(in pages: [MonthPage]) -> Int? {
        guard !pages.isEmpty else { return nil }
        return pages.firstIndex { $0.id == displayedMonthID } ?? 0
    }

    private var footnote: String {
        let hours = "These are the shop's hours. Squire shows \(BookingFlowCopy.barberPossessive(choice)) real openings in the last step."
        // Checked on the day being looked at, which may be across a daylight
        // saving change from today. Noon is clear of the 2 AM switch.
        let reference = selectedSlot?.start
            ?? selectedDay.flatMap { calendar.date(on: $0, at: TimeOfDay(hour: 12)) }
            ?? now
        guard let zone = BookingFlowCopy.timeZoneNote(at: reference) else { return hours }
        return "\(hours) \(zone)"
    }

    static func monthID(for day: CalendarDay) -> String {
        MonthPage(year: day.year, month: day.month).id
    }

    // MARK: Actions

    private func showMonth(at index: Int, in pages: [MonthPage]) {
        guard pages.indices.contains(index) else { return }
        withAnimation(.snappy) {
            displayedMonthID = pages[index].id
        }
    }

    private func selectDay(_ day: CalendarDay) {
        guard day != selectedDay else { return }
        withAnimation(.snappy) {
            selectedDay = day
            // A time on another day doesn't carry over.
            selectedSlot = nil
            expiredNote = nil
            dayPickCount += 1
        }
    }

    private func selectSlot(_ slot: TimeSlot) {
        withAnimation(.snappy) {
            selectedSlot = slot
            expiredNote = nil
        }
    }

    private func continueToReview() {
        // A second tap while the review slides in mustn't push it twice.
        if let last = router.bookingPath.last, case .review = last { return }
        // A time that has just slipped inside the lead time still goes
        // through: the review warns about short-notice and passed times.
        guard let slot = selectedSlot else { return }
        router.bookingPath.append(.review(BookingPlan(choice: choice, start: slot.start)))
    }

    /// Catches up with the clock, e.g. after the app was in the background or
    /// the client came back from the review: a day or time that's no longer
    /// offered is dropped, and the first open day is picked if needed.
    private func refresh() {
        let current = Date()
        let droppedSlot = selectedSlot
        let oldDay = selectedDay
        let oldMonthID = oldDay.map(Self.monthID(for:))
        now = current
        if let day = selectedDay,
           calendar.availability(of: day, durationMinutes: durationMinutes, now: current).isBookable {
            if let slot = selectedSlot,
               !calendar.slots(on: day, durationMinutes: durationMinutes, now: current).contains(slot) {
                selectedSlot = nil
            }
        } else {
            let first = calendar.firstBookableDay(durationMinutes: durationMinutes, now: current)
            selectedDay = first
            selectedSlot = nil
            // Follows the new day only if the client was looking at the old
            // one's month, not browsing another.
            if let first, oldMonthID == nil || displayedMonthID == oldMonthID {
                displayedMonthID = Self.monthID(for: first)
            }
        }
        let pages = calendar.months(now: current)
        if !pages.contains(where: { $0.id == displayedMonthID }), let firstPage = pages.first {
            displayedMonthID = firstPage.id
        }
        if let droppedSlot, selectedSlot == nil {
            noteExpired(droppedSlot, on: oldDay)
        }
    }

    /// Says why the picked time went away, on screen and to VoiceOver.
    private func noteExpired(_ slot: TimeSlot, on oldDay: CalendarDay?) {
        let note: String
        if let oldDay, let newDay = selectedDay, newDay != oldDay {
            note = "\(slot.label) on \(calendar.shortLabel(for: oldDay)) is no longer available. Pick a time on \(calendar.longLabel(for: newDay))."
        } else {
            note = "\(slot.label) is no longer available. Pick another time."
        }
        expiredNote = note
        UIAccessibility.post(notification: .announcement, argument: note)
    }
}

// MARK: - Times for the selected day

/// The start times in one part of the day.
private struct ChooseTimeSlotGroup: Identifiable {
    let part: DayPart
    let slots: [TimeSlot]

    var id: String { part.id }
}

/// The selected day's name and hours, then its start times grouped into
/// morning, afternoon and evening.
private struct ChooseTimeDayCard: View {
    let calendar: BookingCalendar
    /// Why the picked time went away, if it did.
    let notice: String?
    let day: CalendarDay?
    let today: CalendarDay
    let durationMinutes: Int
    let now: Date
    let selectedSlot: TimeSlot?
    let onSelect: (TimeSlot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let notice {
                ChooseTimeExpiredNote(text: notice)
            }
            if let day {
                dayHeader(day)
            }
            let slots = currentSlots
            if slots.isEmpty {
                ChooseTimeEmptyMessage(text: emptyText)
                if day == nil {
                    CallButton {
                        Label("Call \(AppData.shop.phone.display)", systemImage: Symbol.call)
                    }
                    .buttonStyle(.secondary)
                }
            } else {
                ForEach(groups(of: slots)) { group in
                    ChooseTimeGroupView(group: group, selectedSlot: selectedSlot, onSelect: onSelect)
                }
            }
        }
        .card()
    }

    private func dayHeader(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(calendar.longLabel(for: day))
                .font(.display(.title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("selectedDayLabel")
            Label(hoursText(for: day), systemImage: Symbol.clock)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.blue)
        }
    }

    private var currentSlots: [TimeSlot] {
        guard let day else { return [] }
        return calendar.slots(on: day, durationMinutes: durationMinutes, now: now)
    }

    private func groups(of slots: [TimeSlot]) -> [ChooseTimeSlotGroup] {
        DayPart.allCases.compactMap { part -> ChooseTimeSlotGroup? in
            let matching = slots.filter { $0.part == part }
            return matching.isEmpty ? nil : ChooseTimeSlotGroup(part: part, slots: matching)
        }
    }

    /// "Open 10 AM – 7 PM", or "Closed".
    private func hoursText(for day: CalendarDay) -> String {
        guard let hours = calendar.clock.schedule.hours(on: day.weekday) else { return "Closed" }
        return "Open \(hours.label)"
    }

    private var emptyText: String {
        guard let day else {
            return "There are no open times in the next \(calendar.windowDays) days. Give the shop a call and they'll find you a time."
        }
        switch calendar.availability(of: day, durationMinutes: durationMinutes, now: now) {
        case .open:
            return "Pick a day above to see its times."
        case .noTimesLeft:
            if day == today {
                return "That's it for today. Pick another day for more times."
            }
            return "Nothing fits on this day. Pick another day."
        case .closed:
            return "The shop is closed on \(day.weekday.name)s. Pick another day."
        case .past:
            return "That day has passed. Pick another day."
        case .outsideWindow:
            let last = calendar.lastBookableDay(now: now)
            return "You can book up to \(calendar.shortLabel(for: last)). Pick an earlier day."
        }
    }
}

/// The picked time is no longer offered, e.g. it slipped inside the lead time.
private struct ChooseTimeExpiredNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: Symbol.warning)
                .foregroundStyle(Theme.soon)
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("slotExpiredNote")
    }
}

/// A friendly note when the day has no times.
private struct ChooseTimeEmptyMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Symbol.calendar)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// "Morning" and its time chips.
private struct ChooseTimeGroupView: View {
    let group: ChooseTimeSlotGroup
    let selectedSlot: TimeSlot?
    let onSelect: (TimeSlot) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(group.part.title)
                    .foregroundStyle(Theme.ink)
            } icon: {
                Image(systemName: Symbol.symbol(for: group.part))
                    .foregroundStyle(Theme.blue)
            }
            .font(.subheadline.weight(.bold))
            .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 10)], spacing: 10) {
                ForEach(group.slots) { slot in
                    ChooseTimeChip(slot: slot, isSelected: slot == selectedSlot) {
                        onSelect(slot)
                    }
                }
            }
        }
    }
}

/// One start time. Selected, it's filled royal blue.
private struct ChooseTimeChip: View {
    let slot: TimeSlot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: slot.label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? Theme.blue : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Theme.blue : Theme.ink.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: isSelected ? Theme.blue.opacity(0.28) : Color.clear, radius: 6, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(slot.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("time-\(slot.id)")
    }
}

// MARK: - Continue

/// The bar pinned above the tab bar: "Continue", with the picked time under it.
private struct ChooseTimeContinueBar: View {
    /// "Thu, Oct 30 at 2:30 PM", or `nil` before a time is picked.
    let subtitle: String?
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            VStack(spacing: 2) {
                Text("Continue")
                Text(subtitle ?? "Pick a time to continue")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.9)
            }
        }
        .buttonStyle(.primary)
        .disabled(subtitle == nil)
        .accessibilityIdentifier("continueToReview")
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
