import SwiftUI
import UIKit

/// Step 3: the day and time, from the shop's live calendar.
///
/// The month grid marks the days with open times (asked from the server two weeks at a time);
/// picking one lists its times by part of the day, all in the shop's time zone. The first day
/// with openings is picked to start with. If someone else books the picked time first, the client
/// lands back here with the list refreshed and a note saying so.
///
/// The screen's one red is the Continue bar; it stays `ink3` until a time is picked.
struct ChooseTimeView: View {
    let choice: BookingChoice

    @Environment(\.shopAPI) private var api
    @State private var loader: AvailabilityLoader?

    var body: some View {
        Group {
            if let loader {
                ChooseTimeScreen(choice: choice, loader: loader)
            } else {
                Theme.ink.ignoresSafeArea()
            }
        }
        .bookingStepChrome(title: "Day and time")
        .onAppear {
            if loader == nil {
                loader = AvailabilityLoader(target: choice.target, api: api)
            }
        }
    }
}

private struct ChooseTimeScreen: View {
    let choice: BookingChoice
    let loader: AvailabilityLoader

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    /// The month on screen, as `MonthPage.id` ("2026-10").
    @State private var displayedMonthID: String
    @State private var selectedDay: LocalDate?
    @State private var selectedStart: Date?
    /// Why the client is looking at this again, e.g. the time was taken.
    @State private var notice: String?
    /// Once the client picks a day, the screen stops picking one for them.
    @State private var hasPickedDay = false
    /// The first look moves on to next month when this one has no openings left.
    @State private var hasLookedAhead = false

    private let calendar = AppData.bookingCalendar

    /// How old the times may get before they're asked for again when the client comes back.
    private static let maxAge: TimeInterval = 2 * 60

    init(choice: BookingChoice, loader: AvailabilityLoader) {
        self.choice = choice
        self.loader = loader
        _displayedMonthID = State(initialValue: MonthPage(year: loader.today.year, month: loader.today.month).id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    BookingStepHeader(step: 3, title: "Pick a day and time")
                    ChooseTimeChoiceSummary(choice: choice)
                }
                if let notice {
                    ChooseTimeNotice(text: notice)
                }
                if let page = displayedPage {
                    CalendarMonthView(
                        page: page,
                        today: loader.today.calendarDay,
                        selectedDay: selectedDay?.calendarDay,
                        status: { loader.status(of: LocalDate($0)) },
                        canShowPrevious: pageIndex > 0,
                        canShowNext: pageIndex < pages.count - 1,
                        onPrevious: { showMonth(at: pageIndex - 1) },
                        onNext: { showMonth(at: pageIndex + 1) },
                        onSelect: { selectDay(LocalDate($0)) }
                    )
                }
                times
                if let zone = BookingFlowCopy.timeZoneNote(at: selectedStart ?? Date()) {
                    Text(zone)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("timeZoneNote")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .screenBackground()
        .refreshable {
            await reload(saying: nil)
        }
        .stickyBottomBar {
            ChooseTimeContinueBar(
                summary: selectedStart.map { calendar.dateTimeLabel(for: $0) },
                onContinue: continueToDetails
            )
        }
        .task(id: displayedMonthID) {
            guard let page = displayedPage else { return }
            await loader.load(page)
            pickFirstOpenDayIfNeeded()
        }
        .task(id: router.timeStepNotice?.id) {
            guard let sent = router.timeStepNotice else { return }
            router.clearTimeStepNotice()
            if let dropped = sent.droppedStart, dropped == selectedStart {
                selectedStart = nil
            }
            await reload(saying: sent.message)
        }
        .onAppear {
            if loader.isStale(maxAge: Self.maxAge), loader.loadedAt != nil {
                Task { await reload(saying: nil) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, loader.isStale(maxAge: Self.maxAge) {
                Task { await reload(saying: nil) }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedStart) { _, newValue in newValue != nil }
    }

    // MARK: Times

    @ViewBuilder private var times: some View {
        if let day = selectedDay {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(calendar.longLabel(for: day.calendarDay))
                    .textRole(.displayS)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("selectedDayLabel")
                dayContent(day)
            }
        } else if let error = loader.error {
            loadError(error)
        } else if loader.isLoading || !hasLoadedDisplayedMonth {
            LoadingStateView(text: "Checking open times…")
                .accessibilityIdentifier("timesLoading")
        } else {
            ChooseTimeEmptyMessage(text: noDaysText, offersNextMonth: pageIndex < pages.count - 1) {
                showMonth(at: pageIndex + 1)
            }
        }
    }

    @ViewBuilder private func dayContent(_ day: LocalDate) -> some View {
        switch loader.status(of: day) {
        case .open(let slots):
            ForEach(ChooseTimeSlotGroup.groups(of: slots)) { group in
                ChooseTimeGroupView(group: group, selectedStart: selectedStart) { slot in
                    selectedStart = slot.start
                    notice = nil
                }
            }
        case .noOpenings:
            ChooseTimeEmptyMessage(text: "No openings left on this day. Pick another day.", offersNextMonth: false) {}
        case .closed:
            ChooseTimeEmptyMessage(text: "The shop is closed on \(day.weekday.name)s. Pick another day.", offersNextMonth: false) {}
        case .past, .tooFar:
            ChooseTimeEmptyMessage(text: "This day can't be booked. Pick another day.", offersNextMonth: false) {}
        case .notLoaded:
            if let error = loader.error {
                loadError(error)
            } else {
                LoadingStateView(text: "Checking open times…")
                    .accessibilityIdentifier("timesLoading")
            }
        }
    }

    private func loadError(_ error: APIError) -> some View {
        ErrorStateView(
            title: "Couldn't load the times",
            message: error.userMessage,
            onRetry: { Task { await reload(saying: nil) } },
            isRetrying: loader.isLoading
        )
        .accessibilityIdentifier("timesError")
    }

    // MARK: Months

    private var pages: [MonthPage] {
        calendar.months(now: Date())
    }

    private var pageIndex: Int {
        pages.firstIndex { $0.id == displayedMonthID } ?? 0
    }

    private var displayedPage: MonthPage? {
        let pages = pages
        guard !pages.isEmpty else { return nil }
        return pages[min(pageIndex, pages.count - 1)]
    }

    /// Whether every bookable day on screen has an answer.
    private var hasLoadedDisplayedMonth: Bool {
        guard let page = displayedPage, let range = loader.bookableRange(of: page) else { return true }
        var day = range.lowerBound
        while day <= range.upperBound {
            if loader.status(of: day) == .notLoaded { return false }
            day = day.adding(days: 1)
        }
        return true
    }

    private var noDaysText: String {
        if pageIndex < pages.count - 1 {
            return "No openings left in \(displayedPage?.title ?? "this month"). Try next month."
        }
        return "No openings left in the next \(calendar.windowDays) days. Give the shop a call and they'll find you a time."
    }

    private func showMonth(at index: Int) {
        guard pages.indices.contains(index) else { return }
        displayedMonthID = pages[index].id
    }

    // MARK: Picking

    private func selectDay(_ day: LocalDate) {
        guard day != selectedDay else { return }
        hasPickedDay = true
        selectedDay = day
        // A time on another day doesn't carry over.
        selectedStart = nil
        notice = nil
    }

    /// Picks the first day with openings in the month on screen, unless a bookable day is already
    /// picked (by the client, or on screen). On the first look, a month with nothing left moves on
    /// to the next.
    private func pickFirstOpenDayIfNeeded() {
        let range = displayedPage.flatMap { loader.bookableRange(of: $0) }
        if let day = selectedDay, loader.status(of: day).isBookable {
            if hasPickedDay || range?.contains(day) == true { return }
        }
        if let range, let first = loader.firstOpenDay(onOrAfter: range.lowerBound), range.contains(first) {
            selectedDay = first
            selectedStart = nil
            return
        }
        if hasLoadedDisplayedMonth {
            advanceIfNothingThisMonth()
        }
    }

    private func advanceIfNothingThisMonth() {
        guard !hasLookedAhead, !hasPickedDay, loader.error == nil, pageIndex < pages.count - 1 else { return }
        hasLookedAhead = true
        showMonth(at: pageIndex + 1)
    }

    /// Asks for the month on screen again. A picked time that's gone is dropped, with a note.
    private func reload(saying message: String?) async {
        guard let page = displayedPage else { return }
        await loader.reload(page)
        if let message {
            notice = message
            UIAccessibility.post(notification: .announcement, argument: message)
        }
        if let start = selectedStart, let day = selectedDay,
           !(loader.slots(on: day) ?? []).contains(where: { $0.start == start }) {
            selectedStart = nil
            if message == nil, loader.error == nil {
                let text = "\(calendar.timeLabel(for: start)) is no longer available. Pick another time."
                notice = text
                UIAccessibility.post(notification: .announcement, argument: text)
            }
        }
        if let day = selectedDay, !loader.status(of: day).isBookable, loader.status(of: day) != .notLoaded {
            // The picked day filled up: move to the next one with openings.
            hasPickedDay = false
            selectedDay = nil
        }
        pickFirstOpenDayIfNeeded()
    }

    private func continueToDetails() {
        // A second tap while the next step slides in mustn't push it twice.
        if let last = router.bookingPath.last, case .details = last { return }
        guard let start = selectedStart else { return }
        router.bookingPath.append(.details(BookingPlan(choice: choice, start: start)))
    }
}

// MARK: - What's being booked

/// "Haircut with Carlos" over "$45 · 45 min".
private struct ChooseTimeChoiceSummary: View {
    let choice: BookingChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(choice.serviceName) \(BookingFlowCopy.withBarber(choice))")
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
            Text("\(choice.priceLabel) · \(choice.durationLabel)")
                .textRole(.detail)
                .foregroundStyle(Theme.smoke)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(choice.serviceName) \(BookingFlowCopy.withBarber(choice)), \(choice.priceLabel.spokenRanges), \(choice.durationLabel.spokenRanges)")
    }
}

/// Why the client is back here, e.g. "Someone just booked 2:30 PM. Pick another time."
private struct ChooseTimeNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: Symbol.warning)
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
        .accessibilityIdentifier("timeNotice")
    }
}

/// A day or month with no times, with the shop's number, and "Next month" when there is one.
private struct ChooseTimeEmptyMessage: View {
    let text: String
    let offersNextMonth: Bool
    let onNextMonth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.calendar)
                    .font(.title3)
                    .foregroundStyle(Theme.bone)
                    .accessibilityHidden(true)
                Text(text)
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("noTimesMessage")
            if offersNextMonth {
                Button("Show next month", action: onNextMonth)
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("showNextMonth")
            }
            CallButton {
                Label("Call the shop", systemImage: Symbol.call)
            }
            .buttonStyle(.tertiary)
        }
        .card()
    }
}

// MARK: - Times for the picked day

/// The start times in one part of the day.
private struct ChooseTimeSlotGroup: Identifiable {
    let part: DayPart
    let slots: [IzzyAPI.Slot]

    var id: String { part.id }

    static func groups(of slots: [IzzyAPI.Slot]) -> [ChooseTimeSlotGroup] {
        DayPart.allCases.compactMap { part in
            let matching = slots.filter { DayPart(time: ShopTime.timeOfDay(of: $0.start)) == part }
            return matching.isEmpty ? nil : ChooseTimeSlotGroup(part: part, slots: matching)
        }
    }
}

/// "Afternoon" and its time chips: as many columns as fit.
private struct ChooseTimeGroupView: View {
    let group: ChooseTimeSlotGroup
    let selectedStart: Date?
    let onSelect: (IzzyAPI.Slot) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            BookingSectionLabel(title: group.part.title, symbol: Symbol.symbol(for: group.part))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                ForEach(group.slots) { slot in
                    ChooseTimeChip(slot: slot, isSelected: slot.start == selectedStart) {
                        onSelect(slot)
                    }
                }
            }
        }
    }
}

/// One start time: "2:30 PM". Selected, it's bone with ink, bold text and the selected trait,
/// never red.
private struct ChooseTimeChip: View {
    let slot: IzzyAPI.Slot
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: AppData.bookingCalendar.timeLabel(for: slot.start))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, cornerRadius: Theme.Radius.chip, minHeight: Theme.minimumTapSize))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("time-\(ShopTime.identifier(for: slot.start))")
    }
}

/// Wall-clock times in the shop's time zone, whatever the phone is set to.
enum ShopTime {
    static func timeOfDay(of date: Date) -> TimeOfDay {
        let parts = AppData.clock.calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "1430": 24-hour, zero-padded, for accessibility identifiers.
    static func identifier(for date: Date) -> String {
        let time = timeOfDay(of: date)
        return String(format: "%02d%02d", time.hour, time.minute)
    }
}

// MARK: - Continue

/// The red Continue bar pinned above the tab bar, with the picked day and time under it. Until a
/// time is picked it's `ink3`, not red, and says to pick one.
private struct ChooseTimeContinueBar: View {
    /// "Thu, Oct 29 at 2:30 PM", or `nil` before a time is picked.
    let summary: String?
    let onContinue: () -> Void

    var body: some View {
        Button(action: onContinue) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Continue")
                Text(summary ?? "Pick a time first")
                    .textRole(.caption)
            }
        }
        .buttonStyle(.primary)
        .disabled(summary == nil)
        .accessibilityLabel("Continue")
        .accessibilityValue(summary ?? "Pick a time first")
        .accessibilityIdentifier("continueToDetails")
    }
}
