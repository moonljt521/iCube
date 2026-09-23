import XCTest
import CubeKit
import CubeSolve

@testable import iCube

/// 录入模型：填色、校验、求解。
///
/// 求解那条是端到端的——它把「录入的 54 格 → 面位串 → 求解 → 施加解」整条链路
/// 串起来验证，是这套 UI 唯一能证明自己没把颜色填反的硬证据。
@MainActor
final class RestoreModelTests: XCTestCase {

    // MARK: - 初始状态

    func test_initPrefillsSixDistinctCenters() {
        let model = RestoreModel()
        XCTAssertEqual(model.filledCount, 6, "只该预填六个中心块")
        XCTAssertFalse(model.isComplete)

        let centers = Face.allCases.map { model.color(at: $0, row: 1, col: 1) }
        XCTAssertEqual(Set(centers.compactMap { $0 }).count, 6, "六个中心块颜色必须互异")
        for face in Face.allCases {
            XCTAssertEqual(model.color(at: face, row: 1, col: 1), face.defaultColor)
        }
    }

    /// 中心块之外的格子都该是空的
    func test_initLeavesNonCenterCellsEmpty() {
        let model = RestoreModel()
        for face in Face.allCases {
            for row in 0..<3 {
                for col in 0..<3 where !(row == 1 && col == 1) {
                    XCTAssertNil(model.color(at: face, row: row, col: col), "\(face) (\(row),\(col)) 应为空")
                }
            }
        }
    }

    // MARK: - 填色

    func test_paintAndErase() {
        let model = RestoreModel()
        model.paint(.red, at: .f, row: 0, col: 0)
        XCTAssertEqual(model.color(at: .f, row: 0, col: 0), .red)

        model.paint(nil, at: .f, row: 0, col: 0)
        XCTAssertNil(model.color(at: .f, row: 0, col: 0))
    }

    /// 画笔驱动的填色
    func test_paintUsesBrush() {
        let model = RestoreModel()
        model.brush = .blue
        model.paint(at: .u, row: 0, col: 0)
        XCTAssertEqual(model.color(at: .u, row: 0, col: 0), .blue)

        model.brush = nil
        XCTAssertTrue(model.isErasing)
        model.paint(at: .u, row: 0, col: 0)
        XCTAssertNil(model.color(at: .u, row: 0, col: 0))
    }

    /// 填色不能串格：填一格只该改那一格
    func test_paintTouchesOnlyTargetCell() {
        let model = RestoreModel()
        let before = model.stickers
        model.paint(.red, at: .f, row: 0, col: 0)
        let changed = zip(before, model.stickers).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.offset, faceletIndex(.f, row: 0, col: 0))
    }

    func test_clearThenFillCentersRestoresOnlyCenters() {
        let model = RestoreModel()
        model.load(state: .solved)
        XCTAssertTrue(model.isComplete)

        model.clear()
        XCTAssertEqual(model.filledCount, 0)
        XCTAssertFalse(model.isComplete)

        model.fillCenters()
        XCTAssertEqual(model.filledCount, 6)
    }

    // MARK: - 校验

    func test_statusMessageCountsMissingCells() {
        let model = RestoreModel()
        XCTAssertEqual(model.missingCount, 48)
        XCTAssertEqual(model.statusMessage, "还差 48 格")
    }

    func test_statusMessageReportsColorImbalance() {
        let model = RestoreModel()
        model.load(state: .solved)
        XCTAssertEqual(model.statusMessage, "已填满，可以求解")

        // 把一格白色改成红色：白少 1、红多 1
        model.paint(.red, at: .u, row: 0, col: 0)
        XCTAssertTrue(model.isComplete)
        XCTAssertFalse(model.canSolve)
        XCTAssertTrue(model.statusMessage.contains("白还差 1"), "实际：\(model.statusMessage)")
        XCTAssertTrue(model.statusMessage.contains("红多了 1"), "实际：\(model.statusMessage)")
    }

    func test_canSolveRequiresCompleteAndBalanced() {
        let model = RestoreModel()
        XCTAssertFalse(model.canSolve, "没填满不能求解")

        model.load(state: .solved)
        XCTAssertTrue(model.canSolve)

        model.paint(.red, at: .u, row: 0, col: 0)
        XCTAssertFalse(model.canSolve, "颜色个数不对不能求解")
    }

    // MARK: - 状态往返

    func test_loadStateRoundTripsThroughStickers() {
        for seed in 0..<5 {
            let scrambled = Scramble.random(length: 20, seed: UInt64(seed)).initialState
            let model = RestoreModel()
            model.load(state: scrambled)
            XCTAssertEqual(model.state, scrambled, "seed \(seed) 往返不一致")
        }
    }

    func test_loadIgnoresNonCubicStates() {
        let model = RestoreModel()
        model.load(state: .solved(size: 2))
        XCTAssertEqual(model.filledCount, 6, "非三阶应被忽略，仍是初始的中心块")
    }

    // MARK: - 求解

    func test_solveReturnsSolutionThatRestoresTheState() async throws {
        for seed in 0..<3 {
            let scrambled = Scramble.random(length: 20, seed: UInt64(seed)).initialState
            let model = RestoreModel()
            model.load(state: scrambled)
            XCTAssertTrue(model.canSolve)

            await model.solve()

            XCTAssertNil(model.failure, "seed \(seed) 不该失败")
            let solution = try XCTUnwrap(model.solution)
            XCTAssertEqual(scrambled.applying(solution.algorithm), .solved,
                           "seed \(seed) 未还原，解：\(solution.notation)")
        }
    }

    func test_solvedInputYieldsEmptySolution() async throws {
        let model = RestoreModel()
        model.load(state: .solved)
        await model.solve()
        XCTAssertNil(model.failure)
        XCTAssertEqual(model.solution?.count, 0)
    }

    /// 单独翻一条棱：每色个数仍是 9，但物理上不可能。
    /// 个数校验拦不住它，必须靠求解器判——这正是"识别结果需要人工复核"的信号。
    func test_solveRejectsIllegalState() async {
        let model = RestoreModel()
        model.load(state: .solved)
        XCTAssertTrue(model.canSolve, "个数是对的，本地校验会放行")

        let edge = model.color(at: .u, row: 2, col: 1)
        model.paint(model.color(at: .f, row: 0, col: 1), at: .u, row: 2, col: 1)
        model.paint(edge, at: .f, row: 0, col: 1)

        await model.solve()
        XCTAssertNil(model.solution)
        guard case .illegalState = model.failure else {
            return XCTFail("应报 illegalState，实际 \(String(describing: model.failure))")
        }
    }

    /// 改一格就该作废已有的解，否则用户会照着过期的步骤转
    func test_editingInvalidatesPreviousSolution() async {
        let model = RestoreModel()
        model.load(state: Scramble.random(length: 20, seed: 1).initialState)
        await model.solve()
        XCTAssertNotNil(model.solution)

        model.paint(.red, at: .u, row: 0, col: 0)
        XCTAssertNil(model.solution)
        XCTAssertNil(model.failure)
    }

    func test_solveDoesNothingWhenNotReady() async {
        let model = RestoreModel()
        await model.solve()
        XCTAssertNil(model.solution)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.isSolving)
    }
}
