// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NPYViewer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NPYCore", targets: ["NPYCore"]),
        .executable(name: "NPYViewer", targets: ["NPYViewer"])
    ],
    targets: [
        .target(
            name: "NPYCore",
            path: "sources/NPYCore"
        ),
        .executableTarget(
            name: "NPYViewer",
            dependencies: ["NPYCore"],
            path: "sources/NPYViewer"
        ),
        .testTarget(
            name: "NPYCoreTests",
            dependencies: ["NPYCore"],
            path: "tests/NPYCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
