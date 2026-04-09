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
            path: "Sources/KAutomobileTrackerCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "KAutomobileTracker",
            dependencies: ["KAutomobileTrackerCore"],
            path: "Sources/KAutomobileTracker",
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources/Models")]
        ),
        .testTarget(
            name: "KAutomobileTrackerTests",
            dependencies: ["KAutomobileTrackerCore"],
            path: "Tests/KAutomobileTrackerTests"
        ),
    ]
)
