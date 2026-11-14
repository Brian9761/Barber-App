#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import SwiftUI

extension View {
    /// Asks iOS for the person's age range at launch, where a law requires it (`AgeCheck`), and puts
    /// the answer in `outcome`. Nothing happens before iOS 26, in an SDK without the framework, or
    /// when `isEnabled` is off (UI tests, which mustn't show iOS's sheet).
    func ageRangeCheck(isEnabled: Bool, outcome: Binding<AgeCheck.Outcome>) -> some View {
        modifier(AgeRangeCheck(isEnabled: isEnabled, outcome: outcome))
    }
}

private struct AgeRangeCheck: ViewModifier {
    let isEnabled: Bool
    @Binding var outcome: AgeCheck.Outcome

    func body(content: Content) -> some View {
        if isEnabled {
            #if canImport(DeclaredAgeRange)
            if #available(iOS 26.0, *) {
                content.background(AgeRangeAsker(outcome: $outcome))
            } else {
                content
            }
            #else
            content
            #endif
        } else {
            content
        }
    }
}

#if canImport(DeclaredAgeRange)
/// Asks once, when the app opens. iOS shows its own sheet the first time and remembers the answer;
/// the app keeps it only in memory.
@available(iOS 26.0, *)
private struct AgeRangeAsker: View {
    @Binding var outcome: AgeCheck.Outcome
    @Environment(\.requestAgeRange) private var requestAgeRange

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task { outcome = await ask() }
    }

    private func ask() async -> AgeCheck.Outcome {
        do {
            // Only where a law requires the signal (AB 1856 bars asking elsewhere). iOS 26.0 and 26.1
            // can't say, so the app asks there.
            if #available(iOS 26.2, *) {
                guard try await AgeRangeService.shared.isEligibleForAgeFeatures else { return .notAsked }
            }
            switch try await requestAgeRange(ageGates: AgeCheck.ageGate) {
            case .declinedSharing:
                return .declined
            case .sharing(let range):
                return AgeCheck.outcome(lowerBound: range.lowerBound, upperBound: range.upperBound)
            @unknown default:
                return .notAsked
            }
        } catch {
            // Not available (a build without the entitlement, say): carry on.
            return .failed
        }
    }
}
#endif

/// What someone under 13 sees instead of the app: a calm screen asking a parent or guardian to
/// book, with the shop's number to call. No tabs and nothing to fill in, so no details are taken.
struct ParentScreen: View {
    private let shop = AppData.shop

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                LogoBadge(size: 72)
                    .accessibilityHidden(true)
                VStack(spacing: Theme.Space.m) {
                    Text(AgeCheck.title)
                        .textRole(.displayM)
                        .foregroundStyle(Theme.bone)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("parentScreenTitle")
                    Text(AgeCheck.message)
                        .textRole(.body)
                        .foregroundStyle(Theme.smoke)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("parentScreenMessage")
                }
                CallButton {
                    Label("Call \(shop.phone.display)", systemImage: Symbol.call)
                }
                .buttonStyle(.primary(trailingSymbol: nil))
                .accessibilityIdentifier("parentScreenCall")
                Text("\(shop.fullName) · \(shop.address.singleLine)")
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, Theme.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }
}
