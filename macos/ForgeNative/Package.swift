// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ForgeNative",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "ForgeNative", targets: ["ForgeNative"])
    ],
    targets: [
        .executableTarget(
            name: "ForgeNative",
            path: "Sources/ForgeNative",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ForgeNativeTests",
            dependencies: ["ForgeNative"],
            path: "Tests/ForgeNativeTests"
        )
    ]
)
