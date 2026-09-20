// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CubeKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "CubeKit", targets: ["CubeKit"])
    ],
    targets: [
        .target(name: "CubeKit"),
        .testTarget(name: "CubeKitTests", dependencies: ["CubeKit"])
    ]
)
