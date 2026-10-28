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

/// An icon-over-label tile for quick actions.
struct ActionTile: View {
    let title: String
    let symbol: String
    /// Symbols differ in height; a shared frame keeps the labels in line.
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: iconSize, height: iconSize)
                .background(Theme.tint, in: Circle())
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.shadow, radius: 10, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Call, directions and Instagram, side by side, or stacked at large text sizes.
struct QuickActions: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { tiles }
            VStack(spacing: 12) { tiles }
        }
    }

    @ViewBuilder private var tiles: some View {
        CallButton { ActionTile(title: "Call", symbol: Symbol.call) }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("callButton")
        DirectionsButton { ActionTile(title: "Directions", symbol: Symbol.directions) }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("directionsButton")
        Link(destination: AppData.shop.instagramURL) {
            ActionTile(title: "Instagram", symbol: Symbol.instagram)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(AppData.shop.name) on Instagram")
        .accessibilityIdentifier("instagramButton")
    }
}
