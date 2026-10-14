// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltTabber",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AltTabber", targets: ["AltTabber"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "AltTabber",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/AltTabber"
        ),
        .testTarget(
            name: "AltTabberTests",
            dependencies: ["AltTabber"],
            path: "Tests/AltTabberTests"
        )
    ]
)
