import AVFoundation
import CubeKit
import CubeScan
import SwiftUI

/// 拍照识别：六个面各拍一张，识别出当前状态。
///
/// 拍照的次序和角度都随意——每个面拍进去时转了 90° 的几倍、先拍哪个面，
/// 都不影响结果。面与面之间的对应关系由 `FaceletAssembler` 枚举筛出来，
/// 所以界面上只需要一条"已拍几个面"的进度，不需要告诉用户先拍哪面。
///
/// 阶数由调用方按全局设置传进来（练习页的阶数开关），引导框与已拍缩略图都跟着变 N×N。
struct ScanView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var model: ScanModel

    /// 识别成功：把结果交出去（状态 + 全部候选 + 提醒），见 `ScanResult`。
    let onFinished: (ScanResult) -> Void

    init(size: Int, onFinished: @escaping (ScanResult) -> Void) {
        _model = State(initialValue: ScanModel(size: size))
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            Color(white: 0.05).ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) { topBar }
        .task {
            model.onFinished = { result in
                onFinished(result)
                dismiss()
            }
            model.start()
        }
        .onDisappear { model.stop() }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button("关闭") { dismiss() }
                .font(.body)
                .foregroundStyle(.orange)
            Spacer()
            Text("拍照识别")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text("\(model.capturedCount)/\(ScanModel.faceCount)")
                .font(.body.monospacedDigit())
                .foregroundStyle(model.isFull ? .green : .white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .preparing:
            placeholder("正在启动相机…", systemImage: "camera")
        case .denied:
            placeholder("没有相机权限。请到「设置 › iCube › 相机」打开后回来重试，也可以直接手动录入。",
                        systemImage: "lock.circle")
        case .unavailable:
            placeholder("这台设备没有可用的后置摄像头。用「手动录入」一样可以还原。",
                        systemImage: "camera.metering.unknown")
        case .cameraFailed(let message):
            placeholder(message, systemImage: "exclamationmark.triangle")
        default:
            VStack(spacing: 16) {
                viewfinder
                filmstrip
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, 44)
            .padding(.bottom, 16)
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - 取景

    private var viewfinder: some View {
        GeometryReader { proxy in
            let geometry = ScanGeometry(videoSize: model.videoSize, viewSize: proxy.size, size: model.size)
            ZStack(alignment: .topLeading) {
                CameraPreview(session: model.captureSession)
                mask(geometry: geometry, size: proxy.size)
                cells(geometry: geometry)
                guideBorder(geometry: geometry)
                hint(geometry: geometry, size: proxy.size)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { model.updateViewSize($0) }
            .overlay { if model.phase == .analysing { analysingOverlay } }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// 引导框外压暗，只留方框透亮
    private func mask(geometry: ScanGeometry, size: CGSize) -> some View {
        let guide = geometry.guideRect
        let shade = Color.black.opacity(0.55)
        return Group {
            shade.frame(width: size.width, height: max(0, guide.minY))
            shade.frame(width: size.width, height: max(0, size.height - guide.maxY))
                .offset(y: guide.maxY)
            shade.frame(width: max(0, guide.minX), height: guide.height)
                .offset(y: guide.minY)
            shade.frame(width: max(0, size.width - guide.maxX), height: guide.height)
                .offset(x: guide.maxX, y: guide.minY)
        }
        .allowsHitTesting(false)
    }

    /// 实时把"我现在读到的 N² 个颜色"画出来，用户据此对齐。
    ///
    /// 用的是 `liveSamplesOnScreen`——模型已经把帧次序拧成屏幕次序了，这里别再自己索引。
    private func cells(geometry: ScanGeometry) -> some View {
        let samples = model.liveSamplesOnScreen
        return ForEach(0..<model.cellCount, id: \.self) { index in
            let cell = geometry.cellRect(index, inset: 0.04)
            RoundedRectangle(cornerRadius: 5)
                .fill(color(at: index, samples: samples))
                .frame(width: cell.width, height: cell.height)
                .offset(x: cell.minX, y: cell.minY)
        }
        .allowsHitTesting(false)
    }

    private func color(at index: Int, samples: [LabColor]?) -> Color {
        guard let samples, samples.indices.contains(index) else { return Color.white.opacity(0.06) }
        return samples[index].uiColor.opacity(0.85)
    }

    private func guideBorder(geometry: ScanGeometry) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            .frame(width: geometry.guideRect.width, height: geometry.guideRect.height)
            .offset(x: geometry.guideRect.minX, y: geometry.guideRect.minY)
            .allowsHitTesting(false)
    }

    private func hint(geometry: ScanGeometry, size: CGSize) -> some View {
        Text(model.duplicateHint ?? "把一面魔方填满方框")
            .font(.footnote.weight(.medium))
            .foregroundStyle(model.duplicateHint == nil ? Color.white : Color.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(width: size.width)
            .offset(y: min(size.height - 34, geometry.guideRect.maxY + 10))
            .allowsHitTesting(false)
    }

    private var analysingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("正在识别六个面…")
                .font(.footnote)
                .foregroundStyle(.white)
        }
        .padding(20)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 已拍的面

    private var filmstrip: some View {
        HStack(spacing: 8) {
            ForEach(0..<ScanModel.faceCount, id: \.self) { index in
                slot(index)
            }
        }
        .padding(.horizontal, 16)
    }

    private func slot(_ index: Int) -> some View {
        // 模型给的已经是屏幕次序，miniGrid 直接照画即可
        let samples = model.captureSamplesOnScreen(at: index)
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.06))
            .overlay {
                if let samples {
                    miniGrid(samples)
                } else {
                    Text("\(index + 1)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(samples == nil ? Color.white.opacity(0.18) : Color.orange,
                                  lineWidth: samples == nil ? 1 : 2)
            }
            .aspectRatio(1, contentMode: .fit)
    }

    /// 画一个面的 N² 格。**传进来的必须已经是屏幕次序**（见 `ScanModel.captureSamplesOnScreen`）——
    /// 早先这里直接拿帧次序画，拍完的缩略图就跟刚看到的那一面差 90°。
    private func miniGrid(_ samples: [LabColor]) -> some View {
        GeometryReader { proxy in
            let size = model.size
            let side = min(proxy.size.width, proxy.size.height) / CGFloat(size)
            // 用 VStack/HStack 让网格**自身撑开**成 side*N 见方。
            //
            // 之前是 ZStack + 逐格 `.offset`，那是错的：`offset` 不参与布局，ZStack
            // 的布局尺寸只有 side*side，于是外层 `.frame(side*3, side*3)` 把这个小块
            // **居中**放进大框，左上角被推到 (side, side)——九格再从这里 offset 展开，
            // 右下角就冲出槽位了。
            VStack(spacing: 0) {
                ForEach(0..<size, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<size, id: \.self) { column in
                            let index = row * size + column
                            Rectangle()
                                .fill(index < samples.count ? samples[index].uiColor : Color.clear)
                        }
                    }
                }
            }
            .frame(width: side * CGFloat(size), height: side * CGFloat(size))
            // 再撑满一层，把这块居中对齐到槽位里
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(3)
    }

    // MARK: - 底部操作

    private var footer: some View {
        VStack(spacing: 14) {
            if case .failed(let message) = model.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            HStack {
                sideButton("重拍", systemImage: "arrow.uturn.backward", enabled: !model.captures.isEmpty) {
                    model.retakeLast()
                }
                Spacer()
                shutter
                Spacer()
                sideButton("清空", systemImage: "trash", enabled: !model.captures.isEmpty) {
                    model.reset()
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private var shutter: some View {
        Button {
            model.capture()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(model.hasLiveSamples ? .white : Color.white.opacity(0.35))
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .scanning || !model.hasLiveSamples)
        .accessibilityLabel("拍下这一面")
    }

    private func sideButton(
        _ title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 18))
                Text(title).font(.caption2)
            }
            .frame(width: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
        .disabled(!enabled)
    }
}
