import EventKit
import EventKitUI
import SwiftUI

/// Apple's "New Event" screen, filled in with an appointment.
///
/// Since iOS 17 this screen runs outside the app, so adding the event needs no calendar
/// permission: the client sees exactly what's saved and taps Add.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let event: CalendarEvent
    /// Off only when the app will send its own hour-before reminder, so the client doesn't get two
    /// alerts at once. With notifications off, or the reminder turned off, the calendar's alert is
    /// the one they get.
    var includesAlert = true
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let calendarEvent = EKEvent(eventStore: store)
        let shop = AppData.shop
        calendarEvent.title = event.title
        calendarEvent.startDate = event.start
        calendarEvent.endDate = event.end
        calendarEvent.timeZone = shop.timeZone
        calendarEvent.location = "\(shop.fullName), \(shop.address.singleLine)"
        calendarEvent.notes = event.notes
        calendarEvent.url = shop.websiteURL
        if includesAlert {
            calendarEvent.addAlarm(EKAlarm(relativeOffset: -60 * 60))
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = calendarEvent
        controller.editViewDelegate = context.coordinator
        controller.view.tintColor = UIColor(Theme.bone)
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}

/// The "New Event" screen in a sheet. UI tests get a stand-in, since the real one runs in another
/// process.
struct AddToCalendarSheet: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(AppointmentStore.self) private var appointments

    var body: some View {
        if LaunchOptions.isUITesting {
            NavigationStack {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("New event")
                        .textRole(.headline)
                    Text(event.title)
                        .accessibilityIdentifier("calendarEventTitle")
                    Text(AppData.bookingCalendar.dateTimeLabel(for: event.start))
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { dismiss() }
                    }
                }
            }
        } else {
            CalendarEventEditor(
                event: event,
                includesAlert: !appointments.willSendHourBeforeReminder(for: event.id)
            ) {
                dismiss()
            }
            .ignoresSafeArea()
        }
    }
}
