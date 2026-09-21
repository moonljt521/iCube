import AVFoundation
import os

/// 魔方转动音效：预载 3 条合成"咔哒"变体，池化播放器轮换，
/// 连续快速拧动时不互相打断。
/// AVAudioSession 用 playback + mixWithOthers：静音拨片下依然出声（转动反馈
/// 是交互的一部分），同时与背景音乐混音、不抢占。
final class TurnSoundPlayer {
    static let shared = TurnSoundPlayer()
    static let defaultsKey = "turnSoundEnabled"

    private static let logger = Logger(subsystem: "com.moonding.icube", category: "sound")

    private var players: [AVAudioPlayer] = []
    private var next = 0

    /// 已加载的音效数（测试/诊断用）
    var playerCount: Int { players.count }

    /// 测试可见的播放器池（只读）
    var testPlayers: [AVAudioPlayer] { players }

    private init() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Self.logger.error("audio session setup failed: \(error.localizedDescription)")
        }
        for name in ["turn_a", "turn_b", "turn_c"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
                Self.logger.error("sound resource missing: \(name)")
                continue
            }
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                Self.logger.error("sound resource unreadable: \(name)")
                continue
            }
            player.volume = 0.7
            player.prepareToPlay()
            players.append(player)
        }
        Self.logger.info("TurnSoundPlayer ready with \(self.players.count) players")
    }

    /// 音效开关（练习页菜单可切，默认开）
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
    }

    func play() {
        guard isEnabled, !players.isEmpty else { return }
        let player = players[next % players.count]
        next += 1
        player.currentTime = 0
        player.play()
    }
}
