// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacStatus",
            path: "Sources/MacStatus"
        )
    ]
)
