import IzzyClipzKit
import SwiftUI

/// Take payment, a checkout ticket ("Check out"): who it's for (the appointment it started from,
/// or a walk-in with an optional name), Sold by (the barber who gets credit), the items (services
/// at the barber's prices, the shop's products, and amounts on the keypad), the total in large type,
/// and how the client pays: Tap to Pay on iPhone, Cash, or Other (recorded only). Today's sales are
/// at the bottom.
struct TakePaymentView: View {
    @Bindable var checkout: CheckoutModel
    let workspace: Workspace
    @State private var showsNote = false
    @State private var sheet: TicketSheet?
    /// Cash or Other, while its question is up.
    @State private var confirming: IzzyAPI.SaleMethod?
    /// A sale or Card payments today, when one is open.
    @State private var path = NavigationPath()
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 48
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    if let notice = checkout.recoveryNotice {
                        HStack(alignment: .top) {
                            InlineMessage(text: notice, systemImage: "checkmark.circle.fill", color: .green)
                            Spacer(minLength: 0)
                            Button {
                                checkout.recoveryNotice = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                            }
                            .accessibilityLabel("Dismiss")
                        }
                        .accessibilityIdentifier("recoveryNotice")
                    }
                    Text("Ring up services, products or any amount, then choose how the client pays.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("checkoutIntro")
                    modeSection
                    readerStatus
                    clientSection
                    soldBySection
                    itemsSection
                    totalSection
                    noteSection
                    if let message = checkout.validationMessage {
                        InlineMessage(text: message, systemImage: "exclamationmark.octagon.fill", color: .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("paymentValidation")
                    }
                    paySection
                    TodaysSalesSection(store: workspace.sales)
                    todaysPayments
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Check out")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PaymentsLink.self) { _ in
                PaymentsTodayView(checkout: checkout)
            }
            .navigationDestination(for: SaleLink.self) { link in
                SaleDetailView(saleID: link.id, store: workspace.sales)
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .service:
                    ServicePickerSheet(checkout: checkout)
                case .product:
                    ProductPickerSheet(checkout: checkout, products: workspace.products)
                case .amount:
                    NavigationStack {
                        AmountEntryView(purpose: .newAmount, checkout: checkout) { sheet = nil }
                    }
                case .price(let id):
                    NavigationStack {
                        AmountEntryView(purpose: .price(itemID: id), checkout: checkout) { sheet = nil }
                    }
                }
            }
            .confirmationDialog(
                confirming.map { recordQuestion($0) } ?? "",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                titleVisibility: .visible,
                presenting: confirming
            ) { method in
                Button(method == .cash ? "Record cash sale" : "Record sale") {
                    checkout.record(method)
                }
                .accessibilityIdentifier("confirmRecordSale")
                Button("Not yet", role: .cancel) {}
            } message: { method in
                Text(recordMessage(method))
            }
            .fullScreenCover(isPresented: Binding(get: { checkout.phase != .editing }, set: { _ in })) {
                PaymentProgressView(checkout: checkout, workspace: workspace)
            }
            // A checkout started from the schedule shows its ticket, not a sale left open here.
            .onChange(of: workspace.checkoutsStarted) { _, _ in
                path = NavigationPath()
            }
            .task {
                await workspace.recheckStatusIfNeeded()
                async let payments: Void = checkout.loadPayments()
                async let sales: Void = workspace.sales.refresh()
                async let products: Void = workspace.products.refresh()
                _ = await (payments, sales, products)
                await checkout.syncPendingPayments()
            }
        }
    }

    // MARK: Mode

    @ViewBuilder
    private var modeSection: some View {
        switch checkout.mode {
        case .checking:
            if let problem = workspace.paymentsStatusError {
                // The check with the server failed: say why, and offer to check again.
                IssueCard(issue: TerminalIssue(title: "Can't check card payments", message: problem)) {
                    Button("Check again") { Task { await workspace.refreshStatus() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("checkStripeAgain")
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startPractice")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("paymentsStatusUnknown")
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Checking card payments…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .unavailable(let issue):
            IssueCard(issue: issue) {
                if issue.fixInSettings {
                    // The shop's own Stripe account: connected (or finished) in Settings.
                    Button("Go to Settings") { workspace.openSettings() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("goToStripeSettings")
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startPractice")
                } else {
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("startPractice")
                    Button("Check again") { Task { await workspace.refreshStatus() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("checkStripeAgain")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("paymentsUnavailable")
        case .practice(let reason):
            VStack(alignment: .leading, spacing: 8) {
                TestModeBanner()
                switch reason {
                case .deviceUnsupported:
                    Text("This iPhone can't take Tap to Pay, so card payments here are practice only and aren't sent to Stripe. Cash and other sales are saved as usual.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .chosen:
                    HStack {
                        Text("Practice card payments aren't sent to Stripe or recorded. Cash and other sales are saved as usual.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Leave test mode") { checkout.stopPractice() }
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: BusinessTheme.minimumTapSize)
                            .accessibilityIdentifier("stopPractice")
                    }
                }
            }
        case .sampleServer:
            TestModeBanner()
        case .live(_, let stripeTestMode):
            if stripeTestMode {
                TestModeBanner(text: "Stripe test mode — only test cards, no real money")
            }
            if !workspace.hasSetUpTapToPay {
                IssueCard(issue: TerminalIssue(
                    title: "Set up Tap to Pay on iPhone",
                    message: "Accept cards, Apple Pay and other digital wallets with just this iPhone. The first time, Apple asks the shop's owner to accept its terms."
                ), symbol: "wave.3.right.circle.fill", tint: BusinessTheme.red) {
                    Button {
                        Task { await workspace.setUpTapToPay() }
                    } label: {
                        if workspace.isSettingUpTapToPay { ProgressView() } else { Text("Set up Tap to Pay on iPhone") }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("setUpTapToPay")
                }
            }
        }
    }

    /// Progress while Apple configures the iPhone, and readiness.
    @ViewBuilder
    private var readerStatus: some View {
        if case .live = checkout.mode {
            switch checkout.currentTerminal.state {
            case .preparing(let progress):
                ReaderProgress(progress: progress)
            case .reconnecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reconnecting Tap to Pay…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .unavailable(let issue):
                IssueCard(issue: issue) {
                    if issue.canRetry {
                        Button("Try again") { Task { await workspace.setUpTapToPay() } }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Practice in test mode") { checkout.startPractice() }
                        .buttonStyle(.bordered)
                }
            case .ready:
                Label("Tap to Pay is ready", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .collecting, .processing:
                EmptyView()
            }
        }
    }

    // MARK: Who it's for

    @ViewBuilder
    private var clientSection: some View {
        if let appointment = checkout.ticket.appointment {
            appointmentCard(appointment)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Walk-in", systemImage: "figure.walk")
                    .font(.headline)
                TextField("Client's name (optional)", text: $checkout.ticket.walkInName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("walkInName")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func appointmentCard(_ appointment: CheckoutTicket.AppointmentLink) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(appointment.clientName).font(.headline)
                Text("\(appointment.serviceName) with \(appointment.barberName)")
                    .font(.subheadline)
                Text("\(appointment.when) · \(appointment.priceLabel)")
                    .font(.footnote).foregroundStyle(.secondary)
                if let paid = appointment.alreadyPaidCents {
                    Text("Already paid \(Money.amount(paid)).")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            Button {
                checkout.forgetAppointment()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
            }
            .accessibilityLabel("Not for this appointment")
            .accessibilityIdentifier("clearAppointment")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paymentAppointment")
    }

    // MARK: Sold by

    private var soldBySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sold by")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 8) {
                ForEach(checkout.catalog.barbers) { barber in
                    let selected = checkout.ticket.barberId == barber.id
                    Button {
                        checkout.chooseBarber(barber.id)
                    } label: {
                        Text(barber.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: BusinessTheme.minimumTapSize)
                            .background(Capsule().fill(selected ? BusinessTheme.red : Color(.tertiarySystemFill)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint("Gets credit for this sale.")
                    .accessibilityIdentifier("soldBy-\(barber.name)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Items")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if checkout.ticket.isEmpty {
                Text("Nothing yet. Add a service, a product or an amount.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ticketEmpty")
            } else {
                ForEach(checkout.ticket.items) { item in
                    TicketItemRow(item: item, checkout: checkout) {
                        sheet = .price(item.id)
                    }
                }
            }
            FlowLayout(spacing: 8) {
                addButton("Service", systemImage: "scissors", id: "addService") { sheet = .service }
                addButton("Product", systemImage: "bag", id: "addProduct") { sheet = .product }
                addButton("Amount", systemImage: "number", id: "addAmount") { sheet = .amount }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addButton(_ title: String, systemImage: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("+ \(title)", systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .buttonStyle(.bordered)
        .disabled(checkout.phase != .editing)
        .accessibilityLabel("Add \(title.lowercased())")
        .accessibilityIdentifier(id)
    }

    private var totalSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Total")
                .font(.title3.weight(.semibold))
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Text(Money.amount(checkout.amountCents))
                .font(.system(size: amountSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityLabel("Total")
                .accessibilityValue(Money.spoken(checkout.amountCents))
                .accessibilityIdentifier("paymentAmount")
        }
    }

    private var noteSection: some View {
        DisclosureGroup(isExpanded: $showsNote) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Note (optional), e.g. Tip included", text: $checkout.note)
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: BusinessTheme.minimumTapSize)
                    .accessibilityIdentifier("paymentNote")
                Text("For a card payment: Stripe shows it instead of what was sold. Leave out the client's name.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Text(checkout.note.trimmingCharacters(in: .whitespaces).isEmpty ? "Add a note for the card payment" : "Note added")
                .frame(minHeight: BusinessTheme.minimumTapSize)
        }
        .accessibilityIdentifier("paymentDetails")
    }

    // MARK: How are they paying?

    /// Tap to Pay is offered when the iPhone can take a card now (or practice in test mode).
    private var takesCards: Bool {
        switch checkout.mode {
        case .live, .sampleServer, .practice: return true
        case .checking, .unavailable: return false
        }
    }

    private var paySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are they paying?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if takesCards {
                // Apple's label, no Apple logo, never disabled: a problem explains itself.
                Button {
                    checkout.charge()
                } label: {
                    Label("Tap to Pay on iPhone", systemImage: "wave.3.right.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint("Charges \(Money.spoken(checkout.amountCents)) to a card.")
                .accessibilityIdentifier("tapToPayButton")
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                PayMethodButton(title: "Cash", subtitle: nil, systemImage: "banknote", id: "payCash") { ask(.cash) }
                PayMethodButton(title: "Other", subtitle: "Squire, Zelle, Cash App…", systemImage: "ellipsis.circle", id: "payOther") { ask(.other) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cash or Other: the question with the amount, unless the ticket isn't ready.
    private func ask(_ method: IzzyAPI.SaleMethod) {
        checkout.validationMessage = nil
        if let problem = checkout.ticket.problem(for: method) {
            checkout.validationMessage = problem
            return
        }
        confirming = method
    }

    /// "Record a $60 cash sale for Izzy?", "Record a $36 sale paid another way for Izzy?"
    private func recordQuestion(_ method: IzzyAPI.SaleMethod) -> String {
        let amount = Price.currencyString(cents: checkout.amountCents)
        let barber = checkout.barberName.map { " for \($0)" } ?? ""
        return method == .cash ? "Record a \(amount) cash sale\(barber)?" : "Record a \(amount) sale paid another way\(barber)?"
    }

    private func recordMessage(_ method: IzzyAPI.SaleMethod) -> String {
        let items = checkout.ticket.items.map { "\($0.name) \($0.priceLabel)" }.joined(separator: ", ")
        let how = method == .cash
            ? "Record it once you have the cash."
            : "Squire, Zelle, Cash App or another way: the app only records it, so record it once the money is in."
        return "\(items). \(how)"
    }

    private var todaysPayments: some View {
        NavigationLink(value: PaymentsLink()) {
            HStack {
                Label("Card payments today", systemImage: "list.bullet.rectangle")
                Spacer()
                if checkout.isLoadingPayments && checkout.todaysPayments.isEmpty {
                    ProgressView()
                } else {
                    Text("\(Money.amount(checkout.todaysTotalCents)) · \(checkout.todaysPayments.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .frame(minHeight: BusinessTheme.minimumTapSize)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Card payments today, \(Money.spoken(checkout.todaysTotalCents)) from \(checkout.todaysPayments.count) payments")
        .accessibilityIdentifier("paymentsTodayLink")
    }
}

/// What Take payment has open in a sheet.
enum TicketSheet: Identifiable, Hashable {
    case service
    case product
    case amount
    /// A new price for the item with this id.
    case price(Int)

    var id: String {
        switch self {
        case .service: return "service"
        case .product: return "product"
        case .amount: return "amount"
        case .price(let item): return "price-\(item)"
        }
    }
}

/// One line on the ticket: its name, its price (tap to change it), the quantity for a product, the
/// line's total, and a remove button.
struct TicketItemRow: View {
    let item: CheckoutTicket.Item
    let checkout: CheckoutModel
    let editPrice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(Money.amount(item.totalCents))
                    .font(.body.monospacedDigit().weight(.semibold))
                Button {
                    checkout.ticket.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: BusinessTheme.minimumTapSize, height: BusinessTheme.minimumTapSize)
                }
                .buttonStyle(.plain)
                .disabled(checkout.phase != .editing)
                .accessibilityLabel("Remove \(item.name)")
                .accessibilityIdentifier("removeItem-\(item.name)")
            }
            HStack(spacing: 8) {
                Button(action: editPrice) {
                    Label(item.startsAtThisPrice ? "From \(Money.amount(item.unitCents)): change price" : "\(Money.amount(item.unitCents)) each · Change", systemImage: "pencil")
                        .font(.footnote)
                        .frame(minHeight: BusinessTheme.minimumTapSize)
                }
                .disabled(checkout.phase != .editing)
                .accessibilityLabel("Change the price of \(item.name), \(Money.spoken(item.unitCents))")
                .accessibilityIdentifier("editPrice-\(item.name)")
                Spacer(minLength: 8)
                if item.isProduct {
                    Stepper(
                        "Quantity \(item.quantity)",
                        value: Binding(get: { item.quantity }, set: { checkout.ticket.setQuantity($0, of: item.id) }),
                        in: IzzyAPI.NewSaleItem.quantityRange
                    )
                    .fixedSize()
                    .disabled(checkout.phase != .editing)
                    .accessibilityLabel("Quantity of \(item.name)")
                    .accessibilityValue("\(item.quantity)")
                    .accessibilityIdentifier("quantity-\(item.name)")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ticketItem-\(item.name)")
    }
}

/// Cash or Other: a big button with an icon, a title and an optional line under it.
struct PayMethodButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title), \($0)" } ?? title)
        .accessibilityIdentifier(id)
    }
}

/// Lays its views out in rows, wrapping onto the next row when one is full (the barber chips, the
/// add buttons), so they stay big with large text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let fitted = CGSize(width: min(size.width, width), height: size.height)
            if rowWidth > 0, rowWidth + spacing + fitted.width > width {
                height += rowHeight + spacing
                widest = max(widest, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + fitted.width
            rowHeight = max(rowHeight, fitted.height)
        }
        widest = max(widest, rowWidth)
        return CGSize(width: proposal.width ?? widest, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if x > bounds.minX, x + width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: width, height: size.height))
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PaymentsLink: Hashable {}

/// Why payments can't be taken, with buttons for what to do.
struct IssueCard<Actions: View>: View {
    let issue: TerminalIssue
    var symbol = "exclamationmark.triangle.fill"
    var tint: Color = BusinessTheme.caution
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(issue.title).font(.headline)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions() }
                VStack(alignment: .leading, spacing: 8) { actions() }
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

/// "Getting Tap to Pay ready… 40%".
struct ReaderProgress: View {
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress {
                ProgressView(value: progress) {
                    Text("Getting Tap to Pay ready… \(Int((progress * 100).rounded()))%")
                        .font(.footnote)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting Tap to Pay ready…").font(.footnote)
                }
            }
            Text("The first time can take a minute or two. You can start a payment anyway.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("readerProgress")
    }
}
