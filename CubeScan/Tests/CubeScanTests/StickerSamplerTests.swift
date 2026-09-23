import CoreGraphics
import XCTest
@testable import CubeScan

final class StickerSamplerTests: XCTestCase {

    /// 造一张 BGRA 像素图：底色 + 可选的黑色网格线
    private func makeBuffer(
        width: Int,
        height: Int,
        color: (r: UInt8, g: UInt8, b: UInt8),
        gapEvery: Int? = nil,
        gapWidth: Int = 0,
        gapColor: (r: UInt8, g: UInt8, b: UInt8) = (0, 0, 0)
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let onGap = gapEvery.map { step in
                    gapWidth > 0 && (x % step < gapWidth || y % step < gapWidth)
                } ?? false
                let source = onGap ? gapColor : color
                let offset = (y * width + x) * 4
                bytes[offset] = source.b
                bytes[offset + 1] = source.g
                bytes[offset + 2] = source.r
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    private func withView<T>(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        _ body: (PixelBufferView) -> T
    ) -> T {
        bytes.withUnsafeBufferPointer { pointer in
            body(PixelBufferView(
                baseAddress: pointer.baseAddress!,
                width: width,
                height: height,
                bytesPerRow: width * 4
            ))
        }
    }

    func test_solidColorIsSampledExactly() {
        let bytes = makeBuffer(width: 60, height: 60, color: (200, 40, 30))
        let sampled = withView(bytes, width: 60, height: 60) { view in
            StickerSampler.sample(view, normalizedRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        }
        let expected = LabColor(byteRed: 200, green: 40, blue: 30)
        XCTAssertNotNil(sampled)
        XCTAssertEqual(sampled!.distance(to: expected), 0, accuracy: 1.0)
    }

    /// 不做裁尾、直接对全图求平均（对照组）
    private func naiveMean(_ bytes: [UInt8], width: Int, height: Int) -> LabColor {
        var sum = (red: 0.0, green: 0.0, blue: 0.0)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                sum.red += LabColor.linearize(Double(bytes[offset + 2]) / 255)
                sum.green += LabColor.linearize(Double(bytes[offset + 1]) / 255)
                sum.blue += LabColor.linearize(Double(bytes[offset]) / 255)
            }
        }
        let count = Double(width * height)
        return LabColor(linearRed: sum.red / count, green: sum.green / count, blue: sum.blue / count)
    }

    func test_blackGapsDoNotDragTheSampleDown() {
        // 贴纸之间是黑色塑料缝，占采样点的比例大约两成——正好是裁尾的额度。
        // 直接平均会被这些缝拉暗，裁尾之后应该基本不受影响。
        let plain = makeBuffer(width: 90, height: 90, color: (60, 160, 70))
        let gapped = makeBuffer(width: 90, height: 90, color: (60, 160, 70),
                                gapEvery: 10, gapWidth: 1)
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)

        let plainSample = withView(plain, width: 90, height: 90) { StickerSampler.sample($0, normalizedRect: rect) }!
        let gappedSample = withView(gapped, width: 90, height: 90) { StickerSampler.sample($0, normalizedRect: rect) }!
        let naive = naiveMean(gapped, width: 90, height: 90)

        XCTAssertLessThan(gappedSample.distance(to: plainSample), 3,
                          "黑缝把采样色拉偏了：\(plainSample) vs \(gappedSample)")
        // 直接取平均确实明显偏暗——这条确认裁尾不是白做的
        XCTAssertGreaterThan(naive.distance(to: plainSample), 5,
                             "这个用例没造出足够的黑缝，失去意义了：\(naive)")
        XCTAssertLessThan(gappedSample.distance(to: plainSample), naive.distance(to: plainSample) / 3,
                          "裁尾没有比直接平均更好：裁尾 \(gappedSample) / 直接平均 \(naive)")
    }

    func test_specularHighlightDoesNotWashOutTheSample() {
        // 中心一小块高光：裁掉亮端之后主体色应该还在
        var bytes = makeBuffer(width: 90, height: 90, color: (180, 30, 40))
        for y in 40..<50 {
            for x in 40..<50 {
                let offset = (y * 90 + x) * 4
                bytes[offset] = 255
                bytes[offset + 1] = 255
                bytes[offset + 2] = 255
            }
        }
        let sampled = withView(bytes, width: 90, height: 90) {
            StickerSampler.sample($0, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        }!
        let expected = LabColor(byteRed: 180, green: 30, blue: 40)
        XCTAssertLessThan(sampled.distance(to: expected), 10, "高光没被裁掉：\(sampled)")
    }

    func test_outOfBoundsRectIsClampedNotCrashing() {
        let bytes = makeBuffer(width: 40, height: 40, color: (10, 200, 90))
        let sampled = withView(bytes, width: 40, height: 40) { view in
            StickerSampler.sample(view, normalizedRect: CGRect(x: -0.5, y: -0.5, width: 2, height: 2))
        }
        XCTAssertNotNil(sampled)
    }

    func test_zeroSizedBufferReturnsNil() {
        let bytes = [UInt8](repeating: 0, count: 4)
        let sampled = withView(bytes, width: 0, height: 0) { view in
            StickerSampler.sample(view, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertNil(sampled)
    }

    func test_cellRectsTileTheGuideWithoutOverlap() {
        let guide = CGRect(x: 0, y: 0, width: 0.9, height: 0.9)
        var rects: [CGRect] = []
        for index in 0..<9 { rects.append(StickerSampler.cellRect(in: guide, index: index, inset: 0)) }
        // 九格刚好铺满
        let total = rects.reduce(0.0) { $0 + $1.width * $1.height }
        XCTAssertEqual(total, guide.width * guide.height, accuracy: 1e-9)
        for (first, a) in rects.enumerated() {
            for b in rects[(first + 1)...] {
                XCTAssertFalse(a.intersects(b), "格子重叠了")
            }
        }
        XCTAssertEqual(rects[0].origin.x, guide.minX, accuracy: 1e-9)
        XCTAssertEqual(rects[8].maxX, guide.maxX, accuracy: 1e-9)
    }

    func test_cellInsetShrinksTowardsTheCentre() {
        let guide = CGRect(x: 0.1, y: 0.1, width: 0.9, height: 0.9)
        let full = StickerSampler.cellRect(in: guide, index: 4, inset: 0)
        let inset = StickerSampler.cellRect(in: guide, index: 4, inset: 0.2)
        XCTAssertLessThan(inset.width, full.width)
        XCTAssertEqual(inset.midX, full.midX, accuracy: 1e-9)
        XCTAssertEqual(inset.midY, full.midY, accuracy: 1e-9)
    }

    /// 回归：引导框在归一化坐标里**不是正方形**（帧 1280×720，引导框在像素上是正方形）。
    /// 九格必须照样铺满引导框。曾经拿 `guide.width` 去走 y 方向，网格纵向被压扁——
    /// 1280×720 的帧上九格只铺满引导框上方 56%，最下面一行贴纸从来没被采到过。
    func test_cellRectsTileANonSquareGuide() {
        let guide = CGRect(x: 0.2694, y: 0.09, width: 0.4612, height: 0.82)
        var rects: [CGRect] = []
        for index in 0..<9 { rects.append(StickerSampler.cellRect(in: guide, index: index, inset: 0)) }

        let total = rects.reduce(0.0) { $0 + $1.width * $1.height }
        XCTAssertEqual(total, guide.width * guide.height, accuracy: 1e-9, "九格没铺满引导框")
        XCTAssertEqual(rects[0].origin.x, guide.minX, accuracy: 1e-9)
        XCTAssertEqual(rects[0].origin.y, guide.minY, accuracy: 1e-9)
        XCTAssertEqual(rects[8].maxX, guide.maxX, accuracy: 1e-9)
        XCTAssertEqual(rects[8].maxY, guide.maxY, accuracy: 1e-9, "纵向没铺到底")
        for (first, a) in rects.enumerated() {
            for b in rects[(first + 1)...] {
                XCTAssertFalse(a.intersects(b), "格子重叠了")
            }
        }
    }

    /// 端到端回归：真机链路是 `guideRectInFrame` → `sampleGrid`，两边必须落在同一块区域。
    ///
    /// 造一张 1280×720 的帧，在**引导框真正落到的位置**上按手算的三等分画九块纯色，
    /// 采出来的九格要一一对上。图案刻意用独立于 `cellRect` 的算式铺——不然测试和被测
    /// 代码一起错，反而测不出来。
    func test_gridSamplingReadsTheCellsWhereTheGuideActuallyIs() {
        let frame = CGSize(width: 1280, height: 720)
        let geometry = ScanGeometry(videoSize: CGSize(width: 720, height: 1280),
                                    viewSize: CGSize(width: 390, height: 844))
        let guide = geometry.guideRectInFrame(frameSize: frame)

        let width = Int(frame.width)
        let height = Int(frame.height)
        // 底色挑一个和调色板都拉得开的灰，采偏了必然露馅
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            bytes[offset] = 200
            bytes[offset + 1] = 200
            bytes[offset + 2] = 200
            bytes[offset + 3] = 255
        }

        let palette: [(UInt8, UInt8, UInt8)] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255),
            (255, 255, 0), (0, 255, 255), (255, 0, 255),
            (255, 255, 255), (0, 0, 0), (128, 128, 128),
        ]
        // 手算三等分，不借 cellRect
        let x0 = guide.minX * frame.width
        let y0 = guide.minY * frame.height
        let cellWidth = guide.width * frame.width / 3
        let cellHeight = guide.height * frame.height / 3
        for index in 0..<9 {
            let row = index / 3
            let col = index % 3
            let left = Int((x0 + CGFloat(col) * cellWidth).rounded())
            let top = Int((y0 + CGFloat(row) * cellHeight).rounded())
            let right = Int((x0 + CGFloat(col + 1) * cellWidth).rounded())
            let bottom = Int((y0 + CGFloat(row + 1) * cellHeight).rounded())
            for y in top..<bottom {
                for x in left..<right {
                    let offset = (y * width + x) * 4
                    bytes[offset] = palette[index].2
                    bytes[offset + 1] = palette[index].1
                    bytes[offset + 2] = palette[index].0
                }
            }
        }

        let samples = withView(bytes, width: width, height: height) {
            StickerSampler.sampleGrid($0, normalizedGuide: guide)
        }
        XCTAssertNotNil(samples)
        for index in 0..<9 {
            let expected = LabColor(byteRed: palette[index].0, green: palette[index].1, blue: palette[index].2)
            XCTAssertLessThan(samples![index].distance(to: expected), 10,
                              "第 \(index) 格采到的不是它自己那块：\(samples![index]) vs \(expected)")
        }
    }

    func test_gridSamplingReadsNineDistinctCells() {
        // 一张 3×3 拼接图：每格纯色，格与格之间 6 像素黑缝
        let cell = 30
        let gap = 6
        let side = cell * 3 + gap * 4
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let palette: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255), (255, 210, 10), (0, 160, 60),
            (20, 90, 220), (220, 30, 30), (250, 115, 10),
            (255, 255, 255), (0, 160, 60), (20, 90, 220),
        ]
        for index in 0..<9 {
            let row = index / 3
            let col = index % 3
            let x0 = gap + col * (cell + gap)
            let y0 = gap + row * (cell + gap)
            for y in y0..<(y0 + cell) {
                for x in x0..<(x0 + cell) {
                    let offset = (y * side + x) * 4
                    bytes[offset] = palette[index].2
                    bytes[offset + 1] = palette[index].1
                    bytes[offset + 2] = palette[index].0
                    bytes[offset + 3] = 255
                }
            }
        }

        let guide = CGRect(x: 0, y: 0, width: 1, height: 1)
        let samples = withView(bytes, width: side, height: side) {
            StickerSampler.sampleGrid($0, normalizedGuide: guide, inset: 0.12)
        }
        XCTAssertNotNil(samples)
        XCTAssertEqual(samples!.count, 9)
        for index in 0..<9 {
            let expected = LabColor(byteRed: palette[index].0, green: palette[index].1, blue: palette[index].2)
            XCTAssertLessThan(samples![index].distance(to: expected), 10,
                              "第 \(index) 格偏了：\(samples![index]) vs \(expected)")
        }
    }
}
