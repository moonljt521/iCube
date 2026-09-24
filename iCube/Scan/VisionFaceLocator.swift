import CoreVideo
import CubeScan
import Foundation
import Vision

/// 用 Vision 找到视频画面里“一整面的方形贴纸区”。
///
/// `FaceLocator` 的网格搜索适合魔方正对镜头的情况；用户这段视频里魔方一直斜着转，
/// 最大的方框其实包住了可见的两三个面，采样自然会混色。这里先找画面中的矩形面，
/// 再把这个小矩形交给同一套 `StickerSampler`。
enum VisionFaceLocator {

    static func locateCandidates(
        in buffer: CVPixelBuffer,
        size: Int,
        limit: Int = 3
    ) -> [FaceLocator.LocatedFace] {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.35
        request.minimumSize = 0.035
        request.maximumObservations = 20
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 1.75

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results,
              !observations.isEmpty
        else { return [] }

        let frameWidth = CGFloat(CVPixelBufferGetWidth(buffer))
        let frameHeight = CGFloat(CVPixelBufferGetHeight(buffer))
        let candidates = observations.compactMap { observation -> (CGRect, Float)? in
            let box = topLeftBox(observation.boundingBox)
            let pixelWidth = box.width * frameWidth
            let pixelHeight = box.height * frameHeight
            let aspect = pixelWidth / max(pixelHeight, 1)
            let area = box.width * box.height
            // 最大的候选通常是整颗魔方（多个面），太小的通常是单个贴纸。
            // 单面落在中间这个区间；真实视频中会随远近变化。
            guard area >= 0.012, area <= 0.14,
                  aspect >= 0.45, aspect <= 1.75 else { return nil }
            return (box, observation.confidence)
        }
        .sorted { lhs, rhs in
            let la = lhs.0.width * lhs.0.height
            let ra = rhs.0.width * rhs.0.height
            if abs(la - ra) > 0.01 { return la > ra }
            return lhs.1 > rhs.1
        }

        var result: [FaceLocator.LocatedFace] = []
        for (box, _) in candidates.prefix(limit * 3) {
            let samples = normalizedSamples(
                buffer,
                box: box,
                size: size
            )
            guard let samples else { continue }
            let score = FaceLocator.score(samples)
            result.append(FaceLocator.LocatedFace(samples: samples, guide: box, score: score))
            if result.count == limit { break }
        }
        return result
    }

    /// Vision 使用左下角原点，采样器使用左上角原点。
    private static func topLeftBox(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    private static func normalizedSamples(
        _ buffer: CVPixelBuffer,
        box: CGRect,
        size: Int
    ) -> [LabColor]? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let view = PixelBufferView(
            baseAddress: base.assumingMemoryBound(to: UInt8.self),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
        )
        return StickerSampler.sampleGrid(
            view,
            normalizedGuide: box,
            size: size,
            inset: 0.22,
            samplesPerAxis: FaceLocator.coarseSamplesPerAxis
        )
    }
}
