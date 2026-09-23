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
    /// 视频识别入口：录一段或选一段展示六个面的视频，自动挑面识别
    let onVideoScan: () -> Void
    /// 拍照识别回来时把握度不够的提醒；nil 表示够有把握（或还没拍过）
    ///
    /// 必须排在 `onSolved` **前面**：`onSolved` 是尾随闭包，得是成员逐一构造器的
    /// 最后一个参数，否则调用处 `FaceEntryView(...) { state, solution in }` 绑不上。
    @Binding var scanHint: String?
    /// 视频识别失败——必须比 `scanHint`（黄色"把握不大"）更醒目，不然用户关掉
    /// 识别页就完全不知道发生了什么
    @Binding var scanError: String?
    let onSolved: (CubeState, CubeSolution) -> Void

    var body: some View {
        VStack(spacing: 14) {
            scanEntry
            scanWarning
            scanErrorBanner
            candidateSwitcher
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

    /// 显式 init：`@Binding` 不会自动获得默认值，得由调用方传 `$state`。
    init(
        model: RestoreModel,
        onScan: @escaping () -> Void,
        onVideoScan: @escaping () -> Void,
        scanHint: Binding<String?>,
        scanError: Binding<String?>,
        onSolved: @escaping (CubeState, CubeSolution) -> Void
    ) {
        self.model = model
        self.onScan = onScan
        self.onVideoScan = onVideoScan
        self._scanHint = scanHint
        self._scanError = scanError
        self.onSolved = onSolved
    }

    // MARK: - 多种拼法

    /// 识别出不止一种拼法时的切换入口。
    ///
    /// 只会在偶数阶出现：两个**不同的面**互为 90° 旋转时，照片分不出谁是谁
    /// （实测二阶约一成状态如此，且用求解器验过每个候选都是真能拧出来的）。
    /// 硬选一个是赌运气，所以把候选摆出来让用户对照魔方挑。
    @ViewBuilder
    private var candidateSwitcher: some View {
        if model.hasCandidateChoices {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                Text("识别到 \(model.candidates.count) 种拼法，当前第 \(model.candidateIndex + 1) 种")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("换拼法") { model.cycleCandidate() }
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
            }
            .disabled(model.isSolving)
        }
    }

    // MARK: - 拍照入口

    private var scanEntry: some View {
        HStack(spacing: 10) {
            entry(icon: "camera.viewfinder", title: "拍照识别", subtitle: "用 \(model.size) 阶魔方 · 拍六个面", action: onScan)
            entry(icon: "video", title: "视频识别", subtitle: "用 \(model.size) 阶魔方 · 转一圈", action: onVideoScan)
        }
        .disabled(model.isSolving)
    }

    private func entry(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
        }
        .padding(.top, 4)
    }

    // MARK: - 识别把握度提醒

    /// 拍照识别回来、但把握度不够时的提醒。
    ///
    /// 刻意**不拦**：把握度低只说明有格子骑在两个颜色中间，结果仍可能是对的，而回录入
    /// 手改一格的成本远低于重拍六个面。所以给一句提醒加一个关掉，判断权交给人。
    @ViewBuilder
    private var scanWarning: some View {
        if let scanHint {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                Text(scanHint)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    self.scanHint = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关掉这条提醒")
            }
            .foregroundStyle(.yellow)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 1)
            }
        }
    }

    /// 视频识别失败——红色，比 `scanWarning` 严重，因为它意味着识别页关了
    /// 之后用户就什么都不知道了，所以录入页必须能继续告诉他发生了什么。
    @ViewBuilder
    private var scanErrorBanner: some View {
        if let scanError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                Text(scanError)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    self.scanError = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关掉这条错误")
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
            }
        }
    }

    // MARK: - 说明

    private var hint: some View {
        Text(model.hasFixedCenters
             ? "也可以照展开图逐格填色。魔方按 白顶 · 绿前 摆好，六个中心块已按标准配色填好。"
             : "也可以照展开图逐格填色。\(model.size) 阶没有固定中心块，识别结果的朝向是随手挑的一个"
               + "（照片里不含“哪面朝上”）——配色对不上就按下面的「转 90°／翻 90°」拧到跟手上一致。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 展开图

    private var editor: some View {
        GeometryReader { geometry in
            let layout = CubeNetLayout(in: geometry.size, faceSize: model.size)
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
        let faceSize = model.size
        let origin = layout.faceOrigin(face)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .frame(width: cell * CGFloat(faceSize),
                       height: cell * CGFloat(faceSize))
            ForEach(0..<(faceSize * faceSize), id: \.self) { index in
                let row = index / faceSize
                let col = index % faceSize
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
                // 偶数阶才给：没有中心块锚定，识别结果的朝向得让用户自己拧
                if model.canRotate {
                    Button("转 90°") { model.rotate(by: .y) }
                    Button("翻 90°") { model.rotate(by: .x) }
                }
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
