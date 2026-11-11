import SwiftUI

/// "Your details" in a sheet, from Book: change the name and number the app fills in, or forget
/// them. Appointments already booked keep the details they were booked with; the booking being
/// made takes the new ones. The card kept for no-show protection is here too, to remove it;
/// forgetting the details forgets the card as well.
struct CustomerDetailsSheet: View {
    @Environment(CustomerDetailsStore.self) private var store
    @Environment(SavedCardStore.self) private var cards
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var showsProblems = false
    @State private var isConfirmingForget = false

    private var details: CustomerDetails { CustomerDetails(name: name, phone: phone) }

    /// Under the name and number: when they leave this iPhone, with the Privacy Policy linked.
    static let footer = "Filled in when you book. They leave this iPhone only with a booking, as our Privacy Policy explains."
    /// The same in the demo version, where nothing leaves the iPhone.
    static let demoFooter = "Filled in when you book. In the demo, they stay on this iPhone."

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("detailsSheetName")
                    if showsProblems, let problem = details.nameProblem {
                        Text(problem)
                            .textRole(.caption)
                            .foregroundStyle(Theme.caution)
                    }
                    TextField("Mobile number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .accessibilityIdentifier("detailsSheetPhone")
                    if showsProblems, let problem = details.phoneProblem {
                        Text(problem)
                            .textRole(.caption)
                            .foregroundStyle(Theme.caution)
                    }
                } footer: {
                    if DemoMode.isOn {
                        Text(Self.demoFooter)
                    } else {
                        LegalLinksText(text: Self.footer, pages: LegalCopy.detailsPrivacyPages)
                    }
                }
                if let card = cards.saved {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.label)
                            Text(card.card.isValid(at: Date(), in: AppData.shop.timeZone) ? card.card.expiryLabel : "Expired")
                                .textRole(.caption)
                                .foregroundStyle(Theme.smoke)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            NoShowCopy.spokenCard(card.card.cardOnFile) + ", "
                                + (card.card.isValid(at: Date(), in: AppData.shop.timeZone) ? card.card.expiryLabel : "Expired")
                        )
                        .accessibilityIdentifier("detailsSheetCard")
                        Button(NoShowCopy.removeCardButton, role: .destructive) {
                            cards.forget()
                        }
                        .accessibilityIdentifier("removeCardButton")
                    } header: {
                        Text(NoShowCopy.detailsCardHeader)
                    } footer: {
                        Text(NoShowCopy.detailsCardNote)
                    }
                }
                Section {
                    Button("Forget my details", role: .destructive) {
                        isConfirmingForget = true
                    }
                    .accessibilityIdentifier("forgetDetailsButton")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink2.ignoresSafeArea())
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("saveDetailsButton")
                }
            }
            .confirmationDialog(
                NoShowCopy.forgetDetailsTitle(hasCard: cards.saved != nil),
                isPresented: $isConfirmingForget,
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    RememberedDetails.forget(store, cards: cards)
                    router.rememberedDetailsChanged(to: nil)
                    dismiss()
                }
                Button("Keep them", role: .cancel) {}
            } message: {
                Text(NoShowCopy.forgetDetailsMessage(hasCard: cards.saved != nil))
            }
        }
        .onAppear {
            name = store.saved?.name ?? ""
            phone = store.saved?.phone ?? ""
        }
    }

    private func save() {
        guard details.isValid else {
            showsProblems = true
            return
        }
        store.remember(details)
        router.rememberedDetailsChanged(to: store.saved)
        dismiss()
    }
}
