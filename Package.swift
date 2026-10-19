// swift-tools-version: 6.0
// The Xcode project (project.yml) is what ships to the App Store and as a DMG. This package lets the core
// library and its tests build with plain `swift build` / `swift test`, and gives a quick `swift run` dev loop.
import PackageDescription

let package = Package(
    name: "TronIPTV",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TronIPTVCore", targets: ["TronIPTVCore"]),
        .executable(name: "TronIPTV", targets: ["TronIPTV"]),
    ],
    targets: [
        .target(name: "TronIPTVCore"),
        .binaryTarget(name: "VLCKit", path: "Frameworks/VLCKit.xcframework"),
        .executableTarget(
            name: "TronIPTV",
            dependencies: ["TronIPTVCore", "VLCKit"],
            path: "App/Sources"
        ),
        .testTarget(
            name: "TronIPTVCoreTests",
            dependencies: ["TronIPTVCore"]
        ),
    ]
)
