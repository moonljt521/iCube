import AVFoundation
import CoreVideo
import Foundation

/// 从视频里按间隔抽帧。
///
/// ## 为什么不先把帧都取出来
///
/// 一段 10 秒 1080p 的视频有 300 帧，每帧 BGRA 约 8MB——全取出来是 2.4GB，
/// 手机上直接就被 kill 了。所以这里**边抽边回调**：调用方在回调里把这一帧
/// 处理掉（定位 + 采样），只留下 N² 个颜色，帧本身用完就扔。
enum FrameExtractor {

    /// 抽帧失败的原因
    enum Failure: Error {
        /// 视频里没有视频轨（比如误选了一个音频文件）
        case noVideoTrack
        /// AVAssetReader 起不来（文件损坏、格式不支持）
        case cannotRead
    }

    /// 抽帧上限。
    ///
    /// 同一个面在视频里会连续出现好几秒，抽太多帧只是重复——90 帧足够覆盖
    /// "转一圈展示六个面"，再多只是线性增加处理时间。
    static let defaultMaxFrames = 90

    /// 抽帧并对每一帧调用 `body`。
    ///
    /// 回调在**调用方的线程**上同步执行，所以里面可以直接做 CPU 密集的活
    /// （定位、采样）——这个方法本身应该在后台线程调用。
    ///
    /// - Parameters:
    ///   - asset: 视频
    ///   - maxFrames: 最多回调多少帧
    ///   - stride: 每隔几帧取一帧。传 nil 时按 `maxFrames` 自动推算。
    /// - Returns: 实际回调了多少帧
    @discardableResult
    static func extract(
        _ asset: AVAsset,
        maxFrames: Int = defaultMaxFrames,
        stride: Int? = nil,
        body: (CVPixelBuffer) -> Void
    ) throws -> Int {
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw Failure.noVideoTrack
        }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw Failure.cannotRead
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        // 不额外拷贝一份像素数据：回调里会立刻处理掉，留着副本纯属浪费
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw Failure.cannotRead }

        let step = stride ?? Self.suggestedStride(asset: asset, track: track, maxFrames: maxFrames)
        var delivered = 0
        var index = 0
        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer(),
                  let buffer = CMSampleBufferGetImageBuffer(sample)
            else { continue }
            if index % step == 0 {
                body(buffer)
                delivered += 1
                if delivered >= maxFrames { break }
            }
            index += 1
        }
        return delivered
    }

    /// 按视频时长与帧率推算"每隔几帧取一帧"，使总数不超过 `maxFrames`
    static func suggestedStride(asset: AVAsset, track: AVAssetTrack, maxFrames: Int) -> Int {
        let seconds = asset.duration.seconds
        let rate = track.nominalFrameRate
        guard seconds.isFinite, seconds > 0, rate > 0 else { return 1 }
        let total = Int((seconds * Double(rate)).rounded())
        return max(1, total / max(1, maxFrames))
    }
}
