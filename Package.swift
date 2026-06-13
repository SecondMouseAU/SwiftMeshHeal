// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMeshHeal",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(name: "SwiftMeshHeal", targets: ["SwiftMeshHeal"]),
    ],
    targets: [
        .target(
            name: "SwiftMeshHeal",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftMeshHealTests",
            dependencies: ["SwiftMeshHeal"]
        ),
    ]
)
