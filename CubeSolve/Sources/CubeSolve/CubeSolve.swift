import CubeKit
import Foundation
import SwiftTB2PKit

/// 求解失败的原因。
///
/// 底层求解库的 `TB2PError` 不直接暴露给上层——它是 vendor 进来的第三方类型，
/// 换实现就会变。这里把它的语义翻译成本项目自己的错误面。
public enum CubeSolveError: Error, Equatable, Sendable {
    /// 面位记法只定义在三阶，其他阶数没有可用的求解器。
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

/// 三阶魔方求解器。
///
/// 内部是 vendor 进 `Vendor/SwiftTB2PKit` 的 Kociemba 两阶段算法实现。
/// 这一层只做三件事：把 `CubeState` 译成面位串、把底层错误译成本项目的错误、
/// 把结果译回 `Algorithm`。
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
    ///   - state: 待求解的状态。必须是三阶。
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
    public static func solve(
        _ state: CubeState,
        maxLength: Int = 25,
        timeout: TimeInterval = 5
    ) throws -> CubeSolution {
        guard state.size == 3, let facelets = state.faceletString else {
            throw CubeSolveError.unsupportedSize(state.size)
        }
        guard !state.isSolved else { return .alreadySolved }

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
