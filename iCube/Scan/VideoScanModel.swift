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
        locateCandidates(in: buffer, size: size, limit: 1).first
    }

    static func locateCandidatesWithoutVision(
        in buffer: CVPixelBuffer,
        size: Int,
        limit: Int
    ) -> [FaceLocator.LocatedFace] {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        return FaceLocator.locateCandidates(
            PixelBufferView(baseAddress: base.assumingMemoryBound(to: UInt8.self), width: width,
                            height: height, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)),
            size: size, limit: limit
        )
    }

    static func locateCandidates(
        in buffer: CVPixelBuffer,
        size: Int,
        limit: Int
    ) -> [FaceLocator.LocatedFace] {
        // 先尝试透视画面中的单面矩形；这一步专门处理“魔方斜着转”的视频。
        // 失败时退回原来的中心正方形搜索，拍摄正对镜头的素材仍走老路径。
        let vision = VisionFaceLocator.locateCandidates(in: buffer, size: size, limit: limit)
        if !vision.isEmpty { return vision }

        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        return FaceLocator.locateCandidates(
            PixelBufferView(
                baseAddress: base.assumingMemoryBound(to: UInt8.self),
                width: width,
                height: height,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
            ),
            size: size,
            limit: limit
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
    /// 失败也回调到外面，不然用户关掉识别页就什么都看不到了——
    /// 4 阶偶数阶识别成功率本身就比奇数阶低，必须把失败带到录入页让用户看到
    @ObservationIgnored var onFailed: ((String) -> Void)?

    init(size: Int = 3) {
        self.size = size
    }

    // MARK: - 处理

    func process(_ asset: AVAsset) async {
        guard phase != .extracting, phase != .analysing else { return }
        phase = .extracting
        foundCount = 0

        let size = self.size
        let faces = await Task.detached(priority: .userInitiated) { () -> [FaceCapture] in
            let collector = FaceCollector(size: size)
            try? FrameExtractor.extract(asset) { buffer in
                collector.feed(buffer)
            }
            return collector.finish()
        }.value

        foundCount = faces.count
        guard faces.count == ScanModel.faceCount else {
            let message = Self.shortageMessage(found: faces.count, size: size)
            phase = .failed(message)
            onFailed?(message)
            return
        }

        phase = .analysing
        let outcome = await Task.detached(priority: .userInitiated) {
            ScanAnalysis.analyse(faces, size: size)
        }.value

        if case .failed(var message) = outcome {
            // 拼不出来时提醒一句阶数——拿错阶数是最常见的原因，
            // 而它在这条链路上不会报任何专门的错，只会静默采出一堆错颜色
            message += Self.sizeReminder(size: size)
            phase = .failed(message)
            onFailed?(message)
            return
        }
        if case .assembled(let result) = outcome {
            onFinished?(result)
        }
    }

    /// 失败后重来：回到可录制/可选择的状态
    func reset() {
        phase = .idle
        foundCount = 0
    }

    /// 提醒一句阶数。
    ///
    /// 拿三阶在四阶页面录是最常见的错法，而它在这条链路上**不会报任何专门的错**——
    /// 只会静默采出一堆错颜色、评分全面崩掉（实测 −15 到 −20，正常 −5 到 0），
    /// 最后攒出一堆拼不出的面。用户看到"认不出来"根本想不到是拿错了魔方。
    ///
    /// 试过自动探测画面里是几阶（数贴纸之间的黑缝），**实测不可靠**：真实视频里
    /// 魔方是斜的、手指会挡、暗色贴纸和阴影也会被数成缝，拿三阶的视频去探会得出
    /// 2 阶——误报比不报更糟，所以改成在这里明确提醒用户自己核一下。
    nonisolated static func sizeReminder(size: Int) -> String {
        " 如果手上的魔方不是 \(size) 阶，请先到练习页切换阶数。"
    }

    /// 没凑够六个面时的提示。要说清"看到了几个"和"下一步怎么办"。
    nonisolated static func shortageMessage(found: Int, size: Int) -> String {
        guard found > 0 else {
            return "这段视频里没找到魔方。请让魔方填满画面、避开强反光再录一次。"
                + sizeReminder(size: size)
        }
        if found > ScanModel.faceCount {
            return "这段视频里找到了 \(found) 段画面，但无法确定哪 6 段分别对应六个面。"
                + "请让每个面正对镜头停一秒，转动时慢一点，避免同时露出多个面。"
                + sizeReminder(size: size)
        }
        return "只认出 \(found) 个面，还差 \(ScanModel.faceCount - found) 个。"
            + "每个面请正对镜头停一秒、转的时候慢一点，手指别挡住贴纸。"
            + sizeReminder(size: size)
    }
}

/// 把帧流压缩成六个代表面。
///
/// ## 为什么不用“连续稳定帧”或 k-means
///
/// 连续稳定帧对停留时间极敏感：真实视频里会收出 13 个假段，或者只剩 4 个。
/// k-means 也不适合这里：视频展示的是连续旋转，帧不是天然的 6 个球状簇，
/// 迭代后会把多个面吞进同一簇，或留下重复中心。
///
/// 现在只做一件更稳的事：从**清晰帧**里用 farthest-point sampling 选 6 个彼此
/// 不相似的代表。相似度同时看两件事：
///
/// 1. **颜色组成**（这一帧里有多少白/黄/绿/蓝/红/橙），不受面内旋转影响；
/// 2. **格子颜色**（同一面转 90° 仍允许旋转匹配）。
///
/// 旧版只看格子逐格 Lab 距离，手持转动导致同一个面透视/旋转后会被当成新面，
/// 于是用户截图里的 6.68 秒视频被收成 9~13 个“面”。新版不再强行凑 6 个：
/// 如果候选之间没有足够差异，就返回少于 6 个并明确提示视频没有提供六个不同面。
final class FaceCollector {

    let size: Int
    /// 测试可关闭 Vision，生产默认开启。纯色合成帧没有真实的透视矩形，
    /// 直接走原始网格定位更适合它。
    let useVision: Bool
    /// 每个时间位置保留多个候选框；不能只保留单一“最佳框”。
    private var observations: [[FaceLocator.LocatedFace]] = []

    init(size: Int, useVision: Bool = true) {
        self.size = size
        self.useVision = useVision
    }

    func feed(_ buffer: CVPixelBuffer) {
        let candidates = useVision
            ? FrameSampling.locateCandidates(in: buffer, size: size, limit: size >= 4 ? 3 : 3)
            : FrameSampling.locateCandidatesWithoutVision(in: buffer, size: size, limit: size >= 4 ? 3 : 3)
        guard !candidates.isEmpty else { return }
        observations.append(candidates)
    }

    func finish() -> [FaceCapture] {
        guard observations.count >= 6 else { return [] }

        // 先按时间切成六段：用户的约定是“挨个展示六个面”，时间顺序比颜色
        // 更可靠。每段留下几个候选，再用合法性反选，避免某一帧的错误框把整段带偏。
        if let legal = chooseLegalCombination() {
            return legal
        }

        // 合法性反选失败时，不再强行凑六个。只返回外观上足够不同的代表，
        // 让上层显示真实的“找到了几段/但无法拼装”，而不是伪造一个状态。
        let best = observations.compactMap(\.first)
        let representatives = selectRepresentatives(from: best, count: 6)
        return representatives.map { FaceCapture(samples: $0.samples) }
    }

    /// 每段取前几个候选，枚举组合；找到能拼成真实魔方的组合就停止。
    ///
    /// 3 阶最多 4⁶=4096 组，4 阶最多 2⁶=64 组。这个工作在后台线程，且只在
    /// 视频结束后做一次，比把所有帧喂给分类器便宜得多。
    private func chooseLegalCombination() -> [FaceCapture]? {
        let bins = 6
        let limit = size >= 4 ? 3 : 3
        var choices: [[[LabColor]]] = []
        choices.reserveCapacity(bins)
        for bin in 0..<bins {
            let lo = bin * observations.count / bins
            let hi = max(lo + 1, (bin + 1) * observations.count / bins)
            let candidates = observations[lo..<min(hi, observations.count)]
                .flatMap { $0 }
                .sorted { $0.score > $1.score }
            var unique: [[LabColor]] = []
            for candidate in candidates {
                guard unique.count < limit else { break }
                let duplicate = unique.contains { StickerClassifier.closestRotationDistance($0, candidate.samples) < 2 }
                if !duplicate { unique.append(candidate.samples) }
            }
            guard !unique.isEmpty else { return nil }
            choices.append(unique)
        }

        var selected: [[LabColor]] = []
        func search(_ bin: Int) -> [FaceCapture]? {
            if bin == choices.count {
                let captures = selected.map(FaceCapture.init(samples:))
                guard let classified = try? StickerClassifier.classify(captures, size: size) else { return nil }
                guard !FaceletAssembler.assembleAll(classified.colors, size: size).isEmpty else { return nil }
                return captures
            }
            for candidate in choices[bin] {
                selected.append(candidate)
                if let answer = search(bin + 1) { return answer }
                selected.removeLast()
            }
            return nil
        }
        return search(0)
    }

    /// 颜色组成签名：按最近参考色计数，再归一化到 0...1。
    private func composition(_ samples: [LabColor]) -> [Double] {
        var counts = Array(repeating: 0.0, count: 6)
        for sample in samples {
            let color = FaceLocator.nearestReference(sample).0
            counts[color.rawValue] += 1
        }
        let total = Double(samples.count)
        return counts.map { $0 / total }
    }

    /// 两帧的外观距离。0 表示颜色组成一样；越大越可能是不同面。
    private func appearanceDistance(_ lhs: [LabColor], _ rhs: [LabColor]) -> Double {
        guard lhs.count == rhs.count else { return .infinity }
        let left = composition(lhs)
        let right = composition(rhs)
        var compositionDistance = 0.0
        for index in left.indices { compositionDistance += abs(left[index] - right[index]) }
        compositionDistance /= 2
        let gridDistance = StickerClassifier.closestRotationDistance(lhs, rhs)
        return compositionDistance * 40 + min(gridDistance, 20) * 0.15
    }

    private func selectRepresentatives(
        from pool: [FaceLocator.LocatedFace], count: Int
    ) -> [FaceLocator.LocatedFace] {
        guard let first = pool.first else { return [] }
        var selected = [first]
        var selectedIndexes: Set<Int> = [0]
        while selected.count < count {
            var bestIndex: Int?
            var bestDistance = -Double.infinity
            for index in pool.indices where !selectedIndexes.contains(index) {
                let distance = selected.map { appearanceDistance(pool[index].samples, $0.samples) }.min() ?? .infinity
                guard distance >= Self.minimumDistinctDistance else { continue }
                let tieBreak = pool[index].score * 0.001
                if distance + tieBreak > bestDistance {
                    bestDistance = distance + tieBreak
                    bestIndex = index
                }
            }
            guard let index = bestIndex else { break }
            selectedIndexes.insert(index)
            selected.append(pool[index])
        }
        return selected
    }

    static let minimumDistinctDistance = 1.0
}