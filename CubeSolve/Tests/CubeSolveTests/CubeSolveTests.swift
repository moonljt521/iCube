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
        // 2 阶与 3 阶有求解器；4 阶要先做降阶（中心归位 + 翼棱配对），尚未实现
        for size in [4, 5] {
            XCTAssertThrowsError(try CubeSolve.solve(.solved(size: size))) { error in
                XCTAssertEqual(error as? CubeSolveError, .unsupportedSize(size))
            }
        }
    }

    // MARK: - 二阶（嵌入三阶）

    func test_twoByTwoAlreadySolvedNeedsNoMoves() throws {
        let solution = try CubeSolve.solve(.solved(size: 2))
        XCTAssertTrue(solution.algorithm.isEmpty)
    }

    /// 二阶走的是"把角状态嵌进一个棱与中心都还原的三阶"的路子，
    /// 解出来的外层转动序列必须真能把二阶还原。这条同时钉住了三件事：
    /// 2 阶 ↔ 3 阶角块的槽位对应、外层转动在两种阶数上对角的动作一致、奇偶性补丁有效。
    func test_twoByTwoRandomStatesAreSolved() throws {
        for seed in 1...12 {
            let scramble = Scramble.random(size: 2, length: 11, seed: UInt64(seed))
            let state = scramble.initialState
            XCTAssertFalse(state.isSolved, "seed \(seed) 的打乱不该是还原态")
            let solution = try CubeSolve.solve(state)
            XCTAssertEqual(state.applying(solution.algorithm), .solved(size: 2),
                           "seed \(seed) 的二阶解不能还原：\(solution.notation)")
            XCTAssertLessThanOrEqual(solution.count, 25, "seed \(seed) 解长超上限")
        }
    }

    /// 角置换为奇的那一半状态，嵌入三阶时会与"棱置换为偶"冲突，
    /// 必须靠对调 U 层两条棱凑合法。这里专门覆盖那半边。
    func test_twoByTwoOddCornerPermutationIsSolvable() throws {
        var covered = 0
        for seed in 1...40 {
            let state = Scramble.random(size: 2, length: 11, seed: UInt64(seed)).initialState
            guard isOddCornerPermutation(state) else { continue }
            covered += 1
            let solution = try CubeSolve.solve(state)
            XCTAssertEqual(state.applying(solution.algorithm), .solved(size: 2),
                           "seed \(seed) 的奇角置换解不能还原")
        }
        XCTAssertGreaterThan(covered, 5, "样本里奇角置换太少，这条没测到东西")
    }

    /// 二阶整体旋转过的写法（同一颗魔方）也必须可解——识别出来的状态本来就是"某个整体旋转"
    func test_twoByTwoRotatedRepresentationsAreSolvable() throws {
        let state = Scramble.random(size: 2, length: 11, seed: 4).initialState
        for move in [Move.x, Move.y, Move.z] {
            let rotated = state.applying(move)
            let solution = try CubeSolve.solve(rotated)
            XCTAssertEqual(rotated.applying(solution.algorithm), .solved(size: 2),
                           "整体旋转 \(move.notation) 后解不能还原")
        }
    }

    /// 非法二阶（单角扭转）必须报 illegalState，而不是硬给一个解
    func test_twoByTwoIllegalStateIsRejected() {
        var stickers = CubeState.solved(size: 2).stickers
        let x = V3(1, 0, 0), y = V3(0, 1, 0), z = V3(0, 0, 1)
        let indices = [y, z, x].map { StickerGeometry.index(cubieCenter: V3(1, 1, 1), facing: $0, size: 2)! }
        let colors = indices.map { stickers[$0] }
        for (offset, index) in indices.enumerated() { stickers[index] = colors[(offset - 1 + 3) % 3] }
        let twisted = CubeState(stickers: stickers)
        XCTAssertThrowsError(try CubeSolve.solve(twisted)) { error in
            guard case .illegalState = error as? CubeSolveError else {
                return XCTFail("应报 illegalState，实际 \(error)")
            }
        }
        _ = (x, z)
    }

    /// 角置换是不是奇的。二阶没有棱，奇偶是自由的——正好用来挑出需要补丁的那半边样本。
    private func isOddCornerPermutation(_ state: CubeState) -> Bool {
        var permutation = [Int](repeating: 0, count: 8)
        var taken = [Bool](repeating: false, count: 8)
        var signs: [(x: Int, y: Int, z: Int)] = []
        for x in [1, -1] { for y in [1, -1] { for z in [1, -1] { signs.append((x, y, z)) } } }
        let indexByCode = { (s: (x: Int, y: Int, z: Int)) in (s.x + 1) * 9 + (s.y + 1) * 3 + (s.z + 1) }
        var table = [Int](repeating: -1, count: 27)
        for (index, s) in signs.enumerated() { table[indexByCode(s)] = index }
        let axisSign: [CubeColor: (Int, Int)] = [
            .white: (1, 1), .yellow: (1, -1), .red: (0, 1),
            .orange: (0, -1), .green: (2, 1), .blue: (2, -1),
        ]
        for (slot, s) in signs.enumerated() {
            let center = V3(s.x, s.y, s.z)
            let x = V3(s.x, 0, 0), y = V3(0, s.y, 0), z = V3(0, 0, s.z)
            let normals = s.x * s.y * s.z > 0 ? [y, z, x] : [y, x, z]
            let colors = normals.map { state.color(at: center, facing: $0)! }
            var home = [0, 0, 0]
            for color in colors {
                let (axis, sign) = axisSign[color]!
                home[axis] = sign
            }
            let index = table[(home[0] + 1) * 9 + (home[1] + 1) * 3 + (home[2] + 1)]
            guard index >= 0, !taken[index] else { return false }
            taken[index] = true
            permutation[slot] = index
        }
        var visited = [Bool](repeating: false, count: 8)
        var swaps = 0
        for start in 0..<8 where !visited[start] {
            var length = 0
            var node = start
            while !visited[node] {
                visited[node] = true
                node = permutation[node]
                length += 1
            }
            swaps += length - 1
        }
        return swaps % 2 == 1
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
