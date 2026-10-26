// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "FMRephraser",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "FMRephraser", path: "Sources/FMRephraser")
    ],
    swiftLanguageModes: [.v5]
)
