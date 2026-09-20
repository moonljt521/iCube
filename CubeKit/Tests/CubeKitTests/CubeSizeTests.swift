import XCTest
@testable import CubeKit

/// 2/3/4 阶泛化的回归锚点：状态、置换表、层深记法、打乱四条线都要在多阶下成立。
final class CubeSizeTests: XCTestCase {

    private let sizes = [2, 3, 4]

    // MARK: - 状态

    func test_solvedStateBasics() {
        for size in sizes {
            let state = CubeState.solved(size: size)
            XCTAssertEqual(state.size, size)
            XCTAssertEqual(state.stickers.count, 6 * size * size)
            XCTAssertTrue(state.isSolved, "\(size) 阶还原态应判定已还原")
            XCTAssertEqual(state.colorCounts()[.white], size * size)
            // 任意单步转动后不再还原
            for face in Face.allCases {
                XCTAssertFalse(state.applying(Move(.face(face), .cw, depth: 1)).isSolved,
                               "\(size) 阶 \(face.letter) 转动后不应判定还原")
            }
        }
    }

    func test_sizeInferredFromStickerCount() {
        for size in sizes {
            let scrambled = CubeState.solved(size: size).applying(
                Scramble.random(size: size, seed: 11).algorithm)
            XCTAssertEqual(scrambled.size, size, "阶数应由贴纸数反推，不随打乱丢失")
        }
    }

    func test_turnThenInverseRestores_onAllSizes() {
        for size in sizes {
            let maxDepth = size >= 4 ? 2 : 1
            for face in Face.allCases {
                for amount in MoveAmount.allCases {
                    for depth in 1...maxDepth {
                        let move = Move(.face(face), amount, depth: depth)
                        let state = CubeState.solved(size: size)
                        XCTAssertTrue(state.applying(move).applying(move.inverse).isSolved,
                                      "\(size) 阶 \(move.notation) 后逆步应还原")
                    }
                }
            }
        }
    }

    func test_colorCountsConserved_onAllSizes() {
        for size in sizes {
            var state = CubeState.solved(size: size)
            var rng = SplitMix64(seed: UInt64(size) * 1000 + 7)
            for _ in 0..<300 {
                let face = Face.allCases[rng.int(upperBound: 6)]
                let depth = size >= 4 ? rng.int(upperBound: 2) + 1 : 1
                state.apply(Move(.face(face), MoveAmount.allCases[rng.int(upperBound: 3)], depth: depth))
                let counts = state.colorCounts()
                for color in CubeColor.allCases {
                    XCTAssertEqual(counts[color], size * size, "\(size) 阶随机转动后 \(color) 数量异常")
                }
            }
        }
    }

    // MARK: - 层深与记法

    func test_depth2NotationParsesBackToSameMove() {
        let move = Move(.face(.r), .ccw, depth: 2)
        XCTAssertEqual(move.notation, "2R'")
        let parsed = Algorithm.parse("2R'")
        XCTAssertEqual(parsed?.moves, [move])
    }

    func test_wideMoveParsingDependsOnSize() {
        // 三阶惯例：Rw = R M'（保持既有行为）
        XCTAssertEqual(Algorithm.parse("Rw")?.moves,
                       [Move(.face(.r), .cw), Move(.slice(.m), .ccw)])
        // 四阶：Rw = R 2R
        XCTAssertEqual(Algorithm.parse("Rw", size: 4)?.moves,
                       [Move(.face(.r), .cw), Move(.face(.r), .cw, depth: 2)])
        // 二阶没有中层：Rw 退化为单层 R
        XCTAssertEqual(Algorithm.parse("Rw", size: 2)?.moves,
                       [Move(.face(.r), .cw)])
        // 宽层公式在多阶下也必须"逆序还原"
        for size in sizes {
            let formula = Algorithm.parse("Rw U2 Fw' L", size: size)
            XCTAssertNotNil(formula, "\(size) 阶应能解析宽层公式")
            let state = CubeState.solved(size: size)
            XCTAssertTrue(state.applying(formula!).applying(formula!.inverse).isSolved,
                          "\(size) 阶宽层公式 + 逆序应还原")
        }
    }

    func test_layerTurnInfersInnerDepthOnFour() {
        // 四阶：投影 ±3 是外层（depth 1），±1 是内层（depth 2）
        let outer = Move.layerTurn(axis: .x, rotation: Rotation(axis: .x, quarterTurns: 3),
                                   affecting: V3(3, 0, 0), size: 4)
        XCTAssertEqual(outer, Move(.face(.r), .cw))
        let inner = Move.layerTurn(axis: .x, rotation: Rotation(axis: .x, quarterTurns: 3),
                                   affecting: V3(1, 0, 0), size: 4)
        XCTAssertEqual(inner, Move(.face(.r), .cw, depth: 2))
        XCTAssertEqual(inner?.notation, "2R")
        // 二阶没有内层：投影只能是 ±1
        let two = Move.layerTurn(axis: .x, rotation: Rotation(axis: .x, quarterTurns: 3),
                                 affecting: V3(1, 0, 0), size: 2)
        XCTAssertEqual(two, Move(.face(.r), .cw))
    }

    func test_sliceOnlyExistsOnOddSizes() {
        // 二阶/四阶投影没有 0，层筛选天然排除切片
        for size in [2, 4] {
            let state = CubeState.solved(size: size)
            let slice = Move(.slice(.m))
            XCTAssertTrue(state.applying(slice).isSolved, "\(size) 阶切片不该作用于任何贴纸")
        }
    }

    func test_wideMoveOnFourEqualsOuterPlusSecondLayer() {
        let wide = Algorithm.wideMoves(for: .r, amount: MoveAmount.cw, size: 4)
        XCTAssertEqual(wide, [Move(.face(.r), .cw), Move(.face(.r), .cw, depth: 2)])
        // 宽层作用后，除左右各两层外的贴纸不动
        let state = CubeState.solved(size: 4).applying(Algorithm(wide))
        let geometry = StickerGeometry.all(size: 4)
        for (index, sticker) in geometry.enumerated() {
            let block = sticker.center - sticker.normal
            if block.x < 0 {
                XCTAssertEqual(state.stickers[index], CubeState.solved(size: 4).stickers[index],
                               "中层贴纸 \(block) 不应被 Rw 挪动")
            }
        }
    }

    // MARK: - 打乱

    func test_scrambleLengthsAndInverses_onAllSizes() {
        let expected = [2: 11, 3: 20, 4: 40]
        for size in sizes {
            let scramble = Scramble.random(size: size, seed: UInt64(size) * 99)
            XCTAssertEqual(scramble.count, expected[size], "\(size) 阶默认打乱步数")
            XCTAssertEqual(scramble.size, size)
            let initial = scramble.initialState
            XCTAssertFalse(initial.isSolved)
            XCTAssertTrue(initial.applying(scramble.inverse).isSolved, "\(size) 阶打乱逆序应还原")
            // 四阶打乱应包含内层转动
            if size == 4 {
                XCTAssertTrue(scramble.moves.contains { $0.depth > 1 }, "四阶打乱应含 2R 类内层步")
            }
        }
    }
}
