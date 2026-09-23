import AVFoundation
import CubeKit
import CubeScan
import CoreGraphics
import Foundation
import Observation
import SwiftUI

extension LabColor {
    /// 采样色的显示色。屏幕是 sRGB 的，所以走 `srgbComponents` 而不是直接拿 Lab 拼。
    var uiColor: Color {
        let srgb = srgbComponents
        return Color(red: srgb.red, green: srgb.green, blue: srgb.blue)
    }
}

extension ScanError {
    /// 给用户看的中文说明。
    ///
    /// `CubeScan` 保持语言中立，翻译放在应用层——和 `CubeSolveError.userMessage` 一个路子。
    var userMessage: String {
        switch self {
        case .wrongFaceCount:
            "六个面还没拍齐，请继续拍"
        case .wrongSampleCount:
            "有一面没拍全，请重拍"
        case .duplicateCenter:
            "有两面拍到的是同一个面，请重拍其中一个"
        case .duplicateFace:
            "有两面认成了同一种颜色，请换到光线均匀的地方重拍"
        case .ambiguousColors:
            "颜色分不开，请避开强反光、在光线均匀的地方重拍"
        }
    }
}

extension CameraSession.Failure {
    /// 给用户看的中文说明。
    var userMessage: String {
        switch self {
        case .cannotCreateInput:
            "打不开后置摄像头。别的 App 可能正在用它——关掉之后退出本页重进即可，也可以直接手动录入。"
        case .cannotAddInput, .cannotAddOutput:
            "相机初始化失败。退出本页重进即可，也可以直接手动录入。"
        }
    }
}

/// 拍照还原的编排：管相机、管采样、管"六个面凑齐后跑识别"。
///
/// 颜色怎么分、朝向怎么摆，全部在 `CubeScan` 里（纯算法、有单测）；这里只负责
/// 把帧喂进去、把结果接出来，以及把中间状态暴露给界面。
@MainActor
@Observable
final class ScanModel {

    /// 三阶一共六个面
    static let faceCount = 6

    enum Phase: Equatable {
        /// 相机还没就绪
        case preparing
        /// 用户拒绝了相机权限
        case denied
        /// 这台设备没有可用后置摄像头（模拟器）
        case unavailable
        /// 相机起不来（会话配置失败）
        case cameraFailed(String)
        /// 正在拍
        case scanning
        /// 六个面齐了，正在识别
        case analysing
        /// 识别失败，可以重拍
        case failed(String)
    }

    private(set) var phase: Phase = .preparing
    /// 当前帧的 9 格采样（row-major，预览里的次序），实时显示给用户对齐用
    private(set) var liveSamples: [LabColor]?
    /// 已拍的面
    private(set) var captures: [FaceCapture] = []
    /// 拍到重复面时的提示；下一次拍成功、或者重拍/清空时清掉
    private(set) var duplicateHint = false
    /// 显示朝向下的画面尺寸（竖），界面靠它算引导框
    private(set) var videoSize: CGSize = .zero
    /// 界面回填的视图尺寸
    private(set) var viewSize: CGSize = .zero

    /// 识别成功后的回调：拿到拼好的状态，交给录入页复核
    @ObservationIgnored var onFinished: ((CubeState) -> Void)?

    private let camera = CameraSession()
    private let sampling = SamplingState()

    /// 预览层要用的会话。相机本身没有别的对外接口，所以直接把它交出去，
    /// 不为这一个用途再包一层。
    @ObservationIgnored var captureSession: AVCaptureSession { camera.session }

    var capturedCount: Int { captures.count }
    var isFull: Bool { captures.count >= Self.faceCount }

    // MARK: - 生命周期

    func start() {
        guard phase != .analysing else { return }
        guard CameraSession.isAvailable else {
            phase = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted { self.beginRunning() } else { self.phase = .denied }
                }
            }
        default:
            phase = .denied
        }
    }

    func stop() {
        camera.stop()
    }

    private func beginRunning() {
        camera.onFrame = { [weak self] buffer in
            self?.handleFrame(buffer)
        }
        // 会话配置失败必须报到界面上。否则表现是"黑屏 + 快门永远点不动"，
        // 用户完全无从判断是卡住了还是坏了。
        camera.onFailure = { [weak self] failure in
            Task { @MainActor [weak self] in
                guard let self, self.phase != .analysing else { return }
                self.phase = .cameraFailed(failure.userMessage)
            }
        }
        camera.start()
        if phase != .analysing { phase = .scanning }
    }

    // MARK: - 取景几何

    /// 当前取景几何。界面画引导框、采样线程取格子，都用这一份，不会对不上。
    var geometry: ScanGeometry {
        ScanGeometry(videoSize: videoSize, viewSize: viewSize)
    }

    /// 界面把视图尺寸报过来。
    ///
    /// 刻意写成方法而不是 `didSet`：`@Observable` 宏会把存储属性改写成计算属性，
    /// 属性观察器在这种改写下的行为不保证。这里一旦失效就是静默的——采样永远
    /// 拿不到几何、快门永远点不动，而编译和测试都不会报错。
    func updateViewSize(_ size: CGSize) {
        guard size != viewSize else { return }
        viewSize = size
        refreshGeometry()
    }

    /// 视图尺寸或画面尺寸变了，重算取景几何推给采样线程。
    ///
    /// 采样在相机队列上跑，拿不到主 actor 的状态，所以几何要**推**过去，
    /// 不能让它回调时现算。
    private func refreshGeometry() {
        guard viewSize.width > 0, viewSize.height > 0, videoSize.width > 0 else {
            sampling.setGeometry(nil)
            return
        }
        sampling.setGeometry(geometry)
    }

    // MARK: - 采样

    private func handleFrame(_ buffer: CVPixelBuffer) {
        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer)
        )
        // 第一帧（以及极少数分辨率变化）顺便把画面尺寸报给界面
        if sampling.takeFrameSizeIfChanged(frameSize) {
            Task { @MainActor [weak self] in self?.updateVideoSize(frameSize) }
        }

        // 采样在相机队列上做（9 格 × 576 个点，开销可忽略），
        // 但节流到约 10Hz 再回主线程——30fps 全推给 SwiftUI 纯属浪费。
        guard let geometry = sampling.nextGeometry(every: 3) else { return }
        guard let samples = Self.sample(buffer, geometry: geometry) else { return }
        Task { @MainActor [weak self] in
            self?.liveSamples = samples
        }
    }

    private func updateVideoSize(_ frameSize: CGSize) {
        guard frameSize.width > 0, frameSize.height > 0 else { return }
        // 应用锁竖屏，预览里看到的画面是竖的；横帧等价于绕中心转过 90°
        videoSize = frameSize.width > frameSize.height
            ? CGSize(width: frameSize.height, height: frameSize.width)
            : frameSize
        refreshGeometry()
    }

    /// 从一帧里取出 9 个采样色。返回 nil 表示这一帧读不出来。
    private static func sample(_ buffer: CVPixelBuffer, geometry: ScanGeometry) -> [LabColor]? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }

        let view = PixelBufferView(
            baseAddress: base.assumingMemoryBound(to: UInt8.self),
            width: width,
            height: height,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
        )
        let guide = geometry.guideRectInFrame(frameSize: CGSize(width: width, height: height))
        return StickerSampler.sampleGrid(view, normalizedGuide: guide)
    }

    // MARK: - 拍摄

    func capture() {
        guard phase == .scanning, let samples = liveSamples, samples.count == 9 else { return }
        let capture = FaceCapture(samples: samples)

        // 同一个面拍两遍是最常见的失误。当场拦下来，比等六个面拍完再报错强得多。
        if let center = capture.center,
           captures.contains(where: {
               ($0.center?.distance(to: center) ?? .infinity) < StickerClassifier.duplicateCenterDistance
           }) {
            duplicateHint = true
            return
        }

        captures.append(capture)
        duplicateHint = false
        if isFull { analyse() }
    }

    /// 撤掉最后拍的那一面
    func retakeLast() {
        guard !captures.isEmpty, phase != .analysing else { return }
        captures.removeLast()
        phase = .scanning
        duplicateHint = false
    }

    /// 六个面全部重拍
    func reset() {
        guard phase != .analysing else { return }
        captures.removeAll()
        phase = .scanning
        duplicateHint = false
    }

    // MARK: - 识别

    private func analyse() {
        phase = .analysing
        let captures = self.captures
        Task { [weak self] in
            // 分类 + 枚举 4⁶ 种朝向：典型几十毫秒，最坏约 0.2 秒，丢到主线程外
            let outcome = await Task.detached(priority: .userInitiated) { () -> ScanOutcome in
                do {
                    let classified = try StickerClassifier.classify(captures)
                    guard let state = FaceletAssembler.assemble(classified.colors) else {
                        return .failed("这六个面拼不出一个真实的魔方。多半是有一格认错了颜色，或者拍到了同一个面——请重拍。")
                    }
                    return .assembled(state)
                } catch let error as ScanError {
                    return .failed(error.userMessage)
                } catch {
                    return .failed("识别失败，请重拍")
                }
            }.value

            guard let self else { return }
            switch outcome {
            case .assembled(let state):
                self.onFinished?(state)
            case .failed(let message):
                self.phase = .failed(message)
            }
        }
    }
}

/// 识别的两种出口。用专门的枚举而不是 `Result<CubeState, String>`——
/// `Result` 的 Failure 必须实现 `Error`，而这里的失败只需要一句给用户看的话。
private enum ScanOutcome {
    case assembled(CubeState)
    case failed(String)
}

/// 采样状态的读写跨了两条线程：相机队列读、主线程写。用一把锁隔开。
///
/// 单独放一个类而不是直接挂在 `ScanModel` 上，是为了不把 `@MainActor` 的约束
/// 带进相机回调——那边是同步的，不能等 actor 跳转。
private final class SamplingState: @unchecked Sendable {

    private let lock = NSLock()
    private var geometry: ScanGeometry?
    private var frameCounter = 0
    private var lastFrameSize: CGSize = .zero

    func setGeometry(_ value: ScanGeometry?) {
        lock.withLock { geometry = value }
    }

    /// 每 `stride` 帧放行一次；返回 nil 表示这一帧跳过
    func nextGeometry(every stride: Int) -> ScanGeometry? {
        lock.withLock {
            frameCounter += 1
            guard frameCounter % stride == 0 else { return nil }
            return geometry
        }
    }

    /// 帧尺寸变化时返回 true（只在变化那一次）
    func takeFrameSizeIfChanged(_ size: CGSize) -> Bool {
        lock.withLock {
            guard size != lastFrameSize else { return false }
            lastFrameSize = size
            return true
        }
    }
}
