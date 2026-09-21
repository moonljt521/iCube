import XCTest
@testable import iCube

final class TurnSoundPlayerTests: XCTestCase {

    /// 三条音效变体都必须能从主 bundle 加载（资源缺失时 playerCount 会 < 3）
    func test_soundResourcesLoadedFromBundle() {
        XCTAssertGreaterThanOrEqual(TurnSoundPlayer.shared.playerCount, 3,
                                    "turn_*.wav 应全部打进主 bundle")
    }

    /// play() 应让某个池内播放器进入 isPlaying 状态（模拟器音频会话可用性冒烟测试）
    func test_playStartsPlayback() {
        UserDefaults.standard.removeObject(forKey: TurnSoundPlayer.defaultsKey)
        let sut = TurnSoundPlayer.shared
        guard sut.playerCount > 0 else {
            return XCTFail("无可用播放器，音效资源加载失败")
        }
        sut.play()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(sut.testPlayers.contains { $0.isPlaying },
                      "play() 后应有播放器处于播放状态")
    }
}
