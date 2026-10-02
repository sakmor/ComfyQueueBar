// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComfyQueueBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ComfyQueueBar", targets: ["ComfyQueueBar"]),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "ComfyQueueBar", dependencies: [.product(name: "Sparkle", package: "Sparkle")], swiftSettings: [.unsafeFlags(["-parse-as-library"])], linkerSettings: [.linkedFramework("AVKit")]),
    ]
)
