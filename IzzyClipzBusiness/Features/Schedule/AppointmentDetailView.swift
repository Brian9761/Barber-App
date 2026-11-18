import IzzyClipzKit
import SwiftUI

/// One appointment: the client (call or text), what and when, Check out (the main action until
/// it's checked out, then "Paid $60 · Cash"), the card on file and its fee, payment, and what the
/// owner can do with it.
struct AppointmentDetailView: View {
    let appointmentID: String
    let store: ScheduleStore
    let workspace: Workspace
    @State private var confirmsCancel = false
    @State private var confirmsAnotherPayment = false
    @State private var paymentBusyMessage: String?
    /// What Reopen says first about the fee, while it asks.
    @State private var reopenWarning: String?
    /// Void sale, while it asks (with an optional reason).
    @State private var asksToVoidSale = false
    @State private var voidReason = ""
    /// Mark done on a booking with a card on file, while it asks: it can't become a no-show after.
    @State private var confirmsMarkDone = false
    /// Check out while Take payment has a ticket for someone else, while it asks whether to replace
    /// it.
    @State private var replacing: Replacement?

    private struct Replacement: Identifiable {
        let message: String
        var id: String { message }
    }
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

            checkOutSection(appointment)
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
            // This dialog says it if a ticket on Take payment would be replaced (one question, not two).
            Button("Check out something extra") { startExtra(appointment) }
                .accessibilityIdentifier("confirmCheckOutExtra")
            Button("Not now", role: .cancel) {}
        } message: {
            Text(
                ["\(appointment.payment.amountCents.map(Money.amount) ?? "A payment") was already paid for this appointment by card. Check out again only for something extra, like a product or a tip.",
                 workspace.checkout.replacedTicketMessage(forAppointment: nil)].compactMap { $0 }.joined(separator: " ")
            )
        }
        .confirmationDialog(
            CheckoutModel.replaceTicketQuestion,
            isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
            titleVisibility: .visible,
            presenting: replacing
        ) { replacement in
            Button("Replace it", role: .destructive) {
                startCheckout(appointment, replace: true)
            }
            .accessibilityIdentifier("confirmReplaceTicket")
            Button("Keep it", role: .cancel) {}
        } message: { replacement in
            Text(replacement.message)
        }
        .alert(
            "Finish the current payment first",
            isPresented: Binding(get: { paymentBusyMessage != nil }, set: { if !$0 { paymentBusyMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(paymentBusyMessage ?? "")
        }
        .confirmationDialog(
            "Mark \(appointment.customer.name)'s appointment done?",
            isPresented: $confirmsMarkDone,
            titleVisibility: .visible
        ) {
            Button("Mark done") {
                Task { await store.setStatus(.completed, for: appointment) }
            }
            .accessibilityIdentifier("confirmMarkCompleted")
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(Self.markDoneWithCardMessage)
        }
        .alert(
            appointment.sale.map { SalesStore.voidQuestion(totalCents: $0.totalCents, method: $0.method) } ?? "",
            isPresented: $asksToVoidSale
        ) {
            TextField("Reason (optional)", text: $voidReason)
                .accessibilityIdentifier("detailVoidReason")
            Button("Void sale", role: .destructive) {
                guard let sale = appointment.sale else { return }
                let why = voidReason
                Task { await workspace.sales.void(sale, reason: why) }
            }
            .accessibilityIdentifier("confirmDetailVoidSale")
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(SalesStore.voidExplanation(method: appointment.sale?.method ?? .cash, forAppointment: true))
        }
        .alert(
            "That didn't work",
            isPresented: Binding(get: { workspace.sales.appointmentVoidError != nil }, set: { if !$0 { workspace.sales.appointmentVoidError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspace.sales.appointmentVoidError ?? "")
        }
    }

    /// What Mark done asks first for a booked appointment with a card on file: marked done, it can
    /// never become a no-show (the server keeps when it was completed), even if it's reopened.
    static let markDoneWithCardMessage =
        "The client came, so this booking can't become a no-show later, or be charged its no-show fee, even if you reopen it."

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

    /// Check out: the main action for a booked or completed appointment that isn't checked out yet.
    /// Once it is, the Payment section says "Paid $60 · Cash".
    @ViewBuilder
    private func checkOutSection(_ appointment: IzzyAPI.Appointment) -> some View {
        if appointment.canCheckOut {
            Section {
                Button {
                    if appointment.payment.status == .paid {
                        confirmsAnotherPayment = true
                    } else {
                        startCheckout(appointment)
                    }
                } label: {
                    Label("Check out", systemImage: "cart")
                }
                .buttonStyle(PrimaryButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityHint("Opens Take payment with \(appointment.serviceName) on the ticket.")
                .accessibilityIdentifier("checkOutAppointment")
            } footer: {
                Text("Ring up the service, any products, and how the client paid: card, cash or another way.")
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
            if let sale = appointment.sale {
                Text("Checked out. To change the sale, void it, then check the appointment out again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detailSaleNote")
                // From here, whatever day it was made: Today's sales lists only today's.
                Button(role: .destructive) {
                    voidReason = ""
                    asksToVoidSale = true
                } label: {
                    HStack {
                        Label("Void sale", systemImage: "xmark.bin")
                        Spacer()
                        if workspace.sales.voiding.contains(sale.id) { ProgressView() }
                    }
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                }
                .disabled(workspace.sales.voiding.contains(sale.id))
                .accessibilityIdentifier("detailVoidSale")
            }
            if let feeNote = summary.feeNote {
                // A charged fee isn't the service's payment: said here, so it isn't taken again.
                Text(feeNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detailPaymentFeeNote")
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ appointment: IzzyAPI.Appointment, now: Date, isUpdating: Bool, isBusy: Bool) -> some View {
        Section {
            switch appointment.status {
            case .booked:
                // Done without checking out (the service still counts at its booked price). With a
                // card on file it asks first: done, it can never become a no-show.
                actionButton("Mark done", systemImage: "checkmark.circle", id: "markCompleted", disabled: isBusy) {
                    if appointment.card != nil, appointment.noShowFee != nil, appointment.sale == nil, !appointment.completedBefore {
                        confirmsMarkDone = true
                    } else {
                        Task { await store.setStatus(.completed, for: appointment) }
                    }
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
                // A checked-out appointment stays completed until its sale is voided (the server's rule).
                if appointment.sale == nil {
                    actionButton("Reopen", systemImage: "arrow.uturn.backward.circle", id: "reopenAppointment", disabled: isBusy) {
                        if let warning = FeePanel.reopenWarning(for: appointment, now: now) {
                            reopenWarning = warning
                        } else {
                            Task { await store.setStatus(.booked, for: appointment) }
                        }
                    }
                } else {
                    Text("Checked out")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("checkedOutStatus")
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
            case .completed where appointment.sale != nil:
                Text("To reopen it, void its sale first (Void sale, under Payment).")
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

    /// Check out: asks first if it would replace a ticket being rung up on Take payment.
    private func startCheckout(_ appointment: IzzyAPI.Appointment, replace: Bool = false) {
        if !replace, workspace.checkout.canStartCheckout,
           let message = workspace.checkout.replacedTicketMessage(forAppointment: appointment.id) {
            replacing = Replacement(message: message)
            return
        }
        if !workspace.checkOut(appointment) {
            paymentBusyMessage = Workspace.paymentBusyMessage
        }
    }

    /// Something extra, from "This appointment is already paid" (which said if a ticket on Take
    /// payment would be replaced).
    private func startExtra(_ appointment: IzzyAPI.Appointment) {
        if !workspace.checkOutExtra(for: appointment) {
            paymentBusyMessage = Workspace.paymentBusyMessage
        }
    }
}
