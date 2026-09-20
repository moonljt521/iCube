import XCTest
@testable import iCube
import CubeKit

@MainActor
final class PracticeModelTests: XCTestCase {

    private func scrambledModel() -> PracticeModel {
        let model = PracticeModel()
        model.scrambleStepDuration = 0.001
        model.minimumArmDuration = 0
        model.scrambleAndPlay()
        model.skipScramble()
        return model
    }

    func test_skipScrambleLandsOnScrambledState() {
        let model = scrambledModel()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.state, model.scramble?.initialState)
        XCTAssertFalse(model.state.isSolved)
        XCTAssertEqual(model.scrambleCursor, model.scramble?.moves.count)
    }

    func test_movesAreIgnoredBeforeScramble() {
        let model = PracticeModel()
        model.registerUserMove(.r)
        XCTAssertEqual(model.state, .solved, "未打乱时不该接受转动")
        XCTAssertEqual(model.moveCount, 0)
    }

    func test_releaseWithoutArmDoesNotStartTimer() {
        let model = scrambledModel()
        XCTAssertFalse(model.releaseToStart())
        XCTAssertEqual(model.phase, .ready)
    }

    func test_misTapUnderMinimumArmDoesNotStart() {
        let model = scrambledModel()
        model.minimumArmDuration = 5
        model.arm()
        XCTAssertTrue(model.isArmed)
        XCTAssertFalse(model.releaseToStart(), "按得太短应视为误触")
        XCTAssertEqual(model.phase, .ready)
    }

    /// 端到端：打乱 → 开表 → 施加逆序 → 应判定复原并停表落库
    func test_solvingWithInverseStopsTimerAndRecords() {
        let model = scrambledModel()
        var outcomes: [PracticeModel.SolveOutcome] = []
        model.onSolve = { outcomes.append($0) }

        model.arm()
        XCTAssertTrue(model.releaseToStart())
        XCTAssertEqual(model.phase, .running)

        guard let scramble = model.scramble else { return XCTFail("应有打乱串") }
        for move in scramble.inverse.moves {
            model.registerUserMove(move)
        }

        guard case .solved(let duration) = model.phase else {
            return XCTFail("逆序施加后应判定已还原，当前 \(model.phase)")
        }
        XCTAssertEqual(model.state, .solved)
        XCTAssertEqual(model.moveCount, scramble.moves.count)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes.first?.scramble, scramble.notation)
        XCTAssertEqual(outcomes.first?.penalty, SolvePenalty.plain)
        XCTAssertGreaterThanOrEqual(duration, 0)
    }

    func test_elapsedOnlyAdvancesWhileRunning() {
        let model = scrambledModel()
        let start = Date()
        XCTAssertEqual(model.elapsed(at: start.addingTimeInterval(9)), 0, "未开表不该计时")
        model.arm()
        model.releaseToStart()
        XCTAssertEqual(model.elapsed(at: start.addingTimeInterval(3)), model.elapsed(at: start) + 3, accuracy: 0.001)
        model.stopTimer()
        XCTAssertEqual(model.phase, .running)
    }

    func test_stepBackRewindsScramblePrefix() {
        let model = scrambledModel()
        guard let scramble = model.scramble else { return XCTFail("应有打乱串") }
        model.stepScramble(to: 5)
        XCTAssertEqual(model.scrambleCursor, 5)
        var expected = CubeState.solved
        for move in scramble.moves.prefix(5) { expected.apply(move) }
        XCTAssertEqual(model.state, expected)
        model.stepScramble(to: 0)
        XCTAssertEqual(model.state, .solved)
    }

    func test_resetClearsSession() {
        let model = scrambledModel()
        model.reset()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(model.state, .solved)
        XCTAssertNil(model.scramble)
        XCTAssertEqual(model.moveCount, 0)
    }
}
