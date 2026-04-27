// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NPYViewer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "NPYCore", targets: ["NPYCore"]),
        .executable(name: "NPYViewer", targets: ["NPYViewer"])
    ],
    targets: [
        .target(name: "NPYCore"),
        .executableTarget(
            name: "NPYViewer",
            dependencies: ["NPYCore"]
        ),
        .testTarget(
            name: "NPYCoreTests",
            dependencies: ["NPYCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
