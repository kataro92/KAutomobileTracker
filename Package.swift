// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KAutomobileTracker",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "KAutomobileTracker", targets: ["KAutomobileTracker"]),
        .library(name: "KAutomobileTrackerCore", targets: ["KAutomobileTrackerCore"]),
    ],
    targets: [
        .target(
            name: "KAutomobileTrackerCore",
            path: "Sources/KAutomobileTrackerCore"
        ),
        .executableTarget(
            name: "KAutomobileTracker",
            dependencies: ["KAutomobileTrackerCore"],
            path: "Sources/KAutomobileTracker",
            exclude: ["Resources/Info.plist"]
        ),
        .testTarget(
            name: "KAutomobileTrackerTests",
            dependencies: ["KAutomobileTrackerCore"],
            path: "Tests/KAutomobileTrackerTests"
        ),
    ]
)
