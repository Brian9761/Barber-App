import MapKit
import SwiftUI
import UIKit

struct VisitView: View {
    private let shop = AppData.shop

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    MapCard()
                    AddressCard()
                    HoursSection()
                    InfoSection()
                    storefront
                    about
                    links
                    footer
                }
                .padding(Theme.gutter)
            }
            .screenBackground()
            .navigationTitle("Visit")
        }
    }

    private var storefront: some View {
        VStack(alignment: .leading, spacing: 10) {
            FillImage(name: Asset.storefront)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .accessibilityLabel("The Izzy Clipz storefront on Mission Avenue")
            Text("Look for the Izzy Clipz sign at \(shop.address.street).")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("About")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shop.about, id: \.self) { paragraph in
                    Text(paragraph)
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private var links: some View {
        VStack(spacing: 12) {
            Link(destination: shop.instagramURL) {
                Label("@\(shop.instagramHandle)", systemImage: Symbol.instagram)
            }
            .buttonStyle(.secondary)

            Link(destination: shop.websiteURL) {
                Label("izzyclipzbarbershop.net", systemImage: Symbol.website)
            }
            .buttonStyle(.secondary)

            ShareLink(
                item: shop.websiteURL,
                subject: Text(shop.fullName),
                message: Text("\(shop.fullName), \(shop.address.singleLine)")
            ) {
                Label("Share the shop", systemImage: Symbol.share)
            }
            .buttonStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Appointments are booked and managed on Squire.")
            Text("Version \(Self.appVersion)")
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct MapCard: View {
    private let shop = AppData.shop

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: shop.coordinate.latitude, longitude: shop.coordinate.longitude)
    }

    var body: some View {
        DirectionsButton {
            Map(
                initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                interactionModes: []
            ) {
                Marker(shop.name, systemImage: Symbol.services, coordinate: coordinate)
                    .tint(Theme.red)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
            .overlay(alignment: .bottomTrailing) {
                Label("Directions", systemImage: Symbol.directions)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.red, in: Capsule())
                    .padding(12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("mapDirections")
    }
}

private struct AddressCard: View {
    @State private var copyCount = 0
    @State private var showsCopied = false
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(shop.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(shop.address.streetLine)
                    Text(shop.address.cityLine)
                }
                .foregroundStyle(Theme.secondaryText)
                .accessibilityElement(children: .combine)

                Spacer(minLength: 12)

                Button {
                    UIPasteboard.general.string = shop.address.singleLine
                    showsCopied = true
                    copyCount += 1
                } label: {
                    Image(systemName: showsCopied ? Symbol.checkmark : Symbol.copy)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel(showsCopied ? "Address copied" : "Copy address")
                .sensoryFeedback(.success, trigger: copyCount)
                .task(id: copyCount) {
                    guard copyCount > 0 else { return }
                    do {
                        try await Task.sleep(for: .seconds(2))
                        showsCopied = false
                    } catch {
                        // Cancelled by another copy, which restarts the timer.
                    }
                }
            }

            HStack(spacing: 12) {
                DirectionsButton {
                    Label("Directions", systemImage: Symbol.directions)
                }
                .buttonStyle(.primary)

                CallButton {
                    Label("Call", systemImage: Symbol.call)
                }
                .buttonStyle(.secondary)
            }
        }
        .card()
    }
}

private struct HoursSection: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let clock = AppData.clock
            let today = clock.weekday(of: context.date)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Hours")
                StatusPill(summary: clock.summary(at: context.date))

                VStack(spacing: 12) {
                    ForEach(Weekday.mondayFirst) { day in
                        let isToday = day == today
                        HStack(spacing: 8) {
                            Text(day.name)
                                .fontWeight(isToday ? .bold : .regular)
                            if isToday {
                                Text("TODAY")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.red, in: Capsule())
                            }
                            Spacer(minLength: 12)
                            Text(clock.schedule.hours(on: day)?.label ?? "Closed")
                                .fontWeight(isToday ? .bold : .regular)
                                .multilineTextAlignment(.trailing)
                        }
                        .foregroundStyle(isToday ? Color.white : Theme.secondaryText)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(day.name)\(isToday ? ", today" : ""): \(clock.schedule.hours(on: day)?.label ?? "Closed")"
                        )
                    }
                }
                .card()

                Text("Hours are in Pacific time and may change on holidays. Walk-ins are welcome any time we're open.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct InfoSection: View {
    private let shop = AppData.shop

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Good to know")
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(symbol: Symbol.walkIn, title: "Walk-ins & appointments", detail: shop.highlights.joined(separator: " · "))
                InfoRow(symbol: Symbol.payment, title: "Payment", detail: shop.paymentMethods.joined(separator: " · "))
                InfoRow(symbol: Symbol.accessibility, title: "Accessibility", detail: shop.accessibility.joined(separator: " · "))
            }
            .card()
        }
    }
}

private struct InfoRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.red)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
