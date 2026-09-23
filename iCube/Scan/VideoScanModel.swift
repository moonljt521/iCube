import AVFoundation
import CubeKit
import CubeScan
import CoreVideo
import Foundation
import Observation

/// 挑帧的参数与逐帧定位。
///
/// 刻意**不**挂在 `VideoScanModel` 上：那个类是 `@MainActor` 的，它的 static 成员
/// 默认也跟着被隔离，后台线程访问不了——而抽帧、定位恰恰都在后台跑。
enum FrameSampling {

    /// 逐格平均色差在这个以内，就认为"画面没动，还是刚才那个面"。
    ///
    /// 魔方静止时连续两帧的采样几乎一样（差 < 3，只有噪声）；一旦开始转，
    /// 一格的颜色会从上一个面的某个色跳到下一个面的某个色，差通常在 15 以上。
    static let stabilityThreshold = 6.0

    /// 一个面至少要连续稳定这么多帧才收。
    ///
    /// 取 2：抽帧间隔大约 0.1 秒，两帧就是 0.2 秒——用户展示一个面不会比这更短，
    /// 但转动过程中的某一帧确实可能碰巧和上一帧接近，多要求一帧能滤掉它。
    static let minStableFrames = 2

    /// 偶数阶判重用的色差阈值。
    ///
    /// 刻意取得比拍照模式的 `duplicateCaptureDistance`（3.0）更严。拍照时判重只是
    /// **提醒**、收不收由用户决定；这里没人看着，判错了就直接少一个面。而且偶数阶
    /// "两个不同的面互为旋转"是家常便饭（二阶第 3 面与第 6 面实测色差 5.2），
    /// 阈值放宽就会把它们合并掉，最后永远凑不满六个。
    static let duplicateThreshold = 2.0

    /// 在一帧里定位魔方并采样。在**锁的作用域内**完成——`PixelBufferView` 不拥有
    /// 数据，解锁后指针就失效了。
    static func locate(in buffer: CVPixelBuffer, size: Int) -> FaceLocator.LocatedFace? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        return FaceLocator.locate(
            PixelBufferView(
                baseAddress: base.assumingMemoryBound(to: UInt8.self),
                width: width,
                height: height,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
            ),
            size: size
        )
    }
}

/// 视频识别：给一段"挨个展示六个面"的视频，自动挑出六个面并识别。
///
/// 与拍照模式的差别**只在六个面从哪来**：那边是用户按六次快门，这边是算法从
/// 帧流里自己挑。挑齐之后共用 `ScanAnalysis`（分类、拼装、歧义处理）。
///
/// ## 怎么从帧流里挑出六个面
///
/// 用户在镜头前转魔方，画面大致是这样：某个面**停一会儿** → 转动（糊）→ 下一个面
/// **停一会儿** → ……。所以判据是"连续几帧读到的颜色几乎没变"：
///
/// ```
/// 帧:  ①   ②   ③   ④   ⑤   ⑥   ⑦   ⑧   ⑨
///      稳  稳  稳  ←转动→  稳  稳  ←转动→  稳
///      └── 一个面 ──┘      └── 一个面 ──┘
/// ```
///
/// 转动中的帧直接丢掉——那时两面的颜色糊在一个格子里，采出来不是任何魔方色，
/// 喂给分类器等于主动喂垃圾。
@MainActor
@Observable
final class VideoScanModel {

    /// 阶数。2/3/4
    let size: Int

    enum Phase: Equatable {
        case idle
        /// 正在抽帧、挑帧
        case extracting
        /// 六个面凑齐了，正在识别
        case analysing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// 已经挑出几个面
    private(set) var foundCount = 0

    @ObservationIgnored var onFinished: ((ScanResult) -> Void)?

    init(size: Int = 3) {
        self.size = size
    }

    // MARK: - 处理

    func process(_ asset: AVAsset) async {
        guard phase != .extracting, phase != .analysing else { return }
        phase = .extracting
        foundCount = 0

        let size = self.size
        let collected = await Task.detached(priority: .userInitiated) { () -> [FaceCapture] in
            let collector = FaceCollector(size: size)
            try? FrameExtractor.extract(asset) { buffer in
                collector.feed(buffer)
            }
            return collector.finish()
        }.value

        foundCount = collected.count
        guard collected.count == ScanModel.faceCount else {
            phase = .failed(Self.shortageMessage(found: collected.count))
            return
        }

        phase = .analysing
        let outcome = await Task.detached(priority: .userInitiated) {
            ScanAnalysis.analyse(collected, size: size)
        }.value

        switch outcome {
        case .assembled(let result):
            onFinished?(result)
        case .failed(let message):
            phase = .failed(message)
        }
    }

    /// 失败后重来：回到可录制/可选择的状态
    func reset() {
        phase = .idle
        foundCount = 0
    }

    /// 没凑够六个面时的提示。要说清"看到了几个"和"下一步怎么办"。
    static func shortageMessage(found: Int) -> String {
        guard found > 0 else {
            return "这段视频里没找到魔方。请让魔方填满画面、避开强反光再录一次。"
        }
        return "只认出 \(found) 个面，还差 \(ScanModel.faceCount - found) 个。"
            + "每个面请停留半秒以上、转的时候慢一点，让魔方始终在画面里。"
    }
}

/// 把帧流聚成"一个一个面"。
///
/// 单独成一个类而不是在闭包里改局部变量：闭包在后台线程里跑，直接捕获并修改
/// 外层变量会撞上 Swift 的并发检查。
final class FaceCollector {

    let size: Int
    private(set) var faces: [FaceCapture] = []
    private var pending: [LabColor]?
    private var stable = 0

    init(size: Int) {
        self.size = size
    }

    func feed(_ buffer: CVPixelBuffer) {
        guard let located = FrameSampling.locate(in: buffer, size: size) else {
            // 这一帧里没找到魔方（可能转到侧面、被手挡住）。
            // 别急着结束当前段——它很可能只是中间卡了一帧。
            return
        }
        if let current = pending,
           FaceLocator.drift(current, located.samples) < FrameSampling.stabilityThreshold {
            stable += 1
            pending = located.samples
        } else {
            commit()
            pending = located.samples
            stable = 1
        }
    }

    /// 视频读完了，把最后一段也收进去
    func finish() -> [FaceCapture] {
        commit()
        return faces
    }

    private func commit() {
        guard stable >= FrameSampling.minStableFrames, let current = pending else {
            pending = nil
            stable = 0
            return
        }
        if !isDuplicate(current) {
            faces.append(FaceCapture(samples: current))
        }
        pending = nil
        stable = 0
    }

    /// 这一面是不是已经收过了。
    ///
    /// 三阶可以比中心块——六个中心块两两互异，这是硬事实。
    /// 偶数阶没有中心块，只能整面比，而"不同的面互为旋转"分不开（见
    /// `FrameSampling.duplicateThreshold` 为什么取得这么严）。
    private func isDuplicate(_ samples: [LabColor]) -> Bool {
        let capture = FaceCapture(samples: samples)
        for existing in faces {
            if let center = capture.center, let other = existing.center {
                if other.distance(to: center) < StickerClassifier.duplicateCenterDistance { return true }
            } else {
                let distance = StickerClassifier.closestRotationDistance(existing.samples, samples)
                if distance < FrameSampling.duplicateThreshold { return true }
            }
        }
        return false
    }
}
