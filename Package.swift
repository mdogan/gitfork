// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GitFork",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitFork", targets: ["GitFork"]),
        .executable(name: "fork", targets: ["ForkCLI"])
    ],
    targets: [
        .executableTarget(
            name: "GitFork",
            path: "Sources/GitFork"
        ),
        .target(
            name: "ForkCLIKit",
            path: "Sources/ForkCLIKit"
        ),
        .executableTarget(
            name: "ForkCLI",
            dependencies: ["ForkCLIKit"],
            path: "Sources/ForkCLI"
        ),
        .testTarget(
            name: "GitForkTests",
            dependencies: ["GitFork"],
            path: "Tests/GitForkTests"
        ),
        .testTarget(
            name: "ForkCLIKitTests",
            dependencies: ["ForkCLIKit"],
            path: "Tests/ForkCLIKitTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
