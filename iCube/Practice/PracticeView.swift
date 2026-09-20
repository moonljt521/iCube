import SwiftUI
import SwiftData
import CubeKit

struct PracticeView: View {
    @State private var model = PracticeModel()
    @Environment(\.modelContext) private var context
    @Query(sort: \SolveRecord.startedAt, order: .reverse) private var records: [SolveRecord]
    @AppStorage(MaterialCache.defaultsKey) private var skinID = CubeSkin.classic.id

    var body: some View {
        VStack(spacing: 12) {
            ScrambleBar(model: model)
            CubeBoardView(model: model)
                .id(model.cubeSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .top) { TimerLabel(model: model) }
                .overlay { SolveCard(model: model, recordCount: records.count) }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color(white: 0.05).ignoresSafeArea())
        .navigationTitle("练习")
        .toolbar { toolbarContent }
        .onAppear { model.onSolve = save }
        .onChange(of: skinID) { _, newValue in
            model.scene.applySkin(MaterialCache.skin(id: newValue))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("阶数", selection: Binding(
                    get: { model.cubeSize },
                    set: { model.setCubeSize($0) })) {
                    ForEach(CubeSize.supported, id: \.self) { size in
                        Text("\(size) 阶").tag(size)
                    }
                }
                Divider()
                Picker("皮肤", selection: $skinID) {
                    ForEach(CubeSkin.all) { skin in
                        Label(skin.name, systemImage: "paintpalette")
                            .tag(skin.id)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            primaryButton("打乱并开始", systemImage: "shuffle") { model.scrambleAndPlay() }
        case .scrambling:
            primaryButton("跳过打乱", systemImage: "forward.end") { model.skipScramble() }
        case .ready:
            holdToStart
        case .running:
            HStack {
                Button("放弃本次", role: .destructive) { model.reset() }
                    .buttonStyle(.bordered)
            }
        case .solved:
            primaryButton("再来一次", systemImage: "arrow.counterclockwise") { model.reset() }
        }
    }

    /// 竞速式起手：按住待命，松手才开表
    private var holdToStart: some View {
        Button {
        } label: {
            Label(model.isArmed ? "松手开始" : "按住准备",
                  systemImage: model.isArmed ? "hand.tap.fill" : "hand.tap")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.arm() }
                .onEnded { _ in model.releaseToStart() }
        )
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func save(_ outcome: PracticeModel.SolveOutcome) {
        let record = SolveRecord(startedAt: outcome.startedAt,
                                 rawSeconds: outcome.duration,
                                 penalty: outcome.penalty,
                                 scramble: outcome.scramble,
                                 moveCount: outcome.moveCount,
                                 cubeSize: outcome.cubeSize)
        context.insert(record)
        try? context.save()
    }
}

private struct TimerLabel: View {
    let model: PracticeModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.phase != .running)) { context in
            VStack(spacing: 2) {
                Text(SolveStats.format(model.elapsed(at: context.date)))
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.phase == .running ? .white : .white.opacity(0.55))
                    .monospacedDigit()
                if let last = model.lastMove {
                    Text("上一步 \(last.notation)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 12)
        .allowsHitTesting(false)
    }
}

private struct ScrambleBar: View {
    let model: PracticeModel

    var body: some View {
        Group {
            if let scramble = model.scramble {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(scramble.moves.enumerated()), id: \.offset) { index, move in
                                Text(move.notation)
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(index < model.scrambleCursor ? Color.orange.opacity(0.35) : Color.white.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 7))
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: model.scrambleCursor) { _, cursor in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(max(0, cursor - 1), anchor: .leading)
                        }
                    }
                }
            } else {
                Text("点击下方按钮生成打乱").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(height: 38)
    }
}

private struct SolveCard: View {
    let model: PracticeModel
    let recordCount: Int

    var body: some View {
        if case .solved(let duration) = model.phase {
            VStack(spacing: 10) {
                Text("已还原").font(.title2.bold())
                Text(SolveStats.format(duration))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                Text("\(model.moveCount) 步 · \(model.cubeSize) 阶 · 共 \(recordCount) 次记录")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(SolvePenalty.allCases, id: \.self) { penalty in
                        Button(penalty.rawValue) { model.applyPenalty(penalty) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .transition(.scale.combined(with: .opacity))
        }
    }
}
