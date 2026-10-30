import SwiftUI
import UIKit

/// "Time for a fresh cut" reminder settings, shown in a sheet: on or off,
/// how often, and when the last cut was.
struct ReminderSettingsView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ReminderSettingsHeader(isOn: store.isEnabled)
                    ReminderToggleCard()
                    if store.permission == .denied {
                        ReminderPermissionCard()
                            .transition(AnyTransition.opacity)
                    }
                    if store.isEnabled {
                        ReminderScheduleSection()
                            .transition(AnyTransition.opacity)
                    }
                }
                .padding(Theme.gutter)
                .animation(.easeInOut(duration: 0.25), value: store.isEnabled)
                .animation(.easeInOut(duration: 0.25), value: store.permission)
            }
            .screenBackground()
            .navigationTitle("Cut Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("remindersDone")
                }
            }
        }
        // Also notices notifications turned on or off in Settings.
        .onAppear { store.refresh() }
    }
}

/// The bell badge, title and a line on how reminders work.
private struct ReminderSettingsHeader: View {
    let isOn: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 12) {
            // Bone, not red: the reminders sheet has no primary action, so it has no red.
            Image(systemName: isOn ? Symbol.remindersOn : Symbol.reminders)
                .font(.system(size: badgeSize * 0.42, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: badgeSize, height: badgeSize)
                .background(Theme.bone, in: Circle())
                .accessibilityHidden(true)
            Text("KEEP IT FRESH")
                .textRole(.displayM)
                .foregroundStyle(Theme.bone)
                .accessibilityLabel("Keep it fresh")
                .accessibilityAddTraits(.isHeader)
            Text("Get a nudge at 10 AM when it's time for your next cut. Reminders are set on this iPhone only.")
                .font(.subheadline)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// The main switch.
private struct ReminderToggleCard: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.isEnabled },
            set: { store.setEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Remind me to book")
                    .font(.headline)
                    .foregroundStyle(Theme.bone)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.smoke)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Theme.electric)
        .accessibilityIdentifier("remindersToggle")
        .card()
    }

    private var detail: String {
        store.isEnabled
            ? "Every \(store.intervalWeeks) weeks after your last cut"
            : "Turn on to get a nudge when it's time."
    }
}

/// Shown when the system won't let the app send notifications.
private struct ReminderPermissionCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: Symbol.remindersOff)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.bone)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications are off for \(AppData.shop.name)")
                        .font(.headline)
                        .foregroundStyle(Theme.bone)
                    Text("Allow notifications in Settings to get cut reminders.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.smoke)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Label("Open Settings", systemImage: Symbol.external)
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("openSettingsButton")
        }
        .card()
    }
}

/// How often, the last cut, and when the next reminder is.
private struct ReminderScheduleSection: View {
    @Environment(ReminderStore.self) private var store
    @State private var justCutCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Schedule")
            VStack(alignment: .leading, spacing: 16) {
                intervalRow
                Divider()
                lastCutRow
                justCutButton
            }
            .card()
            ReminderNextCard()
        }
        .sensoryFeedback(.success, trigger: justCutCount)
    }

    /// The label and menu side by side, or stacked at large text sizes.
    private var intervalRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                intervalLabel
                Spacer(minLength: 8)
                intervalPicker
            }
            VStack(alignment: .leading, spacing: 6) {
                intervalLabel
                intervalPicker
            }
        }
    }

    /// VoiceOver hears this from the menu's own label instead.
    private var intervalLabel: some View {
        Text("Remind me every")
            .font(.body)
            .foregroundStyle(Theme.bone)
            .accessibilityHidden(true)
    }

    private var intervalPicker: some View {
        Picker("Remind me every", selection: Binding(
            get: { store.intervalWeeks },
            set: { store.setInterval(weeks: $0) }
        )) {
            ForEach(ReminderPlanner.intervalChoices, id: \.self) { weeks in
                Text("\(weeks) weeks").tag(weeks)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(Theme.electric)
        .accessibilityIdentifier("reminderIntervalPicker")
    }

    private var lastCutRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            DatePicker(
                "Last cut",
                selection: Binding(get: { store.lastCut }, set: { store.setLastCut($0) }),
                in: ...Date(),
                displayedComponents: .date
            )
            .font(.body)
            .foregroundStyle(Theme.bone)
            .tint(Theme.electric)
            .accessibilityIdentifier("lastCutPicker")
            Text("Updates on its own after an appointment you saved in the app.")
                .font(.footnote)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var justCutButton: some View {
        Button {
            store.setLastCut(Date())
            justCutCount += 1
            UIAccessibility.post(notification: .announcement, argument: "Last cut set to today")
        } label: {
            Label("I just got a cut", systemImage: Symbol.checkmark)
        }
        .buttonStyle(.secondary)
        .accessibilityIdentifier("justGotCutButton")
    }
}

/// When the next reminder will show up.
private struct ReminderNextCard: View {
    @Environment(ReminderStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Symbol.calendar)
                .font(.body.weight(.semibold))
                // The glyph stops growing with the circle, so it stays inside.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(Theme.electric)
                .frame(width: min(iconSize, 56), height: min(iconSize, 56))
                .background(Theme.ink4, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Next reminder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.smoke)
                nextDate
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    /// The reminder fires at 10 AM on this iPhone's own clock, so it's shown
    /// in the phone's time zone and format rather than the shop's.
    @ViewBuilder private var nextDate: some View {
        if let next = store.nextReminder {
            Text(next.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                .font(.headline)
                .foregroundStyle(Theme.bone)
        } else {
            Text("Scheduling…")
                .font(.headline)
                .foregroundStyle(Theme.smoke)
        }
    }
}
