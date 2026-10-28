// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Shelf", targets: ["Shelf"]),
        .library(name: "ShelfCore", targets: ["ShelfCore"]),
    ],
    dependencies: [
        // Auto-updates: checks a signed feed, installs in the background.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.6.4"),
    ],
    targets: [
        // Pure Foundation: models, metadata fetching, capture parsing.
        // No AppKit/SwiftUI so it stays portable (and testable off-Mac).
        .target(name: "ShelfCore"),
        // The native macOS app.
        .executableTarget(
            name: "Shelf",
            dependencies: ["ShelfCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ShelfCoreTests", dependencies: ["ShelfCore"]),
    ]
)
