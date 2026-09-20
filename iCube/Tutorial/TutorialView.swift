import SwiftUI
import RealityKit
import CubeKit

/// 教程：层先法 7 步 + 2-look PLL 进阶，每个案型在 3D 魔方上重演。
/// 阶数跟随全局设置（练习页切换），模型与公式随阶重建；教学文案仍以三阶为例。
struct TutorialView: View {
    @AppStorage(CubeSize.defaultsKey) private var cubeSize = 3

    var body: some View {
        List {
            if cubeSize != 3 {
                Section {
                    Label("当前以 \(cubeSize) 阶魔方演示，讲解以三阶为例（二阶无棱块/中心块，四阶另有中心与棱合并步骤）",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(TutorialStage.all) { stage in
                Section {
                    if stage.cases.isEmpty {
                        Text(stage.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stage.cases) { tutorialCase in
                            NavigationLink(value: tutorialCase) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tutorialCase.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(tutorialCase.formula)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } header: {
                    Text(stage.title)
                } footer: {
                    if !stage.cases.isEmpty, !stage.summary.isEmpty {
                        Text(stage.summary)
                    }
                }
            }
        }
        .navigationTitle("教程")
        .navigationDestination(for: TutorialCase.self) { tutorialCase in
            // 阶数变化时整个详情页重建，模型按新阶摆案型
            TutorialCaseDetailView(tutorialCase: tutorialCase)
                .id(cubeSize)
        }
    }
}

// MARK: - 案型详情

struct TutorialCaseDetailView: View {
    let tutorialCase: TutorialCase

    @AppStorage(CubeSize.defaultsKey) private var cubeSize = 3
    @State private var model = TutorialCubeModel()
    @State private var orbit = CubeScene.defaultOrbit

    private var algorithm: Algorithm? { tutorialCase.algorithm(size: cubeSize) }

    var body: some View {
        VStack(spacing: 14) {
            CubeDemoBoard(model: model, orbit: $orbit)
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            formulaStrip

            HStack(spacing: 12) {
                Button {
                    if let algorithm { model.loadCase(algorithm: algorithm) }
                } label: {
                    Label("重置案型", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    if model.isPlaying {
                        model.stop()
                    } else if let algorithm {
                        model.play(algorithm)
                    }
                } label: {
                    Label(model.isPlaying ? "停止" : "演示还原",
                          systemImage: model.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(algorithm == nil)

                Menu {
                    ForEach(TutorialCubeModel.Speed.allCases) { speed in
                        Button(speed.rawValue) { model.speed = speed }
                    }
                } label: {
                    Label(model.speed.rawValue, systemImage: "gauge.with.needle")
                }
                .buttonStyle(.bordered)
            }

            if model.state.isSolved, !model.isPlaying {
                Label("已还原，重置案型可以再看一遍", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }

            Text(tutorialCase.tips)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding()
        .navigationTitle(tutorialCase.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model = TutorialCubeModel(state: .solved(size: cubeSize))
            orbit = CubeScene.defaultOrbit
            if let algorithm { model.loadCase(algorithm: algorithm) }
        }
        .onDisappear { model.stop() }
    }

    /// 公式字块：演示到哪一步就高亮哪一块
    @ViewBuilder
    private var formulaStrip: some View {
        if let algorithm {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(algorithm.moves.enumerated()), id: \.offset) { index, move in
                        Text(move.notation)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(model.currentMoveIndex == index
                                        ? Color.orange.opacity(0.85)
                                        : Color(.secondarySystemFill))
                            .foregroundStyle(model.currentMoveIndex == index ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal)
            }
        } else {
            Text("公式无法解析")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - 演示棋盘（只转视角，不改魔方）

private struct CubeDemoBoard: View {
    let model: TutorialCubeModel
    @Binding var orbit: simd_quatf

    @State private var content = DemoContentBox()
    @State private var lastTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private final class DemoContentBox {
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
