# SwiftTB2PKit（vendor 副本）

这是第三方库的**本地 vendor 副本**，不是本项目的原创代码。请勿在此目录下做
与本项目无关的重构——所有改动都应记录在下面，方便日后对齐上游。

## 来源

| 项 | 值 |
| --- | --- |
| 上游 | <https://github.com/edmw/SwiftTB2PKit> |
| 作者 | Michael Baumgärtner（TwistAssist） |
| 许可 | MIT，见 `LICENSE.md` |
| 取用 commit | `915d9f0ba25af93e8a6a811890394975afb7da91`（2025-12-31，「clarify license」） |
| 取用日期 | 2026-09-23 |

上游**没有打过任何 tag**，只能按 commit 钉版本；本地 vendor 正好把这件事固化下来。

## 它是什么

Herbert Kociemba **两阶段算法**的纯 Swift 实现，用来求三阶魔方的解。
是 [tcbegley/cube-solver](https://github.com/tcbegley/cube-solver) 的 Swift 移植
（MIT，未复制源码）。

核心产物：

- `TB2PTables.bin`（21MB）—— 预计算的转动表与剪枝表。不随包发布就得在首次运行
  时从零生成，实测 7s（含剪枝表更久），不可接受。
- `TB2PFaceCube` / `TB2PCubieCube` / `TB2PCoordCube` —— 面位 / 块位 / 坐标三套表示。
- `TB2PSolver` —— 迭代加深的两阶段搜索。

面位串约定（与 `CubeKit.FaceletNotation` 对齐）：

- 54 字符，面顺序 **U R F D L B**，每面 9 字符按「正视该面，左上→右下」行优先。
- 配色：U 白 / R 红 / F 绿 / D 黄 / L 橙 / B 蓝。

## 相对上游的改动

**1. `Package.swift`：删掉 `SwiftLintPlugins` 构建插件依赖。**

上游 target 上挂了 `plugins: [.plugin(name: "SwiftLintBuildToolPlugin", ...)]`。
在 Xcode 里构建工具插件需要人工「信任」，且会拿这个包的源码跑 lint，对宿主
项目是纯负担。删掉后不再需要任何远程依赖，`swift build` 完全离线。

**2. `Sources/SwiftTB2PKit/TB2P.swift`：新增只读属性 `isTablesResourceBundled`。**

```swift
public static var isTablesResourceBundled: Bool {
    Bundle.module.url(forResource: "TB2PTables", withExtension: "bin") != nil
}
```

上游的 `TB2P.tables` 是 `static let` 惰性全局量，加载失败时走 `fatalError`，
调用方**无法捕获**。这个属性只做查询、无副作用，让 `CubeSolve` 能在资源缺失时
抛错降级，而不是把宿主 App 崩掉。既有行为一字未改。

**3. `Tests/`：只保留上游的 `SwiftTB2PKitTests.swift`。**

上游没有别的测试文件，取用时 `Tests/` 下另外两个文件是当时临时写的验证脚本，
不属于上游，未带走。

## 已知行为（集成时必须知道）

- `TB2P.tables` 首次访问会调 `TB2PTables.loadFromBinary()`：先看
  **Caches 目录**（iOS 为 `Library/Caches/TB2PTables.bin`）有没有表；
  没有就**从零生成**（很慢）再写回去。
- 所以宿主必须在碰 `TB2P.tables` **之前**调 `TB2P.installTables()`——它会把
  bundle 里的 `TB2PTables.bin` 拷进 Caches。这一步是幂等的，已有文件就直接返回。
- iOS 会清 `Library/Caches`。因此 `installTables()` 必须**每次启动都调**，
  不能只调一次。
- `TB2P.tables` 是进程内单例，首次加载约 50ms，之后常驻。

## 升级方式

```sh
git clone https://github.com/edmw/SwiftTB2PKit.git /tmp/tb2p
cd /tmp/tb2p && git checkout <新 commit>
# 覆盖 Sources/ 与 LICENSE.md、README.md，然后照上面「相对上游的改动」重做两处修改
```

覆盖后务必跑一遍 `cd Vendor/SwiftTB2PKit && swift test`，以及
`cd CubeSolve && swift test` 里的端到端求解测试。
