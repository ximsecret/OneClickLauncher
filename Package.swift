// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "OneClickLauncher",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "OneClickLauncher", targets: ["OneClickLauncher"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OneClickLauncher",
            dependencies: [],
            path: "Sources/OneClickLauncher"
        )
    ]
)
