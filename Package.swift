// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComfyQueueBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ComfyQueueBar", targets: ["ComfyQueueBar"]),
    ],
    targets: [
        .executableTarget(name: "ComfyQueueBar"),
    ]
)
