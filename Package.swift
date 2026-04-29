// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NPYViewer",
    platforms: [
        .macOS(.v11)
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
        .target(
            name: "NPYViewerSupport",
            dependencies: ["NPYCore"],
            path: "sources/NPYViewerSupport"
        ),
        .target(
            name: "NPYViewerApp",
            dependencies: ["NPYCore", "NPYViewerSupport"],
            path: "sources/NPYViewer",
            exclude: ["Shaders.metal"]
        ),
        .executableTarget(
            name: "NPYViewer",
            dependencies: ["NPYViewerApp"],
            path: "sources/NPYViewerExecutable"
        ),
        .testTarget(
            name: "NPYCoreTests",
            dependencies: ["NPYCore"],
            path: "tests/NPYCoreTests"
        ),
        .testTarget(
            name: "NPYViewerSupportTests",
            dependencies: ["NPYCore", "NPYViewerSupport"],
            path: "tests/NPYViewerSupportTests"
        ),
        .testTarget(
            name: "NPYViewerAppTests",
            dependencies: ["NPYCore", "NPYViewerApp", "NPYViewerSupport"],
            path: "tests/NPYViewerAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
