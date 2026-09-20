import XCTest
@testable import CubeKit

final class CubeStateTests: XCTestCase {

    // MARK: - 真实世界的转动语义

    /// U 顺时针（俯视）把顶层各面按 R→F→L→B→R 搬动，且列索引保持对齐。
    /// 这一条同时校验网格读法、手性与转动方向三件事。
    func test_U_turn_carries_top_rows_in_physical_order() {
        let before = CubeState.solved.applying(Algorithm.parse("R U F' D L' B R2")!)
        let after = before.applying(.u)

        for col in 0..<3 {
            XCTAssertEqual(after.color(at: .f, row: 0, col: col), before.color(at: .r, row: 0, col: col), "R 顶排应进 F")
            XCTAssertEqual(after.color(at: .l, row: 0, col: col), before.color(at: .f, row: 0, col: col), "F 顶排应进 L")
            XCTAssertEqual(after.color(at: .b, row: 0, col: col), before.color(at: .l, row: 0, col: col), "L 顶排应进 B")
            XCTAssertEqual(after.color(at: .r, row: 0, col: col), before.color(at: .b, row: 0, col: col), "B 顶排应进 R")
        }
        // 侧面的非顶排完全不受影响
        for face in [Face.f, .r, .b, .l] {
            for row in 1..<3 {
                for col in 0..<3 {
                    XCTAssertEqual(after.color(at: face, row: row, col: col), before.color(at: face, row: row, col: col))
                }
            }
        }
    }

    /// U 面自身绕中心旋转：U[r][c] 落到 U[c][2-r]
    func test_U_face_rotates_in_place() {
        let before = CubeState.solved.applying(Algorithm.parse("R U F' D L' B")!)
        let after = before.applying(.u)
        for row in 0..<3 {
            for col in 0..<3 {
                XCTAssertEqual(after.color(at: .u, row: col, col: 2 - row), before.color(at: .u, row: row, col: col),
                               "U 面自身旋转映射有误")
            }
        }
    }

    /// D 逆着 U：F→R→B→L→F，列索引同样对齐
    func test_D_turn_carries_bottom_rows() {
        let before = CubeState.solved.applying(Algorithm.parse("R U F' D L' B")!)
        let after = before.applying(.d)
        for col in 0..<3 {
            XCTAssertEqual(after.color(at: .r, row: 2, col: col), before.color(at: .f, row: 2, col: col))
            XCTAssertEqual(after.color(at: .b, row: 2, col: col), before.color(at: .r, row: 2, col: col))
            XCTAssertEqual(after.color(at: .l, row: 2, col: col), before.color(at: .b, row: 2, col: col))
            XCTAssertEqual(after.color(at: .f, row: 2, col: col), before.color(at: .l, row: 2, col: col))
        }
    }

    /// F 顺时针：U 底排 → R 左列 → D 顶排 → L 右列 → U，且行列互换
    func test_F_turn_cycle_with_transposed_indices() {
        let before = CubeState.solved.applying(Algorithm.parse("R U F' D L' B")!)
        let after = before.applying(.f)
        for k in 0..<3 {
            XCTAssertEqual(after.color(at: .r, row: k, col: 0), before.color(at: .u, row: 2, col: k), "U 底排应进 R 左列")
            XCTAssertEqual(after.color(at: .d, row: 0, col: 2 - k), before.color(at: .r, row: k, col: 0), "R 左列应进 D 顶排")
            XCTAssertEqual(after.color(at: .l, row: k, col: 2), before.color(at: .d, row: 0, col: k), "D 顶排应进 L 右列")
            XCTAssertEqual(after.color(at: .u, row: 2, col: 2 - k), before.color(at: .l, row: k, col: 2), "L 右列应进 U 底排")
        }
    }

    // MARK: - 群论已知事实（独立于本项目几何推导的锚点）

    /// sexy move (R U R' U') 的阶是 6
    func test_sexy_move_has_order_6() {
        let sexy = Algorithm.parse("R U R' U'")!
        var walker = CubeState.solved
        for step in 1..<6 {
            walker.apply(sexy)
            XCTAssertFalse(walker.isSolved, "(R U R' U') 第 \(step) 次不应还原")
        }
        walker.apply(sexy)
        XCTAssertTrue(walker.isSolved, "(R U R' U')^6 必须是还原态")
    }

    /// (R U) 的阶是 105，这条能抓出任何手性/方向错误
    func test_RU_has_order_105() {
        let ru = Algorithm.parse("R U")!
        var state = CubeState.solved
        var firstReturn = 0
        for step in 1...105 {
            state.apply(ru)
            if state.isSolved {
                firstReturn = step
                break
            }
        }
        XCTAssertEqual(firstReturn, 105, "(R U) 应在第 105 次才回到还原态")
    }

    /// 互不相交的层可交换。R 与 U 共享 2 个角块所以不可交换，
    /// 但外层与其平行中层（R 与 M）确实不相交。
    func test_disjoint_layers_commute() {
        let pairs: [(Move, Move)] = [
            (.r, .l), (.u, .d), (.f, .b), (.r2, .l), (.f, .b2), (.u2, .d),
            (.r, .m), (.l, .mPrime), (.u, .e), (.d, .ePrime), (.f, .s), (.b, .sPrime),
        ]
        var rng = SplitMix64(seed: 7)
        for (a, b) in pairs {
            var state = CubeState.solved
            for _ in 0..<20 {
                let face = Face.allCases[rng.int(upperBound: 6)]
                state.apply(Move(.face(face), MoveAmount.allCases[rng.int(upperBound: 3)]))
            }
            XCTAssertEqual(state.applying(a).applying(b), state.applying(b).applying(a),
                           "\(a.notation) 与 \(b.notation) 应可交换")
        }
    }

    /// 相邻层不可交换——反证上面那条不是恒等式带来的假绿
    func test_adjacent_layers_do_not_commute() {
        let state = Scramble.random(length: 12, seed: 3).initialState
        XCTAssertNotEqual(state.applying(.r).applying(.u), state.applying(.u).applying(.r))
        XCTAssertNotEqual(state.applying(.m).applying(.u), state.applying(.u).applying(.m))
    }

    func test_opposite_face_quadruple_is_identity() {
        // R L 可交换，(R L)^4 = R4 L4 = 还原；(R L)^2 = R2 L2 不是还原态
        XCTAssertFalse(CubeState.solved.applying(Algorithm.parse("R L R L")!).isSolved)
        XCTAssertTrue(CubeState.solved.applying(Algorithm.parse("R L R L R L R L")!).isSolved)
    }

    // MARK: - 不变量

    func test_color_counts_are_conserved() {
        var state = CubeState.solved
        var rng = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let face = Face.allCases[rng.int(upperBound: 6)]
            state.apply(Move(.face(face), MoveAmount.allCases[rng.int(upperBound: 3)]))
            let counts = state.colorCounts()
            for color in CubeColor.allCases {
                XCTAssertEqual(counts[color], 9, "随机 500 步后 \(color) 数量异常")
            }
        }
    }

    func test_scramble_then_inverse_restores_solved() {
        for seed: UInt64 in [1, 99, 12345, UInt64.max] {
            let scramble = Scramble.random(length: 20, seed: seed)
            var state = scramble.initialState
            XCTAssertFalse(state.isSolved)
            state.apply(scramble.inverse)
            XCTAssertTrue(state.isSolved, "seed \(seed) 的打乱施加逆序后应还原")
        }
    }

    func test_isSolved_rejectsSingleTurn() {
        for face in Face.allCases {
            for amount in MoveAmount.allCases {
                XCTAssertFalse(CubeState.solved.applying(Move(.face(face), amount)).isSolved,
                               "\(face.letter)\(amount.suffix) 之后不应判定为已还原")
            }
        }
    }

    // MARK: - 渲染层入口

    func test_stickerLookupByPosition() {
        let solved = CubeState.solved
        XCTAssertEqual(solved.color(at: V3(2, 2, 2), facing: .posX), .red)
        XCTAssertEqual(solved.color(at: V3(2, 2, 2), facing: .posY), .white)
        XCTAssertEqual(solved.color(at: V3(2, 2, 2), facing: .posZ), .green)
        XCTAssertNil(solved.color(at: V3(2, 2, 2), facing: .negX), "内侧面不应查到贴纸")
        XCTAssertNil(solved.color(at: V3(0, 0, 0), facing: .posZ), "中心块内部不应查到贴纸")
    }

    func test_stickerLookupAfterTurn() {
        let state = CubeState.solved.applying(.u)
        // U 顺时针把右后上角搬到右前上位置：红贴纸朝前、蓝贴纸朝右、白仍朝上
        XCTAssertEqual(state.color(at: V3(2, 2, 2), facing: .posZ), .red)
        XCTAssertEqual(state.color(at: V3(2, 2, 2), facing: .posX), .blue)
        XCTAssertEqual(state.color(at: V3(2, 2, 2), facing: .posY), .white, "顶面贴纸仍应是白色")
    }

    func test_codableRoundTrip() throws {
        let state = CubeState.solved.applying(Algorithm.parse("R U R' U' F")!)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CubeState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}
