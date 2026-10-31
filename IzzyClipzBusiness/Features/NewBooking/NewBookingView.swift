import IzzyClipzKit
import SwiftUI

/// New booking for walk-ins and phone bookings: service, barber, day and
/// time (with "Now" and "Next open slot" for walk-ins), client name and
/// optional phone.
struct NewBookingView: View {
    @Bindable var store: NewBookingStore
    let workspace: Workspace
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case name, phone, note
    }

    private let timeColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        NavigationStack {
            // Every minute, so "Now" shows the time it is and goes when the shop closes.
            TimelineView(.everyMinute) { _ in
                Form {
                    serviceSection
                    if store.serviceID != nil {
                        barberSection
                        timeSection
                        clientSection
                        bookSection
                    }
                }
            }
            .navigationTitle("New booking")
            .scrollDismissesKeyboard(.interactively)
            .task(id: SlotsKey(target: store.target, day: store.day, version: store.slotsVersion)) {
                if store.target != nil, store.slotsState == .idle {
                    await store.loadSlots()
                }
            }
            .sheet(item: Binding(get: { store.booked.map(BookedItem.init) }, set: { if $0 == nil { store.startOver() } })) { item in
                BookedSheet(appointment: item.appointment, store: store, workspace: workspace)
            }
        }
    }

    // MARK: Sections

    private var serviceSection: some View {
        Section("Service") {
            Picker("Service", selection: Binding(get: { store.serviceID }, set: { store.selectService($0) })) {
                Text("Choose a service").tag(String?.none)
                ForEach(store.services) { service in
                    Text(service.name).tag(Optional(service.id))
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("servicePicker")
        }
    }

    private var barberSection: some View {
        Section("Barber") {
            Picker("Barber", selection: Binding(get: { store.choice }, set: { store.selectChoice($0) })) {
                if store.offersAnyBarber {
                    Text("Any barber (first free)").tag(Optional(NewBookingStore.Choice.anyBarber))
                }
                ForEach(store.offerings) { offering in
                    Text(store.label(for: offering)).tag(Optional(NewBookingStore.Choice.offering(offering.id)))
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityIdentifier("barberPicker")
        }
    }

    private var timeSection: some View {
        Section {
            Button {
                Task { await store.findNextOpenSlot() }
            } label: {
                HStack {
                    Label("Next open slot", systemImage: "figure.walk.arrival")
                    Spacer()
                    if store.isFindingNextSlot { ProgressView() }
                }
                .frame(minHeight: BusinessTheme.minimumTapSize)
            }
            .disabled(store.isFindingNextSlot)
            .accessibilityHint("Picks the earliest time that's free, for a walk-in.")
            .accessibilityIdentifier("nextOpenSlot")

            DatePicker(
                "Day",
                selection: $store.dayAsDate,
                in: store.shopTime.startOfDay(store.today)...,
                displayedComponents: .date
            )
            .environment(\.timeZone, store.shopTime.timeZone)
            .accessibilityIdentifier("bookingDay")

            if let start = store.nowStart {
                nowButton(start)
            }

            slots
        } header: {
            Text("Day and time")
        } footer: {
            if let slot = store.selectedSlot, store.choice == .anyBarber {
                if NewBookingStore.isNow(slot) {
                    Text("A barber who's free now gets it: the one with the fewest bookings today.")
                } else {
                    Text("Free at \(store.shopTime.time(slot.start)): \(store.barberNames(for: slot)). The one with the fewest bookings that day gets it.")
                }
            } else if store.nowStart != nil {
                Text("Times are the shop's. Pick Now for a walk-in who's here.")
            } else {
                Text("Times are the shop's.")
            }
        }
    }

    /// "Now (11:10 AM)": books the walk-in from this minute, not the next half hour.
    private func nowButton(_ start: Date) -> some View {
        // Once picked, the minute it was picked; until then, the time it is.
        let picked = store.isNowSelected ? store.selectedSlot?.start : nil
        let selected = picked != nil
        let text = "Now (\(store.shopTime.time(picked ?? start)))"
        return Button {
            store.selectNow()
        } label: {
            TimeChip(text: text, selected: selected)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(text)
        .accessibilityHint("Books it from now, for a walk-in who's here.")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("bookNow")
    }

    @ViewBuilder
    private var slots: some View {
        switch store.slotsState {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Finding open times…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                InlineMessage(text: message)
                Button("Try again") { Task { await store.loadSlots() } }
                    .accessibilityIdentifier("retrySlots")
            }
        case .loaded:
            if store.slots.isEmpty {
                Text(store.nowStart == nil
                    ? "No open times on \(store.shopTime.longDay(store.day)). Try another day or barber."
                    : "No other open times today. Pick Now, or try another day or barber.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("noSlots")
            } else {
                LazyVGrid(columns: timeColumns, spacing: 8) {
                    ForEach(store.slots) { slot in
                        let selected = !store.isNowSelected && store.selectedSlot?.start == slot.start
                        Button {
                            store.selectedSlot = slot
                        } label: {
                            TimeChip(text: store.shopTime.time(slot.start), selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.shopTime.time(slot.start))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("slot-\(store.shopTime.time(slot.start))")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var clientSection: some View {
        Section {
            TextField("Client's name", text: $store.clientName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .name)
                .submitLabel(.next)
                .onSubmit { focusedField = .phone }
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("clientName")
            TextField("Mobile number (optional)", text: $store.clientPhone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($focusedField, equals: .phone)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("clientPhone")
            if !store.phoneIsValid {
                InlineMessage(text: "That doesn't look like a US mobile number.")
            }
            TextField("Note (optional)", text: $store.note, axis: .vertical)
                .focused($focusedField, equals: .note)
                .lineLimit(1...4)
                .frame(minHeight: BusinessTheme.minimumTapSize)
                .accessibilityIdentifier("bookingNote")
        } header: {
            Text("Client")
        } footer: {
            Text("A phone number lets you call or text them from the schedule.")
        }
    }

    private var bookSection: some View {
        Section {
            if let error = store.formError {
                InlineMessage(text: error, systemImage: "exclamationmark.octagon.fill", color: .red)
                    .accessibilityIdentifier("bookingError")
            }
            Button {
                focusedField = nil
                Task { await store.book() }
            } label: {
                HStack {
                    if store.isBooking { ProgressView().tint(.white) }
                    Text(bookTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isBooking)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("bookButton")
        }
    }

    private var bookTitle: String {
        if store.isBooking { return "Booking…" }
        guard let slot = store.selectedSlot else { return "Book appointment" }
        return "Book \(store.shopTime.relativeDay(store.day, today: store.today).lowercasedIfRelative) at \(store.shopTime.time(slot.start))"
    }
}

private extension String {
    var lowercasedIfRelative: String {
        ["Today", "Tomorrow", "Yesterday"].contains(self) ? lowercased() : self
    }
}

/// One time to pick: red when it's the one picked.
private struct TimeChip: View {
    let text: String
    let selected: Bool

    var body: some View {
        Text(text)
            .font(.body.monospacedDigit().weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? BusinessTheme.red : Color(.tertiarySystemFill))
            )
    }
}

/// Reloads the times when the service, barber or day changes.
private struct SlotsKey: Hashable {
    let target: IzzyAPI.BookingTarget?
    let day: LocalDate
    let version: Int
}

private struct BookedItem: Identifiable {
    let appointment: IzzyAPI.Appointment
    var id: String { appointment.id }
}

/// "Booked": what was booked, with Take payment and Done.
private struct BookedSheet: View {
    let appointment: IzzyAPI.Appointment
    let store: NewBookingStore
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Booked \(appointment.customer.name)")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("bookedTitle")
                Text(store.summary(of: appointment))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Take payment") {
                    let item = appointment
                    dismiss()
                    workspace.takePayment(for: item)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("bookedTakePayment")
                Button("Done") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("bookedDone")
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
