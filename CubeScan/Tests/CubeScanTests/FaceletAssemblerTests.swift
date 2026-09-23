import CubeKit
import XCTest
@testable import CubeScan

final class FaceletAssemblerTests: XCTestCase {

    /// 把状态按给定朝向拍成六个面（"中心块颜色决定面归属"这一步直接由状态给出）
    private func captured(_ state: CubeState, rotations: [Face: Int]) -> [Face: [CubeColor]] {
        var result: [Face: [CubeColor]] = [:]
        for face in Face.allCases {
            result[face] = FaceletAssembler.rotated(
                SyntheticCapture.grid(of: state, face: face),
                quarterTurns: rotations[face] ?? 0
            )
        }
        return result
    }

    func test_solvedCubeAssemblesBack() {
        let state = CubeState.solved
        XCTAssertEqual(FaceletAssembler.assemble(captured(state, rotations: [:])), state)
    }

    func test_randomRotationsAreUndone() {
        for seed in UInt64(1)...30 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            let rotations = SyntheticCapture.randomRotations(seed: seed)
            let assembled = FaceletAssembler.assemble(captured(original, rotations: rotations))
            XCTAssertEqual(assembled, original, "seed \(seed) 没还原出原状态")
        }
    }

    func test_allRotationsCombinationResolvesToASingleState() {
        // 打乱态应当只有一个合法组合。多于一个说明"整面同向旋转"这类
        // 变换被误当成了合法解——那会让解的方向对不上手里的魔方
        for seed in UInt64(1)...15 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            let solutions = FaceletAssembler.assembleAll(
                captured(original, rotations: SyntheticCapture.randomRotations(seed: seed))
            )
            XCTAssertEqual(solutions, [original], "seed \(seed) 有 \(solutions.count) 个合法解")
        }
    }

    func test_solvedCubeHasExactlyOneDistinctSolution() {
        // 还原态每个面都是纯色，4096 种朝向组合给出的其实是同一个状态，
        // 去重之后应当只剩一个
        let solutions = FaceletAssembler.assembleAll(captured(.solved, rotations: [:]))
        XCTAssertEqual(solutions, [CubeState.solved])
    }

    func test_swappingTwoStickersYieldsNoSolution() {
        // 只换两格：无论换哪两格，都会破坏块结构，4096 种组合里没有一个合法。
        // 前提是**两格颜色不同**——同色互换等于没换。而打乱态里同一个面上
        // 出现两块同色太常见了，所以要显式挑一对异色的，否则测的是空气。
        for seed in UInt64(1)...3 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            let base = captured(original, rotations: [:])
            for face in Face.allCases {
                var colors = base
                var grid = colors[face]!
                guard let pair = firstDifferingPair(in: grid) else { continue }
                grid.swapAt(pair.0, pair.1)
                colors[face] = grid
                XCTAssertNil(FaceletAssembler.assemble(colors),
                             "seed \(seed) 把 \(face.letter) 面第 \(pair.0)、\(pair.1) 格换掉之后仍拼出了合法状态")
            }
        }
    }

    /// 面上第一对颜色不同的格子
    private func firstDifferingPair(in grid: [CubeColor]) -> (Int, Int)? {
        for first in 0..<grid.count {
            for second in (first + 1)..<grid.count where grid[first] != grid[second] {
                return (first, second)
            }
        }
        return nil
    }

    func test_missingFaceYieldsNil() {
        var colors = captured(.solved, rotations: [:])
        colors[.b] = nil
        XCTAssertNil(FaceletAssembler.assemble(colors))
    }

    func test_incompleteFaceYieldsNil() {
        var colors = captured(.solved, rotations: [:])
        colors[.b] = [.blue, .blue, .blue]
        XCTAssertNil(FaceletAssembler.assemble(colors))
    }

    func test_rotationIsAConsistentFourCycle() {
        let grid = SyntheticCapture.grid(of: Scramble.random(size: 3, length: 20, seed: 3).initialState, face: .f)
        XCTAssertEqual(FaceletAssembler.rotated(grid, quarterTurns: 4), grid)
        XCTAssertEqual(FaceletAssembler.rotated(grid, quarterTurns: -1),
                       FaceletAssembler.rotated(grid, quarterTurns: 3))
        // 转两次 = 上下左右翻转
        let twice = FaceletAssembler.rotated(grid, quarterTurns: 2)
        for index in 0..<9 {
            XCTAssertEqual(twice[index], grid[8 - index], "180° 不是首尾对应")
        }
    }

    func test_assembledStateIsSolvableLooking() {
        // 拼出来的状态必须是合法的（这本来就是筛选条件，这里显式再钉一次）
        let original = Scramble.random(size: 3, length: 20, seed: 17).initialState
        let assembled = FaceletAssembler.assemble(
            captured(original, rotations: SyntheticCapture.randomRotations(seed: 17))
        )
        XCTAssertEqual(assembled?.legality, .legal)
    }

    func test_assemblyMatchesWhatTheClassifierProduces() throws {
        // 端到端：状态 → 模拟拍摄 → 分类 → 拼装 → 必须回到原状态
        for seed in UInt64(1)...10 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            let captures = SyntheticCapture.captures(
                of: original,
                rotations: SyntheticCapture.randomRotations(seed: seed),
                seed: seed
            )
            let classified = try StickerClassifier.classify(captures)
            let assembled = FaceletAssembler.assemble(classified.colors)
            XCTAssertEqual(assembled, original, "seed \(seed) 端到端没回到原状态")
        }
    }
}
