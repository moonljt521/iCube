import AVFoundation

/// 魔方转动音效：预载 3 条合成"咔哒"变体，池化播放器轮换，
/// 连续快速拧动时不互相打断。AVAudioSession 用 ambient：跟随静音键、与其他 App 混音。
final class TurnSoundPlayer {
    static let shared = TurnSoundPlayer()
    static let defaultsKey = "turnSoundEnabled"

    private var players: [AVAudioPlayer] = []
    private var next = 0

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for name in ["turn_a", "turn_b", "turn_c"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = 0.6
            player.prepareToPlay()
            players.append(player)
        }
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
