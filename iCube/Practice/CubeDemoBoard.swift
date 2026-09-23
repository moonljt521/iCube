import SwiftUI
import RealityKit
import CubeKit

/// 3D 演示棋盘：只转视角，不改魔方。
///
/// 教程详情页与还原步骤页共用。模型里的 `CubeScene` 由调用方在视图 `init`
/// 时建好——`RealityView` 的 make 只跑一次，之后换模型实例不会重新上屏。
struct CubeDemoBoard: View {
    let model: CubeDemoModel
    @Binding var orbit: simd_quatf

    @State private var content = ContentBox()
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private final class ContentBox {
        var camera: RealityViewCameraContent?
    }

    private static let pixelsPerRadian: CGFloat = 190
    /// 捏合缩放阈值（与练习页一致）
    private static let minScale: Float = 0.7
    private static let maxScale: Float = 1.5

    var body: some View {
        RealityView { camera in
            camera.add(Self.makeKeyLight())
            camera.add(model.scene.root)
            camera.cameraTarget = model.scene.root
            content.camera = camera
            model.scene.root.orientation = orbit
        }
        .gesture(orbitGesture)
        .simultaneousGesture(magnifyGesture)
        .accessibilityLabel("演示魔方")
    }

    /// 演示页全是空白区域，SwiftUI 自带捏合手势直接用，阈值与练习页一致
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastMagnification
                lastMagnification = value
                let current = model.scene.root.scale.x
                let next = min(Self.maxScale, max(Self.minScale, current * Float(delta)))
                model.scene.root.scale = SIMD3<Float>(repeating: next)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let step = CGSize(width: value.translation.width - lastTranslation.width,
                                  height: value.translation.height - lastTranslation.height)
                lastTranslation = value.translation
                orbit = CubeScene.orbitDelta(step: step, pixelsPerRadian: Self.pixelsPerRadian) * orbit
                model.scene.root.orientation = orbit
            }
            .onEnded { _ in lastTranslation = .zero }
    }

    private static func makeKeyLight() -> Entity {
        let light = DirectionalLight()
        light.light.color = .white
        light.light.intensity = 3200
        light.orientation = simd_quatf(angle: -0.7, axis: [1, 0, 0]) * simd_quatf(angle: 0.5, axis: [0, 1, 0])
        return light
    }
}
