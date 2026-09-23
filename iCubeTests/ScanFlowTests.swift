import CubeKit
import CubeScan
import CubeSolve
import XCTest
@testable import iCube

/// 拍照 → 识别 → 灌进录入页 这条链路的集成测试。
///
/// 相机本身不测（那层没有可测的逻辑，只是把帧转出来）；测的是**契约**：
/// 六个面的采样色进来，最后录入页是不是满的、能不能直接求解。
/// 这条链路跨了 `CubeScan` 和 `RestoreModel` 两个模块，各自单测覆盖不到接缝。
@MainActor
final class ScanFlowTests: XCTestCase {

    /// 把一个状态模拟成"用户拍的六张照片"：每个面可以各自转一个角度
    private func captures(of state: CubeState, rotations: [Face: Int]) -> [FaceCapture] {
        let n = state.size
        return Face.allCases.map { face in
            var grid = (0..<(n * n)).map { state.color(at: face, row: $0 / n, col: $0 % n) }
            grid = FaceletAssembler.rotated(grid, quarterTurns: rotations[face] ?? 0, size: n)
            return FaceCapture(samples: grid.map { StickerClassifier.references[$0]! })
        }
    }

    /// 偶数阶没有固定中心块，照片与面的对应关系未知，这里连**拍摄次序**也一起打乱
    private func shuffledCaptures(of state: CubeState, seed: UInt64) -> [FaceCapture] {
        var generator = SplitMix64(seed: seed &* 7919)
        var order = Face.allCases
        for index in stride(from: order.count - 1, through: 1, by: -1) {
            order.swapAt(index, Int.random(in: 0...index, using: &generator))
        }
        let n = state.size
        return order.map { face in
            var grid = (0..<(n * n)).map { state.color(at: face, row: $0 / n, col: $0 % n) }
            grid = FaceletAssembler.rotated(grid, quarterTurns: Int.random(in: 0..<4, using: &generator), size: n)
            return FaceCapture(samples: grid.map { StickerClassifier.references[$0]! })
        }
    }

    func test_scannedStateLandsReadyToSolve() throws {
        for seed in UInt64(1)...10 {
            let original = Scramble.random(size: 3, length: 20, seed: seed).initialState
            // 每个面拍进去的朝向都不一样，模拟"用户随手拿着拍"
            let rotations = Dictionary(uniqueKeysWithValues: Face.allCases.enumerated().map {
                ($0.element, ($0.offset + Int(seed)) % 4)
            })

            let classified = try StickerClassifier.classify(captures(of: original, rotations: rotations))
            let state = try XCTUnwrap(FaceletAssembler.assemble(classified.colors),
                                      "seed \(seed) 拼不出合法状态")

            let model = RestoreModel()
            model.load(state: state)

            XCTAssertEqual(model.filledCount, 54, "seed \(seed) 识别后录入页没填满")
            XCTAssertTrue(model.canSolve, "seed \(seed) 识别后录入页不能求解：\(model.statusMessage)")
            XCTAssertEqual(model.state, original, "seed \(seed) 录入页里的状态与真实状态不一致")
        }
    }

    func test_missingOneFaceIsRejectedInsteadOfGuessed() {
        // 只拍了五个面：必须明确报错，不能拿半个魔方硬猜一个状态出来
        let original = Scramble.random(size: 3, length: 20, seed: 7).initialState
        let partial = Array(captures(of: original, rotations: [:]).dropLast())
        XCTAssertThrowsError(try StickerClassifier.classify(partial)) { error in
            XCTAssertEqual(error as? ScanError, .wrongFaceCount(5))
        }
    }

    func test_sameFaceTwiceIsRejectedAtClassification() {
        // 同一面拍了两遍：中心块颜色必然撞车
        let original = Scramble.random(size: 3, length: 20, seed: 11).initialState
        let six = captures(of: original, rotations: [:])
        let repeated = [six[0], six[1], six[2], six[3], six[4], six[4]]
        XCTAssertThrowsError(try StickerClassifier.classify(repeated)) { error in
            guard case .duplicateCenter = error as? ScanError else {
                return XCTFail("应报 duplicateCenter，实际 \(error)")
            }
        }
    }

    /// 把握度提醒的阈值边界：够有把握必须给 nil，低于阈值必须给话。
    ///
    /// 提醒只提示不拦截，所以这里钉的是"什么时候说话"——说多了会变成噪音，
    /// 说少了等于没接。
    func test_confidenceHintOnlyFiresBelowThreshold() {
        let threshold = ClassifiedFaces.lowConfidenceThreshold

        XCTAssertNil(ScanModel.confidenceHint(margin: threshold),
                     "恰好等于阈值不该提醒——语义是「低于才提醒」")
        XCTAssertNil(ScanModel.confidenceHint(margin: threshold + 1),
                     "明显有把握却给了提醒，会变成天天弹的噪音")

        let hint = ScanModel.confidenceHint(margin: 2.5)
        XCTAssertNotNil(hint, "低于阈值却没提醒，这个信号等于白算")
        XCTAssertTrue(hint?.contains("2.5") == true,
                      "提醒里没带把握度数值，用户不知道差多少：\(hint ?? "nil")")
    }

    // MARK: - 2 阶 / 4 阶

    /// 偶数阶全链路：拍照 → 识别 → 灌进录入页。
    ///
    /// 与三阶同一套断言，但**比较前要先规范化**——偶数阶没有固定中心块，
    /// 识别结果只在"整体旋转意义下"唯一。
    func test_evenOrderScannedStateLandsReadyToSolve() throws {
        for size in [2, 4] {
            for seed in 1...4 {
                let original = Scramble.random(size: size, length: 40, seed: UInt64(seed)).initialState
                let classified = try StickerClassifier.classify(
                    shuffledCaptures(of: original, seed: UInt64(seed)), size: size
                )
                let state = try XCTUnwrap(FaceletAssembler.assemble(classified.colors, size: size),
                                          "\(size) 阶 seed \(seed) 拼不出合法状态")

                let model = RestoreModel(size: size)
                model.load(state: state)

                XCTAssertEqual(model.filledCount, 6 * size * size,
                               "\(size) 阶 seed \(seed) 识别后录入页没填满")
                if size == 2 {
                    XCTAssertTrue(model.canSolve, "2 阶 seed \(seed) 识别后不能求解：\(model.statusMessage)")
                }
                XCTAssertEqual(model.state?.rotationallyCanonical, original.rotationallyCanonical,
                               "\(size) 阶 seed \(seed) 录入页里的状态与真实状态不一致")
            }
        }
    }

    /// 界面画采样色之前必须拧到**屏幕次序**：相机帧是横的、屏幕是竖的，差 90°。
    ///
    /// 取景框上的实时色块与下面那排已拍缩略图都走这里。缩略图漏过一次，
    /// 表现就是"拍完那排小图是转的"——实时预览对、缩略图不对，看着像拍歪了。
    func test_displayReorderIsAQuarterTurnOfFrameOrder() {
        for size in [2, 3, 4] {
            // 用 L 当标记：每个采样点一个可区分的值
            let samples = (0..<(size * size)).map { LabColor(l: Double($0), a: 0, b: 0) }
            let display = ScanModel.reorderedForDisplay(samples, size: size)

            XCTAssertEqual(display.count, samples.count)
            XCTAssertEqual(Set(display.map(\.l)).count, size * size, "\(size) 阶重排后不是双射")
            // 顺时针 90° 的签名：帧的**左上角**要落到屏幕的**右上角**（屏幕索引 size−1），
            // 反过来屏幕的左上角取的是帧的**左下角**。转置会把帧左上角送到屏幕的 (1,0)。
            XCTAssertEqual(display[size - 1].l, samples[0].l, "\(size) 阶重排方向不对")
            XCTAssertEqual(display[0].l, samples[(size - 1) * size].l, "\(size) 阶重排方向不对")
            // 拧四次回到原样
            var current = samples
            for _ in 0..<4 { current = ScanModel.reorderedForDisplay(current, size: size) }
            XCTAssertEqual(current.map(\.l), samples.map(\.l), "\(size) 阶拧四次没回到原样")
        }
    }

    /// 阶数要一路传到**取景几何**与**采样格数**上。
    ///
    /// 这条链路上任何一环漏掉 `size`，扫描页就还是九宫格——而且不会有任何报错，
    /// 只是切到 2 阶进来照样切 9 格。所以这里逐环钉住。
    func test_scanModelCarriesSizeAllTheWayToGeometry() {
        for size in [2, 3, 4] {
            let model = ScanModel(size: size)
            XCTAssertEqual(model.size, size)
            XCTAssertEqual(model.cellCount, size * size, "采样格数没跟上阶数")

            model.updateViewSize(CGSize(width: 390, height: 520))
            XCTAssertEqual(model.geometry.size, size, "取景几何没跟上阶数")

            // 引导框里的格子数 = 阶数²，且每一格都落在引导框内
            let geometry = model.geometry
            for index in 0..<model.cellCount {
                let cell = geometry.cellRect(index)
                XCTAssertGreaterThan(cell.width, 0)
                XCTAssertGreaterThan(cell.height, 0)
                XCTAssertTrue(geometry.guideRect.contains(cell.insetBy(dx: -0.01, dy: -0.01))
                              || geometry.guideRect.intersects(cell))
            }
        }
    }

    /// 偶数阶的候选解**每一个都必须是真能拧出来的状态**——不是判据太松放进了镜像。
    ///
    /// 这条是"2 阶偶尔拼出两个解"这个现象的定性依据：用求解器验（它自己会校验合法性，
    /// 且解完还会自检能还原），两个解都过得了，说明**输入本身就对应两颗不同的魔方**，
    /// 不是识别算法有问题。所以那种情况只能让用户挑，不能硬选一个。
    func test_everyEvenOrderCandidateIsGenuinelySolvable() async throws {
        // 素材页那个 2 阶打乱（seed 42）：第 3 面与第 6 面互为 90° 旋转，恰好是两解
        let original = Scramble.random(size: 2, length: 11, seed: 42).initialState
        let classified = try StickerClassifier.classify(shuffledCaptures(of: original, seed: 42), size: 2)
        let candidates = FaceletAssembler.assembleAll(classified.colors, size: 2)
        XCTAssertGreaterThan(candidates.count, 1, "这个素材本该是两解的，前提变了要重新评估")

        var sawTruth = false
        for candidate in candidates {
            if candidate.rotationallyCanonical == original.rotationallyCanonical { sawTruth = true }
            let solution = try CubeSolve.solve(candidate)
            XCTAssertTrue(candidate.applying(solution.algorithm).isSolved,
                          "候选解 \(candidate.stickers.map(\.rawValue)) 拧不回去——说明判据太松，放进了不可达状态")
        }
        XCTAssertTrue(sawTruth, "候选里没有真值，那就不只是歧义问题了")
    }

    /// 拼不出来时的诊断要指名道姓：色数偏了就说哪个色偏了多少格。
    ///
    /// "拍重了一面"与"认错了一格"的下一步动作完全不同（重拍 vs 改一格），
    /// 只丢一句"拼不出"用户不知道从哪下手。
    func test_assemblyFailureMessagePointsAtTheOffColors() {
        var colors: [Face: [CubeColor]] = [:]
        for face in Face.allCases { colors[face] = Array(repeating: face.defaultColor, count: 16) }

        let clean = ScanModel.assemblyFailureMessage(colors: colors, size: 4)
        XCTAssertTrue(clean.contains("颜色数看着都对"), "色数正常时该说别的：\(clean)")

        // 改一格：白少一个、红多一个
        colors[.u]?[0] = .red
        let message = ScanModel.assemblyFailureMessage(colors: colors, size: 4)
        XCTAssertTrue(message.contains("白 15 格"), "该点出白少了几格：\(message)")
        XCTAssertTrue(message.contains("红 17 格"), "该点出红多了几格：\(message)")
        XCTAssertTrue(message.contains("16 格"), "该说清本该多少格：\(message)")
    }

    /// 识别出多种拼法时能来回换，每一种都还是合法状态
    func test_cyclingCandidatesStaysLegal() {
        let first = CubeState.solved(size: 2)
        let second = first.applying(Move(.rotation(.y)))
        let model = RestoreModel(size: 2)
        XCTAssertFalse(model.hasCandidateChoices, "没候选时不该给入口")

        model.load(candidates: [first, second])
        XCTAssertTrue(model.hasCandidateChoices)
        XCTAssertEqual(model.state, first)
        XCTAssertEqual(model.candidateIndex, 0)

        model.cycleCandidate()
        XCTAssertEqual(model.state, second)
        XCTAssertEqual(model.candidateIndex, 1)
        model.cycleCandidate()
        XCTAssertEqual(model.state, first, "应该循环回第一种")
        XCTAssertEqual(model.state?.legality, .legal)
    }

    /// 用户自己动过格子后候选就作废——否则"换拼法"会把他的改动盖掉
    func test_manualEditDropsCandidates() {
        let model = RestoreModel(size: 2)
        model.load(candidates: [.solved(size: 2), .solved(size: 2).applying(Move(.rotation(.y)))])
        XCTAssertTrue(model.hasCandidateChoices)
        model.paint(.red, at: .u, row: 0, col: 0)
        XCTAssertFalse(model.hasCandidateChoices, "手改之后候选该作废")
    }

    /// 三阶恒为一种拼法，不该出现这个入口
    func test_threeByThreeHasNoCandidateChoices() {
        let state = Scramble.random(size: 3, length: 20, seed: 1).initialState
        let model = RestoreModel(size: 3)
        model.load(candidates: [state])
        XCTAssertFalse(model.hasCandidateChoices)
        model.cycleCandidate()
        XCTAssertEqual(model.state, state, "单候选时换拼法应是空操作")
    }

    /// 歧义提醒只在真的多解时说话
    func test_ambiguityHintOnlyFiresWhenThereAreChoices() {
        XCTAssertNil(ScanModel.ambiguityHint(count: 1), "只有一种拼法不该提醒")
        XCTAssertNil(ScanModel.ambiguityHint(count: 0))
        let hint = ScanModel.ambiguityHint(count: 2)
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint?.contains("换拼法") == true, "提醒里得说清下一步做什么：\(hint ?? "nil")")
    }

    /// 偶数阶没有固定中心块，录入页一个格子都不该预填
    func test_evenOrderEntryStartsWithNothingPrefilled() {
        for size in [2, 4] {
            let model = RestoreModel(size: size)
            XCTAssertFalse(model.hasFixedCenters, "\(size) 阶不该有固定中心块")
            XCTAssertEqual(model.filledCount, 0, "\(size) 阶录入页不该预填格子")
            XCTAssertEqual(model.stickers.count, 6 * size * size)
        }
        XCTAssertEqual(RestoreModel(size: 3).filledCount, 6, "三阶应预填六个中心块")
    }

    /// 二阶走完整条链路：识别 → 录入 → 求解 → 解真能还原
    func test_twoByTwoSolvesAfterScan() async throws {
        let original = Scramble.random(size: 2, length: 11, seed: 2).initialState
        let classified = try StickerClassifier.classify(shuffledCaptures(of: original, seed: 2), size: 2)
        let state = try XCTUnwrap(FaceletAssembler.assemble(classified.colors, size: 2))

        let model = RestoreModel(size: 2)
        model.load(state: state)
        await model.solve()

        let solution = try XCTUnwrap(model.solution, "二阶应给出解，实际失败于 \(String(describing: model.failure))")
        XCTAssertEqual(model.solvedState?.applying(solution.algorithm), .solved(size: 2),
                       "二阶的解不能还原录入的那个状态")
    }

    /// 四阶填满后 `canSolve` 为 false，状态栏提示"正在开发中"，不会走到求解入口
    func test_fourByFourSolveReportsUnsupported() async throws {
        let original = Scramble.random(size: 4, length: 40, seed: 6).initialState
        let model = RestoreModel(size: 4)
        model.load(state: original)
        XCTAssertFalse(model.canSolve, "四阶暂不应允许求解")
        XCTAssertTrue(model.statusMessage.contains("开发中"), "状态栏应提示正在开发中：\(model.statusMessage)")

        await model.solve()
        XCTAssertNil(model.solution)
        XCTAssertNil(model.failure, "canSolve 为 false 时 solve() 应直接返回，不设置 failure")
    }

    /// 偶数阶的朝向按钮：转多少次都得还是合法状态，而且还得能求解。
    ///
    /// 这条守的是"整体旋转对偶数阶是合法操作"——判据与求解器都得照单全收。
    func test_rotatingEvenOrderRecognitionKeepsItSolvable() async throws {
        let model = RestoreModel(size: 2)
        model.load(state: Scramble.random(size: 2, length: 11, seed: 9).initialState)
        XCTAssertTrue(model.canRotate)

        for move in [Move.y, .y, .x, .y, .x, .x, .y] {
            model.rotate(by: move)
            XCTAssertEqual(model.state?.legality, .legal, "转完 \(move.notation) 之后状态不合法了")
            XCTAssertEqual(model.filledCount, 24)
        }

        await model.solve()
        let solution = try XCTUnwrap(model.solution,
                                     "转过之后求不出解：\(String(describing: model.failure))")
        XCTAssertEqual(model.solvedState?.applying(solution.algorithm), .solved(size: 2))
    }

    /// 三阶不给这个按钮，调了也是空操作——中心块锚定朝向，整体旋转会让状态脱离面位记法
    func test_rotatingIsANoOpOnThreeByThree() {
        let model = RestoreModel(size: 3)
        model.load(state: Scramble.random(size: 3, length: 20, seed: 3).initialState)
        XCTAssertFalse(model.canRotate)
        let before = model.state
        model.rotate(by: .y)
        XCTAssertEqual(model.state, before, "三阶不该被整体旋转")
    }

    /// 没填满就没有"状态"可转，按钮也不该出现
    func test_rotatingRequiresACompleteGrid() {
        let model = RestoreModel(size: 2)
        XCTAssertFalse(model.canRotate, "空网格不该给转向按钮")
        model.load(state: .solved(size: 2))
        XCTAssertTrue(model.canRotate)
    }

    /// 录入页的展开图几何也要跟着阶数走
    func test_entryNetLayoutFollowsSize() {
        for size in [2, 3, 4] {
            let layout = CubeNetLayout(in: CGSize(width: 360, height: 270), faceSize: size)
            XCTAssertEqual(layout.faceSize, size)
            XCTAssertEqual(layout.netSize.width, layout.cellSize * CGFloat(4 * size), accuracy: 1e-9)
            XCTAssertEqual(layout.netSize.height, layout.cellSize * CGFloat(3 * size), accuracy: 1e-9)
            // 每面 N×N 格都能点到，且行列为 0..<N
            for face in Face.allCases {
                let rect = layout.faceRect(face)
                let hit = layout.sticker(at: CGPoint(x: rect.midX, y: rect.midY))
                XCTAssertEqual(hit?.face, face)
                XCTAssertTrue((0..<size).contains(hit?.row ?? -1))
                XCTAssertTrue((0..<size).contains(hit?.col ?? -1))
            }
        }
    }
}
