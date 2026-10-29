// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brim",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "Brim",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Brim",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "BrimTests", dependencies: ["Brim"])
    ]
)
