import SwiftUI

/// Step 3: the day and start time, on the app's own calendar.
///
/// The calendar knows the shop's hours, not each barber's bookings, so it offers every start time
/// that fits before closing (from `BookingCalendar`, never a hard-coded list) and shows no "taken"
/// times. Squire confirms the real opening in the last step. Everything is in the shop's time zone.
///
/// The screen's one red is the Continue bar pinned above the tab bar; it stays `ink3` until a time
/// is picked. The picked day and time are bone, never red.
struct ChooseTimeView: View {
    let choice: BookingChoice

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Between `onAppear` and `onDisappear`: not covered by the review. (A tab switch doesn't make
    /// it disappear; `isSelectedTab` covers that.) The clock only catches up while it's seen, so
    /// VoiceOver never hears about a dropped time on another screen.
    @State private var isOnScreen = false

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
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    BookingStepTitle(step: 3, name: "Time", title: "Pick a time")
                    ChooseTimeChoiceSummary(choice: choice)
                }
                monthCalendar
                ChooseTimeTimes(
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
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .bookingStepChrome(step: 3, name: "Time", title: "Day & Time")
        .stickyBottomBar {
            ChooseTimeContinueBar(
                summary: continueSummary,
                spokenSummary: selectedSlot.map { calendar.dateTimeLabel(for: $0.start) },
                onContinue: continueToReview
            )
        }
        .onAppear {
            isOnScreen = true
            refresh()
        }
        .onDisappear {
            isOnScreen = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isOnScreen { refresh() }
        }
        // Keeps today's times honest while the client lingers on the calendar. Restarted when the
        // Book tab comes back; stopped while another tab is showing.
        .task {
            while true {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                if isOnScreen { refresh() }
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

    /// "Thu, Oct 29 · 2:30 PM" for the Continue bar, or `nil` before a time is picked.
    private var continueSummary: String? {
        guard let slot = selectedSlot else { return nil }
        return "\(calendar.shortLabel(for: calendar.day(containing: slot.start))) · \(slot.label)"
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

    /// Small, quick changes; none with Reduce Motion.
    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .snappy
    }

    // MARK: Actions

    private func showMonth(at index: Int, in pages: [MonthPage]) {
        guard pages.indices.contains(index) else { return }
        withAnimation(selectionAnimation) {
            displayedMonthID = pages[index].id
        }
    }

    private func selectDay(_ day: CalendarDay) {
        guard day != selectedDay else { return }
        withAnimation(selectionAnimation) {
            selectedDay = day
            // A time on another day doesn't carry over.
            selectedSlot = nil
            expiredNote = nil
            dayPickCount += 1
        }
    }

    private func selectSlot(_ slot: TimeSlot) {
        withAnimation(selectionAnimation) {
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

    /// Catches up with the clock, e.g. after the app was in the background, the client came back
    /// from the review or from another tab: a day or time that's no longer offered is dropped, and
    /// the first open day is picked if needed.
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

// MARK: - What's being booked

/// "Haircut · $45" over "with Carlos · 45 min", under the title (never beside it, where it collides
/// with the title one size step up).
private struct ChooseTimeChoiceSummary: View {
    let choice: BookingChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(choice.serviceName) · \(choice.priceLabel)")
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
            Text("\(BookingFlowCopy.withBarber(choice)) · \(choice.durationLabel)")
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(choice.serviceName) \(BookingFlowCopy.withBarber(choice)), \(choice.priceLabel.spokenRanges), \(choice.durationLabel.spokenRanges)"
        )
    }
}

// MARK: - Times for the selected day

/// The start times in one part of the day.
private struct ChooseTimeSlotGroup: Identifiable {
    let part: DayPart
    let slots: [TimeSlot]

    var id: String { part.id }
}

/// The selected day's name and hours, then its start times under a mono heading for each part of
/// the day. Every time comes from `BookingCalendar.slots`; there are no "taken" times, because the
/// app can't see the barbers' calendars.
private struct ChooseTimeTimes: View {
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
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let notice {
                ChooseTimeExpiredNote(text: notice)
            }
            if let day {
                dayHeader(day)
            }
            let slots = currentSlots
            if slots.isEmpty {
                ChooseTimeEmptyMessage(text: emptyText, offersCall: day == nil)
            } else {
                ForEach(groups(of: slots)) { group in
                    ChooseTimeGroupView(group: group, selectedSlot: selectedSlot, onSelect: onSelect)
                }
            }
        }
    }

    private func dayHeader(_ day: CalendarDay) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(calendar.longLabel(for: day))
                .textRole(.displayS)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("selectedDayLabel")
            Text(hoursText(for: day))
                .textRole(.detail)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
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

    /// "Shop hours 10 AM – 7 PM", or "Closed".
    private func hoursText(for day: CalendarDay) -> String {
        guard let hours = calendar.clock.schedule.hours(on: day.weekday) else { return "Closed" }
        return "Shop hours \(hours.label)"
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
                return "That's it for today. Pick another day."
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
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: Symbol.warning)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            Text(text)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card(padding: Theme.Space.cardPadding)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("slotExpiredNote")
    }
}

/// A day with no times: an `ink3` card with the calendar symbol, and the shop's number when there's
/// nothing in the whole booking window.
private struct ChooseTimeEmptyMessage: View {
    let text: String
    let offersCall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.calendar)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.bone)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink4, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    .accessibilityHidden(true)
                Text(text)
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if offersCall {
                CallButton {
                    Label("Call the shop", systemImage: Symbol.call)
                }
                .buttonStyle(.secondary)
            }
        }
        .card()
    }
}

/// "☀ AFTERNOON ———" and its time chips: as many columns as fit (5 on most phones at the default
/// size, fewer as text grows).
private struct ChooseTimeGroupView: View {
    let group: ChooseTimeSlotGroup
    let selectedSlot: TimeSlot?
    let onSelect: (TimeSlot) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            BookingSectionLabel(title: group.part.title, symbol: Symbol.symbol(for: group.part))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(group.slots) { slot in
                    ChooseTimeChip(slot: slot, isSelected: slot == selectedSlot) {
                        onSelect(slot)
                    }
                }
            }
        }
    }
}

/// One start time: "2:30" (the heading above says morning, afternoon or evening; VoiceOver hears
/// "2:30 PM"). Selected, it's bone with ink, bold text and the selected trait, never red.
private struct ChooseTimeChip: View {
    let slot: TimeSlot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: slot.clockLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, cornerRadius: Theme.Radius.chip, minHeight: Theme.minimumTapSize))
        .accessibilityLabel(slot.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("time-\(slot.id)")
    }
}

private extension TimeSlot {
    /// "2:30", "10:00": the 12-hour clock without AM or PM.
    var clockLabel: String {
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        let minute = time.minute < 10 ? "0\(time.minute)" : "\(time.minute)"
        return "\(hour):\(minute)"
    }
}

// MARK: - Continue

/// The red Continue bar pinned above the tab bar (`stickyBottomBar`): "CONTINUE", the picked day
/// and time in mono, and the arrow square. When the three don't fit on one line (a small phone,
/// bigger text) the time moves under "CONTINUE". Until a time is picked it's `ink3`, not red.
private struct ChooseTimeContinueBar: View {
    /// "Thu, Oct 29 · 2:30 PM", or `nil` before a time is picked.
    let summary: String?
    /// "Thu, Oct 29 at 2:30 PM".
    let spokenSummary: String?
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.l) {
                    Text("Continue")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    detail
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue")
                    detail
                }
            }
        }
        .buttonStyle(.primary)
        .disabled(summary == nil)
        .accessibilityLabel("Continue")
        .accessibilityValue(spokenSummary ?? "Pick a time first")
        .accessibilityIdentifier("continueToReview")
    }

    private var detail: some View {
        // Full white on red (5.24:1), from the button style.
        Text(summary ?? "Pick a time")
            .textRole(.label)
            .fixedSize(horizontal: false, vertical: true)
    }
}
