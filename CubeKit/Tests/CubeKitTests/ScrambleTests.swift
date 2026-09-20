import XCTest
@testable import CubeKit

final class ScrambleTests: XCTestCase {

    func test_defaultLengthIsTwentyMoves() {
        XCTAssertEqual(Scramble.random().count, 20)
        XCTAssertEqual(Scramble.wcaLength, 20)
    }

    func test_noConsecutiveSameFace() {
        for seed in 0..<200 {
            let scramble = Scramble.random(length: 20, seed: UInt64(seed))
            let moves = scramble.moves
            for index in 1..<moves.count {
                XCTAssertNotEqual(moves[index].kind.referenceFace, moves[index - 1].kind.referenceFace,
                                  "seed \(seed) 出现同面连续：\(scramble.notation)")
            }
        }
    }

    func test_noThreeConsecutiveOnSameAxis() {
        for seed in 0..<400 {
            let scramble = Scramble.random(length: 20, seed: UInt64(seed))
            let moves = scramble.moves
            for index in 2..<moves.count {
                let axes = [moves[index], moves[index - 1], moves[index - 2]].map { $0.kind.referenceFace.axis }
                XCTAssertFalse(axes[0] == axes[1] && axes[1] == axes[2],
                               "seed \(seed) 出现同轴三连：\(scramble.notation)")
            }
        }
    }

    func test_onlyOuterFaceTurns() {
        for seed in 0..<50 {
            for move in Scramble.random(length: 20, seed: UInt64(seed)).moves {
                guard case .face = move.kind else {
                    return XCTFail("打乱只应包含外层转动")
                }
            }
        }
    }

    func test_sameSeedIsReproducible() {
        let a = Scramble.random(length: 20, seed: 2026)
        let b = Scramble.random(length: 20, seed: 2026)
        XCTAssertEqual(a.notation, b.notation)
        XCTAssertNotEqual(a.notation, Scramble.random(length: 20, seed: 2027).notation)
    }

    func test_everyScrambleIsSolvableByConstruction() {
        for seed in 0..<300 {
            let scramble = Scramble.random(length: 20, seed: UInt64(seed))
            XCTAssertTrue(scramble.initialState.applying(scramble.inverse).isSolved,
                          "seed \(seed) 打乱逆序不可还原：\(scramble.notation)")
        }
    }

    func test_notationParsesBackToSameMoves() {
        for seed in 0..<50 {
            let scramble = Scramble.random(length: 20, seed: UInt64(seed))
            XCTAssertEqual(Algorithm.parse(scramble.notation)?.moves, scramble.moves)
        }
    }

    func test_suffixDistributionIsRoughlyUniform() {
        var counts: [MoveAmount: Int] = [:]
        var faceCounts: [Face: Int] = [:]
        for seed in 0..<300 {
            for move in Scramble.random(length: 20, seed: UInt64(seed)).moves {
                counts[move.amount, default: 0] += 1
                faceCounts[move.kind.referenceFace, default: 0] += 1
            }
        }
        let total = counts.values.reduce(0, +)
        XCTAssertEqual(total, 6000)
        for amount in MoveAmount.allCases {
            let share = Double(counts[amount] ?? 0) / Double(total)
            XCTAssertTrue((0.28...0.39).contains(share), "\(amount) 占比偏离均匀：\(share)")
        }
        for face in Face.allCases {
            let share = Double(faceCounts[face] ?? 0) / Double(total)
            XCTAssertTrue((0.13...0.20).contains(share), "\(face.letter) 占比偏离均匀：\(share)")
        }
    }

    func test_customLengthAllowed() {
        XCTAssertEqual(Scramble.random(length: 3, seed: 5).count, 3)
        XCTAssertEqual(Scramble.random(length: 50, seed: 5).count, 50)
    }

    func test_splitMixIsDeterministicAndWellSpread() {
        var rng = SplitMix64(seed: 1234)
        let first = (0..<8).map { _ in rng.int(upperBound: 6) }
        var again = SplitMix64(seed: 1234)
        XCTAssertEqual(first, (0..<8).map { _ in again.int(upperBound: 6) })

        var rng2 = SplitMix64(seed: 77)
        var buckets = [Int](repeating: 0, count: 6)
        for _ in 0..<6000 { buckets[rng2.int(upperBound: 6)] += 1 }
        for bucket in buckets {
            XCTAssertTrue(bucket > 800 && bucket < 1200, "分桶不均：\(buckets)")
        }
    }
}
