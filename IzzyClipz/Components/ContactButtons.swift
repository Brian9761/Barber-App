import SwiftUI
import UIKit

/// Calls the shop. Devices that can't make calls (iPads, the Simulator) get
/// the number instead of a silent failure.
struct CallButton<Label: View>: View {
    @Environment(\.openURL) private var openURL
    @State private var showsNumber = false
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        Button {
            openURL(AppData.shop.phone.callURL) { accepted in
                if !accepted { showsNumber = true }
            }
        } label: {
            label
        }
        .accessibilityLabel("Call \(AppData.shop.name)")
        .accessibilityHint(AppData.shop.phone.spoken)
        .alert("Call \(AppData.shop.name)", isPresented: $showsNumber) {
            Button("Copy Number") {
                UIPasteboard.general.string = AppData.shop.phone.display
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device can't make calls. Reach the shop at \(AppData.shop.phone.display).")
        }
    }
}

/// Offers Apple Maps or Google Maps directions to the shop.
struct DirectionsButton<Label: View>: View {
    @Environment(\.openURL) private var openURL
    @State private var isChoosingApp = false
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        Button {
            isChoosingApp = true
        } label: {
            label
        }
        .accessibilityLabel("Directions to \(AppData.shop.name)")
        .confirmationDialog("Directions to \(AppData.shop.name)", isPresented: $isChoosingApp, titleVisibility: .visible) {
            Button("Apple Maps") { openURL(AppData.shop.appleMapsDirectionsURL) }
            Button("Google Maps") { openURL(AppData.shop.googleMapsDirectionsURL) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AppData.shop.address.singleLine)
        }
    }
}

/// The storefront photo with "DIRECTIONS" and the address over an ink fade, and a bone disc with
/// the location glyph. The text sits only where the fade is at least 75% ink.
struct DirectionsTile: View {
    private let address = AppData.shop.address
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 80% ink from 40% of the way down, where the two lines start up to xLarge text (at the
    /// default size they start at about 47%). From xxLarge they reach higher up the tile than any
    /// fade can follow, so the whole photo sits under 80% ink.
    private var scrim: [Gradient.Stop] {
        if dynamicTypeSize >= .xxLarge {
            return [
                .init(color: Theme.ink.opacity(0.80), location: 0),
                .init(color: Theme.ink.opacity(0.88), location: 1),
            ]
        }
        return [
            .init(color: Theme.ink.opacity(0.15), location: 0),
            .init(color: Theme.ink.opacity(0.80), location: 0.4),
            .init(color: Theme.ink.opacity(0.88), location: 1),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Image(systemName: Symbol.directions)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
                .background(Theme.bone, in: Circle())
                .accessibilityHidden(true)
            Spacer(minLength: Theme.Space.l)
            VStack(alignment: .leading, spacing: 2) {
                Text("Directions")
                    .textRole(.buttonSmall)
                    .foregroundStyle(Theme.bone)
                Text(address.streetLine)
                    .textRole(.caption)
                    .foregroundStyle(Theme.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            ZStack {
                FillImage(name: Asset.storefront)
                LinearGradient(stops: scrim, startPoint: .top, endPoint: .bottom)
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }
}

/// "Call" and the shop's number on an ink tile with an electric phone icon.
struct CallTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Image(systemName: Symbol.call)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Theme.electric, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            Spacer(minLength: Theme.Space.l)
            VStack(alignment: .leading, spacing: 2) {
                Text("Call")
                    .textRole(.buttonSmall)
                    .foregroundStyle(Theme.bone)
                Text(AppData.shop.phone.display)
                    .textRole(.caption)
                    .foregroundStyle(Theme.smoke)
                    .monospacedDigit()
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Theme.ink3, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
    }
}

/// Home's quick actions: Directions and Call side by side, stacked at the largest text sizes.
/// (Instagram has its own card.)
struct QuickActions: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize >= .xxxLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.s))
        layout {
            DirectionsButton { DirectionsTile() }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("directionsButton")
            CallButton { CallTile() }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("callButton")
        }
        // Both tiles as tall as the taller one.
        .fixedSize(horizontal: false, vertical: true)
    }
}
