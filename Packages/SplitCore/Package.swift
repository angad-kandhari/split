// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplitCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SplitCore", targets: ["SplitCore"]),
    ],
    targets: [
        .target(name: "SplitCore"),
        .testTarget(name: "SplitCoreTests", dependencies: ["SplitCore"]),
    ]
)
