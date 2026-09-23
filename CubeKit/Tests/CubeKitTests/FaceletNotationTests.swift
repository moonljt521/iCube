import XCTest
@testable import CubeKit

/// 面位记法的往返与结构校验。
/// 这里只验证"编解码本身自洽"；映射是否与外部求解器一致，由 CubeSolve 的
/// 端到端测试（随机状态 → 求解 → 施加解 → 判定还原）来保证。
final class FaceletNotationTests: XCTestCase {

    private let solvedString = "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"

    // MARK: - 基本映射

    func test_solvedCubeMatchesStandardString() {
        XCTAssertEqual(CubeState.solved.faceletString, solvedString)
    }

    func test_lengthIsFiftyFour() {
        XCTAssertEqual(CubeState.solved.faceletString?.count, 54)
    }

    /// 面位记法只定义在三阶上
    func test_nonCubicSizeReturnsNil() {
        for size in [2, 4] {
            XCTAssertNil(CubeState.solved(size: size).faceletString, "\(size) 阶不该有面位串")
        }
    }

    /// 每色恰好 9 个，且字符集合就是 6 个面字母
    func test_stringContainsEachFaceLetterNineTimes() {
        let string = CubeState.solved.faceletString!
        for letter in ["U", "R", "F", "D", "L", "B"] as [Character] {
            XCTAssertEqual(string.filter { $0 == letter }.count, 9, "\(letter) 应出现 9 次")
        }
    }

    // MARK: - 一次转动验证块顺序与行列读法

    /// U 顺时针：F→L→B→R→F，即各侧面上排贴纸整体左移一格。
    /// 若块顺序错、或某面行列被翻转，这条断言会直接失败。
    func test_clockwiseU_rotatesTopRowsAsExpected() {
        let after = CubeState.solved.applying(.u).faceletString!

        XCTAssertEqual(block(after, "U"), "UUUUUUUUU", "U 面自身不变色")
        XCTAssertEqual(block(after, "D"), "DDDDDDDDD", "D 面不受影响")
        XCTAssertEqual(block(after, "F"), "RRRFFFFFF", "F 的上排应换成 R 的颜色")
        XCTAssertEqual(block(after, "L"), "FFFLLLLLL", "L 的上排应换成 F 的颜色")
        XCTAssertEqual(block(after, "B"), "LLLBBBBBB", "B 的上排应换成 L 的颜色")
        XCTAssertEqual(block(after, "R"), "BBBRRRRRR", "R 的上排应换成 B 的颜色")
    }

    /// D 顺时针：从下方看顺时针，从上方看就是逆时针 → 环流 F→R→B→L→F，
    /// 与 U 的 F→L 方向相反。方向正确性另由 test_wholeCubeYEqualsUThenDPrime 独立钉住。
    func test_clockwiseD_rotatesBottomRowsAsExpected() {
        let after = CubeState.solved.applying(.d).faceletString!

        XCTAssertEqual(block(after, "D"), "DDDDDDDDD", "D 面自身不变色")
        XCTAssertEqual(block(after, "U"), "UUUUUUUUU", "U 面不受影响")
        XCTAssertEqual(block(after, "F"), "FFFFFFLLL", "F 的下排应换成 L 的颜色")
        XCTAssertEqual(block(after, "R"), "RRRRRRFFF", "R 的下排应换成 F 的颜色")
        XCTAssertEqual(block(after, "B"), "BBBBBBRRR", "B 的下排应换成 R 的颜色")
        XCTAssertEqual(block(after, "L"), "LLLLLLBBB", "L 的下排应换成 B 的颜色")
    }

    /// R 顺时针：环流 F→U→B→D→F，各面被改动的都是 x=+1 那一列。
    /// 注意 B 面正视时 x=+1 落在**左**列（屏幕右方向是 -X），所以取列方向按面而异。
    func test_clockwiseR_rotatesRightColumnsAsExpected() {
        let after = CubeState.solved.applying(.r).faceletString!

        XCTAssertEqual(block(after, "R"), "RRRRRRRRR", "R 面自身不变色")
        XCTAssertEqual(block(after, "L"), "LLLLLLLLL", "L 面不受影响")
        XCTAssertEqual(columnAtCubeRight(after, "U"), "FFF", "U 的 x=+1 列应换成 F 的颜色")
        XCTAssertEqual(columnAtCubeRight(after, "F"), "DDD", "F 的 x=+1 列应换成 D 的颜色")
        XCTAssertEqual(columnAtCubeRight(after, "D"), "BBB", "D 的 x=+1 列应换成 B 的颜色")
        XCTAssertEqual(columnAtCubeRight(after, "B"), "UUU", "B 的 x=+1 列应换成 U 的颜色")
    }

    /// 整体旋转可拆成「同轴三个层同向转」——标准恒等式 x = R M' L'、y = U E' D'、z = F S B'。
    /// 这条不依赖任何手工推导的期望串，一次钉死 9 个外层/中层转动的方向：
    /// 只要 U/D 被写成同向、或某个面/中层符号反了，这里必挂。
    func test_wholeCubeRotationsDecomposeIntoLayerTurns() {
        let solved = CubeState.solved
        XCTAssertEqual(solved.applying(.r).applying(.mPrime).applying(.lPrime), solved.applying(.x), "x = R M' L'")
        XCTAssertEqual(solved.applying(.u).applying(.ePrime).applying(.dPrime), solved.applying(.y), "y = U E' D'")
        XCTAssertEqual(solved.applying(.f).applying(.s).applying(.bPrime), solved.applying(.z), "z = F S B'")
    }

    // MARK: - 往返

    func test_solvedRoundTrip() {
        let state = CubeState.solved
        let restored = CubeState(faceletString: state.faceletString!)
        XCTAssertEqual(restored, state)
    }

    /// 随机多步转动后，状态 → 串 → 状态 必须回到原状态
    func test_randomStatesRoundTrip() {
        var rng = SplitMix64(seed: 20260923)
        let pool: [Move] = MoveKind.all.flatMap { kind in
            MoveAmount.allCases.map { Move(kind, $0) }
        }
        for trial in 0..<200 {
            var state = CubeState.solved
            for _ in 0..<30 {
                state.apply(pool[rng.int(upperBound: pool.count)])
            }
            guard let string = state.faceletString else {
                return XCTFail("三阶应能生成面位串")
            }
            XCTAssertEqual(string.count, 54)
            XCTAssertEqual(CubeState(faceletString: string), state, "第 \(trial) 次往返不一致")
        }
    }

    /// 串 → 状态 → 串 也必须回到原串（对任意合法字符组合成立）
    func test_stringRoundTrip() {
        var rng = SplitMix64(seed: 7)
        let pool: [Move] = MoveKind.all.flatMap { kind in
            MoveAmount.allCases.map { Move(kind, $0) }
        }
        for _ in 0..<100 {
            var state = CubeState.solved
            for _ in 0..<25 {
                state.apply(pool[rng.int(upperBound: pool.count)])
            }
            let string = state.faceletString!
            XCTAssertEqual(CubeState(faceletString: string)?.faceletString, string)
        }
    }

    /// 转动与面位串应保持一致：先转再编码 == 编码后再按同一位移解码
    func test_moveCommutesWithEncoding() {
        var rng = SplitMix64(seed: 99)
        let pool: [Move] = Face.allCases.flatMap { face in
            MoveAmount.allCases.map { Move(.face(face), $0) }
        }
        for _ in 0..<100 {
            var state = CubeState.solved
            for _ in 0..<20 {
                state.apply(pool[rng.int(upperBound: pool.count)])
            }
            let move = pool[rng.int(upperBound: pool.count)]
            let direct = state.applying(move).faceletString
            let viaString = CubeState(faceletString: state.faceletString!)?.applying(move).faceletString
            XCTAssertEqual(direct, viaString)
        }
    }

    // MARK: - 非法输入

    func test_rejectsWrongLength() {
        XCTAssertNil(CubeState(faceletString: ""))
        XCTAssertNil(CubeState(faceletString: String(solvedString.dropLast())))
        XCTAssertNil(CubeState(faceletString: solvedString + "U"))
    }

    func test_rejectsUnknownCharacters() {
        XCTAssertNil(CubeState(faceletString: String(repeating: "X", count: 54)))
        XCTAssertNil(CubeState(faceletString: String(repeating: "1", count: 54)))
        XCTAssertNil(CubeState(faceletString: String(repeating: " ", count: 54)))
    }

    func test_acceptsLowercaseLetters() {
        XCTAssertEqual(CubeState(faceletString: solvedString.lowercased()), .solved)
    }

    // MARK: - 字母与颜色互逆

    func test_letterColorRoundTrip() {
        for color in CubeColor.allCases {
            let letter = FaceletNotation.letter(for: color)
            XCTAssertEqual(FaceletNotation.color(for: letter), color)
        }
    }

    func test_faceOrderIsExternalConvention() {
        XCTAssertEqual(FaceletNotation.faceOrder, [.u, .r, .f, .d, .l, .b])
        XCTAssertEqual(FaceletNotation.faceOrder.count * 9, 54)
    }

    // MARK: - 辅助

    private func block(_ string: String, _ face: String) -> String {
        let chars = Array(string)
        let index = FaceletNotation.faceOrder.firstIndex { String($0.letter) == face }!
        let start = index * 9
        return String(chars[start..<(start + 9)])
    }

    /// 取某面上 x = +1 那一列（即贴着 R 面那一侧）。
    /// 正视该面时，若其屏幕右方向就是 -X（B 面如此），该列在画面上落在最左边。
    private func columnAtCubeRight(_ string: String, _ face: String) -> String {
        let b = Array(block(string, face))
        let f = FaceletNotation.faceOrder.first { String($0.letter) == face }!
        let column = f.right.dot(.posX) >= 0 ? 2 : 0
        return String([b[column], b[3 + column], b[6 + column]])
    }
}
