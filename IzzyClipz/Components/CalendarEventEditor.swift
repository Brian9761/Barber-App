import EventKit
import EventKitUI
import SwiftUI

/// Apple's "New Event" screen, filled in with an appointment.
///
/// Since iOS 17 this screen runs outside the app, so adding the event needs no
/// calendar permission: the client sees exactly what's saved and taps Add.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let appointment: Appointment
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let shop = AppData.shop
        event.title = "\(appointment.serviceName) at \(shop.name)"
        event.startDate = appointment.start
        event.endDate = appointment.end
        event.timeZone = shop.timeZone
        event.location = "\(shop.fullName), \(shop.address.singleLine)"
        event.notes = CalendarEventEditor.notes(for: appointment)
        event.url = shop.websiteURL
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60))

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        controller.view.tintColor = UIColor(Theme.red)
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    static func notes(for appointment: Appointment) -> String {
        let shop = AppData.shop
        return [
            "\(appointment.serviceName) with \(appointment.barberName)",
            "\(appointment.priceLabel) · \(DurationText.short(minutes: appointment.durationMinutes))",
            "Need to change it? Call \(shop.phone.display).",
        ].joined(separator: "\n")
    }

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

/// The "New Event" screen in a sheet. UI tests get a stand-in, since the real
/// one runs in another process.
struct AddToCalendarSheet: View {
    let appointment: Appointment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if LaunchOptions.isUITesting {
            NavigationStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New Event")
                        .font(.headline)
                    Text("\(appointment.serviceName) at \(AppData.shop.name)")
                        .accessibilityIdentifier("calendarEventTitle")
                    Text(AppData.bookingCalendar.dateTimeLabel(for: appointment.start))
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
            CalendarEventEditor(appointment: appointment) { dismiss() }
                .ignoresSafeArea()
        }
    }
}
