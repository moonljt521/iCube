import SwiftUI
import RealityKit
import CubeKit
import UIKit

/// 3D 棋盘：手势仲裁——拖在贴纸上转该层，拖在空白处转视角，多指可同时转互不相干的层。
struct CubeBoardView: View {
    let model: PracticeModel

    private final class ContentBox {
        var content: RealityViewCameraContent?
    }

    /// 一根手指的会话
    final class FingerSession {
        let id: Int
        let start: CGPoint
        var last: CGPoint
        var hit: CubeScene.Hit?
        var intent: CubeScene.DragIntent = .undecided
        var handle: CubeScene.TurnHandle?
        var angle: Float = 0

        init(id: Int, start: CGPoint, hit: CubeScene.Hit?) {
            self.id = id
            self.start = start
            self.last = start
            self.hit = hit
        }
    }

    /// 手势簿记。放在引用类型里，避免每帧写 @State 触发无谓重绘
    @MainActor final class FingerTracker {
        var fingers: [Int: FingerSession] = [:]
        var orbitFingerID: Int?
        /// 双指捏合会话：起始指距 + 起始缩放；nil = 未在捏合
        var pinch: (startDistance: CGFloat, startScale: Float)?
    }

    @State private var box = ContentBox()
    @State private var tracker = FingerTracker()
    @State private var orbit = CubeScene.defaultOrbit
    @State private var scale: Float = 1

    private static let pixelsPerRadian: CGFloat = 190
    /// 捏合缩放阈值：整体尺寸在 0.7x ~ 1.5x 之间
    private static let minScale: Float = 0.7
    private static let maxScale: Float = 1.5

    var body: some View {
        RealityView { content in
            content.add(Self.makeKeyLight())
            content.add(model.scene.root)
            content.cameraTarget = model.scene.root
            box.content = content
            applyOrientation()
            applyScale()
        }
        .overlay {
            CubeTouchView { events in handle(events) }
        }
        .accessibilityLabel("魔方")
    }

    private func applyOrientation() {
        model.scene.root.orientation = orbit
    }

    private func applyScale() {
        model.scene.root.scale = SIMD3<Float>(repeating: scale)
    }

    private static func makeKeyLight() -> Entity {
        let light = DirectionalLight()
        light.light.color = .white
        light.light.intensity = 3200
        light.orientation = simd_quatf(angle: -0.7, axis: [1, 0, 0]) * simd_quatf(angle: 0.5, axis: [0, 1, 0])
        return light
    }

    // MARK: - 事件处理

    private func handle(_ events: [CubeTouchEvent]) {
        let scene = model.scene
        for event in events {
            switch event.phase {
            case .began:
                // 空白区的手指随时记入会话（双指招合缩放任意阶段可用）；
                // 能不能真的转层/转视角由 advance 里的 canTurn 把关
                guard let content = box.content else { continue }
                tracker.fingers[event.id] = FingerSession(id: event.id,
                                                          start: event.location,
                                                          hit: scene.hit(at: event.location, in: content, rootOrientation: orbit))
            case .moved:
                guard let finger = tracker.fingers[event.id] else { continue }
                let drag = CGSize(width: event.location.x - finger.start.x,
                                  height: event.location.y - finger.start.y)
                let step = CGSize(width: event.location.x - finger.last.x,
                                  height: event.location.y - finger.last.y)
                finger.last = event.location
                advance(finger, drag: drag, step: step, scene: scene)
            case .stationary, .regionEntered, .regionMoved, .regionExited:
                continue
            case .ended, .cancelled:
                guard let finger = tracker.fingers[event.id] else { continue }
                tracker.fingers[event.id] = nil
                if tracker.orbitFingerID == event.id { tracker.orbitFingerID = nil }
                finish(finger, event: event, scene: scene)
            }
        }
        updatePinch()
    }

    // MARK: - 双指捏合缩放（仅限空白处，双指都没摸到魔方）

    private func updatePinch() {
        let active = tracker.fingers.values.sorted { $0.id < $1.id }
        let allOnEmpty = active.allSatisfy { $0.hit == nil }
        if active.count >= 2, allOnEmpty,
           let distance = Self.distance(active[0].last, active[1].last), distance > 1 {
            if tracker.pinch == nil {
                // 捏合接管：终止视角拖动，避免缩放与旋转互相拉扯
                tracker.orbitFingerID = nil
                tracker.pinch = (distance, scale)
            }
            let pinch = tracker.pinch!
            scale = min(Self.maxScale, max(Self.minScale, pinch.startScale * Float(distance / pinch.startDistance)))
            applyScale()
        } else {
            tracker.pinch = nil
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat? {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let value = (dx * dx + dy * dy).squareRoot()
        return value > 0 ? value : nil
    }

    private func advance(_ finger: FingerSession, drag: CGSize, step: CGSize, scene: CubeScene) {
        // 非可操作阶段（待机/打乱中/演示脚本）只做招合缩放的簿记，不触发转层或转视角
        guard model.canTurn, !scene.isPlayingScript else { return }
        switch finger.intent {
        case .undecided:
            // 每帧重取命中：上一次转动可能刚提交完，落点下的贴纸已经换了
            if let content = box.content,
               let fresh = scene.hit(at: finger.start, in: content, rootOrientation: orbit) {
                finger.hit = fresh
            }
            let intent = scene.resolveIntent(hit: finger.hit, drag: drag, rootOrientation: orbit)
            finger.intent = intent
            if case .turn(let plan) = intent, let handle = scene.beginDrag(plan) {
                finger.handle = handle
                finger.angle = scene.angle(for: plan, drag: drag)
                scene.updateDragAngle(handle, finger.angle)
            } else if intent == .orbit {
                claimOrbit(fingerID: finger.id, step: step)
            }
        case .turn(let plan):
            guard let handle = finger.handle else { return }
            finger.angle = scene.angle(for: plan, drag: drag)
            scene.updateDragAngle(handle, finger.angle)
        case .orbit:
            driveOrbit(step: step, ownerID: finger.id)
        }
    }

    private func finish(_ finger: FingerSession, event: CubeTouchEvent, scene: CubeScene) {
        guard case .turn(let plan) = finger.intent, let handle = finger.handle else { return }
        let drag = CGSize(width: event.location.x - finger.start.x,
                          height: event.location.y - finger.start.y)
        guard event.phase == .ended else {
            scene.cancelDrag(handle)
            return
        }
        // 甩动预测：轻扫也能转过 90°
        let flick = CGSize(width: drag.width * 1.6, height: drag.height * 1.6)
        let predicted = scene.angle(for: plan, drag: flick)
        let angle = abs(predicted) > abs(finger.angle) ? predicted : finger.angle
        scene.endDrag(handle: handle, angle: angle) { committed in
            if let committed {
                model.registerUserMove(committed)
            }
        }
    }

    // MARK: - 转视角

    private func claimOrbit(fingerID: Int, step: CGSize) {
        guard tracker.orbitFingerID == nil, tracker.pinch == nil else { return }
        tracker.orbitFingerID = fingerID
        driveOrbit(step: step, ownerID: fingerID)
    }

    /// 只有第一根进入 orbit 的手指驱动相机，其余的忽略，避免互相抵消；捏合期间暂停
    private func driveOrbit(step: CGSize, ownerID: Int) {
        guard tracker.orbitFingerID == ownerID, tracker.pinch == nil else { return }
        orbit = CubeScene.orbitDelta(step: step, pixelsPerRadian: Self.pixelsPerRadian) * orbit
        applyOrientation()
    }
}

// MARK: - UIKit 触摸转发

struct CubeTouchEvent {
    let id: Int
    let location: CGPoint
    let phase: UITouch.Phase
}

/// SwiftUI 的 DragGesture 一次只跟一根手指，多指对拨必须按 UITouch 身份分别追踪
final class TouchForwardingView: UIView {
    var onEvent: (([CubeTouchEvent]) -> Void)?

    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, .began) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { report(touches, .cancelled) }

    private func report(_ touches: Set<UITouch>, _ phase: UITouch.Phase) {
        var events: [CubeTouchEvent] = []
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let id: Int
            if let existing = ids[key] {
                id = existing
            } else {
                id = nextID
                nextID += 1
                ids[key] = id
            }
            events.append(CubeTouchEvent(id: id, location: touch.location(in: self), phase: phase))
            if phase == .ended || phase == .cancelled { ids[key] = nil }
        }
        onEvent?(events)
    }
}

struct CubeTouchView: UIViewRepresentable {
    let onEvent: ([CubeTouchEvent]) -> Void

    func makeUIView(context: Context) -> TouchForwardingView {
        let view = TouchForwardingView()
        view.onEvent = onEvent
        view.backgroundColor = .clear
        // 关键：UIView 默认只收一根手指，双指捏合/多指并转都必须显式打开
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TouchForwardingView, context: Context) {
        uiView.onEvent = onEvent
    }
}
