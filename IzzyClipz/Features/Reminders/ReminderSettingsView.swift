import SwiftUI
import UIKit

/// "Keep it fresh": the cut-reminder settings, in a sheet from the bell. On or off, how often, when
/// the last cut was, and when the next nudge comes.
///
/// No red here: nothing on this sheet is a primary action. Selection is bone, switches are electric
/// and the one warning (notifications off) is caution yellow.
struct ReminderSettingsView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isScrolled = false
    @State private var titleIsUnderBar = false

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                ScrollView {
                    VStack(spacing: Theme.Space.xxl) {
                        ReminderSettingsHeader()
                            .pageScrolledUnderBar($titleIsUnderBar)
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
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, Theme.Space.xs)
                    .padding(.bottom, Theme.Space.xxl)
                    .animation(.easeInOut(duration: 0.25), value: store.isEnabled)
                    .animation(.easeInOut(duration: 0.25), value: store.permission)
                    .pageScrolled($isScrolled)
                }
            }
            .coordinateSpace(.named(PageBar.space))
            .background(Theme.ink2.ignoresSafeArea())
            // The title is in the content ("Cut reminders" over "Keep it fresh"); the bar holds
            // Done, and the name once the title has scrolled away.
            .pageBar(title: "Cut reminders", showsTitle: titleIsUnderBar, isScrolled: isScrolled, background: Theme.ink2)
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

/// A still barber pole, the kicker, "KEEP IT FRESH" and how reminders work.
private struct ReminderSettingsHeader: View {
    var body: some View {
        VStack(spacing: Theme.Space.m) {
            VStack(spacing: Theme.Space.xxs) {
                Kicker("Cut reminders")
                Text("Keep it fresh")
                    .textRole(.displayL)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("Get a nudge at 10 AM when it's time for your next cut. Reminders are set on this iPhone only.")
                .textRole(.body)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

/// The main switch, on an ink card, tinted electric.
private struct ReminderToggleCard: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.isEnabled },
            set: { store.setEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Remind me to book")
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                Text(detail)
                    .textRole(.body)
                    .foregroundStyle(Theme.smoke)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Theme.electric)
        .accessibilityIdentifier("remindersToggle")
        .card(padding: Theme.Space.xl)
    }

    private var detail: String {
        store.isEnabled
            ? "Every \(store.intervalWeeks) weeks after your last cut"
            : "Turn on to get a nudge when it's time."
    }
}

/// Shown when the system won't let the app send notifications: a caution icon and a bone button
/// to the app's notification settings.
private struct ReminderPermissionCard: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.l) {
                Image(systemName: Symbol.warning)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.caution)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Notifications are off for \(AppData.shop.name)")
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    Text("Allow notifications in Settings to get cut reminders.")
                        .textRole(.body)
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
                HStack(spacing: 6) {
                    Text("Open Settings")
                    Image(systemName: Symbol.external)
                        .font(.system(size: 13, weight: .heavy))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("openSettingsButton")
        }
        .card(padding: Theme.Space.xl)
    }
}

/// How often, the last cut, and when the next reminder is.
private struct ReminderScheduleSection: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var justCutCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                intervalPicker
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                lastCut
            }
            .card(padding: Theme.Space.xl)
            ReminderNextCard()
        }
        .sensoryFeedback(.success, trigger: justCutCount)
    }

    /// "REMIND ME EVERY … 3 WEEKS" over five chips, 2 to 6 weeks, the picked one in bone.
    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // Each chip says its own value to VoiceOver.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Kicker("Remind me every")
                    Spacer(minLength: Theme.Space.s)
                    pickedInterval
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Kicker("Remind me every")
                    pickedInterval
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: Theme.Space.s) {
                ForEach(ReminderPlanner.intervalChoices, id: \.self) { weeks in
                    intervalChip(weeks)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Remind me every")
            .accessibilityIdentifier("reminderIntervalPicker")
        }
    }

    private var pickedInterval: some View {
        Text(Self.weeks(store.intervalWeeks))
            .textRole(.detail)
            .foregroundStyle(Theme.bone)
    }

    private func intervalChip(_ weeks: Int) -> some View {
        let isSelected = weeks == store.intervalWeeks
        return Button {
            store.setInterval(weeks: weeks)
        } label: {
            HStack(spacing: 4) {
                // More than color: a check (when there's room), bold type and the selected trait.
                if isSelected && !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: Symbol.checkmark)
                        .font(.system(size: 11, weight: .heavy))
                        .accessibilityHidden(true)
                }
                Text("\(weeks)")
            }
        }
        .buttonStyle(ReminderChipStyle(isSelected: isSelected))
        .accessibilityLabel(Self.weeks(weeks))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("reminderInterval-\(weeks)")
    }

    private var lastCut: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.l) {
                    Kicker("Last cut")
                    Spacer(minLength: Theme.Space.s)
                    lastCutPicker
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Kicker("Last cut")
                    lastCutPicker
                }
            }
            Text("Updates on its own after an appointment you saved in the app.")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.setLastCut(Date())
                justCutCount += 1
                UIAccessibility.post(notification: .announcement, argument: "Last cut set to today")
            } label: {
                Label("I just got a cut", systemImage: Symbol.checkmark)
            }
            .buttonStyle(.compact)
            .accessibilityIdentifier("justGotCutButton")
        }
    }

    private var lastCutPicker: some View {
        DatePicker(
            "Last cut",
            selection: Binding(get: { store.lastCut }, set: { store.setLastCut($0) }),
            in: ...Date(),
            displayedComponents: .date
        )
        .labelsHidden()
        .tint(Theme.electric)
        .accessibilityIdentifier("lastCutPicker")
    }

    /// "3 weeks".
    static func weeks(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }
}

/// A week chip on the ink3 card: `ink4` with a bone number, or bone with a bold ink number when
/// picked (selection is never red). 44 pt tall; the five share the card's width.
private struct ReminderChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
        return configuration.label
            .font(.system(.subheadline, design: .default, weight: isSelected ? .bold : .semibold).monospacedDigit())
            .foregroundStyle(isSelected ? Theme.ink : Theme.bone)
            .lineLimit(1)
            .padding(.horizontal, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapSize)
            .background(isSelected ? Theme.bone : (configuration.isPressed ? Theme.line : Theme.ink4), in: shape)
            .contentShape(shape)
    }
}

/// When the next reminder will show up, on a bone card: the day in Display M, the time in mono.
/// While it's being scheduled, the pole spins in its place.
private struct ReminderNextCard: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Kicker("Next reminder")
            if let next = store.nextReminder {
                // The reminder fires at 10 AM on this iPhone's own clock, so it's shown in the
                // phone's time zone and format rather than the shop's.
                Text(next.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .textRole(.displayM)
                    .fixedSize(horizontal: false, vertical: true)
                Text(next.date, format: .dateTime.hour().minute())
                    .textRole(.detail)
                    .foregroundStyle(Theme.smokeDark)
            } else {
                HStack(spacing: Theme.Space.m) {
                    ProgressView()
                        .accessibilityLabel("Scheduling")
                    Text("Scheduling…")
                        .textRole(.callout)
                        .foregroundStyle(Theme.smokeDark)
                        .accessibilityHidden(true)
                }
            }
        }
        .boneCard(padding: Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }
}
