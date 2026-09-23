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
///
/// 阶数由调用方按全局设置传进来：引导框切 N×N 格、每面采 N² 个点、
/// 拼装时要不要枚举面身份，全都跟着它走。
@MainActor
@Observable
final class ScanModel {

    /// 六个面（2/3/4 阶都一样）
    static let faceCount = 6

    /// 阶数。2/3/4
    let size: Int

    /// 一面有多少格
    var cellCount: Int { size * size }

    init(size: Int = 3) {
        self.size = size
    }

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
    /// 当前帧的 N² 格采样，**相机帧的次序**（row-major）。
    ///
    /// 界面不要直接索引它——帧是横的、屏幕是竖的，两者差 90°。要画就用
    /// `liveSamplesOnScreen` / `captureSamplesOnScreen(at:)`，那两个已经拧到屏幕次序了。
    private var liveSamples: [LabColor]?
    /// 已拍的面
    private(set) var captures: [FaceCapture] = []
    /// 拍到重复面时的提示；下一次拍成功、或者重拍/清空时清掉。
    ///
    /// 带上是和第几面撞的、差多少——只说"拍过了"没法区分"屏幕没翻页"和
    /// "取景偏了采到背景"，这两种要采取的行动完全不同。
    private(set) var duplicateHint: String?
    /// 显示朝向下的画面尺寸（竖），界面靠它算引导框
    private(set) var videoSize: CGSize = .zero
    /// 界面回填的视图尺寸
    private(set) var viewSize: CGSize = .zero

    /// 识别成功后的回调：拿到拼好的状态，交给录入页复核。
    ///
    /// 第二个参数是**把握度不够时的提醒**，够有把握时为 nil。刻意只提醒不拦截：
    /// 把握度低只说明有格子骑在两个颜色中间，结果仍可能是对的，而回录入手改一格的
    /// 成本远低于重拍六个面——判断权交给人。
    @ObservationIgnored var onFinished: ((ScanResult) -> Void)?

    /// 一次识别的结果
    struct ScanResult {
        /// 首选状态
        let state: CubeState
        /// 全部候选（只差整体旋转的已归并）。三阶恒为 1 个；
        /// **偶数阶可能多于 1 个**——两个不同的面互为旋转时，照片分不出谁是谁。
        let candidates: [CubeState]
        /// 给用户看的一句提醒（把握度不够 / 有多解），没有则为 nil
        let hint: String?
    }

    private let camera = CameraSession()
    private let sampling = SamplingState()

    /// 预览层要用的会话。相机本身没有别的对外接口，所以直接把它交出去，
    /// 不为这一个用途再包一层。
    @ObservationIgnored var captureSession: AVCaptureSession { camera.session }

    var capturedCount: Int { captures.count }
    var isFull: Bool { captures.count >= Self.faceCount }

    // MARK: - 给界面看的采样色（已拧到屏幕次序）

    /// 当前帧有没有读到东西（快门能不能按）
    var hasLiveSamples: Bool { liveSamples != nil }

    /// 实时采样，已按**屏幕次序**排好，界面直接照着画
    var liveSamplesOnScreen: [LabColor]? {
        liveSamples.map { Self.reorderedForDisplay($0, size: size) }
    }

    /// 第 `index` 个已拍面的采样，已按**屏幕次序**排好
    func captureSamplesOnScreen(at index: Int) -> [LabColor]? {
        guard captures.indices.contains(index) else { return nil }
        return Self.reorderedForDisplay(captures[index].samples, size: size)
    }

    /// 把**相机帧**次序的采样重排成**屏幕**次序。
    ///
    /// 帧是横的、屏幕是竖的，预览层把画面**顺时针转了 90°**才上屏。界面凡是画采样色的地方
    /// 都要过这一道：取景框上压的实时色块、下面那排已拍缩略图——**漏了哪一处，哪一处就会
    /// 跟用户看到的贴纸差 90°**（缩略图漏过一次，表现是"拍完缩略图是转的"）。
    ///
    /// **只用于显示**：分类器吃的仍是帧的次序。帧的次序与屏幕次序是"旋转"关系，
    /// `FaceletAssembler` 枚举 4 种朝向能消化；一旦把采样顺序也改了，关系就变成"转置"
    /// （镜像），下游再也补不回来。
    static func reorderedForDisplay(_ samples: [LabColor], size: Int) -> [LabColor] {
        guard samples.count == size * size else { return samples }
        return (0..<samples.count).map { samples[ScanGeometry.frameIndex(forDisplayIndex: $0, size: size)] }
    }

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
        ScanGeometry(videoSize: videoSize, viewSize: viewSize, size: size)
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

        // 采样在相机队列上做（N² 格 × 576 个点，开销可忽略），
        // 但节流到约 10Hz 再回主线程——30fps 全推给 SwiftUI 纯属浪费。
        guard let geometry = sampling.nextGeometry(every: 3) else { return }
        guard let samples = sample(buffer, geometry: geometry) else { return }
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

    /// 从一帧里取出 N² 个采样色。返回 nil 表示这一帧读不出来。
    private func sample(_ buffer: CVPixelBuffer, geometry: ScanGeometry) -> [LabColor]? {
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
        return StickerSampler.sampleGrid(view, normalizedGuide: guide, size: size)
    }

    // MARK: - 拍摄

    func capture() {
        guard phase == .scanning, let samples = liveSamples, samples.count == cellCount else { return }
        let capture = FaceCapture(samples: samples)

        // 同一个面拍两遍是最常见的失误。当场拦下来，比等六个面拍完再报错强得多。
        //
        // **但只有奇数阶拦得起**：三阶的中心块两两互异，比中心色是硬事实，判错不了。
        // 偶数阶没有中心块，只能整面比，而"两个不同的面互为 90° 旋转"是家常便饭——
        // 二阶一面只有 4 格，实测第 3 面（BRUF）与第 6 面（UBFR）就完全互为旋转。
        // 拿这种判据硬拦，会把一次正常的扫描卡死在"拍不到第 6 个面"，所以偶数阶**只提醒不拦**：
        // 真拍重了，最后拼装也会失败并提示"或者拍到了同一个面"，代价只是白拍几张。
        if let center = capture.center {
            if let hint = duplicateCenterHint(for: center) {
                duplicateHint = hint
                return
            }
            captures.append(capture)
            duplicateHint = nil
        } else {
            // 先跟**已拍的那些**比，再把自己收进去——顺序反了就会拿自己跟自己比，
            // 距离恒为 0，于是每拍一张都弹"和第 N 面很像（色差 0.0）"。
            let hint = similarFaceHint(for: capture)
            captures.append(capture)
            duplicateHint = hint
        }
        if isFull { analyse() }
    }

    /// 中心色和第几面撞了；没撞返回 nil（奇数阶）
    private func duplicateCenterHint(for center: LabColor) -> String? {
        for (index, existing) in captures.enumerated() {
            guard let other = existing.center else { continue }
            let distance = other.distance(to: center)
            if distance < StickerClassifier.duplicateCenterDistance {
                return "中心色和第 \(index + 1) 面几乎一样（差 \(String(format: "%.1f", distance))）"
            }
        }
        return nil
    }

    /// 整面跟第几面很像；不像返回 nil（偶数阶，**只提醒不拦**）
    private func similarFaceHint(for capture: FaceCapture) -> String? {
        for (index, existing) in captures.enumerated() {
            let distance = StickerClassifier.closestRotationDistance(existing.samples, capture.samples)
            if distance < StickerClassifier.duplicateCaptureDistance {
                return "和第 \(index + 1) 面很像（平均色差 \(String(format: "%.1f", distance))）"
                    + "——若确实是同一个面，请重拍这一张"
            }
        }
        return nil
    }

    /// 撤掉最后拍的那一面
    func retakeLast() {
        guard !captures.isEmpty, phase != .analysing else { return }
        captures.removeLast()
        phase = .scanning
        duplicateHint = nil
    }

    /// 六个面全部重拍
    func reset() {
        guard phase != .analysing else { return }
        captures.removeAll()
        phase = .scanning
        duplicateHint = nil
    }

    // MARK: - 识别

    private func analyse() {
        phase = .analysing
        let captures = self.captures
        let size = self.size
        Task { [weak self] in
            // 分类 + 枚举朝向：三阶是 4⁶ 种（几十毫秒），偶数阶还要枚举面身份
            // （十几万种，实测四阶 0.15 秒），一律丢到主线程外
            let outcome = await Task.detached(priority: .userInitiated) { () -> ScanOutcome in
                do {
                    let classified = try StickerClassifier.classify(captures, size: size)
                    let solutions = FaceletAssembler.assembleAll(classified.colors, size: size)
                    guard let first = solutions.first else {
                        return .failed(Self.assemblyFailureMessage(colors: classified.colors, size: size))
                    }
                    // 多于一个解不是错误：偶数阶没有中心块，两个不同的面互为旋转时，
                    // "哪张照片是哪个面"就真的分不出来（实测二阶约一成状态如此，而且
                    // 每个候选都是真能拧出来的状态）。把候选交给用户挑，别替他赌。
                    return .assembled(first, candidates: solutions.sorted { $0.stickers.map(\.rawValue).lexicographicallyPrecedes($1.stickers.map(\.rawValue)) },
                                      margin: classified.margin)
                } catch let error as ScanError {
                    return .failed(error.userMessage)
                } catch {
                    return .failed("识别失败，请重拍")
                }
            }.value

            guard let self else { return }
            switch outcome {
            case .assembled(let state, let candidates, let margin):
                let hint = Self.ambiguityHint(count: candidates.count) ?? Self.confidenceHint(margin: margin)
                self.onFinished?(ScanResult(state: state, candidates: candidates, hint: hint))
            case .failed(let message):
                self.phase = .failed(message)
            }
        }
    }

    /// 拼不出来时尽量说清"哪里不对"。
    ///
    /// 最有用的是**色数**：任何合法魔方每色恒 N² 格。少了说明有面没拍到或拍重了，
    /// 多了说明有格子认错——这两种的下一步动作完全不同（一个重拍、一个改一格），
    /// 只丢一句"拼不出"用户不知道从哪下手。
    /// 只做纯计算，所以标 `nonisolated`——它要在后台线程里被调用（识别就在那儿跑）。
    nonisolated static func assemblyFailureMessage(colors: [Face: [CubeColor]], size: Int) -> String {
        var counts: [CubeColor: Int] = [:]
        for grid in colors.values {
            for color in grid { counts[color, default: 0] += 1 }
        }
        let expected = size * size
        let off = CubeColor.allCases.compactMap { color -> String? in
            let count = counts[color] ?? 0
            guard count != expected else { return nil }
            return "\(color.displayName) \(count) 格"
        }
        guard !off.isEmpty else {
            return "这六个面拼不出一个真实的魔方。颜色数看着都对，那多半是格子认错了或者有面拍重了——请重拍。"
        }
        return "这六个面拼不出一个真实的魔方：\(off.joined(separator: "、"))，本该每色 \(expected) 格。"
            + "多半是有一面拍重了或没拍全——请重拍。"
    }

    /// 候选多于一个时给一句提醒；只有一个返回 nil。
    /// 文案要说清"为什么"和"怎么办"：用户得知道这不是识别坏了，而是照片里真的缺这个信息，
    /// 以及下一步该做什么（对照魔方核对，不对就换拼法）。
    static func ambiguityHint(count: Int) -> String? {
        guard count > 1 else { return nil }
        return "这个状态有 \(count) 种拼法（有两个面互为旋转，光看照片分不出来）。"
            + "请对照手上的魔方核对，不对就按下面的「换拼法」。"
    }

    /// 把握度不够时给一句提醒；够有把握返回 nil。
    ///
    /// 文案要说清"哪里可能不对、该怎么办"——只说"把握不大"用户不知道下一步做什么。
    /// 非 private 是为了让测试能直接钉住阈值边界。
    static func confidenceHint(margin: Double) -> String? {
        guard margin < ClassifiedFaces.lowConfidenceThreshold else { return nil }
        return "识别把握不大（把握度 \(String(format: "%.1f", margin))）。"
            + "反光或光线不均时容易有格子认错，建议对照展开图核一遍，不对就改一格或重拍。"
    }
}

/// 识别的两种出口。用专门的枚举而不是 `Result<CubeState, String>`——
/// `Result` 的 Failure 必须实现 `Error`，而这里的失败只需要一句给用户看的话。
private enum ScanOutcome {
    /// 成功。`candidates` 里可能不止一个（偶数阶的拼法歧义）；
    /// `margin` 是 `ClassifiedFaces.margin`，应用层靠它决定要不要提醒用户复核。
    case assembled(CubeState, candidates: [CubeState], margin: Double)
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
