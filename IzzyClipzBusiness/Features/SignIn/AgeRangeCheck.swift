#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
import IzzyClipzKit
import SwiftUI

extension View {
    /// Asks iOS for the person's age range at launch, where a law requires it (`AgeCheck`), and puts
    /// the answer in `outcome`. Nothing happens on iOS before 26, or when `isEnabled` is off (UI
    /// tests and previews, which mustn't show iOS's sheet).
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
            // Not available (an unsigned build, say): carry on.
            return .failed
        }
    }
}
#endif

/// What someone under 13 sees instead of the app: it's for the shop's team, a parent or guardian
/// books for a child, and the shop's number. No details are asked for.
struct UnderAgeView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 140)
                .accessibilityHidden(true)
            Text(AgeCheck.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("underAgeTitle")
            Text(AgeCheck.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                openURL(ShopInfo.izzyClipz.phone.callURL)
            } label: {
                Label("Call \(ShopInfo.izzyClipz.phone.display)", systemImage: "phone.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("underAgeCall")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
