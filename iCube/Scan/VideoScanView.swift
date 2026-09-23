import AVFoundation
import CubeKit
import CubeScan
import SwiftUI

/// 视频识别：录一段（或从相册选一段）展示六个面的视频，自动挑出六个面并识别。
///
/// 与拍照识别（`ScanView`）的差别只在六个面从哪来：那边是用户按六次快门，
/// 这边是算法从帧流里自己挑。挑齐之后共用 `ScanAnalysis`。
///
/// ## 引导框为什么还在
///
/// 录制时仍然画一个方框，但**不是**要求魔方严格填满它——`FaceLocator` 会在
/// 画面里搜索魔方的实际位置，方框只是告诉用户"往这儿放、别出画面"。
/// 手持晃动、远近变化都能容忍，偏出大半个画面才会丢帧。
struct VideoScanView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var model: VideoScanModel
    @State private var camera = CameraSession()
    @State private var isRecording = false
    @State private var showingPicker = false
    @State private var viewSize: CGSize = .zero

    /// 识别成功：把结果交出去（状态 + 全部候选 + 提醒），见 `ScanResult`
    let onFinished: (ScanResult) -> Void

    init(size: Int, onFinished: @escaping (ScanResult) -> Void) {
        _model = State(initialValue: VideoScanModel(size: size))
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
            camera.start()
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showingPicker) {
            VideoPicker { url in
                showingPicker = false
                guard let url else { return }
                process(url)
            }
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            Button("关闭") { dismiss() }
                .font(.body)
                .foregroundStyle(.orange)
            Spacer()
            Text("视频识别")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text("\(model.foundCount)/\(ScanModel.faceCount)")
                .font(.body.monospacedDigit())
                .foregroundStyle(model.foundCount >= ScanModel.faceCount ? .green : .white.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .failed:
            captureArea
        case .extracting, .analysing:
            workingArea
        }
    }

    /// 录制 / 选择的界面
    private var captureArea: some View {
        VStack(spacing: 16) {
            viewfinder
            if case .failed(let message) = model.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(.top, 44)
        .padding(.bottom, 16)
    }

    private var viewfinder: some View {
        GeometryReader { proxy in
            let geometry = ScanGeometry(videoSize: recordedSize, viewSize: proxy.size, size: model.size)
            ZStack(alignment: .topLeading) {
                CameraPreview(session: camera.session)
                guideBorder(geometry: geometry)
                hint(geometry: geometry, size: proxy.size)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .padding(.horizontal, 12)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// 预览画面按竖屏理解（应用锁竖屏）；没有信号时给个占位比例，引导框照样能画
    private var recordedSize: CGSize {
        viewSize.width > 0 ? CGSize(width: viewSize.height, height: viewSize.width) : .zero
    }

    private func guideBorder(geometry: ScanGeometry) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
            .frame(width: geometry.guideRect.width, height: geometry.guideRect.height)
            .offset(x: geometry.guideRect.minX, y: geometry.guideRect.minY)
            .allowsHitTesting(false)
    }

    private func hint(geometry: ScanGeometry, size: CGSize) -> some View {
        Text(isRecording ? "正在录制…慢慢转，每个面停半秒" : "把魔方放在方框里，按录制后慢慢转一圈")
            .font(.footnote.weight(.medium))
            .foregroundStyle(isRecording ? Color.red : Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .frame(width: size.width)
            .offset(y: min(size.height - 34, geometry.guideRect.maxY + 10))
            .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                recordButton
                Spacer()
            }
            Button {
                showingPicker = true
            } label: {
                Label("从相册选视频", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isRecording)
        }
        .padding(.horizontal, 32)
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.red)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 58, height: 58)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "停止录制" : "开始录制")
    }

    private func toggleRecording() {
        if isRecording {
            camera.stopRecording { url in
                isRecording = false
                guard let url else { return }
                process(url)
            }
        } else {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            isRecording = true
            camera.startRecording(to: destination)
        }
    }

    /// 处理中的界面
    private var workingArea: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white).controlSize(.large)
            Text(model.phase == .extracting ? "正在逐帧找出六个面…" : "正在识别…")
                .font(.footnote)
                .foregroundStyle(.white)
            if model.phase == .extracting {
                Text("已认出 \(model.foundCount) 个面")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 处理

    private func process(_ url: URL) {
        let asset = AVAsset(url: url)
        Task { await model.process(asset) }
    }
}
