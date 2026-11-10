// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenZones",
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "PrivateAPI", path: "Sources/PrivateAPI"),
        .executableTarget(name: "ScreenZones", dependencies: ["PrivateAPI"], path: "Sources/ScreenZones"),
        .testTarget(name: "ScreenZonesTests", dependencies: ["ScreenZones"], path: "Tests/ScreenZonesTests")
    ]
)
