import SwiftUI

// No-show protection on screen: the "Late Cancellation & No-Show Fee" notice (Pick a day
// and time, Review) and Review's card section. What they say comes from the shop's server
// (`NoShowPolicy`) and `NoShowCopy`.

/// "Late Cancellation & No-Show Fee" and the server's message, on a card with a caution
/// outline so it can't be missed, and the note about the picked time when cancelling it can't be
/// free any more. Under it, the Cancellation & No-Show Policy, in the in-app browser, as the
/// website's notice has it (research.md §18 item 1: the policies next to the fee notice).
struct NoShowWarningCard: View {
    let content: NoShowWarningContent

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            notice
            Button {
                router.openWeb(Website.LegalPage.cancellationPolicy.url())
            } label: {
                Label(NoShowCopy.readPolicyLink, systemImage: Symbol.calendarClock)
                    .textRole(.callout)
                    .foregroundStyle(Theme.electric)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the page on the shop's website")
            .accessibilityIdentifier("feePolicyLink")
        }
        .card(padding: Theme.Space.xl)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.caution.opacity(0.7), lineWidth: 1.5)
        )
    }

    /// The notice itself, read by VoiceOver in one go.
    private var notice: some View {
        HStack(alignment: .top, spacing: Theme.Space.l) {
            Image(systemName: Symbol.warning)
                .font(.title3)
                .foregroundStyle(Theme.caution)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(content.title)
                    .textRole(.headline)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(content.message)
                    .textRole(.body)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = content.notice {
                    Label(notice, systemImage: Symbol.clock)
                        .textRole(.callout)
                        .foregroundStyle(Theme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.xxs)
                        .accessibilityIdentifier("lateCancelNotice")
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
        .accessibilityIdentifier("noShowWarning")
    }
}

/// Review's "Card on file" section, when the booking needs a card: the card (with Change), or Add
/// a card (Stripe's page), and the policy the client agrees to by booking.
struct ReviewCardSection: View {
    let requirement: NoShowRequirement
    let setup: CardSetup
    let onAddCard: () -> Void

    private let timeZone = AppData.shop.timeZone

    var body: some View {
        if let policy = requirement.policy {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(NoShowCopy.sectionTitle)
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                        .accessibilityAddTraits(.isHeader)
                    Text(NoShowCopy.sectionSubtitle)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                        .fixedSize(horizontal: false, vertical: true)
                }

                cardRow

                if let text = policy.policyText {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(NoShowCopy.agreeLabel)
                            .textRole(.label)
                            .foregroundStyle(Theme.smoke)
                        Text(text)
                            .textRole(.body)
                            .foregroundStyle(Theme.bone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("noShowPolicyText")
                }
            }
            .card(padding: Theme.Space.xl)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cardSection")
        }
    }

    @ViewBuilder private var cardRow: some View {
        if case .ready(_, let card) = requirement {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(card.label, systemImage: Symbol.payment)
                        .textRole(.headline)
                        .foregroundStyle(Theme.bone)
                    Text(card.card.expiryLabel)
                        .textRole(.caption)
                        .foregroundStyle(Theme.smoke)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(NoShowCopy.spokenCard(card.card.cardOnFile)), \(card.card.expiryLabel)")
                .accessibilityIdentifier("savedCard")
                if setup.isWorking {
                    ProgressView()
                        .accessibilityLabel(NoShowCopy.addingCard)
                } else {
                    Button(NoShowCopy.changeCardButton, action: onAddCard)
                        .buttonStyle(.textLink(color: Theme.electric))
                        .accessibilityLabel("Change card")
                        .accessibilityIdentifier("changeCardButton")
                }
            }
            failureNote
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if case .needsCard(_, let unusable?) = requirement {
                    Label(NoShowCopy.unusableCardNote(unusable, now: Date(), timeZone: timeZone), systemImage: Symbol.warning)
                        .textRole(.callout)
                        .foregroundStyle(Theme.caution)
                        .fixedSize(horizontal: false, vertical: true)
                        // "Visa ending in 4242", not each dot.
                        .accessibilityLabel(NoShowCopy.spokenUnusableCardNote(unusable, now: Date(), timeZone: timeZone))
                        .accessibilityIdentifier("unusableCardNote")
                }
                failureNote
                Button(action: onAddCard) {
                    HStack(spacing: Theme.Space.s) {
                        if setup.isWorking {
                            ProgressView()
                                .tint(Theme.ink)
                        }
                        Text(buttonTitle)
                    }
                }
                .buttonStyle(.secondary)
                .disabled(setup.isWorking)
                .accessibilityIdentifier("addCardButton")
                Text(NoShowCopy.stripePageNote)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttonTitle: String {
        if setup.isWorking { return NoShowCopy.addingCard }
        if setup.failure != nil { return NoShowCopy.tryAgainButton }
        return NoShowCopy.addCardButton
    }

    @ViewBuilder private var failureNote: some View {
        if let failure = setup.failure {
            Label(failure, systemImage: Symbol.warning)
                .textRole(.callout)
                .foregroundStyle(Theme.caution)
                .fixedSize(horizontal: false, vertical: true)
                // One message ("Warning, The card wasn't added…"), not the icon and the words apart.
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("cardError")
            // Another way forward, as with every error: the shop can book it by phone.
            CallButton {
                Label("Call the shop", systemImage: Symbol.call)
            }
            .buttonStyle(.textLink(color: Theme.electric))
            .accessibilityIdentifier("cardErrorCallButton")
        }
    }
}
