import IzzyClipzKit
import SwiftUI

/// One appointment: the client (call or text), what and when, the card on
/// file and its fee, payment, and what the owner can do with it.
struct AppointmentDetailView: View {
    let appointmentID: String
    let store: ScheduleStore
    let workspace: Workspace
    @State private var confirmsCancel = false
    @State private var confirmsAnotherPayment = false
    @State private var paymentBusyMessage: String?
    /// What Reopen says first about the fee, while it asks.
    @State private var reopenWarning: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let appointment = store.appointment(withID: appointmentID) {
                // Every minute the clock is read again, so a booking with a card on file offers
                // "Mark no-show" (and its fee) once it has ended.
                TimelineView(.everyMinute) { _ in
                    details(appointment, now: store.now)
                }
            } else {
                ContentUnavailableView(
                    "Appointment not found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("It's no longer on this day's schedule.")
                )
            }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func details(_ appointment: IzzyAPI.Appointment, now: Date) -> some View {
        let isUpdating = store.updating.contains(appointment.id)
        // No status change while the fee is being charged: the server decides the fee by the status.
        let isBusy = isUpdating || store.chargingFee.contains(appointment.id)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appointment.customer.name)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("detailClientName")
                    Text("\(appointment.serviceName) with \(appointment.barberName)")
                        .font(.headline)
                    Text("\(store.shopTime.shortDay(store.shopTime.day(containing: appointment.start))), \(store.shopTime.timeRange(appointment.start, appointment.end))")
                        .foregroundStyle(.secondary)
                    AppointmentBadgeRow(badges: AppointmentBadges(appointment: appointment), statusIdentifier: "detailStatus")
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
                LabeledContent("Length", value: appointment.durationLabel)
                LabeledContent("Price", value: appointment.priceLabel)
                if appointment.status == .cancelled {
                    LabeledContent("Cancelled by", value: appointment.cancelledBy == .customer ? "The client" : "The shop")
                }
                if let cancelledAt = appointment.noShowFee?.customerCancelledAt {
                    // Kept even after the shop reopens it: a client who cancelled is never charged a no-show fee.
                    LabeledContent("Client cancelled in the app", value: store.shopTime.dayAndTime(cancelledAt))
                        .accessibilityIdentifier("detailCustomerCancelled")
                }
                if let note = appointment.note {
                    LabeledContent("Note") {
                        Text(note).multilineTextAlignment(.trailing)
                    }
                    .accessibilityIdentifier("detailNote")
                }
            }

            contactSection(appointment)
            NoShowFeeSection(appointment: appointment, now: now, store: store)
            paymentSection(appointment)
            actionsSection(appointment, now: now, isUpdating: isUpdating, isBusy: isBusy)
        }
        .confirmationDialog(
            "Cancel \(appointment.customer.name)'s appointment?",
            isPresented: $confirmsCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel appointment", role: .destructive) {
                Task { await store.setStatus(.cancelled, for: appointment) }
            }
            .accessibilityIdentifier("confirmCancelAppointment")
            Button("Keep it", role: .cancel) {}
                .accessibilityIdentifier("keepAppointment")
        } message: {
            Text(cancelMessage(appointment))
        }
        .confirmationDialog(
            "Reopen \(appointment.customer.name)'s appointment?",
            isPresented: Binding(get: { reopenWarning != nil }, set: { if !$0 { reopenWarning = nil } }),
            titleVisibility: .visible
        ) {
            Button("Reopen") {
                Task { await store.setStatus(.booked, for: appointment) }
            }
            .accessibilityIdentifier("confirmReopen")
            Button("Keep it as it is", role: .cancel) {}
        } message: {
            Text(reopenWarning ?? "")
        }
        .confirmationDialog(
            "This appointment is already paid",
            isPresented: $confirmsAnotherPayment,
            titleVisibility: .visible
        ) {
            Button("Take another payment") { startPayment(appointment) }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("\(appointment.payment.amountCents.map(Money.amount) ?? "A payment") was already paid for this appointment. Take another payment only for something extra, like a product or a tip.")
        }
        .alert(
            "Finish the current payment first",
            isPresented: Binding(get: { paymentBusyMessage != nil }, set: { if !$0 { paymentBusyMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paymentBusyMessage ?? "")
        }
    }

    @ViewBuilder
    private func contactSection(_ appointment: IzzyAPI.Appointment) -> some View {
        Section("Client") {
            if let phone = appointment.customer.phone, let number = PhoneNumber(parsing: phone) {
                LabeledContent("Phone", value: number.display)
                    .accessibilityValue(number.spoken)
                HStack(spacing: 12) {
                    Button {
                        openURL(number.callURL)
                    } label: {
                        Label("Call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Call \(appointment.customer.name)")
                    .accessibilityIdentifier("callClient")
                    Button {
                        if let url = URL(string: "sms:\(number.e164)") { openURL(url) }
                    } label: {
                        Label("Text", systemImage: "message.fill")
                            .frame(maxWidth: .infinity, minHeight: BusinessTheme.minimumTapSize)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Text \(appointment.customer.name)")
                    .accessibilityIdentifier("textClient")
                }
            } else {
                Text(appointment.customer.phone == nil ? "No phone number (booked at the shop)." : "Phone: \(appointment.customer.phone ?? "")")
                    .foregroundStyle(.secondary)
            }
            if let email = appointment.customer.email {
                LabeledContent("Email", value: email)
            }
        }
    }

    @ViewBuilder
    private func paymentSection(_ appointment: IzzyAPI.Appointment) -> some View {
        let summary = PaymentSummary(appointment: appointment)
        Section("Payment") {
            LabeledContent(summary.title, value: summary.value)
                .accessibilityIdentifier("detailPayment")
            if appointment.payment.status == .paid, let paidAt = appointment.payment.paidAt {
                LabeledContent("When", value: store.shopTime.dayAndTime(paidAt))
            }
            if let feeNote = summary.feeNote {
                // A charged fee isn't the service's payment: said here, so it isn't taken again.
                Text(feeNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detailPaymentFeeNote")
            }
            if appointment.status != .cancelled {
                Button {
                    if appointment.payment.status == .paid {
                        confirmsAnotherPayment = true
                    } else {
                        startPayment(appointment)
                    }
                } label: {
                    Label(appointment.payment.status == .paid ? "Take another payment" : "Take payment", systemImage: "wave.3.right.circle")
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                }
                .accessibilityIdentifier("takePaymentForAppointment")
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ appointment: IzzyAPI.Appointment, now: Date, isUpdating: Bool, isBusy: Bool) -> some View {
        Section {
            switch appointment.status {
            case .booked:
                actionButton("Mark completed", systemImage: "checkmark.circle", id: "markCompleted", disabled: isBusy) {
                    Task { await store.setStatus(.completed, for: appointment) }
                }
                // A booking with a card on file is a no-show only once it has ended (the client may still come until then).
                if appointment.canMarkNoShow(at: now) {
                    actionButton("Mark no-show", systemImage: "person.fill.questionmark", id: "markNoShow", disabled: isBusy) {
                        Task { await store.setStatus(.noShow, for: appointment) }
                    }
                }
                actionButton("Cancel appointment", systemImage: "xmark.circle", id: "cancelAppointment", role: .destructive, disabled: isBusy) {
                    confirmsCancel = true
                }
            case .completed, .noShow, .cancelled:
                actionButton("Reopen", systemImage: "arrow.uturn.backward.circle", id: "reopenAppointment", disabled: isBusy) {
                    if let warning = FeePanel.reopenWarning(for: appointment, now: now) {
                        reopenWarning = warning
                    } else {
                        Task { await store.setStatus(.booked, for: appointment) }
                    }
                }
            }
        } header: {
            HStack {
                Text("Status")
                if isUpdating { ProgressView().controlSize(.small) }
            }
        } footer: {
            switch appointment.status {
            case .booked:
                if let hint = FeePanel.noShowHint(for: appointment, now: now, shopTime: store.shopTime) {
                    Text("Cancelling frees the time for other clients.\n\(hint)")
                        .accessibilityIdentifier("noShowHint")
                } else {
                    Text("Cancelling frees the time for other clients.")
                }
            case .cancelled:
                Text("Reopening books the time again, if nobody else has taken it.")
            case .completed, .noShow:
                Text("Reopening sets it back to booked.")
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        id: String,
        role: ButtonRole? = nil,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .disabled(disabled)
        .accessibilityIdentifier(id)
    }

    private func cancelMessage(_ appointment: IzzyAPI.Appointment) -> String {
        var message = "\(store.shopTime.time(appointment.start)) with \(appointment.barberName). The time opens up for other clients. The app doesn't message the client, so let them know."
        if let note = FeePanel.shopCancelNote(for: appointment) { message += " \(note)" }
        return message
    }

    private func startPayment(_ appointment: IzzyAPI.Appointment) {
        if !workspace.takePayment(for: appointment) {
            paymentBusyMessage = "A payment is in progress on the Take payment tab. Finish or cancel it, then try again."
        }
    }
}
