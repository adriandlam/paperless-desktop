// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PaperlessCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "PaperlessCore", targets: ["PaperlessCore"])],
    targets: [
        .target(name: "PaperlessCore"),
        .testTarget(name: "PaperlessCoreTests", dependencies: ["PaperlessCore"]),
    ],
    swiftLanguageModes: [.v5]
)
