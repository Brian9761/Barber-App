import IzzyClipzKit
import SwiftUI

/// The shop's day: appointments in every status and blocked time, for
/// everyone or one barber. Refreshes every minute while it's on screen and
/// the app is in the foreground, and on pull to refresh.
struct ScheduleView: View {
    @Bindable var store: ScheduleStore
    let workspace: Workspace
    @State private var showsBlockTime = false
    @State private var blockToRemove: IzzyAPI.TimeOff?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayPicker(store: store)
                }
                content
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Barber", selection: $store.barberFilter) {
                            Text("Everyone").tag(String?.none)
                            ForEach(store.barbers) { barber in
                                Text(barber.name).tag(Optional(barber.id))
                            }
                        }
                    } label: {
                        Label(store.filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Show appointments for \(store.filterTitle)")
                    .accessibilityHint("Picks which barber's appointments to show.")
                    .accessibilityIdentifier("barberFilter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsBlockTime = true
                    } label: {
                        Label("Block time", systemImage: "calendar.badge.minus")
                    }
                    .accessibilityIdentifier("blockTimeButton")
                }
            }
            .refreshable { await store.refresh() }
            .navigationDestination(for: AppointmentLink.self) { link in
                AppointmentDetailView(appointmentID: link.id, store: store, workspace: workspace)
            }
            .sheet(isPresented: $showsBlockTime) {
                BlockTimeView(store: store)
            }
            .confirmationDialog(
                "Remove this blocked time?",
                isPresented: Binding(get: { blockToRemove != nil }, set: { if !$0 { blockToRemove = nil } }),
                titleVisibility: .visible,
                presenting: blockToRemove
            ) { block in
                Button("Remove blocked time", role: .destructive) {
                    Task { await store.removeTimeOff(block) }
                }
                .accessibilityIdentifier("confirmRemoveBlock")
                Button("Keep it", role: .cancel) {}
            } message: { block in
                Text("\(store.barberName(for: block.barberId)), \(store.shopTime.timeRange(block.start, block.end)). Clients can book this time again.")
            }
            .alert(
                "That didn't work",
                isPresented: Binding(get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.actionError ?? "")
            }
        }
        // While the tab is on screen and the app is in the foreground: load
        // now, then every minute. SwiftUI cancels the task when the tab goes
        // away or the app leaves the foreground.
        .task(id: AutoRefreshKey(day: store.day, isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await Ticker.run(every: ScheduleStore.refreshInterval) {
                await store.refresh()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            if store.appointments.isEmpty && store.timeOff.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading the schedule…")
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
            } else {
                loadedSections
            }
        case .failed(let message):
            Section {
                ContentUnavailableView {
                    Label("Couldn't load the schedule", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await store.refresh() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("retrySchedule")
                }
            }
        case .loaded:
            loadedSections
        }
    }

    @ViewBuilder
    private var loadedSections: some View {
        if let refreshError = store.refreshError {
            Section {
                InlineMessage(text: "Couldn't refresh: \(refreshError) Showing what was loaded before.")
            }
        }
        if !store.visibleTimeOff.isEmpty {
            Section("Blocked time") {
                ForEach(store.visibleTimeOff) { block in
                    TimeOffRow(block: block, store: store)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) { blockToRemove = block }
                        }
                        .contextMenu {
                            Button("Remove blocked time", systemImage: "trash", role: .destructive) { blockToRemove = block }
                        }
                }
            }
        }
        Section {
            if store.visibleAppointments.isEmpty {
                ContentUnavailableView(
                    "No appointments",
                    systemImage: "calendar",
                    description: Text(store.barberFilter == nil
                        ? "Nothing is booked for \(store.shopTime.longDay(store.day))."
                        : "\(store.filterTitle) has nothing booked for \(store.shopTime.longDay(store.day)).")
                )
                .accessibilityIdentifier("scheduleEmpty")
            } else {
                ForEach(store.visibleAppointments) { appointment in
                    NavigationLink(value: AppointmentLink(id: appointment.id)) {
                        AppointmentRow(appointment: appointment, shopTime: store.shopTime)
                    }
                    .accessibilityIdentifier("appointment-\(appointment.customer.name)")
                }
            }
        } header: {
            Text(store.summary)
        } footer: {
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(store.shopTime.time(lastUpdated)). Refreshes every minute.")
            }
        }
    }
}

/// Opens an appointment's details.
struct AppointmentLink: Hashable {
    let id: String
}

/// What the auto-refresh task depends on.
struct AutoRefreshKey: Hashable {
    let day: LocalDate
    let isActive: Bool
}

/// ‹ Monday, November 2 › with a date picker and a way back to today.
struct DayPicker: View {
    @Bindable var store: ScheduleStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    store.showPreviousDay()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous day")
                .accessibilityIdentifier("previousDay")

                Spacer()
                VStack(spacing: 2) {
                    Text(store.shopTime.relativeDay(store.day, today: store.today))
                        .font(.headline)
                    DatePicker("Day", selection: $store.dayAsDate, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.timeZone, store.shopTime.timeZone)
                        .accessibilityLabel("Day")
                        .accessibilityValue(store.shopTime.longDay(store.day))
                        .accessibilityIdentifier("dayPicker")
                }
                Spacer()

                Button {
                    store.showNextDay()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next day")
                .accessibilityIdentifier("nextDay")
            }
            if store.day != store.today {
                Button("Back to today") { store.showToday() }
                    .buttonStyle(.borderless)
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("backToToday")
            }
        }
    }
}

/// One appointment in the list: time, client, service, barber, status, paid.
struct AppointmentRow: View {
    let appointment: IzzyAPI.Appointment
    let shopTime: ShopTime
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(shopTime.time(appointment.start))
                    .font(.headline.monospacedDigit())
                Text(appointment.durationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.customer.name)
                    .font(.body.weight(.semibold))
                    .strikethrough(appointment.status == .cancelled)
                Text("\(appointment.serviceName) · \(appointment.barberName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    StatusBadge(status: appointment.status)
                    if appointment.payment.status == .paid {
                        Badge(text: paidText, color: BusinessTheme.paid)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(appointment.status == .cancelled ? 0.65 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var paidText: String {
        appointment.payment.amountCents.map { "Paid \(Money.amount($0))" } ?? "Paid"
    }

    private var accessibilityText: String {
        var parts = [
            shopTime.time(appointment.start),
            appointment.customer.name,
            "\(appointment.serviceName) with \(appointment.barberName)",
            appointment.status.title,
        ]
        if appointment.payment.status == .paid { parts.append(paidText) }
        return parts.joined(separator: ", ")
    }
}

struct StatusBadge: View {
    let status: IzzyAPI.AppointmentStatus

    var body: some View {
        Badge(text: status.title, color: status.color)
    }
}

extension IzzyAPI.AppointmentStatus {
    var color: Color {
        switch self {
        case .booked: return .blue
        case .completed: return .green
        case .noShow: return .orange
        case .cancelled: return .gray
        }
    }
}

/// A blocked stretch of time.
struct TimeOffRow: View {
    let block: IzzyAPI.TimeOff
    let store: ScheduleStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: block.isWholeShop ? "building.2" : "person.crop.circle.badge.minus")
                .foregroundStyle(.orange)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.shopTime.timeRange(block.start, block.end))
                    .font(.headline.monospacedDigit())
                Text([store.barberName(for: block.barberId), block.reason].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if store.removingTimeOff.contains(block.id) {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocked, \(store.barberName(for: block.barberId)), \(store.shopTime.timeRange(block.start, block.end))\(block.reason.map { ", \($0)" } ?? "")")
        .accessibilityHint("Swipe left to remove.")
        .accessibilityIdentifier("timeOff-\(block.reason ?? store.barberName(for: block.barberId))")
    }
}
