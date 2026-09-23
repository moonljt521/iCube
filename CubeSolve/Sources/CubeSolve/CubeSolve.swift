import CubeKit
import Foundation
import SwiftTB2PKit

/// 求解失败的原因。
///
/// 底层求解库的 `TB2PError` 不直接暴露给上层——它是 vendor 进来的第三方类型，
/// 换实现就会变。这里把它的语义翻译成本项目自己的错误面。
public enum CubeSolveError: Error, Equatable, Sendable {
    /// 只有 2/3 阶有求解器。四阶要先做降阶（中心归位 + 翼棱配对），尚未实现。
    case unsupportedSize(Int)

    /// 该状态在物理上不可能：单角翻转、单棱翻转、两角互换等。
    /// 拍照识别出错时最可能落到这里——它是"识别结果需要人工复核"的信号。
    case illegalState(reason: String)

    /// 求解器依赖的查找表资源没有打进产物。
    /// 走到这一步说明构建配置有问题，不是运行期偶发。
    case solverUnavailable

    /// 在给定时间内没搜到解。
    case timedOut

    /// 在给定步数上限内没搜到解。合法状态几乎不会发生，留作兜底。
    case noSolutionFound(maxLength: Int)

    /// 求解库返回了本项目的记法解析器读不懂的解。
    /// 正常不会发生，一旦出现说明两边约定脱节了。
    case unparsableSolution(String)

    /// 二阶走的是"嵌入三阶"的路子（见 `CubeSolve.solveTwoByTwo`），
    /// 解出来之后会拿原状态自检一遍。自检不过说明映射写错了，是实现 bug，不是用户的问题。
    case selfCheckFailed(notation: String)
}

/// 一次求解的结果。
public struct CubeSolution: Hashable, Sendable {
    /// 解，已经解析成 CubeKit 的转动序列，可直接交给场景播放。
    public let algorithm: Algorithm

    /// 求解库给出的原始记法串（形如 `U2 B' U F L'`），便于日志与人工核对。
    public let notation: String

    /// 步数
    public var count: Int { algorithm.count }

    public init(algorithm: Algorithm, notation: String) {
        self.algorithm = algorithm
        self.notation = notation
    }

    /// 已还原的魔方不需要解
    public static let alreadySolved = CubeSolution(algorithm: Algorithm([]), notation: "")
}

/// 魔方求解器（2 阶与 3 阶）。
///
/// 三阶内部是 vendor 进 `Vendor/SwiftTB2PKit` 的 Kociemba 两阶段算法实现；
/// 二阶没有单独的求解器，走**嵌入三阶**的路子（见下）。这一层只做三件事：
/// 把 `CubeState` 译成面位串、把底层错误译成本项目的错误、把结果译回 `Algorithm`。
///
/// ## 调用姿势
///
/// ```swift
/// try CubeSolve.prepare()                                  // 启动时调一次，可放后台
/// let solution = try CubeSolve.solve(state)                // 同步，典型 40ms
/// scene.play(solution.algorithm)                           // 交给场景播放
/// ```
///
/// `solve` 是同步且 CPU 密集的，在 iOS 上应放到主线程之外执行。
public enum CubeSolve {

    // MARK: - 可用性

    /// 查找表资源是否随产物一起打包。
    ///
    /// 为 false 时 `solve` 会抛 `solverUnavailable`，不会去碰底层那个
    /// 加载失败即 `fatalError` 的单例。
    public static var isAvailable: Bool {
        TB2P.isTablesResourceBundled
    }

    // MARK: - 预热

    /// 把查找表就位并触发首次加载。
    ///
    /// 底层把表存在 Caches 目录，而 iOS 会清 Caches，所以**每次启动都要调**，
    /// 不能只调一次。本方法是幂等的：表已就位时只是一次文件存在性检查。
    ///
    /// 首次调用会从 bundle 拷 21MB 进 Caches（约 50ms）并把表读进内存，
    /// 之后常驻。建议在启动时丢到后台队列调一次，别卡首屏。
    public static func prepare() throws {
        guard TB2P.isTablesResourceBundled else {
            throw CubeSolveError.solverUnavailable
        }
        // 幂等：Caches 里已有表就直接返回
        try TB2P.installTables()
        // 触发一次性加载。走到这里表文件必然存在，不会落到建表或 fatalError 分支
        _ = TB2P.tables
    }

    // MARK: - 求解

    /// 求还原步骤。
    ///
    /// - Parameters:
    ///   - state: 待求解的状态。支持 2 阶与 3 阶；四阶还没有求解器（要先做降阶）。
    ///   - maxLength: 解的长度上限。底层按深度迭代加深，返回搜到的第一个解。
    ///     调大只会让"搜不到"的兜底更宽松，不会让解更长。
    ///   - timeout: 搜索时间上限（秒）。
    /// - Returns: 解。已还原的状态返回空解。
    /// - Throws: `CubeSolveError`
    ///
    /// ## 关于解的长度
    ///
    /// **不保证最短。** 两阶段算法用两张二维剪枝表做下界剪枝，而下界是"可采纳
    /// 但不精确"的——当它高估了到目标子群的距离时，浅层搜索会被整段剪掉，于是
    /// 找到的解可能明显长于最优。
    ///
    /// 实测（`CubeSolveTests.test_singleTurnSolutionsAreDocumented`）：
    ///
    /// | 状态 | 解 |
    /// | --- | --- |
    /// | `U` / `D` 全族 | 1 步（最优） |
    /// | `F'` `F2` `B'` `B2` `R'` `R2` `L'` `L2` | 1 步（最优） |
    /// | `F` `B` `R` `L` | 8 步（非最优） |
    ///
    /// 随机打乱的解长 20~24 步、平均约 22.6，符合两阶段算法的常规口径。
    /// 真要从"离还原只差一步"的状态拿到那一步，得另加优化层，目前不做。
    ///
    /// 二阶同理不保证最优（二阶最优解不超过 11 步，这里会给出 20 步上下）。
    public static func solve(
        _ state: CubeState,
        maxLength: Int = 25,
        timeout: TimeInterval = 5
    ) throws -> CubeSolution {
        switch state.size {
        case 3:
            guard let facelets = state.faceletString else {
                throw CubeSolveError.unsupportedSize(state.size)
            }
            guard !state.isSolved else { return .alreadySolved }
            return try solve(facelets: facelets, maxLength: maxLength, timeout: timeout)
        case 2:
            return try solveTwoByTwo(state, maxLength: maxLength, timeout: timeout)
        default:
            throw CubeSolveError.unsupportedSize(state.size)
        }
    }

    /// 便捷重载：直接吃面位串。
    ///
    /// 主要给测试和调试用——正常路径应该从 `CubeState` 进来。
    public static func solve(
        faceletString: String,
        maxLength: Int = 25,
        timeout: TimeInterval = 5
    ) throws -> CubeSolution {
        guard let state = CubeState(faceletString: faceletString) else {
            throw CubeSolveError.illegalState(reason: "面位串无法解析：\(faceletString)")
        }
        return try solve(state, maxLength: maxLength, timeout: timeout)
    }

    // MARK: - 三阶

    private static func solve(
        facelets: String,
        maxLength: Int,
        timeout: TimeInterval
    ) throws -> CubeSolution {
        try prepare()

        let solver: TB2PSolver
        do {
            solver = try TB2PSolver(facelets: facelets)
        } catch let error as TB2PError {
            throw translate(error)
        } catch {
            throw CubeSolveError.illegalState(reason: String(describing: error))
        }

        let raw: String?
        do {
            raw = try solver.search(allowedLength: maxLength, timeout: timeout)
        } catch let error as TB2PError {
            throw translate(error)
        } catch {
            throw CubeSolveError.illegalState(reason: String(describing: error))
        }

        guard let raw else {
            throw CubeSolveError.noSolutionFound(maxLength: maxLength)
        }
        guard let algorithm = Algorithm.parse(raw, size: 3) else {
            throw CubeSolveError.unparsableSolution(raw)
        }
        return CubeSolution(algorithm: algorithm, notation: raw)
    }

    // MARK: - 二阶：嵌入三阶

    /// 二阶求解：把它的角状态**嵌进一个"棱与中心都还原"的三阶**，交给同一个 Kociemba，
    /// 拿到的转动序列对二阶同样成立。
    ///
    /// ## 为什么成立
    ///
    /// 三阶的转动作用在角块上的效果与二阶的同名转动**逐格一致**（都是把那一层转 90°，
    /// 角块跟着走）。Kociemba 只吐外层转动（`U R F D L B` 及其逆/双），没有中层切片，
    /// 所以解出来的序列施加到二阶上，角块一定被还原。
    ///
    /// ## 为什么不用先摆正朝向
    ///
    /// 二阶没有固定中心块，同一颗魔方的 24 种整体旋转都是合法状态。嵌入时按槽位一一对应
    /// 拷贝即可，不需要（也没法）先把魔方"摆正"——反正解会把角块归位。
    ///
    /// ## 奇偶性的坑
    ///
    /// 三阶要求"角置换奇偶 == 棱置换奇偶"，而二阶**没有棱**，角置换的奇偶是自由的。
    /// 所以角置换为奇的那一半状态，直接嵌入会得到一个非法的三阶。修法是把 U 层的两条棱
    /// 对调：棱置换变成奇的，与角对上；**必须挑同一层的两条棱**，跨层互换会连带改变
    /// 棱朝向和，反而弄出个 `.edgeFlipSum`（`CubeLegalityTests` 已钉住这一点）。
    private static func solveTwoByTwo(
        _ state: CubeState,
        maxLength: Int,
        timeout: TimeInterval
    ) throws -> CubeSolution {
        guard !state.isSolved else { return .alreadySolved }
        guard let embedded = embeddedInThreeByThree(state) else {
            throw CubeSolveError.illegalState(reason: "二阶状态拼不出可解的三阶")
        }
        let solution = try solve(
            facelets: embedded.faceletString!,
            maxLength: maxLength,
            timeout: timeout
        )

        // 自检：把解施加回二阶必须真能还原。嵌入法只要有一处映射写错，
        // 解就会"看起来合理但拧不回去"——这条自检把错误挡在这里，而不是留给用户。
        guard state.applying(solution.algorithm).isSolved else {
            throw CubeSolveError.selfCheckFailed(notation: solution.notation)
        }
        return solution
    }

    /// 2 阶状态 → 一个三阶状态：角块按槽位一一对应拷过去，棱与中心保持还原态。
    /// 角置换为奇时把 U 层两条棱对调凑合法；拼不出合法三阶时返回 nil。
    private static func embeddedInThreeByThree(_ state: CubeState) -> CubeState? {
        guard state.size == 2 else { return nil }
        var stickers = CubeState.solved(size: 3).stickers

        // 2 阶的角块中心在 {±1}³，三阶的在 {±2}³，法向一一对应
        for x in [-1, 1] {
            for y in [-1, 1] {
                for z in [-1, 1] {
                    let source = V3(x, y, z)
                    let target = V3(2 * x, 2 * y, 2 * z)
                    for normal in [V3(x, 0, 0), V3(0, y, 0), V3(0, 0, z)] {
                        guard let from = StickerGeometry.index(cubieCenter: source, facing: normal, size: 2),
                              let to = StickerGeometry.index(cubieCenter: target, facing: normal, size: 3)
                        else { return nil }
                        stickers[to] = state.stickers[from]
                    }
                }
            }
        }

        let embedded = CubeState(stickers: stickers)
        if embedded.isLegalState { return embedded }
        guard case .permutationParity = embedded.legality else { return nil }
        let patched = swappingUpLayerEdges(embedded)
        return patched.isLegalState ? patched : nil
    }

    /// 对调 U 层的前后两条棱（UF ↔ UB）。同层互换不改变棱朝向和，只翻置换奇偶。
    private static func swappingUpLayerEdges(_ state: CubeState) -> CubeState {
        let first = edgeFaceletIndices((0, 1, 1))
        let second = edgeFaceletIndices((0, 1, -1))
        var stickers = state.stickers
        for offset in 0..<2 {
            let buffer = stickers[first[offset]]
            stickers[first[offset]] = stickers[second[offset]]
            stickers[second[offset]] = buffer
        }
        return CubeState(stickers: stickers)
    }

    /// 三阶某个棱块（符号三元组里恰有一个 0）的两个贴纸下标，次序按 (x, y, z) 过滤后的自然次序。
    /// 次序必须两侧一致，"对调两条棱"才是把整块搬过去、而不是只换一张贴纸。
    private static func edgeFaceletIndices(_ signs: (Int, Int, Int)) -> [Int] {
        let center = V3(2 * signs.0, 2 * signs.1, 2 * signs.2)
        return [V3(signs.0, 0, 0), V3(0, signs.1, 0), V3(0, 0, signs.2)]
            .filter { $0 != .zero }
            .map { StickerGeometry.index(cubieCenter: center, facing: $0, size: 3)! }
    }

    // MARK: - 错误翻译

    private static func translate(_ error: TB2PError) -> CubeSolveError {
        switch error {
        case .cubeVerificationFailed(let reason):
            return .illegalState(reason: reason)
        case .cubeSolvingTimeout:
            return .timedOut
        case .faceCubeInvalidFacelets(let facelets):
            return .illegalState(reason: "非法面位串 \(facelets)")
        case .faceCubeInvalidFacelet(let facelet, let index):
            return .illegalState(reason: "第 \(index) 个面位 \(facelet) 非法")
        case .tablesJSONLoadFailed, .tablesJSONLoadInvalidData, .tablesJSONSaveFailed,
            .tablesBinaryLoadFailed, .tablesBinarySaveFailed:
            return .solverUnavailable
        }
    }
}
