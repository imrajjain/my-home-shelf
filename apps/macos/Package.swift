// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Shelf", targets: ["Shelf"]),
        .library(name: "ShelfCore", targets: ["ShelfCore"]),
    ],
    targets: [
        // Pure Foundation: models, metadata fetching, capture parsing.
        // No AppKit/SwiftUI so it stays portable (and testable off-Mac).
        .target(name: "ShelfCore"),
        // The native macOS app.
        .executableTarget(
            name: "Shelf",
            dependencies: ["ShelfCore"]
        ),
        .testTarget(name: "ShelfCoreTests", dependencies: ["ShelfCore"]),
    ]
)
