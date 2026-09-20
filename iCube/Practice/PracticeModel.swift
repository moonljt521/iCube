import Foundation
import Observation
import CubeKit

/// 一次练习的会话状态机：还原态 → 打乱 → 就绪 → 计时中 → 已还原。
/// 计时不持有 Timer：由视图用 TimelineView 按帧读 `elapsed(at:)`，
/// 这样逻辑可测，也不会因为视图重建而漏拍。
@MainActor
@Observable
final class PracticeModel {

    enum Phase: Equatable {
        case idle
        case scrambling
        case ready
        case running
        case solved(TimeInterval)
    }

    struct SolveOutcome {
        let duration: TimeInterval
        let penalty: SolvePenalty
        let scramble: String
        let moveCount: Int
        let startedAt: Date
        let cubeSize: Int
    }

    /// 阶数（2/3/4）。切换阶会重建场景；视图用 `.id(model.cubeSize)` 跟随重建
    private(set) var cubeSize: Int = 3
    /// 场景随阶数变化重建，同阶内的状态变化走 rebuild
    private(set) var scene: CubeScene
    private(set) var state: CubeState
    private(set) var phase: Phase = .idle
    private(set) var scramble: Scramble?
    /// 逐步回看打乱时的游标
    private(set) var scrambleCursor = 0
    private(set) var moveCount = 0
    private(set) var isArmed = false
    /// 玩家刚完成的那一步，用于反馈与排错
    private(set) var lastMove: Move?
    /// 本次计时的起点，停止后仍保留以便落库
    private(set) var runStart: Date?
    private var frozenElapsed: TimeInterval = 0
    private var armedAt: Date?
    private var scrambleTask: Task<Void, Never>?

    /// 打乱动画每步时长（秒）
    var scrambleStepDuration: Double = 0.09
    /// 按住到开表的最小时长，短于此视为误触
    var minimumArmDuration: TimeInterval = 0.2
    var onSolve: ((SolveOutcome) -> Void)?

    init(state: CubeState? = nil) {
        // 显式传入状态（测试用）优先；否则读全局阶数（练习/教程共用）
        let stored = UserDefaults.standard.integer(forKey: CubeSize.defaultsKey)
        let size = state?.size ?? (CubeSize.supported.contains(stored) ? stored : 3)
        let initial = state ?? .solved(size: size)
        self.cubeSize = initial.size
        self.state = initial
        self.scene = CubeScene(state: initial)
    }

    /// 切换阶数：场景整个重建，练习进度作废回到待机；同时写全局，教程页同步跟随
    func setCubeSize(_ size: Int) {
        guard CubeSize.supported.contains(size), size != cubeSize else { return }
        scrambleTask?.cancel()
        stopTimer()
        cubeSize = size
        UserDefaults.standard.set(size, forKey: CubeSize.defaultsKey)
        state = .solved(size: size)
        scene = CubeScene(state: state)
        scramble = nil
        scrambleCursor = 0
        moveCount = 0
        lastMove = nil
        isArmed = false
        frozenElapsed = 0
        phase = .idle
    }

    var isAnimating: Bool { phase == .scrambling }
    var canTurn: Bool { phase == .ready || phase == .running }
    var canScramble: Bool { phase != .scrambling }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        guard phase == .running, let runStart else { return frozenElapsed }
        return frozenElapsed + now.timeIntervalSince(runStart)
    }

    // MARK: - 打乱

    func scrambleAndPlay() {
        guard canScramble else { return }
        stopTimer()
        let generated = Scramble.random(size: cubeSize)
        scramble = generated
        scrambleCursor = 0
        moveCount = 0
        phase = .scrambling
        isArmed = false

        scrambleTask?.cancel()
        scrambleTask = Task { [weak self] in
            guard let self else { return }
            for (index, move) in generated.moves.enumerated() {
                if Task.isCancelled { return }
                await self.scene.play(move, duration: self.scrambleStepDuration)
                if Task.isCancelled { return }
                self.state.apply(move)
                self.scrambleCursor = index + 1
            }
            guard !Task.isCancelled else { return }
            self.phase = .ready
        }
    }

    /// 跳过打乱动画，直接落到打乱完成的状态
    func skipScramble() {
        guard phase == .scrambling, let scramble else { return }
        scrambleTask?.cancel()
        applyScramblePrefix(count: scramble.moves.count)
        phase = .ready
        moveCount = 0
    }

    /// 逐步回看：把魔方放到"打乱前 n 步"的样子
    func stepScramble(to count: Int) {
        guard let scramble, phase == .scrambling || phase == .ready else { return }
        scrambleTask?.cancel()
        applyScramblePrefix(count: max(0, min(count, scramble.moves.count)))
        if phase == .scrambling { phase = .ready }
    }

    private func applyScramblePrefix(count: Int) {
        guard let scramble else { return }
        scrambleCursor = count
        let prefix = Array(scramble.moves.prefix(count))
        state = .solved(size: cubeSize)
        for move in prefix { state.apply(move) }
        scene.rebuild(state: state)
    }

    // MARK: - 计时

    /// 按住按钮：进入待发
    func arm() {
        guard phase == .ready else { return }
        armedAt = Date()
        isArmed = true
    }

    func disarm() {
        isArmed = false
        armedAt = nil
    }

    /// 松手：真的开始计时；按得太短视为误触
    @discardableResult
    func releaseToStart() -> Bool {
        guard phase == .ready, isArmed, let armedAt else {
            disarm()
            return false
        }
        isArmed = false
        self.armedAt = nil
        guard Date().timeIntervalSince(armedAt) >= minimumArmDuration else { return false }
        frozenElapsed = 0
        runStart = Date()
        phase = .running
        return true
    }

    func stopTimer() {
        if phase == .running {
            frozenElapsed = elapsed()
        }
    }

    /// 玩家完成一次转动后调用（场景已提交）
    func registerUserMove(_ move: Move) {
        guard phase == .ready || phase == .running else { return }
        state.apply(move)
        lastMove = move
        moveCount += 1
        if phase == .running, state.isSolved {
            let duration = elapsed()
            stopTimer()
            phase = .solved(duration)
            if let scramble {
                onSolve?(SolveOutcome(duration: duration,
                                      penalty: .plain,
                                      scramble: scramble.notation,
                                      moveCount: moveCount,
                                      startedAt: runStart ?? Date(),
                                      cubeSize: cubeSize))
            }
        }
    }

    /// 手动改罚则并落库（仅在已还原状态下可用）
    func applyPenalty(_ penalty: SolvePenalty) {
        guard case .solved(let duration) = phase, let scramble else { return }
        onSolve?(SolveOutcome(duration: duration,
                              penalty: penalty,
                              scramble: scramble.notation,
                              moveCount: moveCount,
                              startedAt: runStart ?? Date(),
                              cubeSize: cubeSize))
    }

    func reset() {
        scrambleTask?.cancel()
        stopTimer()
        state = .solved(size: cubeSize)
        scene.rebuild(state: state)
        scramble = nil
        scrambleCursor = 0
        moveCount = 0
        lastMove = nil
        isArmed = false
        frozenElapsed = 0
        phase = .idle
    }

}
