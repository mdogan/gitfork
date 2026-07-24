// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GitFork",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitFork", targets: ["GitFork"])
    ],
    targets: [
        .executableTarget(
            name: "GitFork",
            path: "Sources/GitFork"
        ),
        .testTarget(
            name: "GitForkTests",
            dependencies: ["GitFork"],
            path: "Tests/GitForkTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
