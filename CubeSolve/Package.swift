// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CubeSolve",
    platforms: [.macOS(.v13), .iOS(.v18)],
    products: [
        .library(name: "CubeSolve", targets: ["CubeSolve"])
    ],
    dependencies: [
        .package(path: "../CubeKit"),
        .package(path: "../Vendor/SwiftTB2PKit"),
    ],
    targets: [
        .target(
            name: "CubeSolve",
            dependencies: [
                .product(name: "CubeKit", package: "CubeKit"),
                .product(name: "SwiftTB2PKit", package: "SwiftTB2PKit"),
            ],
        ),
        .testTarget(
            name: "CubeSolveTests",
            dependencies: ["CubeSolve"],
        ),
    ],
)
