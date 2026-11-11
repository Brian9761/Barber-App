import SwiftUI
import UIKit

/// "Your details" in a sheet, from Book: change the name and number the app fills in, or forget
/// them. Appointments already booked keep the details they were booked with; the booking being
/// made takes the new ones. The card kept for no-show protection is here too, to remove it;
/// forgetting the details forgets the card as well.
///
/// Removing the card, or forgetting it with the details, also asks the shop to delete it
/// (`CardDeleter`), after a confirmation, since that can't be undone. The key leaves this iPhone
/// straight away whatever the shop answers; the sheet then says what the shop said ("Your saved card
/// is deleted…", or that it's deleted once no appointment needs it), or, when the shop couldn't be
/// reached, to call to have it deleted.
struct CustomerDetailsSheet: View {
    @Environment(CustomerDetailsStore.self) private var store
    @Environment(SavedCardStore.self) private var cards
    @Environment(AppRouter.self) private var router
    @Environment(\.shopAPI) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var showsProblems = false
    @State private var isConfirmingForget = false
    @State private var isConfirmingRemoveCard = false
    /// "Forget my details" went through with a card: the sheet stays to say what the shop answered.
    @State private var forgotten = false
    /// Asking the shop to delete the card just removed or forgotten, or what it said.
    @State private var cardRemoval: CardRemovalState?

    private var details: CustomerDetails { CustomerDetails(name: name, phone: phone) }

    /// Under the name and number: when they leave this iPhone, with the Privacy Policy linked.
    static let footer = "Filled in when you book. They leave this iPhone only with a booking, as our Privacy Policy explains."
    /// The same in the demo version, where nothing leaves the iPhone.
    static let demoFooter = "Filled in when you book. In the demo, they stay on this iPhone."

    var body: some View {
        NavigationStack {
            Form {
                if forgotten {
                    Section {
                        Label(NoShowCopy.forgottenNote, systemImage: Symbol.checkmark)
                            .foregroundStyle(Theme.bone)
                            .accessibilityIdentifier("detailsForgottenNote")
                    }
                }
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
                            isConfirmingRemoveCard = true
                        }
                        .accessibilityIdentifier("removeCardButton")
                    } header: {
                        Text(NoShowCopy.detailsCardHeader)
                    } footer: {
                        Text(NoShowCopy.detailsCardNote)
                    }
                }
                if let cardRemoval {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            if cardRemoval == .asking {
                                ProgressView()
                            }
                            Text(cardRemoval.message)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("cardRemovalMessage")
                        if cardRemoval.offersCall {
                            CallButton {
                                Label("Call \(AppData.shop.phone.display)", systemImage: Symbol.call)
                            }
                            .accessibilityIdentifier("cardRemovalCallButton")
                        }
                    } header: {
                        Text(NoShowCopy.detailsCardHeader)
                    }
                }
                if store.saved != nil || cards.saved != nil {
                    Section {
                        Button("Forget my details", role: .destructive) {
                            isConfirmingForget = true
                        }
                        .accessibilityIdentifier("forgetDetailsButton")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink2.ignoresSafeArea())
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(forgotten ? "Close" : "Cancel") { dismiss() }
                        .accessibilityIdentifier("closeDetailsButton")
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
                Button("Forget", role: .destructive, action: forget)
                Button("Keep them", role: .cancel) {}
            } message: {
                Text(NoShowCopy.forgetDetailsMessage(hasCard: cards.saved != nil))
            }
            .confirmationDialog(NoShowCopy.removeCardTitle, isPresented: $isConfirmingRemoveCard, titleVisibility: .visible) {
                Button(NoShowCopy.removeCardButton, role: .destructive, action: removeCard)
                Button(NoShowCopy.keepCardButton, role: .cancel) {}
            } message: {
                Text(NoShowCopy.removeCardMessage)
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

    /// "Remove card": off this iPhone now, and the shop is asked to delete it.
    private func removeCard() {
        guard let token = cards.saved?.token else { return }
        cards.forget()
        deleteAtShop(token)
    }

    /// "Forget my details": the name and number, and the card with them. With a card, the sheet
    /// stays to say what the shop answered about it; without one, there's nothing more to say.
    private func forget() {
        let token = RememberedDetails.forget(store, cards: cards)
        router.rememberedDetailsChanged(to: nil)
        guard let token else {
            dismiss()
            return
        }
        name = ""
        phone = ""
        showsProblems = false
        forgotten = true
        deleteAtShop(token)
    }

    /// Asks the shop to delete the card, and says what it answered (to VoiceOver too). The request
    /// isn't tied to the sheet: closing it doesn't stop the shop from deleting the card.
    private func deleteAtShop(_ token: IzzyAPI.CardToken) {
        cardRemoval = .asking
        let api = self.api
        Task {
            let result = CardRemovalState.finished(await CardDeleter.delete(token, api: api))
            cardRemoval = result
            UIAccessibility.post(notification: .announcement, argument: result.message)
        }
    }
}
