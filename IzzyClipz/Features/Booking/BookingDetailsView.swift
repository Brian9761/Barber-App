import SwiftUI

/// Step 4: who the appointment is for. A name and a US mobile number (so the shop knows who's
/// coming and can reach them), and an optional note for the barber. The name and number are
/// filled in from last time and remembered for next time, unless the client turns that off.
/// Everything typed here is kept while they book, so a trip back to the times doesn't lose it.
struct BookingDetailsView: View {
    let plan: BookingPlan

    @Environment(AppRouter.self) private var router
    @Environment(CustomerDetailsStore.self) private var savedDetails
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var remember = true
    /// Problems show once the client tries to continue, not while they type.
    @State private var showsProblems = false
    @State private var didFill = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, phone, note
    }

    static let maxNoteLength = 300

    private var details: CustomerDetails {
        CustomerDetails(name: name, phone: phone)
    }

    private var typed: BookingDetailsInProgress {
        BookingDetailsInProgress(customer: details, note: note, remember: remember)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                BookingStepHeader(
                    step: 4,
                    title: "Your details",
                    subtitle: "So the shop knows who's coming and can reach you if anything changes."
                )

                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    field(
                        "Name",
                        text: $name,
                        prompt: "First and last name",
                        problem: showsProblems ? details.nameProblem : nil,
                        identifier: "nameField"
                    )
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .phone }

                    field(
                        "Mobile number",
                        text: $phone,
                        prompt: "(442) 555-0123",
                        problem: showsProblems ? details.phoneProblem : nil,
                        identifier: "phoneField"
                    )
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focus, equals: .phone)

                    noteField
                }

                Toggle(isOn: $remember) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remember me on this iPhone")
                            .textRole(.callout)
                            .foregroundStyle(Theme.bone)
                        Text("Your name and number fill in next time.")
                            .textRole(.caption)
                            .foregroundStyle(Theme.smoke)
                    }
                }
                .tint(Theme.electric)
                .accessibilityIdentifier("rememberDetailsToggle")

                Text("Your name and number are sent only to \(AppData.shop.name), to book and manage this appointment.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .bookingStepChrome(title: "Your details")
        .stickyBottomBar {
            HStack(spacing: Theme.Space.s) {
                Button(action: continueToReview) {
                    Text("Continue")
                }
                .buttonStyle(.primary)
                .accessibilityHint("Next, review and book")
                .accessibilityIdentifier("continueToReview")
                if focus != nil {
                    hideKeyboardButton
                }
            }
        }
        .onAppear(perform: fillIn)
        .onChange(of: typed) { _, newValue in
            router.detailsInProgress = newValue
        }
    }

    /// Puts the keyboard away: the number pad has no return key. It sits next to Continue rather
    /// than in the keyboard's own toolbar, which iOS 26 floats over the Continue button.
    private var hideKeyboardButton: some View {
        Button {
            focus = nil
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.bone)
                .frame(width: 60, height: 60)
                .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Hide keyboard")
        .accessibilityIdentifier("hideKeyboard")
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        prompt: String,
        problem: String?,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .textRole(.callout)
                .foregroundStyle(Theme.bone)
                .accessibilityHidden(true)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.smoke))
                .textRole(.body)
                .foregroundStyle(Theme.bone)
                .padding(.horizontal, Theme.Space.l)
                .frame(minHeight: 50)
                .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(problem == nil ? Theme.line : Theme.caution, lineWidth: problem == nil ? 1 : 2)
                )
                .accessibilityLabel(label)
                .accessibilityHint(problem ?? "")
                .accessibilityIdentifier(identifier)
            if let problem {
                Label(problem, systemImage: Symbol.warning)
                    .textRole(.caption)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier)Problem")
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("Note for your barber")
                    .textRole(.callout)
                    .foregroundStyle(Theme.bone)
                Text("Optional")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
            }
            .accessibilityHidden(true)
            TextField(
                "Note for your barber, optional",
                text: $note,
                prompt: Text("e.g. a fade with a beard trim").foregroundStyle(Theme.smoke),
                axis: .vertical
            )
            .lineLimit(2...5)
            .textRole(.body)
            .foregroundStyle(Theme.bone)
            .padding(Theme.Space.l)
            .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.line))
            .focused($focus, equals: .note)
            .accessibilityIdentifier("noteField")
            .onChange(of: note) { _, newValue in
                if newValue.count > Self.maxNoteLength {
                    note = String(newValue.prefix(Self.maxNoteLength))
                }
            }
            Text("\(note.count) of \(Self.maxNoteLength) characters")
                .textRole(.caption)
                .foregroundStyle(Theme.smoke)
                .accessibilityHidden(note.isEmpty)
        }
    }

    /// What was typed earlier in this booking (before going back to the times), or else the name
    /// and number from last time. Coming back from the review keeps this same screen as it was.
    private func fillIn() {
        guard !didFill else { return }
        didFill = true
        let initial = BookingDetailsInProgress.start(kept: router.detailsInProgress, saved: savedDetails.saved)
        name = initial.customer.name
        phone = initial.customer.phone
        note = initial.note
        remember = initial.remember
    }

    private func continueToReview() {
        guard details.isValid else {
            showsProblems = true
            focus = details.nameProblem != nil ? .name : .phone
            UIAccessibility.post(notification: .announcement, argument: details.nameProblem ?? details.phoneProblem ?? "")
            return
        }
        // A second tap while the review slides in mustn't push it twice.
        if let last = router.bookingPath.last, case .review = last { return }
        focus = nil
        if remember {
            savedDetails.remember(details)
        } else {
            savedDetails.forget()
        }
        let draft = BookingDraft(
            plan: plan,
            customer: CustomerDetails(name: details.trimmedName, phone: details.displayPhone),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        router.bookingPath.append(.review(draft))
    }
}
