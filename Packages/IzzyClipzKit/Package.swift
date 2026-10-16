// swift-tools-version:5.9

import PackageDescription

// Platform-independent business logic for the Izzy Clipz app: the service
// menu, team, business hours, booking links and reminder scheduling.
// It only depends on Foundation so it can be tested anywhere `swift test` runs.
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
        .testTarget(name: "IzzyClipzKitTests", dependencies: ["IzzyClipzKit"]),
    ]
)
