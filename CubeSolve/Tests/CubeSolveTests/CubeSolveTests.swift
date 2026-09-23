import CubeKit
import XCTest

@testable import CubeSolve

/// 端到端求解测试。
///
/// 这里的核心是 `test_randomScramblesAreSolvedByReturnedSolution`：它同时钉死
/// 三件事——面位串的块顺序、每面内部的行列读法、字母↔颜色的对应。任何一处
/// 与外部求解器的约定脱节，求解库给出的解都无法还原我们手上的状态。
final class CubeSolveTests: XCTestCase {

    // MARK: - 可用性

    func test_solverResourceIsBundled() {
        XCTAssertTrue(CubeSolve.isAvailable, "TB2PTables.bin 应随包打进产物")
    }

    func test_prepareIsIdempotent() throws {
        try CubeSolve.prepare()
        try CubeSolve.prepare()
        try CubeSolve.prepare()
    }

    // MARK: - 平凡情形

    func test_alreadySolvedStateNeedsNoMoves() throws {
        let solution = try CubeSolve.solve(.solved)
        XCTAssertTrue(solution.algorithm.isEmpty)
        XCTAssertEqual(solution.count, 0)
        XCTAssertEqual(solution.notation, "")
    }

    /// 只转一步的状态，解必须能把它还原
    func test_singleTurnIsAlwaysSolvable() throws {
        for face in Face.allCases {
            for amount in MoveAmount.allCases {
                let move = Move(.face(face), amount)
                let state = CubeState.solved.applying(move)
                let solution = try CubeSolve.solve(state)
                XCTAssertEqual(
                    state.applying(solution.algorithm), .solved,
                    "\(move.notation) 的解应能还原：\(solution.notation)"
                )
                XCTAssertLessThanOrEqual(solution.count, 25, "\(move.notation) 解长超上限")
            }
        }
    }

    /// 钉住求解器**不保证最短**这一事实。
    ///
    /// 两阶段算法的剪枝表只是可采纳下界，下界高估时浅层搜索会被整段剪掉，
    /// 于是解可能明显长于最优。这里的期望值是从实际输出抄下来的——它记录的是
    /// 当前 vendor 版本的行为，不是"正确"的定义。升级 `Vendor/SwiftTB2PKit`
    /// 后若这条挂了，先确认新行为能否还原状态，再决定是改期望还是回退。
    ///
    /// 真要去掉这个怪癖（比如"离还原只差一步却给 8 步"），得在本层另加优化，
    /// 目前不做——拍照进来的魔方总是打乱态，解长口径本就是 20~24 步。
    func test_singleTurnSolutionsAreDocumented() throws {
        // 不改变棱角朝向的转动落在第一阶段目标子群内，走纯第二阶段，解必然最优
        for face in [Face.u, .d] {
            for amount in MoveAmount.allCases {
                let move = Move(.face(face), amount)
                let solution = try CubeSolve.solve(CubeState.solved.applying(move))
                XCTAssertEqual(solution.count, 1, "\(move.notation) 应一步还原")
            }
        }
        // 逆时针与半转也落在子群内，同样最优
        for face in [Face.f, .b, .r, .l] {
            for amount in [MoveAmount.ccw, .half] {
                let move = Move(.face(face), amount)
                let solution = try CubeSolve.solve(CubeState.solved.applying(move))
                XCTAssertEqual(solution.count, 1, "\(move.notation) 应一步还原")
            }
        }
        // 单个顺时针四分之一转会把棱角朝向全打乱，落不到子群内，解被拉长到 8 步
        for face in [Face.f, .b, .r, .l] {
            let move = Move(.face(face), .cw)
            let solution = try CubeSolve.solve(CubeState.solved.applying(move))
            XCTAssertEqual(solution.count, 8, "\(move.notation) 当前口径为 8 步，实际 \(solution.notation)")
        }
    }

    // MARK: - 随机打乱端到端

    /// 随机打乱 → 求解 → 施加解 → 必须回到还原态。
    /// 这是面位记法约定是否与外部求解器一致的唯一硬证据。
    func test_randomScramblesAreSolvedByReturnedSolution() throws {
        var lengths: [Int] = []
        for seed in 0..<30 {
            let scramble = Scramble.random(length: 20, seed: UInt64(seed))
            let state = scramble.initialState
            XCTAssertFalse(state.isSolved, "seed \(seed) 的打乱不该是还原态")

            let solution = try CubeSolve.solve(state)
            XCTAssertEqual(
                state.applying(solution.algorithm), .solved,
                "seed \(seed) 未还原。打乱 \(scramble.notation) / 解 \(solution.notation)"
            )
            lengths.append(solution.count)
        }

        let average = Double(lengths.reduce(0, +)) / Double(lengths.count)
        print("解长：\(lengths.min()!)~\(lengths.max()!) 平均 \(String(format: "%.1f", average)) 步")
        XCTAssertGreaterThan(average, 14, "两阶段算法不该给出这么短的解，可能约定有误")
        XCTAssertLessThan(average, 26, "解偏长，超出预期口径")
    }

    /// 求解库只该吐出外层转动，不该出现中层切片或整体旋转
    func test_solutionOnlyUsesOuterFaceTurns() throws {
        for seed in 0..<5 {
            let state = Scramble.random(length: 20, seed: UInt64(seed)).initialState
            let solution = try CubeSolve.solve(state)
            for move in solution.algorithm.moves {
                guard case .face = move.kind else {
                    return XCTFail("解里出现了非外层转动：\(move.notation)")
                }
                XCTAssertEqual(move.depth, 1, "三阶不该出现内层：\(move.notation)")
            }
        }
    }

    /// 解串重新解析必须回到同一个转动序列，否则说明记法有歧义
    func test_solutionNotationReparsesToSameAlgorithm() throws {
        for seed in 0..<5 {
            let state = Scramble.random(length: 20, seed: UInt64(seed)).initialState
            let solution = try CubeSolve.solve(state)
            XCTAssertEqual(Algorithm.parse(solution.notation, size: 3), solution.algorithm)
        }
    }

    // MARK: - 非法状态

    /// 单独翻一条棱：物理上不可能，求解库应拒绝
    func test_rejectsIllegalState_singleFlippedEdge() throws {
        // UF 棱：U 面 row2col1（绝对下标 7）与 F 面 row0col1（绝对下标 19）
        let facelets = swap(CubeState.solved.faceletString!, 7, 19)
        assertIllegal(facelets)
    }

    /// 单独拧一个角：角块扭转和必须 ≡ 0 (mod 3)，单个不成立
    func test_rejectsIllegalState_singleTwistedCorner() throws {
        // URF 角：U(row2col2)=8、R(row0col0)=9、F(row0col2)=20
        let facelets = rotate3(CubeState.solved.faceletString!, 8, 9, 20)
        assertIllegal(facelets)
    }

    /// 面位串本身能解析成状态（`CubeState` 不做合法性校验），
    /// 非法性必须由求解器在这一层拦下——这正是拍照识别纠错要依赖的信号。
    func test_illegalFaceletStringStillParsesButSolverRejectsIt() throws {
        let facelets = swap(CubeState.solved.faceletString!, 7, 19)
        XCTAssertNotNil(CubeState(faceletString: facelets), "解析层不该做合法性校验")
        assertIllegal(facelets)
    }

    // MARK: - 阶数

    func test_rejectsUnsupportedSize() {
        for size in [2, 4] {
            XCTAssertThrowsError(try CubeSolve.solve(.solved(size: size))) { error in
                XCTAssertEqual(error as? CubeSolveError, .unsupportedSize(size))
            }
        }
    }

    func test_rejectsMalformedFaceletString() {
        XCTAssertThrowsError(try CubeSolve.solve(faceletString: "NOTACUBE")) { error in
            guard case .illegalState = error as? CubeSolveError else {
                return XCTFail("应报 illegalState，实际 \(error)")
            }
        }
    }

    // MARK: - 辅助

    private func assertIllegal(
        _ facelets: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CubeSolve.solve(faceletString: facelets), file: file, line: line) { error in
            guard case .illegalState = error as? CubeSolveError else {
                return XCTFail("应报 illegalState，实际 \(error)", file: file, line: line)
            }
        }
    }

    private func swap(_ string: String, _ i: Int, _ j: Int) -> String {
        var chars = Array(string)
        chars.swapAt(i, j)
        return String(chars)
    }

    private func rotate3(_ string: String, _ i: Int, _ j: Int, _ k: Int) -> String {
        var chars = Array(string)
        let first = chars[i]
        chars[i] = chars[k]
        chars[k] = chars[j]
        chars[j] = first
        return String(chars)
    }
}
