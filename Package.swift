// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KAutomobileTracker",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "KAutomobileTracker", targets: ["KAutomobileTracker"]),
    ],
    targets: [
        .executableTarget(
            name: "KAutomobileTracker",
            path: "Sources/KAutomobileTracker",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
