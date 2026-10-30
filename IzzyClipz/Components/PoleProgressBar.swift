import SwiftUI

/// The booking steps as short horizontal poles: finished steps are striped, the current one is
/// striped and wider, the steps to come are plain `ink4`.
///
/// When a step advances (the bar appears for the first time on a newly pushed step, or `step`
/// goes up) the current segment spins once, one stripe period, then holds still. Popping back to
/// an earlier step doesn't spin it again. With Reduce Motion nothing moves. VoiceOver reads it as
/// one element: "Step 3 of 4".
///
///     PoleProgressBar(step: 3)
struct PoleProgressBar: View {
    /// The current step, from 1.
    let step: Int
    var total = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0
    @State private var hasAppeared = false

    /// Tall enough that the stripes keep a readable period (0.92 × the glass width).
    private let height: CGFloat = 8
    private let segmentWidth: CGFloat = 26
    private let currentWidth: CGFloat = 44

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(total, 1), id: \.self) { index in
                segment(index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(max(step, 1), total)) of \(total)")
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            spinOnce()
        }
        .onChange(of: step) { oldStep, newStep in
            if newStep > oldStep {
                spinOnce()
            }
        }
    }

    @ViewBuilder private func segment(_ index: Int) -> some View {
        let isCurrent = index == step
        let width = isCurrent ? currentWidth : segmentWidth
        if index <= step {
            HorizontalPole(phase: isCurrent ? spin : 0)
                .frame(width: width, height: height)
                .clipShape(Capsule())
        } else {
            Capsule()
                .fill(Theme.ink4)
                .frame(width: width, height: height)
        }
    }

    private func spinOnce() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.7)) {
            spin += 1
        }
    }
}

/// A glass-only pole lying on its side: its top points left, so the stripes travel left as it spins.
/// The same renderer as every other pole, so the stripes match.
private struct HorizontalPole: View, Animatable {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        Canvas { context, size in
            var sideways = context
            // Drawing point (x, y) lands on (y, height − x): the pole's length runs along the width.
            sideways.translateBy(x: 0, y: size.height)
            sideways.rotate(by: .degrees(-90))
            BarberPoleRenderer.draw(
                in: sideways,
                rect: CGRect(x: 0, y: 0, width: size.height, height: size.width),
                phase: phase,
                detail: .glassOnly,
                colors: .streetDrip
            )
        }
        .accessibilityHidden(true)
    }
}
