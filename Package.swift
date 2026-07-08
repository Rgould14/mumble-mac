// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenFlow",
            path: "Sources/OpenFlow"
        )
    ]
)
