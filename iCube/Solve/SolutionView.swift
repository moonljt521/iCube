import SwiftUI
import CubeKit
import CubeSolve

/// 还原步骤页：3D 动画 + 文字步骤。
///
/// 魔方按录入状态建好，播完解即回到还原态；"重置"把魔方摆回录入状态再放一遍。
struct SolutionView: View {
    let enteredState: CubeState
    let solution: CubeSolution

    @State private var model: CubeDemoModel
    @State private var orbit = CubeScene.defaultOrbit

    init(enteredState: CubeState, solution: CubeSolution) {
        self.enteredState = enteredState
        self.solution = solution
        // 场景在视图创建时按录入状态建好：RealityView 的 make 只跑一次，
        // 之后换 model 实例不会重新上屏（与教程详情页同一约定）
        _model = State(initialValue: CubeDemoModel(state: enteredState))
    }

    var body: some View {
        VStack(spacing: 14) {
            CubeDemoBoard(model: model, orbit: $orbit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))

            stepStrip
            controls
            footer
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color(white: 0.05).ignoresSafeArea())
        .navigationTitle("还原步骤")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { orbit = CubeScene.defaultOrbit }
        .onDisappear { model.stop() }
    }

    // MARK: - 文字步骤

    /// 步骤条：演示到哪一步就高亮哪一块，并自动滚到可见处
    private var stepStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(solution.algorithm.moves.enumerated()), id: \.offset) { index, move in
                        VStack(spacing: 1) {
                            Text("\(index + 1)")
                                .font(.system(size: 10))
                                .foregroundStyle(model.currentMoveIndex == index ? .white.opacity(0.75) : .secondary)
                            Text(move.notation)
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(model.currentMoveIndex == index
                                    ? Color.orange.opacity(0.85)
                                    : Color(.secondarySystemFill))
                        .foregroundStyle(model.currentMoveIndex == index ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .id(index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: model.currentMoveIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .frame(height: 50)
    }

    // MARK: - 操作

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if model.isPlaying {
                    model.stop()
                } else {
                    model.play(solution.algorithm)
                }
            } label: {
                Label(model.isPlaying ? "停止" : "演示还原",
                      systemImage: model.isPlaying ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                model.load(state: enteredState)
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.state == enteredState && !model.isPlaying)

            Menu {
                ForEach(CubeDemoModel.Speed.allCases) { speed in
                    Button(speed.rawValue) { model.speed = speed }
                }
            } label: {
                Label(model.speed.rawValue, systemImage: "gauge.with.needle")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("共 \(solution.count) 步")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if model.state.isSolved {
                    Label("已还原", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                } else if let index = model.currentMoveIndex {
                    Text("第 \(index + 1) / \(solution.count) 步")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Text("解不保证最短——两阶段算法返回的是它搜到的第一个解，典型 20~24 步。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
