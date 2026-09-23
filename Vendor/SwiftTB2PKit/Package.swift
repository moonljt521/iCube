// swift-tools-version: 6.2
//
// 本项目 vendor 版：相对上游 915d9f0 只做了一处删减——
// 去掉 SwiftLintPlugins 构建插件依赖（Xcode 里需要手动信任，且会拿本包源码
// 跑 lint，对本项目是纯负担）。其余清单与上游逐字一致。
// 详见 VENDORED.md。

import PackageDescription

let package = Package(
    name: "SwiftTB2PKit",
    platforms: [
        .macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SwiftTB2PKit",
            targets: ["SwiftTB2PKit"],
        ),
    ],
    targets: [
        .target(
            name: "SwiftTB2PKit",
            resources: [
                .process("TB2PTables.bin")
            ],
        ),
        .testTarget(
            name: "SwiftTB2PKitTests",
            dependencies: ["SwiftTB2PKit"],
        ),
    ],
)
