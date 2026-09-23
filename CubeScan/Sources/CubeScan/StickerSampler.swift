import CoreGraphics
import Foundation

/// 一块 BGRA 像素内存的只读视图。
///
/// 故意不拥有数据：相机回调里锁住 `CVPixelBuffer` 的基址直接传进来，不复制整帧——
/// 1080p 一帧 8MB，实时预览每秒要采好几次。生命周期由调用方在锁的作用域内保证。
public struct PixelBufferView {
    public let baseAddress: UnsafePointer<UInt8>
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int

    public init(baseAddress: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) {
        self.baseAddress = baseAddress
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }
}

/// 从一个像素区域里提取"这一格是什么颜色"。
///
/// 单个贴纸的采样区域里其实混着三种东西：贴纸本身、贴纸之间的黑色塑料缝隙、
/// 以及塑料上的高光。所以不能直接取平均——直接平均会被缝隙拉暗、被高光拉白。
///
/// 做法是**按明度裁掉两端各 20% 再平均**：缝隙在暗端、高光在亮端，两头一裁，
/// 剩下的基本就是贴纸本体。平均在**线性 RGB** 里做（Lab 不是线性空间，
/// 直接对 Lab 求平均会偏），算完再转 Lab。
public enum StickerSampler {

    /// 明度裁尾比例：两端各丢这么多
    public static let trimFraction = 0.2

    /// 每个方向最多取多少个像素。一个格子通常有上百像素见方，
    /// 等距抽 24×24 ≈ 576 个样本已经足够稳，且把排序代价压到可忽略。
    public static let defaultSamplesPerAxis = 24

    /// 取某个矩形区域（归一化坐标 0...1）的代表色。
    /// 区域退化成 0 面积、或整个落在图外时返回 nil。
    public static func sample(
        _ buffer: PixelBufferView,
        normalizedRect rect: CGRect,
        samplesPerAxis: Int = defaultSamplesPerAxis
    ) -> LabColor? {
        guard buffer.width > 0, buffer.height > 0 else { return nil }

        // 归一化 → 像素，并夹到图内
        let minX = Int((rect.minX * CGFloat(buffer.width)).rounded(.down))
        let maxX = Int((rect.maxX * CGFloat(buffer.width)).rounded(.up))
        let minY = Int((rect.minY * CGFloat(buffer.height)).rounded(.down))
        let maxY = Int((rect.maxY * CGFloat(buffer.height)).rounded(.up))
        let x0 = max(0, min(minX, buffer.width - 1))
        let x1 = max(x0 + 1, min(maxX, buffer.width))
        let y0 = max(0, min(minY, buffer.height - 1))
        let y1 = max(y0 + 1, min(maxY, buffer.height))
        guard x1 > x0, y1 > y0 else { return nil }

        // 等距抽样
        let stepX = max(1, (x1 - x0) / max(1, samplesPerAxis))
        let stepY = max(1, (y1 - y0) / max(1, samplesPerAxis))

        var samples: [(luminance: Double, red: Double, green: Double, blue: Double)] = []
        samples.reserveCapacity(samplesPerAxis * samplesPerAxis)
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let offset = y * buffer.bytesPerRow + x * 4
                let r = LabColor.linearize(Double(buffer.baseAddress[offset + 2]) / 255)
                let g = LabColor.linearize(Double(buffer.baseAddress[offset + 1]) / 255)
                let b = LabColor.linearize(Double(buffer.baseAddress[offset]) / 255)
                samples.append((0.2126 * r + 0.7152 * g + 0.0722 * b, r, g, b))
                x += stepX
            }
            y += stepY
        }
        guard !samples.isEmpty else { return nil }

        // 按明度裁尾
        samples.sort { $0.luminance < $1.luminance }
        let drop = Int(Double(samples.count) * trimFraction)
        let kept = samples.count > 2 * drop && drop > 0
            ? Array(samples[drop..<(samples.count - drop)])
            : samples

        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        for sample in kept {
            sum.red += sample.red
            sum.green += sample.green
            sum.blue += sample.blue
        }
        let count = Double(kept.count)
        return LabColor(
            linearRed: sum.red / count,
            green: sum.green / count,
            blue: sum.blue / count
        )
    }

    /// 取 N×N 引导框里的 N² 个代表色，按"正视该面时 row-major"排。
    /// `inset` 是每格向内收缩的比例——贴着格子边缘采会吃到塑料缝隙。
    public static func sampleGrid(
        _ buffer: PixelBufferView,
        normalizedGuide: CGRect,
        size: Int = 3,
        inset: Double = 0.18,
        samplesPerAxis: Int = defaultSamplesPerAxis
    ) -> [LabColor]? {
        var result: [LabColor] = []
        result.reserveCapacity(size * size)
        for index in 0..<(size * size) {
            let rect = cellRect(in: normalizedGuide, index: index, size: size, inset: inset)
            guard let color = sample(buffer, normalizedRect: rect, samplesPerAxis: samplesPerAxis) else {
                return nil
            }
            result.append(color)
        }
        return result
    }

    /// 引导框里第 index 格（row-major）的采样矩形，归一化坐标。
    ///
    /// 两个方向必须**分开算步长**。归一化坐标里 x 和 y 的尺度不一样（帧是 1280×720
    /// 这种非正方形的），引导框在像素上是正方形，落到归一化坐标就成了 0.46×0.82 的
    /// 长方形。这里要是拿 `guide.width` 去走 y 方向，网格会被纵向压扁：引导框越"高"
    /// （竖屏帧越明显），漏采越多——1280×720 的帧上九格只铺满引导框上方 56%，
    /// 最下面一行贴纸从来没被采到过，中间那行的采样还横跨两行贴纸。
    public static func cellRect(in guide: CGRect, index: Int, size: Int = 3, inset: Double = 0.18) -> CGRect {
        let row = index / size
        let col = index % size
        let cellWidth = guide.width / CGFloat(size)
        let cellHeight = guide.height / CGFloat(size)
        let cell = CGRect(
            x: guide.minX + CGFloat(col) * cellWidth,
            y: guide.minY + CGFloat(row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        return cell.insetBy(dx: CGFloat(inset) * cellWidth, dy: CGFloat(inset) * cellHeight)
    }
}
