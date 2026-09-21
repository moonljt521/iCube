import Foundation
import Observation
import CubeKit

/// 教程演示：持有自己的 CubeScene，负责"摆案型 / 播放公式"两个动作。
/// 与练习页的 PracticeModel 互不干扰——教程魔方不计步、不开计时。
@MainActor
@Observable
final class TutorialCubeModel {

    enum Speed: String, CaseIterable, Identifiable {
        case slow = "慢速"
        case normal = "正常"
        case fast = "快速"

        var id: String { rawValue }

        var duration: Double {
            switch self {
            case .slow: 0.5
            case .normal: 0.28
            case .fast: 0.14
            }
        }
    }

    let scene: CubeScene
    private(set) var state: CubeState
    /// 正在演示的公式步下标（用于高亮公式字块），空闲时为 nil
    private(set) var currentMoveIndex: Int?
    private(set) var isPlaying = false
    var speed: Speed = .normal

    private var task: Task<Void, Never>?

    init(state: CubeState = .solved) {
        self.state = state
        self.scene = CubeScene(state: state)
    }

    /// 把魔方摆成案型：还原态先施加公式的逆（保持当前阶数）
    func loadCase(algorithm: Algorithm) {
        stop()
        state = CubeState.solved(size: state.size).applying(algorithm.inverse)
        scene.rebuild(state: state)
    }

    /// 从案型出发播放公式本体，结束时应为还原态
    func play(_ algorithm: Algorithm) {
        stop()
        guard !algorithm.moves.isEmpty else { return }
        isPlaying = true
        let duration = speed.duration
        task = Task { [weak self] in
            for (index, move) in algorithm.moves.enumerated() {
                guard let self, !Task.isCancelled else { break }
                currentMoveIndex = index
                TurnSoundPlayer.shared.play()
                await scene.play(move, duration: duration)
                guard !Task.isCancelled else { break }
                state.apply(move)
            }
            if !Task.isCancelled { currentMoveIndex = nil }
            isPlaying = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        currentMoveIndex = nil
        isPlaying = false
    }
}
