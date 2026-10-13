// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltTabber",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AltTabber", targets: ["AltTabber"])
    ],
    targets: [
        .executableTarget(
            name: "AltTabber",
            path: "Sources/AltTabber"
        ),
        .testTarget(
            name: "AltTabberTests",
            dependencies: ["AltTabber"],
            path: "Tests/AltTabberTests"
        )
    ]
)
