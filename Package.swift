// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Brim",
            path: "Sources/Brim"
        ),
        .testTarget(name: "BrimTests", dependencies: ["Brim"])
    ]
)
