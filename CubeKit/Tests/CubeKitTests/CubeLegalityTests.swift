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
        // 2 阶与 4 阶现在都有判据了，只剩 5 阶以上没有
        for size in [5, 6] {
            XCTAssertEqual(CubeState(size: size).legality, .unsupportedSize(size))
        }
    }

    // MARK: - 偶数阶（2 阶 / 4 阶）

    /// 偶数阶的四条不变量，逐条实测：
    /// 角块各一次 + 扭角和 ≡ 0 (mod 3)、翼棱分组各两条 + 翻转和 ≡ 0 (mod 2)、每色 N² 个。
    ///
    /// 这几条**不是手推出来的**——偶数阶没有固定中心块，配色朝向无从锚定，
    /// 朝向的取法又是自定的，守恒性只能靠穷举钉住。
    func test_evenOrderInvariantsHoldOnRandomStates() {
        for size in [2, 4] {
            for seed in 1...150 {
                let state = randomState(size: size, seed: UInt64(seed))
                XCTAssertEqual(state.legality, .legal, "\(size) 阶 seed \(seed) 的可达态被判成不合法")
            }
        }
    }

    /// 四阶的转动生成元：6 个外层 × 3 种角度 + 6 个内层（每轴两层里除去外层那一层）× 3 种角度。
    /// 内层必须一起数——翼棱朝向和的守恒正是靠内层转动撑住的。
    private func generatorMoves(size: Int) -> [Move] {
        var moves: [Move] = []
        let maxDepth = (size + 1) / 2
        for face in Face.allCases {
            for depth in 1...max(1, maxDepth) {
                for amount in MoveAmount.allCases {
                    moves.append(Move(.face(face), amount, depth: depth))
                }
            }
        }
        return moves
    }

    func test_evenOrderGeneratorsPreserveLegality() {
        // 150 个打乱态 × 全部生成元。这是"翼棱朝向和模 2 守恒"的主证据。
        for size in [2, 4] {
            let moves = generatorMoves(size: size)
            for seed in 1...150 {
                let state = randomState(size: size, seed: UInt64(seed))
                XCTAssertEqual(state.legality, .legal, "\(size) 阶 seed \(seed) 的可达态不合法")
                for move in moves {
                    XCTAssertEqual(state.applying(move).legality, .legal,
                                   "\(size) 阶 seed \(seed) 施加 \(move.notation) 后不合法")
                }
            }
        }
    }

    func test_fourByFourSingleWingFlipIsIllegal() {
        // 单独翻一条翼棱：翻转和变成奇数，必须被揪出来
        for seed in [1, 7, 99] {
            let state = randomState(size: 4, seed: UInt64(seed))
            let flipped = flippingWing(at: V3(1, 3, 3), of: state)
            XCTAssertEqual(flipped.legality, .wingFlipSum, "seed \(seed) 的单条翼棱翻转没被抓住")
        }
    }

    func test_evenOrderSingleCornerTwistIsIllegal() {
        for size in [2, 4] {
            let state = randomState(size: size, seed: 3)
            let signs = size == 2 ? V3(1, 1, 1) : V3(3, 3, 3)
            for twist in 1...2 {
                XCTAssertEqual(twistingCorner(signs: signs, by: twist, of: state).legality,
                               .cornerTwistSum, "\(size) 阶扭 \(twist) 格没被抓住")
            }
        }
    }

    /// 镜像摆放：把 R 面与 L 面的颜色对调，等于把整颗魔方镜像了一下。
    /// 8 个角块照样各归其位、扭角和照样是 3 的倍数，**只有手性不对**。
    /// 奇数阶靠中心块就能挡住（中心块会被挪走），偶数阶没有中心块，必须靠显式手性检查。
    func test_mirroredPlacementIsIllegal() {
        for size in [2, 4] {
            let mirrored = swappingFaceColors(.r, .l, of: CubeState.solved(size: size))
            XCTAssertEqual(mirrored.legality, .mirroredCorner(slot: 0),
                           "\(size) 阶的镜像摆放没被抓住——整个镜像族都会被当成候选")
        }
    }

    func test_evenOrderSingleStickerRecolorIsAlwaysRejected() {
        for size in [2, 4] {
            let state = randomState(size: size, seed: 11)
            for (row, col) in [(0, 0), (size - 1, size - 1)] {
                var stickers = state.stickers
                let index = faceletIndex(.f, row: row, col: col, size: size)
                stickers[index] = stickers[index] == .white ? .yellow : .white
                XCTAssertFalse(CubeState(stickers: stickers).isLegalState,
                               "\(size) 阶把 (\(row),\(col)) 改个颜色竟然还是合法的")
            }
        }
    }

    /// 四阶中心块的贴纸改一格：角块与翼棱结构都还好好的，只能靠色数抓
    func test_fourByFourCenterRecolorIsCaughtByColorCount() {
        let state = randomState(size: 4, seed: 11)
        var stickers = state.stickers
        let index = faceletIndex(.f, row: 1, col: 1, size: 4)
        stickers[index] = stickers[index] == .white ? .yellow : .white
        guard case .colorCountMismatch = CubeState(stickers: stickers).legality else {
            return XCTFail("四阶中心块改一格应报 colorCountMismatch")
        }
    }

    // MARK: - 整体旋转下的规范代表

    func test_canonicalRepresentativeIsStableUnderWholeCubeRotation() {
        // 偶数阶同一颗魔方的 24 种整体旋转都是合法状态，规范化后必须收敛到同一个
        for size in [2, 4] {
            let state = randomState(size: size, seed: 5)
            let canonical = state.rotationallyCanonical
            for x in 0..<4 {
                for y in 0..<4 {
                    let rotated = state.applying(Algorithm(
                        [Move(.rotation(.x), .cw)].prefix(x).map { $0 }
                        + [Move(.rotation(.y), .cw)].prefix(y).map { $0 }
                    ))
                    XCTAssertEqual(rotated.rotationallyCanonical, canonical,
                                   "\(size) 阶整体旋转后规范代表变了")
                }
            }
        }
    }

    func test_threeByThreeIsLeftAloneByCanonicalization() {
        // 三阶有中心块锚定，不需要也不应该被规范化
        let state = Scramble.random(size: 3, length: 15, seed: 8).initialState
        XCTAssertEqual(state.rotationallyCanonical, state)
    }

    // MARK: - 偶数阶的辅助构造

    private func randomState(size: Int, seed: UInt64, length: Int = 60) -> CubeState {
        var generator = SplitMix64(seed: seed)
        var state = CubeState.solved(size: size)
        var lastFace: Face?
        let maxDepth = max(1, (size + 1) / 2)
        for _ in 0..<length {
            var face = Face.allCases[Int.random(in: 0..<Face.count, using: &generator)]
            while face == lastFace { face = Face.allCases[Int.random(in: 0..<Face.count, using: &generator)] }
            lastFace = face
            let amount = MoveAmount.allCases[Int.random(in: 0..<MoveAmount.allCases.count, using: &generator)]
            let depth = Int.random(in: 1...maxDepth, using: &generator)
            state.apply(Move(.face(face), amount, depth: depth))
        }
        return state
    }

    /// 某块朝外的贴纸下标：坐标绝对值等于 size−1 的那些轴就是它的贴纸方向
    private func pieceFaceletIndices(_ center: V3, size: Int) -> [Int] {
        var result: [Int] = []
        for (value, unit) in [(center.x, V3.posX), (center.y, V3.posY), (center.z, V3.posZ)]
        where abs(value) == size - 1 {
            let direction = value > 0 ? unit : -unit
            result.append(StickerGeometry.index(cubieCenter: center, facing: direction, size: size)!)
        }
        return result
    }

    /// 翻转一条翼棱：把该槽位两个贴纸的颜色对调
    private func flippingWing(at center: V3, of state: CubeState) -> CubeState {
        let indices = pieceFaceletIndices(center, size: state.size)
        var stickers = state.stickers
        stickers.swapAt(indices[0], indices[1])
        return CubeState(stickers: stickers)
    }

    /// 扭转一个角：把该槽位三个贴纸的颜色循环移位（次序与 `cornerColors` 一致）
    private func twistingCorner(signs: V3, by twist: Int, of state: CubeState) -> CubeState {
        let x = V3(signs.x > 0 ? 1 : -1, 0, 0)
        let y = V3(0, signs.y > 0 ? 1 : -1, 0)
        let z = V3(0, 0, signs.z > 0 ? 1 : -1)
        let normals = signs.x * signs.y * signs.z > 0 ? [y, z, x] : [y, x, z]
        let indices = normals.map { StickerGeometry.index(cubieCenter: signs, facing: $0, size: state.size)! }
        var stickers = state.stickers
        let colors = indices.map { stickers[$0] }
        for (offset, index) in indices.enumerated() {
            stickers[index] = colors[(offset - twist + 3) % 3]
        }
        return CubeState(stickers: stickers)
    }

    /// 把两个面的颜色整体对调（构造镜像摆放）
    private func swappingFaceColors(_ lhs: Face, _ rhs: Face, of state: CubeState) -> CubeState {
        let n = state.size
        var stickers = state.stickers
        for offset in 0..<(n * n) {
            let left = lhs.rawValue * n * n + offset
            let right = rhs.rawValue * n * n + offset
            let buffer = stickers[left]
            stickers[left] = stickers[right]
            stickers[right] = buffer
        }
        return CubeState(stickers: stickers)
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
