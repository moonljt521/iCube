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
            "\(size) 阶还原助手正在开发中，目前支持 2 阶和 3 阶"
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
        case .selfCheckFailed:
            "算出来的解没能还原魔方，这是程序内部的问题。请把这一步的操作反馈给我们"
        }
    }
}

/// 拍照/手动还原的状态录入模型。
///
/// 只管"6N² 个格子填了什么"以及由此推出的状态、校验与求解结果；
/// 拍照识别会以同样的方式往 `stickers` 里写值，所以这里不假设输入来自手点。
@MainActor
@Observable
final class RestoreModel {

    /// 阶数。2/3/4，由调用方按全局设置传进来
    let size: Int

    /// 每种颜色恰好 N² 个
    var countPerColor: Int { size * size }

    /// 6N² 个贴纸槽位的填色，下标与 `faceletIndex(face:row:col:size:)` 一致；nil = 还没填
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

    init(size: Int = 3) {
        self.size = size
        stickers = Array(repeating: nil, count: 6 * size * size)
        fillCenters()
    }

    /// 该阶数有没有"真正的中心块"（奇数阶才有，偶数阶的中心块会换面、不是锚点）
    var hasFixedCenters: Bool { size % 2 == 1 }

    // MARK: - 单格读写

    func color(at face: Face, row: Int, col: Int) -> CubeColor? {
        stickers[faceletIndex(face, row: row, col: col, size: size)]
    }

    func paint(_ color: CubeColor?, at face: Face, row: Int, col: Int) {
        let index = faceletIndex(face, row: row, col: col, size: size)
        // 拖动会反复扫过同一格，值没变就别作废已有的求解结果
        guard stickers[index] != color else { return }
        stickers[index] = color
        invalidateSolution()
        forgetCandidates()
    }

    func paint(at face: Face, row: Int, col: Int) {
        paint(brush, at: face, row: row, col: col)
    }

    // MARK: - 批量

    /// 奇数阶：六个中心块必然互异，是整套配色的锚点，先按标准配色（白顶/黄底/绿前/蓝后/红右/橙左）填好。
    /// 用户把魔方按这个朝向摆好，就只需填 6N²−6 个非中心格。
    ///
    /// 偶数阶没有固定中心块，一个都不填——填了反而是错的。
    func fillCenters() {
        guard hasFixedCenters else { return }
        let mid = (size - 1) / 2
        for face in Face.allCases {
            stickers[faceletIndex(face, row: mid, col: mid, size: size)] = face.defaultColor
        }
        invalidateSolution()
        forgetCandidates()
    }

    func clear() {
        stickers = Array(repeating: nil, count: 6 * size * size)
        invalidateSolution()
        forgetCandidates()
    }

    /// 用一整个状态覆盖当前填色。
    /// 拍照识别拿到 6N² 格结果后走这里；测试也用它造输入。
    func load(state: CubeState) {
        guard state.size == size else { return }
        var next: [CubeColor?] = []
        next.reserveCapacity(stickers.count)
        for face in Face.allCases {
            for row in 0..<size {
                for col in 0..<size {
                    next.append(state.color(at: face, row: row, col: col))
                }
            }
        }
        stickers = next
        invalidateSolution()
    }

    // MARK: - 多种拼法（只对偶数阶可能出现）

    /// 识别出来的全部候选拼法，已按贴纸序列排序（确定性）。三阶恒为 1 个。
    ///
    /// 偶数阶没有固定中心块，**两个不同的面互为 90° 旋转时，照片分不出谁是谁**——
    /// 实测二阶约一成状态会拼出两个解，而且用求解器验过：两个解都是真能拧出来的状态，
    /// 不是判据放水。这时候硬选一个是拿用户的魔方赌运气，所以候选留给用户挑。
    private(set) var candidates: [CubeState] = []
    private(set) var candidateIndex = 0

    /// 有没有得挑
    var hasCandidateChoices: Bool { candidates.count > 1 }

    /// 换成下一种拼法
    func cycleCandidate() {
        guard hasCandidateChoices else { return }
        candidateIndex = (candidateIndex + 1) % candidates.count
        load(state: candidates[candidateIndex])
    }

    /// 灌入一次识别的全部候选
    func load(candidates: [CubeState]) {
        guard let first = candidates.first else { return }
        self.candidates = candidates
        candidateIndex = 0
        load(state: first)
    }

    // MARK: - 整体转向（只对偶数阶有意义）

    /// 把当前状态整体转一下，用来把识别结果的朝向拧到跟手上一致。
    ///
    /// ## 为什么需要用户自己转
    ///
    /// 偶数阶没有固定中心块，**同一颗魔方的 24 种整体旋转全都是合法状态**，
    /// 而六个面是分别拍的、空间朝向在照片里丢失了——所以"哪面朝上"这件事
    /// 从输入里根本恢复不出来，算法只能挑一个确定的代表（见
    /// `CubeState.rotationallyCanonical`）。用户看到的就是"颜色对但整体转了"。
    ///
    /// 与其让算法猜，不如给两个按钮让用户拧到自己满意——他一眼就知道对不对，
    /// 算法永远猜不到。`.y` 与 `.x` 两个方向能张成全部 24 种朝向。
    ///
    /// ## 三阶不能用
    ///
    /// 三阶的中心块锚定了朝向，整体旋转会把中心块挪走，状态就不再是面位记法认的那一串，
    /// 求解器会直接拒掉。所以这里挡一道，三阶调用是空操作。
    func rotate(by move: Move) {
        guard size != 3, move.kind.isWholeCube, let current = state else { return }
        load(state: current.applying(move))
    }

    /// 该不该给用户显示"转向"按钮：偶数阶、且格子已经填满（没填满就没有"状态"可转）
    var canRotate: Bool { size != 3 && isComplete }

    // MARK: - 校验

    var filledCount: Int { stickers.compactMap { $0 }.count }

    var missingCount: Int { stickers.count - filledCount }

    var isComplete: Bool { missingCount == 0 }

    /// 个数不对的颜色 → 差值（正数=还差，负数=多了）
    var colorOffsets: [ColorOffset] {
        var counts: [CubeColor: Int] = [:]
        for color in stickers.compactMap({ $0 }) { counts[color, default: 0] += 1 }
        return CubeColor.allCases.compactMap { color in
            let delta = countPerColor - (counts[color] ?? 0)
            return delta == 0 ? nil : ColorOffset(color: color, delta: delta)
        }
    }

    /// 填满、每色 N² 个、且阶数有求解器（目前 2/3 阶）才允许求解。
    /// 更深的合法性（棱角朝向和、奇偶性）交给求解器判——它本来就会校验，不必在这里重写一遍。
    var canSolve: Bool { isComplete && colorOffsets.isEmpty && size <= 3 }

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
        if size > 3 {
            return "\(size) 阶还原助手正在开发中，目前支持 2 阶和 3 阶"
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

    /// 用户自己动过格子了，识别的候选拼法就作废——他已经在用手改，别再让"换拼法"把改动盖掉
    private func forgetCandidates() {
        candidates.removeAll()
        candidateIndex = 0
    }
}

/// 某颜色与目标个数的差值
struct ColorOffset: Equatable, Identifiable {
    let color: CubeColor
    let delta: Int

    var id: CubeColor { color }
}
