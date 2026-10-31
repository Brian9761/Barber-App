import IzzyClipzKit
import SwiftUI

/// Block time: a barber (or the whole shop) can't be booked between a start
/// and an end, with an optional reason. Times are the shop's.
struct BlockTimeView: View {
    let store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var barberID: String?
    @State private var start: Date
    @State private var end: Date
    @State private var reason = ""
    @State private var isSaving = false
    @State private var error: String?

    init(store: ScheduleStore) {
        self.store = store
        let (start, end) = store.defaultBlockTimes()
        _start = State(initialValue: start)
        _end = State(initialValue: end)
        _barberID = State(initialValue: store.barberFilter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who", selection: $barberID) {
                        Text("Whole shop").tag(String?.none)
                        ForEach(store.barbers) { barber in
                            Text(barber.name).tag(Optional(barber.id))
                        }
                    }
                    .accessibilityIdentifier("blockWho")
                } footer: {
                    Text(barberID == nil ? "Nobody can be booked during this time." : "Only \(store.barberName(for: barberID)) is blocked; the others can still be booked.")
                }

                Section {
                    DatePicker("Starts", selection: $start)
                        .accessibilityIdentifier("blockStart")
                    DatePicker("Ends", selection: $end, in: start...)
                        .accessibilityIdentifier("blockEnd")
                } footer: {
                    Text("Shop time (\(store.shopTime.timeZone.identifier.replacingOccurrences(of: "_", with: " "))).")
                }
                .environment(\.timeZone, store.shopTime.timeZone)

                Section("Reason (optional)") {
                    TextField("Lunch, appointment, day off…", text: $reason)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                        .accessibilityIdentifier("blockReason")
                }

                if !overlapping.isEmpty {
                    Section {
                        InlineMessage(text: overlapText)
                    }
                }

                if let error {
                    Section {
                        InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .accessibilityIdentifier("blockError")
                    }
                }
            }
            .navigationTitle("Block time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("saveBlock")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        .onChange(of: start) { oldStart, newStart in
            // Keep the length when the start moves.
            let length = end.timeIntervalSince(oldStart)
            end = newStart.addingTimeInterval(length > 0 ? length : 3_600)
        }
    }

    private var overlapping: [IzzyAPI.Appointment] {
        guard end > start else { return [] }
        return store.appointmentsOverlapping(IzzyAPI.TimeOff(id: "draft", barberId: barberID, start: start, end: end))
    }

    private var overlapText: String {
        let count = overlapping.count
        let names = overlapping.prefix(3).map(\.customer.name).joined(separator: ", ")
        return "\(count == 1 ? "1 booked appointment overlaps" : "\(count) booked appointments overlap") this time (\(names)). They stay booked; call the clients if they need to move."
    }

    private func save() {
        guard !isSaving else { return }
        guard end > start else {
            error = "The end has to be after the start."
            return
        }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.addTimeOff(barberId: barberID, start: start, end: end, reason: reason)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                self.error = (error as? ScheduleError)?.message ?? ErrorText.message(for: error)
            }
        }
    }
}
