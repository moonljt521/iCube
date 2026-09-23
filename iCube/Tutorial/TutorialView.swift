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
            // 阶数变化时整个详情页重建：init 按新阶新建场景，动画作用于上屏的那个场景
            TutorialCaseDetailView(tutorialCase: tutorialCase, cubeSize: cubeSize)
                .id(cubeSize)
        }
    }
}

// MARK: - 案型详情

struct TutorialCaseDetailView: View {
    let tutorialCase: TutorialCase
    let cubeSize: Int

    @State private var model: CubeDemoModel
    @State private var orbit = CubeScene.defaultOrbit

    init(tutorialCase: TutorialCase, cubeSize: Int) {
        self.tutorialCase = tutorialCase
        self.cubeSize = cubeSize
        // 模型（含场景）在视图创建时按阶数生成：RealityView 的 make 只跑一次，
        // 之后换 model 实例不会重新上屏，所以绝不能在 onAppear 里另建模型
        _model = State(initialValue: CubeDemoModel(state: .solved(size: cubeSize)))
    }

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
                    ForEach(CubeDemoModel.Speed.allCases) { speed in
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
