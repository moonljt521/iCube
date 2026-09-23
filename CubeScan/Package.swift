// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CubeScan",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "CubeScan", targets: ["CubeScan"])
    ],
    dependencies: [
        .package(path: "../CubeKit")
    ],
    targets: [
        .target(
            name: "CubeScan",
            dependencies: [.product(name: "CubeKit", package: "CubeKit")]
        ),
        .testTarget(name: "CubeScanTests", dependencies: ["CubeScan"])
    ]
)
