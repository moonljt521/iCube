import Foundation
import Observation
import CubeKit
import CubeSolve

extension CubeColor {
    /// 中文色名，用于录入界面的画笔、提示与校验文案
    var displayName: String {
        switch self {
        case .white: "白"
        case .yellow: "黄"
        case .green: "绿"
        case .blue: "蓝"
        case .red: "红"
        case .orange: "橙"
        }
    }
}

extension CubeSolveError {
    /// 给用户看的中文说明。
    ///
    /// CubeSolve 保持语言中立，翻译放在应用层——底层 `TB2PError` 的原文是英文，
    /// 直接抛给用户没有意义。
    var userMessage: String {
        switch self {
        case .unsupportedSize(let size):
            "\(size) 阶暂时不支持求解，请录入三阶"
        case .illegalState:
            "这个状态在物理上不可能：单独翻转一条棱、单独拧一个角，或两块互换了位置都会这样。请检查有没有填错格子"
        case .solverUnavailable:
            "求解器资源没打进安装包，请重新安装 App"
        case .timedOut:
            "搜索超时，请重试"
        case .noSolutionFound:
            "没找到解，请检查填色是否正确"
        case .unparsableSolution:
            "求解结果无法识别，请重试"
        }
    }
}

/// 拍照/手动还原的状态录入模型。
///
/// 只管"54 个格子填了什么"以及由此推出的状态、校验与求解结果；
/// 拍照识别（后续）会以同样的方式往 `stickers` 里写值，所以这里不假设输入来自手点。
@MainActor
@Observable
final class RestoreModel {

    /// 每种颜色在三阶上恰好 9 个
    static let countPerColor = 9

    /// 54 个贴纸槽位的填色，下标与 `faceletIndex(face:row:col:)` 一致；nil = 还没填
    private(set) var stickers: [CubeColor?]

    /// 当前画笔；nil 表示橡皮（擦掉格子）
    var brush: CubeColor? = .white

    var isErasing: Bool { brush == nil }

    private(set) var solution: CubeSolution?
    /// 与 `solution` **配对**的那份状态，即算这份解时用的那一份。
    ///
    /// 求解是异步的（典型 26ms，最坏到 5s 超时），这段时间录入界面仍然可交互：
    /// 涂格子、填中心块、或者从拍照页灌一份新状态进来，都会把 `solution` 清掉，
    /// 但求解完成时的赋值又会把它写回来。于是"此刻的 stickers"可能已经不是
    /// "算这份解时的状态"——两者错开一格，演示播完就停在"差一格还原"的画面上，
    /// 页脚既不显示「已还原」也不显示步数，用户看到的就是"红色面上多了个白色"。
    /// 所以状态和解绑成一对存，调用方只认这一对。
    private(set) var solvedState: CubeState?
    private(set) var failure: CubeSolveError?
    private(set) var isSolving = false

    init() {
        stickers = Array(repeating: nil, count: FaceletNotation.length)
        fillCenters()
    }

    // MARK: - 单格读写

    func color(at face: Face, row: Int, col: Int) -> CubeColor? {
        stickers[faceletIndex(face, row: row, col: col)]
    }

    func paint(_ color: CubeColor?, at face: Face, row: Int, col: Int) {
        let index = faceletIndex(face, row: row, col: col)
        // 拖动会反复扫过同一格，值没变就别作废已有的求解结果
        guard stickers[index] != color else { return }
        stickers[index] = color
        invalidateSolution()
    }

    func paint(at face: Face, row: Int, col: Int) {
        paint(brush, at: face, row: row, col: col)
    }

    // MARK: - 批量

    /// 六个中心块必然互异，是整套配色的锚点，先按标准配色（白顶/黄底/绿前/蓝后/红右/橙左）填好。
    /// 用户把魔方按这个朝向摆好，就只需填 48 个非中心格。
    func fillCenters() {
        for face in Face.allCases {
            stickers[faceletIndex(face, row: 1, col: 1)] = face.defaultColor
        }
        invalidateSolution()
    }

    func clear() {
        stickers = Array(repeating: nil, count: FaceletNotation.length)
        invalidateSolution()
    }

    /// 用一整个状态覆盖当前填色。
    /// 拍照识别拿到 54 格结果后走这里；测试也用它造输入。
    func load(state: CubeState) {
        guard state.size == 3 else { return }
        var next: [CubeColor?] = []
        next.reserveCapacity(FaceletNotation.length)
        for face in Face.allCases {
            for row in 0..<3 {
                for col in 0..<3 {
                    next.append(state.color(at: face, row: row, col: col))
                }
            }
        }
        stickers = next
        invalidateSolution()
    }

    // MARK: - 校验

    var filledCount: Int { stickers.compactMap { $0 }.count }

    var missingCount: Int { stickers.count - filledCount }

    var isComplete: Bool { missingCount == 0 }

    /// 个数不对的颜色 → 差值（正数=还差，负数=多了）
    var colorOffsets: [ColorOffset] {
        var counts: [CubeColor: Int] = [:]
        for color in stickers.compactMap({ $0 }) { counts[color, default: 0] += 1 }
        return CubeColor.allCases.compactMap { color in
            let delta = Self.countPerColor - (counts[color] ?? 0)
            return delta == 0 ? nil : ColorOffset(color: color, delta: delta)
        }
    }

    /// 填满且每色 9 个才允许求解。
    /// 更深的合法性（棱角朝向和、奇偶性）交给求解器判——它本来就会校验，不必在这里重写一遍。
    var canSolve: Bool { isComplete && colorOffsets.isEmpty }

    /// 拼成的状态；没填满时为 nil
    var state: CubeState? {
        let colors = stickers.compactMap { $0 }
        guard colors.count == stickers.count else { return nil }
        return CubeState(stickers: colors)
    }

    /// 一句话状态，直接显示在录入界面上
    var statusMessage: String {
        if !isComplete { return "还差 \(missingCount) 格" }
        if !colorOffsets.isEmpty {
            return colorOffsets
                .map { $0.delta > 0 ? "\($0.color.displayName)还差 \($0.delta)" : "\($0.color.displayName)多了 \(-$0.delta)" }
                .joined(separator: " · ")
        }
        return "已填满，可以求解"
    }

    // MARK: - 求解

    func solve() async {
        guard canSolve, let state else { return }
        isSolving = true
        failure = nil
        solution = nil
        solvedState = nil
        defer { isSolving = false }
        do {
            // 求解是同步且吃 CPU 的（典型 26ms，最坏到 timeout），丢到主线程外跑
            let result = try await Task.detached(priority: .userInitiated) {
                try CubeSolve.solve(state)
            }.value
            // 和 `state` 一起存：中途可能有人改了 stickers，那份解对"此刻"不成立
            solution = result
            solvedState = state
        } catch let error as CubeSolveError {
            failure = error
        } catch {
            failure = .illegalState(reason: String(describing: error))
        }
    }

    private func invalidateSolution() {
        solution = nil
        solvedState = nil
        failure = nil
    }
}

/// 某颜色与目标个数的差值
struct ColorOffset: Equatable, Identifiable {
    let color: CubeColor
    let delta: Int

    var id: CubeColor { color }
}
