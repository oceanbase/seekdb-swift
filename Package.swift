// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "seekdb-swift",
    platforms: [.iOS("18.0")],
    products: [.library(name: "SeekDB", targets: ["SeekDB"])],
    targets: [
        .systemLibrary(name: "CSeekDB"),
        .target(
            name: "SeekDB",
            dependencies: ["CSeekDB", "SeekDBEngine"],
            swiftSettings: [.enableExperimentalFeature("CheckImplementationOnly")]
        ),
        .binaryTarget(
            name: "SeekDBEngine",
            url: "https://github.com/cao1629/seekdb-swift/releases/download/0.1.0/SeekDBEngine.xcframework.zip",
            checksum: "20eb7bcb6f20912887251b13cd3819e9ac0a6cf043175135c6591060e79a783e"
        ),
    ]
)
