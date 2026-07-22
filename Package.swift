// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Mumble",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mumble",
            path: "Sources/Mumble"
        )
    ]
)
