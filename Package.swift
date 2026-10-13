// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpeakWay",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "SpeakWay", targets: ["SpeakWay"])],
    targets: [
        .target(name: "SpeakWayCore"),
        .executableTarget(name: "SpeakWay", dependencies: ["SpeakWayCore"]),
        .testTarget(name: "SpeakWayCoreTests", dependencies: ["SpeakWayCore"])
    ],
    swiftLanguageModes: [.v5]
)
