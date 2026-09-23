import SwiftUI
import CubeKit
import CubeSolve

/// 手动录入：把 54 格填色。
///
/// 整张展开图只挂**一个**容器级 `DragGesture(minimumDistance: 0)`，
/// 触点先经 `CubeNetLayout` 映射到具体格子再交给模型——这样"点一下"和
/// "拖着刷"是同一条代码路径，不必给 54 个格子各挂手势，连续涂抹也不会漏格。
struct FaceEntryView: View {
    let model: RestoreModel
    let onScan: () -> Void
    let onSolved: (CubeState, CubeSolution) -> Void

    var body: some View {
        VStack(spacing: 14) {
            scanEntry
            hint
            Spacer(minLength: 0)
            editor
            Spacer(minLength: 0)
            palette
            statusBar
            solveButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color(white: 0.05).ignoresSafeArea())
    }

    // MARK: - 拍照入口

    private var scanEntry: some View {
        Button(action: onScan) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("拍照识别")
                        .font(.subheadline.weight(.semibold))
                    Text("六个面各拍一张，自动读出当前状态")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
        }
        .disabled(model.isSolving)
        .padding(.top, 4)
    }

    // MARK: - 说明

    private var hint: some View {
        Text("也可以照展开图逐格填色。魔方按 白顶 · 绿前 摆好，六个中心块已按标准配色填好。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 展开图

    private var editor: some View {
        GeometryReader { geometry in
            let layout = CubeNetLayout(in: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach(Face.allCases, id: \.self) { face in
                    faceGrid(face, layout: layout)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(paintGesture(layout: layout))
            // 求解在飞的时候锁住录入：解只对发起时那份状态成立，
            // 中途改一格就会让"解"和"状态"错开（详见 `RestoreModel.solvedState`）
            .disabled(model.isSolving)
        }
        .aspectRatio(CGFloat(CubeNetLayout.faceColumns) / CGFloat(CubeNetLayout.faceRows), contentMode: .fit)
    }

    private func faceGrid(_ face: Face, layout: CubeNetLayout) -> some View {
        let cell = layout.cellSize
        let origin = layout.faceOrigin(face)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .frame(width: cell * CGFloat(CubeNetLayout.faceSize),
                       height: cell * CGFloat(CubeNetLayout.faceSize))
            ForEach(0..<(CubeNetLayout.faceSize * CubeNetLayout.faceSize), id: \.self) { index in
                let row = index / CubeNetLayout.faceSize
                let col = index % CubeNetLayout.faceSize
                stickerCell(face: face, row: row, col: col)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(col) * cell, y: CGFloat(row) * cell)
            }
        }
        .offset(x: origin.x, y: origin.y)
    }

    private func stickerCell(face: Face, row: Int, col: Int) -> some View {
        let color = model.color(at: face, row: row, col: col)
        return RoundedRectangle(cornerRadius: 4)
            .fill(color.map { Color(MaterialCache.uiColor(of: $0)) } ?? Color.white.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5)
            }
            .padding(1)
    }

    /// 点与拖共用：一按下就上色，移动时继续刷过经过的格子
    private func paintGesture(layout: CubeNetLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let hit = layout.sticker(at: value.location) else { return }
                model.paint(at: hit.face, row: hit.row, col: hit.col)
            }
    }

    // MARK: - 调色板

    private var palette: some View {
        HStack(spacing: 8) {
            ForEach(CubeColor.allCases, id: \.self) { color in
                Button {
                    model.brush = color
                } label: {
                    Circle()
                        .fill(Color(MaterialCache.uiColor(of: color)))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Circle().strokeBorder(model.brush == color ? Color.orange : Color.white.opacity(0.2),
                                                  lineWidth: model.brush == color ? 3 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
            }

            Button {
                model.brush = nil
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 17))
                    .foregroundStyle(model.isErasing ? Color.orange : Color.secondary)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle().strokeBorder(model.isErasing ? Color.orange : Color.white.opacity(0.2),
                                              lineWidth: model.isErasing ? 3 : 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("橡皮")

            Spacer(minLength: 0)
        }
        .disabled(model.isSolving)
    }

    // MARK: - 状态与操作

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(model.statusMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(model.canSolve ? .green : .secondary)
                Spacer(minLength: 0)
                Button("清空") { model.clear() }
                Button("填中心块") { model.fillCenters() }
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .disabled(model.isSolving)

            if let failure = model.failure {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var solveButton: some View {
        Button {
            Task {
                await model.solve()
                // 用配对的那份状态，不是"此刻"的 stickers——求解期间录入界面
                // 可能被改过（旧版本没锁），两者错开一格就会演出非法配色
                if let state = model.solvedState, let solution = model.solution {
                    onSolved(state, solution)
                }
            }
        } label: {
            Group {
                if model.isSolving {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("求解中…")
                    }
                } else {
                    Label("求解", systemImage: "wand.and.stars")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.orange)
        .disabled(!model.canSolve || model.isSolving)
    }
}
