// swift-tools-version:5.9

import PackageDescription

// Platform-independent business logic for the Izzy Clipz apps: the service
// menu, team, business hours, booking calendar, saved appointments, reminder
// scheduling, the catalog the server books against, and the client for the
// shop's server API (IzzyAPI, IzzyAPIClient).
// It only depends on Foundation (and FoundationNetworking on Linux) so it can
// be tested anywhere `swift test` runs.
let package = Package(
    name: "IzzyClipzKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "IzzyClipzKit", targets: ["IzzyClipzKit"]),
    ],
    targets: [
        .target(name: "IzzyClipzKit"),
        .testTarget(
            name: "IzzyClipzKitTests",
            dependencies: ["IzzyClipzKit"],
            // Contract fixtures, read from disk by path (like the server's own
            // fixtures next to them in the repo), not bundled.
            exclude: ["Fixtures"]
        ),
    ]
)
