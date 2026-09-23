import XCTest
import SwiftUI
import RealityKit
@testable import iCube
import CubeKit
import CubeSolve

@MainActor
final class CubeSceneTests: XCTestCase {

    private let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    func test_visibleCubieCentersAreTheVisible26() {
        let centers = CubeScene.visibleCubieCenters()
        XCTAssertEqual(centers.count, 26)
        XCTAssertEqual(Set(centers).count, 26)
        XCTAssertFalse(centers.contains(V3(0, 0, 0)), "看不见的核心块不应渲染")
    }

    func test_sceneBuilds54HitTestableStickers() {
        let scene = CubeScene(state: .solved)
        let stickers = scene.root.children.flatMap(\.children).filter { $0.components[InputTargetComponent.self] != nil }
        XCTAssertEqual(stickers.count, 54, "应挂出 54 片可命中贴纸")
        XCTAssertEqual(Set(scene.stickerPoses.map(\.buildSlot)), Set(0..<54))
    }

    /// 正视前方、沿屏幕右拖中间列：转的是 y 轴中层
    func test_dragRightOnFrontMiddleColumnTurnsSlice() throws {
        let scene = CubeScene(state: .solved)
        let index = try XCTUnwrap(scene.cubieIndex(at: V3(0, 0, 2)))
        let plan = try XCTUnwrap(scene.planDrag(hit: .init(cubieIndex: index, localNormal: .posZ),
                                               drag: CGSize(width: 60, height: 0),
                                               rootOrientation: identity))
        XCTAssertEqual(plan.axis, .y)
        XCTAssertEqual(plan.signedAxis, .posY)
        XCTAssertEqual(plan.cubieIndices.count, 8, "y 轴中层 9 格里有一格是看不见的核心，只渲染 8 个块")
        XCTAssertEqual(try XCTUnwrap(scene.move(for: plan, angle: .pi / 2)).kind, .slice(.e))
    }

    /// 顶排往右拖 = U'（U 顺时针会把顶排推向左）
    func test_dragRightOnTopRowIsUPrime() throws {
        let scene = CubeScene(state: .solved)
        let index = try XCTUnwrap(scene.cubieIndex(at: V3(0, 2, 2)))
        let plan = try XCTUnwrap(scene.planDrag(hit: .init(cubieIndex: index, localNormal: .posZ),
                                               drag: CGSize(width: 60, height: 0),
                                               rootOrientation: identity))
        XCTAssertEqual(plan.axis, .y)
        let move = try XCTUnwrap(scene.move(for: plan, angle: .pi / 2))
        XCTAssertEqual(move, .uPrime)
    }

    /// 正面竖直上拖：绕 x 轴，抓的是 x 中层（M）
    func test_dragUpOnFrontFaceTurnsVerticalSlice() throws {
        let scene = CubeScene(state: .solved)
        let index = try XCTUnwrap(scene.cubieIndex(at: V3(0, -2, 2)))
        let plan = try XCTUnwrap(scene.planDrag(hit: .init(cubieIndex: index, localNormal: .posZ),
                                               drag: CGSize(width: 0, height: -60),
                                               rootOrientation: identity))
        XCTAssertEqual(plan.axis, .x)
        let move = try XCTUnwrap(scene.move(for: plan, angle: .pi / 2))
        XCTAssertEqual(move.kind, .slice(.m))
    }

    func test_shortDragIsIgnoredAndReversedDragIsNegative() throws {
        let scene = CubeScene(state: .solved)
        let plan = CubeScene.TurnPlan(axis: .y, signedAxis: .posY, screenSlide: SIMD2<Float>(1, 0),
                                      cubieIndices: [], referenceCenter: .zero)
        scene.pixelsPerQuarterTurn = 100
        let front = try XCTUnwrap(scene.cubieIndex(at: V3(0, 0, 2)))
        XCTAssertNil(scene.planDrag(hit: .init(cubieIndex: front, localNormal: .posZ),
                                    drag: CGSize(width: 2, height: 0),
                                    rootOrientation: identity), "低于阈值不应起转")
        XCTAssertEqual(scene.angle(for: plan, drag: CGSize(width: 100, height: 0)), Float.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(scene.angle(for: plan, drag: CGSize(width: -50, height: 0)), -Float.pi / 4, accuracy: 0.0001)
        XCTAssertEqual(scene.snappedQuarters(Float.pi / 2 * 1.4), 1)
        XCTAssertEqual(scene.snappedQuarters(Float.pi / 2 * 1.6), 2)
        XCTAssertEqual(scene.snappedQuarters(-Float.pi / 2 * 2.6), -3)
        XCTAssertNil(scene.move(for: plan, angle: 0.2), "没到半格不该产出记法")
    }

    /// 核心不变量：动画烘焙后的画面，必须和 CubeState 逐槽位一致
    func test_bakedPosesMatchLogicalState() async {
        let scene = CubeScene(state: .solved)
        var state = CubeState.solved
        let solvedColors = CubeState.solved.stickers
        for move in Algorithm.parse("R U R' F D2 L' M U2 x' R' F' U")!.moves {
            await scene.play(move, duration: 0.01)
            state.apply(move)
            XCTAssertEqual(scene.stickerPoses.count, 54)
            for pose in scene.stickerPoses {
                XCTAssertEqual(solvedColors[pose.buildSlot], state.stickers[pose.currentSlot],
                               "\(move.notation) 之后槽位 \(pose.currentSlot) 的画面与状态不一致")
            }
        }
        XCTAssertFalse(state.isSolved)
    }

    /// 还原步骤页的真实链路：**从打乱态起步**、播求解器给的解，画面必须回到还原态。
    ///
    /// `test_bakedPosesMatchLogicalState` 是从还原态起步、用一条固定公式验证的，
    /// 它盖不住这条——两者的差别不只是起始状态：这里的解是外部求解器给的，
    /// 而且要经过录入页"状态 → 54 格填色 → 状态"的往返。
    func test_playingSolutionFromScrambledStateEndsSolved() async throws {
        for seed in 0..<5 {
            let entered = Scramble.random(length: 20, seed: UInt64(seed)).initialState

            // 录入页的往返：状态 → 54 格填色 → 状态。拍照识别拿到的状态就是走这条路进模型的。
            let model = RestoreModel()
            model.load(state: entered)
            let roundTripped = try XCTUnwrap(model.state)
            XCTAssertEqual(roundTripped, entered, "seed \(seed)：录入页的状态往返改变了状态")

            let solution = try CubeSolve.solve(roundTripped)

            let scene = CubeScene(state: roundTripped)
            var logical = roundTripped
            for move in solution.algorithm.moves {
                await scene.play(move, duration: 0.01)
                logical.apply(move)
            }
            XCTAssertTrue(logical.isSolved, "seed \(seed)：解没把逻辑状态还原")

            // 画面按"建场景时的颜色 + 此刻所在槽位"对账：播完解应当逐片落回还原态
            let solvedColors = CubeState.solved.stickers
            for pose in scene.stickerPoses {
                XCTAssertEqual(
                    roundTripped.stickers[pose.buildSlot], solvedColors[pose.currentSlot],
                    "seed \(seed)：槽位 \(pose.currentSlot) 的画面不是还原色"
                )
            }
        }
    }

    /// 重建必须抹掉之前烘焙的位姿：每片贴纸回到自己的槽位
    func test_rebuildResetsPoses() async {
        let scene = CubeScene(state: .solved)
        for move in Algorithm.parse("R U F' D2")!.moves {
            await scene.play(move, duration: 0.01)
        }
        XCTAssert(scene.stickerPoses.contains { $0.buildSlot != $0.currentSlot }, "转过后位姿应已偏移")

        scene.rebuild(state: Scramble.random(length: 12, seed: 4).initialState)
        XCTAssertEqual(scene.stickerPoses.count, 54)
        for pose in scene.stickerPoses {
            XCTAssertEqual(pose.buildSlot, pose.currentSlot, "重建后贴纸应回到原槽位")
        }
    }

    /// 上屏的是**实体变换**，不是 `node.rotation`。
    ///
    /// 上面两条对账测试都只比对 `stickerPoses`（逻辑量），证明的是"逻辑上该转的都转了"，
    /// 证明不了"屏幕上的就是它"。这条从 `container.position/orientation` 加贴纸局部偏移
    /// 反推槽位，逐片比颜色。
    ///
    /// **关键是要在打乱态就对账**：还原态每面同色，`build` 就算按错槽位取色也看不出来；
    /// 只有打乱态才能同时钉住两件事——`state.color(at:facing:)` 的取色与
    /// `StickerGeometry.index` 的几何是同一套映射，且上屏的贴纸确实落在那个槽位。
    func test_renderedTransformsMatchLogicalState() async throws {
        for seed in 0..<3 {
            let entered = Scramble.random(length: 20, seed: UInt64(seed) + 100).initialState
            let solution = try CubeSolve.solve(entered)
            let scene = CubeScene(state: entered)

            // 打乱态：画面必须逐槽位等于状态
            try assertRendered(scene, equals: entered, label: "seed \(seed) 打乱态")

            for move in solution.algorithm.moves {
                await scene.play(move, duration: 0.01)
            }

            // 还原态：同样逐槽位对账，并顺带证明画面合法（每色恰好 9 片）
            try assertRendered(scene, equals: .solved, label: "seed \(seed) 播完解")
        }
    }

    private func assertRendered(_ scene: CubeScene, equals state: CubeState, label: String,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let rendered = scene.renderedStickerSlots()
        XCTAssertEqual(rendered.count, 54, "\(label)：渲染出来的贴纸不是 54 片", file: file, line: line)

        var counts: [CubeColor: Int] = [:]
        for (color, slot) in rendered {
            XCTAssertEqual(color, state.stickers[slot],
                           "\(label)：渲染槽位 \(slot) 的贴纸颜色是 \(color)，状态里是 \(state.stickers[slot])",
                           file: file, line: line)
            counts[color, default: 0] += 1
        }
        for color in CubeColor.allCases {
            XCTAssertEqual(counts[color], 9,
                           "\(label)：画面里 \(color) 不是 9 片，画面处于非法配色", file: file, line: line)
        }
    }

    /// 演示中途按「停止」时，场景可能已经把当前这一步转完了，而逻辑态那次 `state.apply`
    /// 会被 `Task.isCancelled` 跳过去——两者就此错开一步。页脚的「已还原」、重置按钮、
    /// 步骤高亮全部跟着错。这条钉住"场景与状态永不脱节"。
    func test_stopDuringDemoDoesNotLeaveSceneAheadOfState() async throws {
        let entered = Scramble.random(length: 20, seed: 2024).initialState
        let solution = try CubeSolve.solve(entered)
        let model = CubeDemoModel(state: entered)
        model.speed = .slow                                  // 0.5s/步，让停止落在一步中间

        model.play(solution.algorithm)
        try await Task.sleep(nanoseconds: 120_000_000)       // 第一步转到一半
        model.stop()
        try await Task.sleep(nanoseconds: 700_000_000)       // 等场景把在飞那一步落定

        for (color, slot) in model.scene.renderedStickerSlots() {
            XCTAssertEqual(color, model.state.stickers[slot],
                           "停止后场景与状态脱节：槽位 \(slot) 的画面与状态不符")
        }
    }

    /// 演示播到一半按「重置」：场景被重建回录入状态，在飞那一步的烘焙会被世代号作废。
    /// 逻辑态若还把这一步 `apply` 上去，状态就跑到场景前头——重置按钮的可用态、
    /// 页脚的「已还原」、以及下一次「演示还原」的起点全跟着错。
    func test_resetDuringDemoDoesNotLeaveStateAheadOfScene() async throws {
        let entered = Scramble.random(length: 20, seed: 303).initialState
        let solution = try CubeSolve.solve(entered)
        let model = CubeDemoModel(state: entered)
        model.speed = .slow                                  // 0.5s/步，让重置落在一步中间

        model.play(solution.algorithm)
        try await Task.sleep(nanoseconds: 120_000_000)
        model.load(state: entered)                           // 「重置」
        try await Task.sleep(nanoseconds: 700_000_000)       // 等场景把在飞那一步作废

        XCTAssertEqual(model.state, entered, "重置后逻辑态必须回到录入状态")
        for (color, slot) in model.scene.renderedStickerSlots() {
            XCTAssertEqual(color, model.state.stickers[slot],
                           "重置后场景与状态脱节：槽位 \(slot) 的画面与状态不符")
        }
    }
}
