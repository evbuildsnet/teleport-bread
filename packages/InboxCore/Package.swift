// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InboxCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "InboxCore", targets: ["InboxCore"])
    ],
    targets: [
        .target(name: "InboxCore"),
        .executableTarget(
            name: "spike",
            dependencies: ["InboxCore"],
            linkerSettings: [
                // Embed Info.plist so a bare CLI binary can request Reminders
                // access (TCC requires usage-description keys in the binary).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/spike/Info.plist",
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(name: "InboxCoreTests", dependencies: ["InboxCore"]),
    ]
)
