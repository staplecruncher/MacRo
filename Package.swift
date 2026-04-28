// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacRo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacRo",
            targets: ["MacRo"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacRo",
            path: "Sources/MacRo"
        ),
        .testTarget(
            name: "MacRoTests",
            dependencies: ["MacRo"],
            path: "Tests/MacRoTests"
        )
    ]
)
