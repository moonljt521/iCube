import XCTest
import SwiftUI
import RealityKit
@testable import iCube
import CubeKit

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
}
