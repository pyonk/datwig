// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Datwig",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Datwig",
            targets: ["Datwig"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Datwig",
            dependencies: [],
            path: "Sources/Datwig"
        ),
        .testTarget(
            name: "DatwigTests",
            dependencies: ["Datwig"],
            path: "Tests/DatwigTests"
        )
    ]
)
