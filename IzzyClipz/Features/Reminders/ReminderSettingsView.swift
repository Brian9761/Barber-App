import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Remind me to book", isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.setEnabled($0) }
                    ))
                    .accessibilityIdentifier("remindersToggle")
                } footer: {
                    Text("Get a nudge at 10 AM when it's time for your next cut. Reminders are set on this iPhone only.")
                }

                if store.permission == .denied {
                    Section {
                        Label("Notifications are off for \(AppData.shop.name)", systemImage: Symbol.info)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    } footer: {
                        Text("Allow notifications in Settings to get cut reminders.")
                    }
                }

                if store.isEnabled {
                    Section("Schedule") {
                        Picker("Remind me every", selection: Binding(
                            get: { store.intervalWeeks },
                            set: { store.setInterval(weeks: $0) }
                        )) {
                            ForEach(ReminderPlanner.intervalChoices, id: \.self) { weeks in
                                Text("\(weeks) weeks").tag(weeks)
                            }
                        }

                        DatePicker(
                            "Last cut",
                            selection: Binding(get: { store.lastCut }, set: { store.setLastCut($0) }),
                            in: ...Date(),
                            displayedComponents: .date
                        )

                        Button("I just got a cut") {
                            store.setLastCut(Date())
                        }
                    }

                    Section("Next reminder") {
                        if let next = store.nextReminder {
                            Label {
                                Text(next.date, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                            } icon: {
                                Image(systemName: Symbol.calendar).foregroundStyle(Theme.red)
                            }
                        } else {
                            Text("Scheduling…")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
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
        .onAppear { store.refresh() }
    }
}
