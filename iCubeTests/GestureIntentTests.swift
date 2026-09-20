import XCTest
import RealityKit
@testable import iCube
import CubeKit

@MainActor
final class GestureIntentTests: XCTestCase {

    private let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    private func makeScene() -> CubeScene {
        CubeScene(state: .solved)
    }

    /// 起拖第一帧位移恒为 0，此时必须保持 undecided。
    /// 早先在这里被判成 orbit，导致"单排永远转不动、怎么拖都在转整体"。
    func test_zeroDragOnStickerStaysUndecided() {
        let scene = makeScene()
        let front = scene.cubieIndex(at: V3(0, 0, 2))!
        let intent = scene.resolveIntent(hit: .init(cubieIndex: front, localNormal: .posZ),
                                        drag: .zero,
                                        rootOrientation: identity)
        XCTAssertEqual(intent, .undecided)
    }

    func test_dragOnStickerResolvesToTurn() {
        let scene = makeScene()
        let front = scene.cubieIndex(at: V3(0, 2, 2))!
        let intent = scene.resolveIntent(hit: .init(cubieIndex: front, localNormal: .posZ),
                                         drag: CGSize(width: 60, height: 0),
                                         rootOrientation: identity)
        guard case .turn(let plan) = intent else { return XCTFail("应判为转层，实际 \(intent)") }
        XCTAssertEqual(plan.axis, .y)
    }

    func test_noHitIsOrbit() {
        let scene = makeScene()
        XCTAssertEqual(scene.resolveIntent(hit: nil, drag: CGSize(width: 40, height: 10), rootOrientation: identity),
                       .orbit)
    }

    /// 在顶面上竖直拖：该面的两个面内方向里只有一个投得上屏幕，转不了任何层，
    /// 拖久了应退化成转视角而不是卡死
    func test_unresolvableLongDragFallsBackToOrbit() {
        let scene = makeScene()
        let top = scene.cubieIndex(at: V3(0, 2, 0))!
        let short = scene.resolveIntent(hit: .init(cubieIndex: top, localNormal: .posY),
                                        drag: CGSize(width: 0, height: -12),
                                        rootOrientation: identity)
        XCTAssertEqual(short, .undecided, "位移还不够大时先别动")
        let long = scene.resolveIntent(hit: .init(cubieIndex: top, localNormal: .posY),
                                       drag: CGSize(width: 0, height: -120),
                                       rootOrientation: identity)
        XCTAssertEqual(long, .orbit)
    }

    // MARK: - 多指

    func test_disjointLayersCanTurnTogether() {
        let scene = makeScene()
        let top = scene.cubieIndex(at: V3(0, 2, 2))!
        let bottom = scene.cubieIndex(at: V3(0, -2, 2))!
        guard case .turn(let upPlan) = scene.resolveIntent(hit: .init(cubieIndex: top, localNormal: .posZ),
                                                          drag: CGSize(width: 60, height: 0),
                                                          rootOrientation: identity),
              case .turn(let downPlan) = scene.resolveIntent(hit: .init(cubieIndex: bottom, localNormal: .posZ),
                                                             drag: CGSize(width: -60, height: 0),
                                                             rootOrientation: identity) else {
            return XCTFail("上下两排都应能起转")
        }
        XCTAssertFalse(Set(upPlan.cubieIndices).intersection(downPlan.cubieIndices).isEmpty == false,
                       "U 层与 D 层不该共用块")
        let first = scene.beginDrag(upPlan)
        XCTAssertNotNil(first)
        XCTAssertTrue(scene.canBegin(downPlan), "不相交的层应允许第二根手指同时转")
        XCTAssertNotNil(scene.beginDrag(downPlan))
        XCTAssertEqual(scene.activeTurnCount, 2)
    }

    func test_overlappingLayerIsRejectedWhileTurnIsActive() {
        let scene = makeScene()
        let topFront = scene.cubieIndex(at: V3(0, 2, 2))!
        let topRight = scene.cubieIndex(at: V3(2, 2, 2))!
        guard case .turn(let firstPlan) = scene.resolveIntent(hit: .init(cubieIndex: topFront, localNormal: .posZ),
                                                              drag: CGSize(width: 60, height: 0),
                                                              rootOrientation: identity),
              case .turn(let secondPlan) = scene.resolveIntent(hit: .init(cubieIndex: topRight, localNormal: .posX),
                                                               drag: CGSize(width: 0, height: 60),
                                                               rootOrientation: identity) else {
            return XCTFail("两根手指都应能解算出转动")
        }
        XCTAssertNotNil(scene.beginDrag(firstPlan))
        XCTAssertFalse(scene.canBegin(secondPlan), "共用块的层不能同时转")
        XCTAssertNil(scene.beginDrag(secondPlan))
    }

    /// 两根手指各转不相交的层，最终状态应等于按顺序分别施加两步
    func test_twoConcurrentTurnsCommitBothMoves() {
        let scene = makeScene()
        let top = scene.cubieIndex(at: V3(0, 2, 2))!
        let bottom = scene.cubieIndex(at: V3(0, -2, 2))!
        guard case .turn(let upPlan) = scene.resolveIntent(hit: .init(cubieIndex: top, localNormal: .posZ),
                                                          drag: CGSize(width: 120, height: 0),
                                                          rootOrientation: identity),
              case .turn(let downPlan) = scene.resolveIntent(hit: .init(cubieIndex: bottom, localNormal: .posZ),
                                                             drag: CGSize(width: -120, height: 0),
                                                             rootOrientation: identity) else {
            return XCTFail("应能解算出两个转动")
        }
        let up = scene.beginDrag(upPlan)!
        let down = scene.beginDrag(downPlan)!

        var committed: [Move] = []
        let expectation = expectation(description: "两次提交")
        expectation.expectedFulfillmentCount = 2
        scene.endDrag(handle: up, angle: .pi / 2) { move in
            if let move { committed.append(move) }
            expectation.fulfill()
        }
        scene.endDrag(handle: down, angle: .pi / 2) { move in
            if let move { committed.append(move) }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(committed.count, 2)
        var expected = CubeState.solved
        for move in committed { expected.apply(move) }
        for pose in scene.stickerPoses {
            XCTAssertEqual(CubeState.solved.stickers[pose.buildSlot], expected.stickers[pose.currentSlot],
                           "双指提交后画面与状态不一致")
        }
    }

    func test_scriptedPlaybackBlocksUserInput() {
        let scene = makeScene()
        let top = scene.cubieIndex(at: V3(0, 2, 2))!
        guard case .turn(let plan) = scene.resolveIntent(hit: .init(cubieIndex: top, localNormal: .posZ),
                                                         drag: CGSize(width: 60, height: 0),
                                                         rootOrientation: identity) else {
            return XCTFail("应能解算出转动")
        }
        scene.play(.r, duration: 0.2) {}
        XCTAssertTrue(scene.isPlayingScript)
        XCTAssertFalse(scene.canBegin(plan), "打乱动画播放中不接受手势")
    }
}


@MainActor
final class OrbitDirectionTests: XCTestCase {

    /// 右拖：正面（朝相机 = +Z）应被推向屏幕右 = +X，即表面跟手指
    func test_horizontalDragMovesFrontFaceRight() {
        let delta = CubeScene.orbitDelta(step: CGSize(width: 40, height: 0), pixelsPerRadian: 190)
        let moved = delta.act(SIMD3<Float>(0, 0, 1))
        XCTAssertGreaterThan(moved.x, 0, "右拖应把正面推向屏幕右")
        XCTAssertEqual(moved.y, 0, accuracy: 0.001)
    }

    /// 下拖：正面应被推向屏幕下（屏幕 y 向下 = 世界 -Y）
    func test_verticalDragMovesFrontFaceDown() {
        let delta = CubeScene.orbitDelta(step: CGSize(width: 0, height: 40), pixelsPerRadian: 190)
        let moved = delta.act(SIMD3<Float>(0, 0, 1))
        XCTAssertLessThan(moved.y, 0, "下拖应把正面推向屏幕下")
        XCTAssertEqual(moved.x, 0, accuracy: 0.001)
    }

    /// 累积旋转不设上限：连拖 200 次仍能继续转（早先 pitch 被夹在 ±77° 会卡住）
    func test_orbitNeverSaturates() {
        var orientation = CubeScene.defaultOrbit
        let step = CGSize(width: 20, height: 20)
        for _ in 0..<200 {
            orientation = CubeScene.orbitDelta(step: step, pixelsPerRadian: 190) * orientation
        }
        let front = orientation.act(SIMD3<Float>(0, 0, 1))
        let before = CubeScene.defaultOrbit.act(SIMD3<Float>(0, 0, 1))
        XCTAssertNotEqual(front.x, before.x, accuracy: 0.001, "累计 200 步后姿态应已明显改变")
        XCTAssertEqual(simd_length(orientation), 1, accuracy: 0.001, "四元数应保持单位长度")
    }
}

@MainActor
final class HitDisambiguationTests: XCTestCase {

    private let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    /// 右前上角同时有正面与右面贴纸，屏幕上是挨着的：必须认"朝向相机的那一面"，
    /// 否则在右列竖直拖会被解算成该面自转（用户报的误识别）。
    func test_prefersStickerFacingTheCamera() {
        let scene = CubeScene(state: .solved)
        let corner = scene.cubieIndex(at: V3(2, 2, 2))!
        let candidates: [(cubie: Int, localNormal: V3, buildSlot: Int)] = [
            (corner, .posX, 0),      // 右面
            (corner, .posZ, 1),      // 正面
        ]

        let straightOn = scene.preferredHit(candidates, rootOrientation: identity)
        XCTAssertEqual(straightOn, CubeScene.Hit(cubieIndex: corner, localNormal: .posZ), "正视时应认正面")

        let defaultPose = scene.preferredHit(candidates, rootOrientation: CubeScene.defaultOrbit)
        XCTAssertEqual(defaultPose?.localNormal, .posZ, "默认 3/4 视角下仍应认正面")

        // 把魔方 yaw 到右面朝向相机，判定必须跟着换边
        let turned = simd_quatf(angle: -1.2, axis: [0, 1, 0])
        let afterTurn = scene.preferredHit(candidates, rootOrientation: turned)
        XCTAssertEqual(afterTurn?.localNormal, .posX, "右面转向相机后应认右面")
    }

    func test_noCandidatesMeansNoHit() {
        let scene = CubeScene(state: .solved)
        XCTAssertNil(scene.preferredHit([], rootOrientation: identity))
    }

    /// 射线穿透魔方时会顺带命中背面的贴纸（worldNormalZ < 0），
    /// 这些候选绝不能当成用户摸到的那一面；全是背面候选时应当视为没摸到
    func test_allBackFacingCandidatesYieldNoHit() {
        let scene = CubeScene(state: .solved)
        let back = scene.cubieIndex(at: V3(0, 0, -2))!
        XCTAssertNil(scene.preferredHit([(back, .negZ, 0)], rootOrientation: identity),
                     "背向相机的贴纸不该被选中")
        // 混入正面候选时必须挑正面
        let front = scene.cubieIndex(at: V3(0, 0, 2))!
        let mixed = scene.preferredHit([(back, .negZ, 0), (front, .posZ, 1)],
                                       rootOrientation: identity)
        XCTAssertEqual(mixed?.localNormal, .posZ)
    }

    /// 默认 3/4 视角下，顶面与右面在右上棱角处都会被射线扫到：
    /// 暴露面积更大（更朝相机）的那面优先——这正是"摸到魔方上优先转到
    /// 暴露最大的那面、手势在某一列就转某一列"的判定基础
    func test_cornerCandidatesPreferMostExposedFace() {
        let scene = CubeScene(state: .solved)
        let corner = scene.cubieIndex(at: V3(2, 2, 2))!
        let candidates: [(cubie: Int, localNormal: V3, buildSlot: Int)] = [
            (corner, .posY, 0),      // 顶面
            (corner, .posX, 1),      // 右面
        ]
        // 默认视角下 R 面比 U 面更朝向相机（暴露面积更大）
        let hit = scene.preferredHit(candidates, rootOrientation: CubeScene.defaultOrbit)
        XCTAssertEqual(hit?.localNormal, .posX, "棱角歧义时应认暴露面积更大的面")
    }
}

@MainActor
final class ConsecutiveTurnTests: XCTestCase {

    private let identity = simd_quatf(angle: 0, axis: [0, 1, 0])

    /// 等过吸附窗口：那段时间同一层被占用，新拖拽会保持 undecided
    private func waitForSettle() {
        let settled = expectation(description: "settle")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2)
    }

    /// 顶排正中那片当前朝前的贴纸，横拖应解算成绕 y 轴转顶排
    private func topRowPlan(_ scene: CubeScene, file: StaticString = #filePath, line: UInt = #line) -> CubeScene.TurnPlan? {
        guard let hit = scene.hitOfSticker(facing: .posZ, at: V3(0, 2, 2)) else {
            XCTFail("找不到顶排朝前的贴纸", file: file, line: line)
            return nil
        }
        guard case .turn(let plan) = scene.resolveIntent(hit: hit,
                                                         drag: CGSize(width: 60, height: 0),
                                                         rootOrientation: identity) else {
            XCTFail("顶排横拖应解算成转层", file: file, line: line)
            return nil
        }
        return plan
    }

    /// 上一次转动还在吸附动画里时，同一层的新拖拽应保持 undecided，
    /// 不能退化成转视角——那正是"偶尔整个魔方跟着转"的来源
    func test_busyLayerStaysUndecidedInsteadOfOrbit() {
        let scene = CubeScene(state: .solved)
        guard let plan = topRowPlan(scene) else { return }
        let handle = try? XCTUnwrap(scene.beginDrag(plan))
        XCTAssertNotNil(handle)
        guard let hit = scene.hitOfSticker(facing: .posZ, at: V3(0, 2, 2)) else { return XCTFail("找不到顶排朝前的贴纸") }
        let bigDrag = CGSize(width: 300, height: 0)
        XCTAssertEqual(scene.resolveIntent(hit: hit, drag: bigDrag, rootOrientation: identity), .undecided,
                       "该层正被占用，既不该起转也不该退化成转视角")

        scene.endDrag(handle: handle!, angle: 0) { move in
            XCTAssertNil(move, "没到半格不该提交转动")
        }
        waitForSettle()
        XCTAssertEqual(scene.resolveIntent(hit: hit, drag: bigDrag, rootOrientation: identity), .turn(plan),
                       "释放后同一拖拽应能正常起转")
    }

    /// 松手后整数位姿必须立刻提交：不等动画跑完，下一次解算就得用新位姿
    func test_releaseBakesImmediately() {
        let scene = CubeScene(state: .solved)
        guard let plan = topRowPlan(scene) else { return }
        let handle = scene.beginDrag(plan)!
        var committed: Move?
        scene.endDrag(handle: handle, angle: .pi / 2) { committed = $0 }
        let move = try? XCTUnwrap(committed)
        XCTAssertNotNil(committed, "松手即应给出记法")

        var expected = CubeState.solved
        if let committed { expected.apply(committed) }
        XCTAssertFalse(expected.isSolved, "U' 之后不该还是还原态")
        for pose in scene.stickerPoses {
            XCTAssertEqual(CubeState.solved.stickers[pose.buildSlot], expected.stickers[pose.currentSlot],
                           "动画还没跑完就应该已经提交")
        }
    }

    /// 连续快速同向转动：每次都必须在同一层上生效，且画面与状态始终一致
    func test_repeatedFastTurnsStayOnLayer() {
        let scene = CubeScene(state: .solved)
        var state = CubeState.solved
        // 同一层连转 4 次必须回到原样：只要有一次算错了层或方向，这里就对不上
        for turn in 1...4 {
            guard let plan = topRowPlan(scene) else { return }
            let handle = scene.beginDrag(plan)!
            var committed: Move?
            scene.endDrag(handle: handle, angle: .pi / 2) { committed = $0 }
            XCTAssertEqual(committed?.notation, "U'", "第 \(turn) 次连转的记法应稳定")
            if let committed { state.apply(committed) }
            waitForSettle()
            for pose in scene.stickerPoses {
                XCTAssertEqual(CubeState.solved.stickers[pose.buildSlot], state.stickers[pose.currentSlot],
                               "连转第 \(turn) 次后画面与状态脱节")
            }
        }
        XCTAssertEqual(state, .solved, "同一层连转 4 次应回到原样")
    }
}
