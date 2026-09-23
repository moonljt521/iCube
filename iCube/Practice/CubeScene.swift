import Foundation
import SwiftUI
import RealityKit
import CubeKit

/// 场景引擎：持有 26 个块实体，把手势或队列里的转动"演出来再提交"。
/// 逻辑状态仍由 CubeKit 持有；这里只维护表现层的整数块位姿，
/// 保证动画结束时的画面与 `CubeState` 严格一致（等价性由 RotationTests 钉住）。
/// 支持多指：允许同时进行多个转动，只要它们不共用块（例如同面左右两列对拨）。
@MainActor
final class CubeScene {

    /// 拖拽解算结果：绕 signedAxis 转 center 所在的那一层
    struct TurnPlan: Hashable {
        let axis: CubeAxis
        /// 右手正方向：角度 > 0 即沿手指滑动方向
        let signedAxis: V3
        /// 已归一化的屏幕滑动方向
        let screenSlide: SIMD2<Float>
        let cubieIndices: [Int]
        let referenceCenter: V3
    }

    struct Hit: Equatable {
        let cubieIndex: Int
        let localNormal: V3
    }

    /// 一根手指当前在干什么。位移太短时保持 undecided，别急着判成转视角
    enum DragIntent: Equatable {
        case undecided
        case turn(TurnPlan)
        case orbit
    }

    struct TurnHandle: Hashable {
        let id: Int
    }

    private final class CubieNode {
        let container: Entity
        var center: V3
        var rotation: Rotation
        init(container: Entity, center: V3) {
            self.container = container
            self.center = center
            self.rotation = .identity
        }
    }

    /// 进行中的一层转动（拖拽与脚本播放共用）
    ///
    /// 显式标 `@MainActor`：嵌套类型**不继承**外层类型的 actor 隔离，而这里的
    /// `pivot` 要在属性初始化时构造 `Entity()`，那个构造器是主 actor 隔离的。
    /// 不标的话编译期会报 "call to main actor-isolated initializer 'init()'
    /// in a synchronous nonisolated context"——运行时没事（这个类只在
    /// `CubeScene` 内部用，而 `CubeScene` 是 `@MainActor`），但警告一直在。
    @MainActor
    private final class ActiveTurn {
        let axis: CubeAxis
        let signedAxis: V3
        /// 一个"正方向 90°"对应的 quarterTurns：+轴为 1，-轴为 3
        let perQuarter: Int
        let cubieIndices: [Int]
        let pivot = Entity()
        init(axis: CubeAxis, signedAxis: V3, perQuarter: Int, cubieIndices: [Int]) {
            self.axis = axis
            self.signedAxis = signedAxis
            self.perQuarter = perQuarter
            self.cubieIndices = cubieIndices
        }

        var axisVector: SIMD3<Float> { CubeScene.vector(signedAxis) }

        /// 转 n 个 90° 后的整数姿态
        func rotation(quarters n: Int) -> Rotation {
            Rotation(axis: axis, quarterTurns: ((n * perQuarter) % 4 + 4) % 4)
        }
    }

    let root = Entity()

    /// 脚本播放中（打乱、演示）：不接受用户输入
    private(set) var isPlayingScript = false

    /// 阶数（2/3/4）。由初始状态反推，重建时必须一致（网格与碰撞体按本阶尺寸生成）
    let size: Int

    /// 每块边长：总宽恒为 3 倍基准，多阶时单块缩小以保持整体尺寸不变
    let cubieSide: Float
    private var unit: Float { cubieSide / 2 }
    /// 贴纸边长占块边的比例：网格与碰撞体共用，避免两者尺寸各自漂移
    private static let stickerRatio: Float = 0.84


    /// 拖多远算转过 90°
    var pixelsPerQuarterTurn: CGFloat = 110
    /// 起拖阈值（点）：低于此值判不出层面方向
    var dragThreshold: CGFloat = 8
    /// 位移超过这个值仍判不出转动，就退化成转视角
    var orbitFallbackDistance: CGFloat = 26

    private var cubies: [CubieNode] = []
    private var owners: [ObjectIdentifier: (cubie: Int, localNormal: V3, buildSlot: Int)] = [:]
    /// 皮肤热切换需要逐实体改材质：贴纸实体 + 各自颜色、本体塑料实体
    private var stickerEntries: [(entity: ModelEntity, color: CubeColor)] = []
    private var bodyEntities: [ModelEntity] = []
    private var turns: [TurnHandle: ActiveTurn] = [:]
    private var nextHandleID = 0
    private var pending: [(move: Move, duration: Double, completion: () -> Void)] = []
    /// 重建场景时自增：让上一代在飞的动画回调作废，不会去烘焙已经换掉的一批块
    private var generation = 0

    private let bodyMesh: MeshResource
    private let stickerMesh: MeshResource
    private let collisionShape: ShapeResource

    init(state: CubeState, cubieSide baseSide: Float = 0.26) {
        self.size = state.size
        self.cubieSide = baseSide * 3 / Float(state.size)
        bodyMesh = MeshResource.generateBox(size: [cubieSide, cubieSide, cubieSide],
                                            cornerRadius: cubieSide * 0.13)
        stickerMesh = MeshResource.generatePlane(width: cubieSide * Self.stickerRatio,
                                                     depth: cubieSide * Self.stickerRatio)
        // 碰撞盒按整格（cubieSide 见方）铺设，盖住贴纸之间的黑色缝隙：
        // 手指落在缝隙或贴纸边缘上也算摸在魔方上，不会漏成“转视角”。
        // 厚度方向与立方体表面齐平、绝不外凸——外凸的碰撞盒在透视下会斜盖到
        // 邻面贴纸上方，“在正面右列边缘竖拖却被解算成整面自转”正是这么来的。
        // （旧实现为了躲开棱边穿插把盒缩到 0.84 见方，代价是缝隙全部漏空，
        //   摸在魔方上也动不动变成整体转，误触反而更多。）
        let slabThickness = cubieSide * 0.06
        let stickerLift = cubieSide / 2 + cubieSide * 0.004   // 贴纸实体悬浮高度
        let slabOuterFace = cubieSide * 0.502                 // 外沿 = 表面 + 0.2%，防与邻面共面
        collisionShape = ShapeResource
            .generateBox(size: [cubieSide, slabThickness, cubieSide])
            .offsetBy(translation: [0, slabOuterFace - slabThickness / 2 - stickerLift, 0])
        build(state: state)
    }

    // MARK: - 搭建

    private func build(state: CubeState) {
        let skin = MaterialCache.current
        for center in Self.visibleCubieCenters(size: size) {
            let container = Entity()
            container.name = "cubie-\(center.x)-\(center.y)-\(center.z)"
            container.position = render(center)
            let body = ModelEntity(mesh: bodyMesh, materials: [MaterialCache.bodyMaterial(for: skin)])
            bodyEntities.append(body)
            container.addChild(body)
            root.addChild(container)
            let index = cubies.count
            cubies.append(CubieNode(container: container, center: center))

            for face in Face.allCases {
                guard let color = state.color(at: center, facing: face.normal),
                      let slot = StickerGeometry.index(cubieCenter: center, facing: face.normal, size: size) else { continue }
                let sticker = ModelEntity(mesh: stickerMesh, materials: [MaterialCache.material(for: color, skin: skin)])
                sticker.position = Self.vector(face.normal) * (unit + cubieSide * 0.004)
                sticker.orientation = simd_quatf(from: [0, 1, 0], to: Self.vector(face.normal))
                sticker.components.set(CollisionComponent(shapes: [collisionShape]))
                sticker.components.set(InputTargetComponent())
                container.addChild(sticker)
                owners[ObjectIdentifier(sticker)] = (index, face.normal, slot)
                stickerEntries.append((sticker, color))
            }
        }
    }

    /// 换肤：只改材质不动结构，所有实体复用缓存里的材质实例
    func applySkin(_ skin: CubeSkin) {
        for entry in stickerEntries {
            entry.entity.model?.materials = [MaterialCache.material(for: entry.color, skin: skin)]
        }
        let body = MaterialCache.bodyMaterial(for: skin)
        for entity in bodyEntities { entity.model?.materials = [body] }
    }

    /// 换状态（开局、重放打乱、求解演示）时整棵重建，80 个实体开销可忽略。
    /// 阶数不同的状态请另建一个 CubeScene（网格与碰撞体尺寸随阶变化）。
    func rebuild(state: CubeState) {
        precondition(state.size == size, "rebuild 不能改变阶数（\(size) → \(state.size)），请新建场景")
        generation += 1
        pending.removeAll()
        for handle in turns.keys { removeTurn(handle) }
        isPlayingScript = false
        for cubie in cubies { cubie.container.removeFromParent() }
        cubies.removeAll()
        owners.removeAll()
        stickerEntries.removeAll()
        bodyEntities.removeAll()
        build(state: state)
    }

    static func visibleCubieCenters(size: Int = 3) -> [V3] {
        let coords = (0..<size).map { 2 * $0 - size + 1 }
        var result: [V3] = []
        for x in coords {
            for y in coords {
                for z in coords {
                    if max(abs(x), abs(y), abs(z)) != size - 1 { continue }  // 只留表面块
                    result.append(V3(x, y, z))
                }
            }
        }
        return result
    }

    // MARK: - 命中与解算

    func hit(at point: CGPoint, in content: RealityViewCameraContent, rootOrientation: simd_quatf) -> Hit? {
        let candidates = content.entities(at: point, in: .local).compactMap { owners[ObjectIdentifier($0)] }
        return preferredHit(candidates, rootOrientation: rootOrientation)
    }

    /// 一个块上相邻两面的贴纸在屏幕上会挨在一起，命中结果可能同时包含它们；
    /// 穿透魔方的射线还会顺带带出背面的贴纸。先剔除背向相机的候选
    /// （worldNormalZ ≤ 0，不可能是用户看着摸的那面），再取本体法向最朝向
    /// 相机的那片——它必然落在暴露面积最大的那一面上，用户点的就是看到的那一面。
    func preferredHit(_ candidates: [(cubie: Int, localNormal: V3, buildSlot: Int)],
                      rootOrientation: simd_quatf) -> Hit? {
        candidates
            .filter { worldNormalZ($0, rootOrientation: rootOrientation) > 0 }
            .max { lhs, rhs in
                worldNormalZ(lhs, rootOrientation: rootOrientation)
                    < worldNormalZ(rhs, rootOrientation: rootOrientation)
            }
            .map { Hit(cubieIndex: $0.cubie, localNormal: $0.localNormal) }
    }

    private func worldNormalZ(_ owner: (cubie: Int, localNormal: V3, buildSlot: Int),
                              rootOrientation: simd_quatf) -> Float {
        let node = cubies[owner.cubie]
        let bodyNormal = node.rotation.applying(to: owner.localNormal)
        return rootOrientation.act(Self.vector(bodyNormal)).z
    }

    /// 本体方向投到屏幕（正交近似：相机固定看向 -Z，物体居中）
    func screenDirection(of bodyDir: V3, rootOrientation: simd_quatf) -> SIMD2<Float> {
        let world = rootOrientation.act(Self.vector(bodyDir))
        let projected = SIMD2<Float>(world.x, -world.y)
        let length = simd_length(projected)
        return length > 0.0001 ? projected / length : .zero
    }

    /// 由命中块与屏幕拖拽向量决定转哪一层、往哪个方向
    func planDrag(hit: Hit, drag: CGSize, rootOrientation: simd_quatf) -> TurnPlan? {
        let node = cubies[hit.cubieIndex]
        let normal = node.rotation.applying(to: hit.localNormal)
        guard let normalAxis = CubeAxis.axis(of: normal) else { return nil }

        let candidates: [V3] = CubeAxis.allCases.filter { $0 != normalAxis }.flatMap { [$0.unit, -$0.unit] }
        var best: (direction: V3, projection: CGFloat)?
        for candidate in candidates {
            let screen = screenDirection(of: candidate, rootOrientation: rootOrientation)
            let projection = CGFloat(Float(drag.width) * screen.x + Float(drag.height) * screen.y)
            if best == nil || abs(projection) > abs(best!.projection) {
                best = (candidate, projection)
            }
        }
        guard let slide = best?.direction, abs(best!.projection) > dragThreshold else { return nil }
        let orientedSlide = best!.projection < 0 ? -slide : slide

        let stickerCenter = node.center + normal
        var signedAxis = normal.cross(orientedSlide)
        guard let axis = CubeAxis.axis(of: signedAxis) else { return nil }
        // 让"正角度"对应手指方向：v = ω × p
        if signedAxis.cross(stickerCenter).dot(orientedSlide) < 0 { signedAxis = -signedAxis }

        let layerProjection = node.center.dot(signedAxis)
        let indices = cubies.indices.filter { cubies[$0].center.dot(signedAxis) == layerProjection }
        guard !indices.isEmpty else { return nil }

        return TurnPlan(axis: axis,
                        signedAxis: signedAxis,
                        screenSlide: screenDirection(of: orientedSlide, rootOrientation: rootOrientation),
                        cubieIndices: indices,
                        referenceCenter: node.center)
    }

    /// 单根手指的意图：没命中贴纸就是转视角；命中了但位移太短就再等等。
    /// 之前是"首帧判不出来就永久转视角"，而 minimumDistance 0 的首帧位移恒为 0，
    /// 结果单排永远转不动——保持 undecided 才对。
    func resolveIntent(hit: Hit?, drag: CGSize, rootOrientation: simd_quatf) -> DragIntent {
        guard let hit else { return .orbit }
        guard let plan = planDrag(hit: hit, drag: drag, rootOrientation: rootOrientation) else {
            return hypot(drag.width, drag.height) > orbitFallbackDistance ? .orbit : .undecided
        }
        // 该层还在吸附中：保持 undecided 等下一帧，绝不能退化成转视角
        return canBegin(plan) ? .turn(plan) : .undecided
    }

    /// 多指并发规则：两层共用任何块就不能同时转（同面左右两列这类平行层可以）
    func canBegin(_ plan: TurnPlan) -> Bool {
        guard !isPlayingScript else { return false }
        let claimed = Set(turns.values.flatMap(\.cubieIndices))
        return plan.cubieIndices.allSatisfy { !claimed.contains($0) }
    }

    /// 拖拽对应的瞬时角度（弧度，可正可负）
    func angle(for plan: TurnPlan, drag: CGSize) -> Float {
        let along = Float(drag.width) * plan.screenSlide.x + Float(drag.height) * plan.screenSlide.y
        return along / Float(pixelsPerQuarterTurn) * .pi / 2
    }

    /// 该拖拽角度对应的记法；不足一个 90° 返回 nil（弹回）
    func move(for plan: TurnPlan, angle: Float) -> Move? {
        let quarters = snappedQuarters(angle)
        guard quarters != 0 else { return nil }
        let perQuarter = plan.signedAxis == plan.axis.unit ? 1 : 3
        return Move.layerTurn(axis: plan.axis,
                              rotation: Rotation(axis: plan.axis,
                                                 quarterTurns: ((quarters * perQuarter) % 4 + 4) % 4),
                              affecting: plan.referenceCenter,
                              size: size)
    }

    func snappedQuarters(_ angle: Float) -> Int {
        max(-3, min(3, Int((angle / (.pi / 2)).rounded())))
    }

    var activeTurnCount: Int { turns.count }

    // MARK: - 跟手转动

    /// 开始跟手：把该层的块挂到临时支点上。层被占用或脚本在播时返回 nil
    func beginDrag(_ plan: TurnPlan) -> TurnHandle? {
        guard canBegin(plan) else { return nil }
        return startTurn(ActiveTurn(axis: plan.axis,
                                    signedAxis: plan.signedAxis,
                                    perQuarter: plan.signedAxis == plan.axis.unit ? 1 : 3,
                                    cubieIndices: plan.cubieIndices))
    }

    func updateDragAngle(_ handle: TurnHandle, _ angle: Float) {
        guard let active = turns[handle] else { return }
        active.pivot.orientation = simd_quatf(angle: angle, axis: active.axisVector)
    }

    /// 松手：吸附到最近的 90°。整数位姿与记法**立刻**提交，动画只管把视觉补完。
    /// 否则下一次落指会打在"画面在动、位姿还没提交"的中间态上，轴向算错。
    func endDrag(handle: TurnHandle, angle: Float, completion: @escaping (Move?) -> Void) {
        guard let active = turns[handle] else { completion(nil); return }
        let quarters = snappedQuarters(angle)

        let committed: Move?
        if quarters == 0 {
            committed = nil
        } else {
            let rotation = active.rotation(quarters: quarters)
            let referenceCenter = active.cubieIndices.first.map { cubies[$0].center }
            bake(active, with: rotation)
            committed = referenceCenter.flatMap {
                Move.layerTurn(axis: active.axis, rotation: rotation, affecting: $0, size: size)
            }
        }

        active.pivot.move(to: Transform(scale: .one,
                                       rotation: simd_quatf(angle: Float(quarters) * .pi / 2, axis: active.axisVector),
                                       translation: .zero),
                          relativeTo: root,
                          duration: 0.12,
                          timingFunction: .easeOut)
        settle(after: 0.12, generation: generation) { [weak self] in
            self?.removeTurn(handle)
        }
        completion(committed)
    }

    func cancelDrag(_ handle: TurnHandle) {
        guard let active = turns[handle] else { return }
        active.pivot.move(to: Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: .zero),
                          relativeTo: root, duration: 0.12, timingFunction: .easeOut)
        settle(after: 0.12, generation: generation) { [weak self] in
            self?.removeTurn(handle)
        }
    }

    // MARK: - 脚本转动（打乱、演示、求解回放）

    func play(_ move: Move, duration: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            play(move, duration: duration) { continuation.resume() }
        }
    }

    /// 忙时排队，保证调用方的"播放即生效"不会与画面脱节
    func play(_ move: Move, duration: Double, completion: @escaping () -> Void) {
        if isPlayingScript || !turns.isEmpty {
            pending.append((move, duration, completion))
            return
        }
        runPlay(move, duration: duration, completion: completion)
    }

    private func runPlay(_ move: Move, duration: Double, completion: @escaping () -> Void) {
        let axis = move.kind.referenceFace.axis
        let indices = cubies.indices.filter { move.affectsLayer(of: cubies[$0].center, size: size) }
        guard !indices.isEmpty else {
            completion()
            drainPending()
            return
        }

        let rotation = Rotation(axis: axis, quarterTurns: move.quarterTurns)
        let active = ActiveTurn(axis: axis, signedAxis: axis.unit, perQuarter: move.quarterTurns, cubieIndices: indices)
        isPlayingScript = true
        guard let handle = startTurn(active) else {
            isPlayingScript = false
            completion()
            return
        }

        active.pivot.move(to: Transform(scale: .one, rotation: rotation.quaternion, translation: .zero),
                          relativeTo: root,
                          duration: duration,
                          timingFunction: .easeInOut)
        settle(after: duration, generation: generation, stale: completion) { [weak self] in
            guard let self else { completion(); return }
            self.bake(active, with: rotation)
            self.removeTurn(handle)
            completion()
            self.drainPending()
        }
    }

    private func drainPending() {
        guard turns.isEmpty, isPlayingScript == false, pending.isEmpty == false else { return }
        let next = pending.removeFirst()
        runPlay(next.move, duration: next.duration, completion: next.completion)
    }

    @discardableResult
    private func startTurn(_ active: ActiveTurn) -> TurnHandle? {
        root.addChild(active.pivot)
        for index in active.cubieIndices {
            active.pivot.addChild(cubies[index].container)
        }
        let handle = TurnHandle(id: nextHandleID)
        nextHandleID += 1
        turns[handle] = active
        return handle
    }

    /// 提交：整数复合块位姿
    private func bake(_ active: ActiveTurn, with rotation: Rotation) {
        for index in active.cubieIndices {
            let node = cubies[index]
            node.center = rotation.applying(to: node.center)
            node.rotation = node.rotation.then(rotation)
        }
    }

    /// 结束一次转动：把块挂回根节点并按整数位姿对齐
    private func removeTurn(_ handle: TurnHandle) {
        guard let active = turns.removeValue(forKey: handle) else { return }
        for index in active.cubieIndices {
            let node = cubies[index]
            root.addChild(node.container)
            node.container.position = render(node.center)
            node.container.orientation = node.rotation.quaternion
        }
        active.pivot.removeFromParent()
        if pending.isEmpty { isPlayingScript = false }
    }

    /// 动画结束后回调；世代号变了就作废（但仍让 await 的调用方解绑，避免悬挂）
    private func settle(after duration: Double, generation expected: Int,
                        stale: (() -> Void)? = nil, _ work: @escaping () -> Void) {
        let nanoseconds = UInt64(max(0.01, duration) * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            guard self.generation == expected else { stale?(); return }
            work()
        }
    }

    // MARK: - 查询（供视图与测试）

    struct StickerPose {
        /// 搭建时所属的槽位，决定这片贴纸的颜色
        let buildSlot: Int
        /// 此刻所在的槽位
        let currentSlot: Int
    }

    func cubieIndex(at center: V3) -> Int? {
        cubies.firstIndex { $0.center == center }
    }

    /// 找出"此刻朝外方向为 normal、所在块中心为 center"的那片贴纸。
    /// 转过之后局部坐标与本体方向不再一一对应，按当前朝向查才可靠。
    func hitOfSticker(facing normal: V3, at center: V3) -> Hit? {
        guard let index = cubieIndex(at: center) else { return nil }
        let node = cubies[index]
        for owner in owners.values where owner.cubie == index {
            if node.rotation.applying(to: owner.localNormal) == normal {
                return Hit(cubieIndex: index, localNormal: owner.localNormal)
            }
        }
        return nil
    }

    /// 每片贴纸当前落在哪个槽位：与 `CubeState` 对账用
    var stickerPoses: [StickerPose] {
        owners.values.compactMap { owner in
            let node = cubies[owner.cubie]
            let normal = node.rotation.applying(to: owner.localNormal)
            guard let slot = StickerGeometry.index(cubieCenter: node.center, facing: normal, size: size) else { return nil }
            return StickerPose(buildSlot: owner.buildSlot, currentSlot: slot)
        }
    }

    // MARK: - 转视角（trackball）

    /// 默认姿态：俯角 28°、偏航 32°，同时看到 U / F / R
    static let defaultOrbit = simd_quatf(angle: -0.56, axis: [0, 1, 0]) * simd_quatf(angle: 0.49, axis: [1, 0, 0])

    /// 一步位移对应的增量旋转。轴取相机轴（屏幕右 = +X，屏幕上 = +Y，视线 = -Z），
    /// 所以永远绕世界轴左乘累积：不夹角度、也不会在大俯仰角时出现"拖不动/反向"的退化。
    /// 方向按"表面跟手指"定：右拖把正面推向屏幕右，下拖把正面推向屏幕下。
    nonisolated static func orbitDelta(step: CGSize, pixelsPerRadian: CGFloat) -> simd_quatf {
        let yaw = Float(step.width / pixelsPerRadian)
        let pitch = Float(step.height / pixelsPerRadian)
        return simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    // MARK: - 坐标换算

    private func render(_ vector: V3) -> SIMD3<Float> {
        Self.vector(vector) * unit
    }

    nonisolated static func vector(_ value: V3) -> SIMD3<Float> {
        SIMD3<Float>(Float(value.x), Float(value.y), Float(value.z))
    }
}

extension Rotation {
    /// 整数矩阵直接喂给 simd 的四元数构造，避免手写矩阵分解
    var quaternion: simd_quatf {
        simd_quatf(simd_float3x3(columns: (CubeScene.vector(xAxis), CubeScene.vector(yAxis), CubeScene.vector(zAxis))))
    }
}
