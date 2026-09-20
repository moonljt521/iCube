import XCTest
@testable import CubeKit

final class NotationTests: XCTestCase {

    func test_parseBasicSequence() {
        let parsed = Algorithm.parse("R U R' U'")
        XCTAssertEqual(parsed?.moves, [Move.r, Move.u, Move.rPrime, Move.uPrime])
    }

    func test_parseDoubleAndLowercase() {
        XCTAssertEqual(Algorithm.parse("U2")?.moves, [Move.u2])
        XCTAssertEqual(Algorithm.parse("u2")?.moves, [Move.u2])
        XCTAssertEqual(Algorithm.parse("r2")?.moves, [Move.r2])
        XCTAssertEqual(Algorithm.parse("R'2")?.moves, [Move.r2], "R'2 与 R2 等价")
        XCTAssertEqual(Algorithm.parse("R''")?.moves, [Move.r2], "R'' 即 R2")
    }

    func test_parseSlicesAndRotations() {
        XCTAssertEqual(Algorithm.parse("M")?.moves, [Move.m])
        XCTAssertEqual(Algorithm.parse("M'")?.moves, [Move.mPrime])
        XCTAssertEqual(Algorithm.parse("E2")?.moves, [Move(.slice(.e), .half)])
        XCTAssertEqual(Algorithm.parse("S")?.moves, [Move.s])
        XCTAssertEqual(Algorithm.parse("x y z")?.moves, [Move.x, Move.y, Move.z])
    }

    func test_parseWideMoves() {
        // 宽层 = 外层 + 同轴中层同向；中层基准面是 L/D/F，故符号需换算
        XCTAssertEqual(Algorithm.parse("Rw")?.moves, [Move.r, Move.mPrime])
        XCTAssertEqual(Algorithm.parse("Lw")?.moves, [Move.l, Move.m])
        XCTAssertEqual(Algorithm.parse("Fw")?.moves, [Move.f, Move.s])
        XCTAssertEqual(Algorithm.parse("Bw")?.moves, [Move.b, Move.sPrime])
        XCTAssertEqual(Algorithm.parse("Uw")?.moves, [Move.u, Move.ePrime])
        XCTAssertEqual(Algorithm.parse("Dw")?.moves, [Move.d, Move.e])
        XCTAssertEqual(Algorithm.parse("Rw'")?.moves, [Move.rPrime, Move.m])
        XCTAssertEqual(Algorithm.parse("Rw2")?.moves, [Move.r2, Move(.slice(.m), .half)])
    }

    func test_wideMoveTurnsTwoSlabs() {
        // Rw 应同时带动外层与中层，贴纸移动数比单层多
        let wide = Algorithm.parse("Rw")!
        let single = Algorithm([Move.r])
        let wideState = CubeState.solved.applying(wide)
        let singleState = CubeState.solved.applying(single)
        XCTAssertNotEqual(wideState, singleState)
        // 中层右列（F 面中间列的 x=0 那一列）在 Rw 下应变化，在 R 下不变
        XCTAssertEqual(singleState.color(at: .f, row: 0, col: 1), .green)
        XCTAssertNotEqual(wideState.color(at: .f, row: 0, col: 1), .green)
    }

    func test_invalidTokensRejected() {
        XCTAssertNil(Algorithm.parse("Q"))
        XCTAssertNil(Algorithm.parse("R Q"))
        XCTAssertNil(Algorithm.parse("RU"))
        XCTAssertNil(Algorithm.parse("R'''"))
        XCTAssertNil(Algorithm.parse("'"))
        XCTAssertNotNil(Algorithm.parse(""))
    }

    func test_notationRoundTrip() {
        let text = "R U2 R' F' D Lw M' x y2 z"
        guard let parsed = Algorithm.parse(text) else { return XCTFail("应能解析 \(text)") }
        XCTAssertEqual(Algorithm.parse(parsed.notation)?.moves, parsed.moves)
    }

    func test_inverseNotation() {
        let algo = Algorithm.parse("R U R' U'")!
        XCTAssertEqual(algo.inverse.notation, "U R U' R'")
        let asymmetric = Algorithm.parse("R U F'")!
        XCTAssertEqual(asymmetric.inverse.notation, "F U' R'")
        XCTAssertTrue(CubeState.solved.applying(asymmetric).applying(asymmetric.inverse).isSolved)
    }

    func test_commonAlgorithmStringsParse() {
        let algorithms = [
            "R U R' U'", "R U R' U' R U' R'", "F R U R' U' F'",
            "R U R' U R U2 R'", "U R U' L' U L U' R'", "M2 U M2 U2 M2 U M2",
            "R U2 R' U' R U R' U' F R F' U2 F' R' F", "x", "y2", "Rw U Rw'",
            "F' L F L' F R2 D L' F2"
        ]
        for text in algorithms {
            XCTAssertNotNil(Algorithm.parse(text), "无法解析常见公式 \(text)")
        }
    }
}
