import XCTest
@testable import CubeKit

final class CubeLegalityTests: XCTestCase {

    // MARK: - 合法状态

    func test_solvedIsLegal() {
        XCTAssertEqual(CubeState.solved.legality, .legal)
    }

    /// 18 个外层转动：不做整体翻转、不碰中层，中心块始终各就各位
    private var outerFaceMoves: [Move] {
        Face.allCases.flatMap { face in
            MoveAmount.allCases.map { Move(.face(face), $0) }
        }
    }

    func test_everyOuterFaceMovePreservesLegality() {
        // 从还原态出发，18 个外层转动各走一步，结果必须仍然合法。
        // 这一条同时钉住了"棱/角朝向和"这两条不变量确实在每次转动下守恒——
        // 朝向的取法是自定的，守恒性必须验证而不是假定。
        let moves = outerFaceMoves
        XCTAssertEqual(moves.count, 18)
        for move in moves {
            let state = CubeState.solved.applying(move)
            XCTAssertEqual(state.legality, .legal, "\(move.notation) 之后不合法了")
        }
    }

    func test_middleSliceAndRotationMovesBreakStandardOrientation() {
        // 中层切片与整体旋转会把中心块挪走。状态本身当然拧得出来，
        // 但面位记法（以及求解器）只认中心块在标准位置的那一串，
        // 所以这里必须报 centerMismatch 而不是 legal。
        for move in [Move.m, Move.e, Move.s, Move.x, Move.y, Move.z] {
            let result = CubeState.solved.applying(move).legality
            guard case .centerMismatch = result else {
                return XCTFail("\(move.notation) 应报 centerMismatch，实际 \(result)")
            }
        }
    }

    func test_scramblesAreLegal() {
        for seed in 1...200 {
            let scramble = Scramble.random(size: 3, length: 25, seed: UInt64(seed))
            let state = CubeState.solved.applying(scramble.algorithm)
            XCTAssertEqual(state.legality, .legal, "打乱 \(scramble.notation) 不合法")
        }
    }

    func test_scrambledStatesStayLegalAfterFurtherMoves() {
        // 200 个打乱态 × 18 个外层转动。这是棱/角朝向"总和守恒"的主证据：
        // 朝向的取法是自定的，守恒性只能靠穷举钉住，不能靠手推。
        for seed in 1...200 {
            let state = Scramble.random(size: 3, length: 20, seed: UInt64(seed)).initialState
            XCTAssertEqual(state.legality, .legal, "seed \(seed) 的打乱态不合法")
            for move in outerFaceMoves {
                XCTAssertEqual(state.applying(move).legality, .legal, "seed \(seed) 施加 \(move.notation) 后不合法")
            }
        }
    }

    func test_wholeCubeRotationsMoveCentersAway() {
        // 整体旋转本身不改变"拧得出来"，但它把中心块挪走了。
        // 本判定的口径是"这串能不能直接喂给求解器"，所以必须报 centerMismatch——
        // 这不是 bug，是刻意的语义，单独钉住免得以后被"修掉"。
        for rotation in CubeRotation.allCases {
            for amount in MoveAmount.allCases {
                let move = Move(.rotation(rotation), amount)
                guard case .centerMismatch = CubeState.solved.applying(move).legality else {
                    return XCTFail("\(move.notation) 应报 centerMismatch")
                }
            }
        }
    }

    // MARK: - 面位串往返

    func test_faceletStringRoundTripKeepsLegality() {
        let state = Scramble.random(size: 3, length: 15, seed: 42).initialState
        let restored = CubeState(faceletString: state.faceletString!)
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored?.legality, .legal)
    }

    // MARK: - 非法状态

    func test_singleEdgeFlipIsIllegal() {
        let state = flippingEdge(at: (1, 0, 1), of: CubeState.solved)
        XCTAssertEqual(state.legality, .edgeFlipSum)
    }

    func test_singleCornerTwistIsIllegal() {
        for twist in 1...2 {
            let state = twistingCorner(at: (1, 1, 1), by: twist, of: CubeState.solved)
            XCTAssertEqual(state.legality, .cornerTwistSum, "扭转 \(twist) 格")
        }
    }

    func test_twoEdgesSwappedIsIllegal() {
        // 必须换同类的两条棱（都在上/下层，或都在中层）。跨类互换会连带
        // 改变棱朝向和，那就先报 edgeFlipSum 了，测不到奇偶性这条。
        let state = swappingEdges((0, 1, 1), (0, 1, -1), of: CubeState.solved)
        XCTAssertEqual(state.legality, .permutationParity(corner: 0, edge: 1))
    }

    func test_twoCornersSwappedIsIllegal() {
        let state = swappingCorners((1, 1, 1), (1, 1, -1), of: CubeState.solved)
        XCTAssertEqual(state.legality, .permutationParity(corner: 1, edge: 0))
    }

    func test_centersMismatchIsDetected() {
        // 把 F 面中心改成红色（红色本就属于 R 面）
        var stickers = CubeState.solved.stickers
        stickers[faceletIndex(.f, row: 1, col: 1)] = .red
        XCTAssertEqual(CubeState(stickers: stickers).legality, .centerMismatch(face: .f))
    }

    func test_colorCountMismatchIsDetected() {
        // 改一格但不动中心块：绿色少一个、红色多一个
        var stickers = CubeState.solved.stickers
        stickers[faceletIndex(.f, row: 0, col: 0)] = .red
        XCTAssertEqual(CubeState(stickers: stickers).legality, .colorCountMismatch(color: .green, count: 8))
    }

    func test_unsupportedSizeIsReported() {
        XCTAssertEqual(CubeState(size: 2).legality, .unsupportedSize(2))
        XCTAssertEqual(CubeState(size: 4).legality, .unsupportedSize(4))
    }

    func test_illegalStatesAreStillRejectedAfterScrambling() {
        // 打乱后再制造一个单棱翻转：错误必须照样被揪出来，
        // 不能只在还原态附近才管用
        let scrambled = Scramble.random(size: 3, length: 18, seed: 99).initialState
        XCTAssertEqual(scrambled.legality, .legal)
        let flipped = flippingEdge(at: (1, 0, 1), of: scrambled)
        XCTAssertEqual(flipped.legality, .edgeFlipSum)
    }

    // MARK: - 构造非法状态的辅助

    /// 翻转某条棱：把该槽位两个贴纸的颜色对调
    private func flippingEdge(at signs: (Int, Int, Int), of state: CubeState) -> CubeState {
        let indices = edgeFaceletIndices(signs)
        var stickers = state.stickers
        stickers.swapAt(indices[0], indices[1])
        return CubeState(stickers: stickers)
    }

    /// 扭转某个角：把该槽位三个贴纸的颜色循环移位。
    ///
    /// 下标顺序刻意与生产代码 `CubieGeometry.cornerFacelets` 一致（上/下面那一格打头），
    /// 这样"循环移位 k 格"恰好等于朝向 k，断言才能写成精确值而不是"非零"。
    private func twistingCorner(at signs: (Int, Int, Int), by twist: Int, of state: CubeState) -> CubeState {
        let indices = cornerFaceletIndices(signs)
        var stickers = state.stickers
        let colors = indices.map { stickers[$0] }
        for (offset, index) in indices.enumerated() {
            stickers[index] = colors[(offset - twist + 3) % 3]
        }
        return CubeState(stickers: stickers)
    }

    /// 交换两条棱
    private func swappingEdges(
        _ a: (Int, Int, Int),
        _ b: (Int, Int, Int),
        of state: CubeState
    ) -> CubeState {
        let first = edgeFaceletIndices(a)
        let second = edgeFaceletIndices(b)
        var stickers = state.stickers
        for offset in 0..<2 {
            let buffer = stickers[first[offset]]
            stickers[first[offset]] = stickers[second[offset]]
            stickers[second[offset]] = buffer
        }
        return CubeState(stickers: stickers)
    }

    /// 交换两个角
    private func swappingCorners(
        _ a: (Int, Int, Int),
        _ b: (Int, Int, Int),
        of state: CubeState
    ) -> CubeState {
        let first = cornerFaceletIndices(a)
        let second = cornerFaceletIndices(b)
        var stickers = state.stickers
        for offset in 0..<3 {
            let buffer = stickers[first[offset]]
            stickers[first[offset]] = stickers[second[offset]]
            stickers[second[offset]] = buffer
        }
        return CubeState(stickers: stickers)
    }

    private func cornerFaceletIndices(_ signs: (Int, Int, Int)) -> [Int] {
        let center = V3(2 * signs.0, 2 * signs.1, 2 * signs.2)
        let x = V3(signs.0, 0, 0)
        let y = V3(0, signs.1, 0)
        let z = V3(0, 0, signs.2)
        let normals = signs.0 * signs.1 * signs.2 > 0 ? [y, z, x] : [y, x, z]
        return normals.map { StickerGeometry.index(cubieCenter: center, facing: $0)! }
    }

    private func edgeFaceletIndices(_ signs: (Int, Int, Int)) -> [Int] {
        let center = V3(2 * signs.0, 2 * signs.1, 2 * signs.2)
        return [V3(signs.0, 0, 0), V3(0, signs.1, 0), V3(0, 0, signs.2)]
            .filter { $0 != .zero }
            .map { StickerGeometry.index(cubieCenter: center, facing: $0)! }
    }
}
