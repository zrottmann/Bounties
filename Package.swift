// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bounties",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project contains exactly one library product = the main app.
        .library(
            name: "Bounties",
            targets: ["Bounties"]
        ),
    ],
    targets: [
        // Pure, platform-agnostic logic — no UIKit, no PassKit. Models,
        // fee math, ledger, service protocol + stub. Compiles and unit-tests
        // on any host (including the Windows CI) without a simulator.
        .target(
            name: "BountiesKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The SwiftUI / PassKit app target (iOS only).
        .target(
            name: "Bounties",
            dependencies: ["BountiesKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BountiesKitTests",
            dependencies: ["BountiesKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
