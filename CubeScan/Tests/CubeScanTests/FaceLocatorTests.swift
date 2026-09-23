import CoreGraphics
import CubeKit
import XCTest
@testable import CubeScan

/// 视频识别里"自动对准"这一环。
///
/// 拍照模式不需要它——引导框固定在画面中央，用户自己把魔方填满方框。
/// 视频里魔方会晃、会远近变化，所以要先找到"魔方在哪一格区域"，再采样。
final class FaceLocatorTests: XCTestCase {

    // MARK: - 造帧

    /// 把参考色转成字节 RGB。`LabColor` 存的是 Lab，转成 sRGB 才能往像素里写。
    private func byteRGB(of color: CubeColor) -> (UInt8, UInt8, UInt8) {
        let srgb = StickerClassifier.references[color]!.srgbComponents
        return (
            UInt8((srgb.red * 255).rounded(.toNearestOrAwayFromZero)),
            UInt8((srgb.green * 255).rounded(.toNearestOrAwayFromZero)),
            UInt8((srgb.blue * 255).rounded(.toNearestOrAwayFromZero))
        )
    }

    /// 模拟光照：给颜色乘一组系数（1 = 理想白平衡）。
    ///
    /// 合成数据若直接用参考色，是**理想光照**——真实拍摄从来不是这样，
    /// `StickerClassifier` 里那道白点校正就是为它准备的。不模拟的话，
    /// 测出来的区分度是偏乐观的假象。
    private func tinted(
        _ rgb: (UInt8, UInt8, UInt8),
        by tint: (Double, Double, Double)
    ) -> (UInt8, UInt8, UInt8) {
        func apply(_ value: UInt8, _ factor: Double) -> UInt8 {
            UInt8(min(255, max(0, (Double(value) * factor).rounded(.toNearestOrAwayFromZero))))
        }
        return (apply(rgb.0, tint.0), apply(rgb.1, tint.1), apply(rgb.2, tint.2))
    }

    /// 一帧 BGRA：底色铺满，可选在 `gridRect`（像素坐标）里铺 N×N 个魔方色块。
    ///
    /// 色块之间留黑缝——真魔方有，采样器的裁尾本来就是为它准备的。
    /// `tint` 给**整帧**（含背景）打同一层光照，模拟真实拍摄的色偏。
    private func makeFrame(
        width: Int,
        height: Int,
        background: (UInt8, UInt8, UInt8),
        grid: [CubeColor]? = nil,
        gridRect: CGRect? = nil,
        tint: (Double, Double, Double) = (1, 1, 1)
    ) -> [UInt8] {
        let wall = tinted(background, by: tint)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                bytes[offset] = wall.2
                bytes[offset + 1] = wall.1
                bytes[offset + 2] = wall.0
                bytes[offset + 3] = 255
            }
        }
        guard let grid, let rect = gridRect else { return bytes }
        let size = Int(Double(grid.count).squareRoot().rounded())
        let cellWidth = rect.width / CGFloat(size)
        let cellHeight = rect.height / CGFloat(size)
        for index in 0..<grid.count {
            let row = index / size
            let col = index % size
            let rgb = tinted(byteRGB(of: grid[index]), by: tint)
            let left = Int((rect.minX + CGFloat(col) * cellWidth).rounded()) + 2
            let top = Int((rect.minY + CGFloat(row) * cellHeight).rounded()) + 2
            let right = Int((rect.minX + CGFloat(col + 1) * cellWidth).rounded()) - 2
            let bottom = Int((rect.minY + CGFloat(row + 1) * cellHeight).rounded()) - 2
            for y in max(0, top)..<min(height, bottom) {
                for x in max(0, left)..<min(width, right) {
                    let offset = (y * width + x) * 4
                    bytes[offset] = rgb.2
                    bytes[offset + 1] = rgb.1
                    bytes[offset + 2] = rgb.0
                }
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

    /// 打乱出来的一个面的格子（用真实状态，保证是可达配色）
    private func faceGrid(size: Int, seed: UInt64, face: Face = .u) -> [CubeColor] {
        let state = Scramble.random(size: size, length: 40, seed: seed).initialState
        return (0..<(size * size)).map { state.color(at: face, row: $0 / size, col: $0 % size) }
    }

    private func normalized(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
               width: rect.width / size.width, height: rect.height / size.height)
    }

    /// 交并比：定位准不准就看这个
    private func iou(_ a: CGRect, _ b: CGRect) -> Double {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return 0 }
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let overlap = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - overlap
        return union > 0 ? Double(overlap / union) : 0
    }

    /// 一帧里"最佳框"与"中位数框"的评分，用来量相对判据的区分度。
    private func contrast(_ view: PixelBufferView, size: Int) -> (best: Double, median: Double) {
        var scores: [Double] = []
        for guide in FaceLocator.candidates(frameSize: CGSize(width: view.width, height: view.height)) {
            guard let samples = StickerSampler.sampleGrid(
                view, normalizedGuide: guide, size: size,
                samplesPerAxis: FaceLocator.coarseSamplesPerAxis
            ) else { continue }
            scores.append(FaceLocator.score(samples))
        }
        guard !scores.isEmpty else { return (.nan, .nan) }
        let sorted = scores.sorted()
        return (sorted.last!, sorted[sorted.count / 2])
    }

    // MARK: - 定位

    /// 魔方大小差别很大（手持远近不同），各种尺寸都要框得准。
    /// 框不准就等于格子采到背景，后面全错。
    func test_locateFramesTheCubeAtAnyDistance() {
        let frame = CGSize(width: 1280, height: 720)
        let width = Int(frame.width)
        let height = Int(frame.height)
        let grid = faceGrid(size: 3, seed: 7)

        for side in [280, 372, 500, 620] {
            let pixel = CGRect(x: (frame.width - CGFloat(side)) / 2,
                               y: (frame.height - CGFloat(side)) / 2,
                               width: CGFloat(side), height: CGFloat(side))
            let bytes = makeFrame(width: width, height: height, background: (205, 198, 185),
                                  grid: grid, gridRect: pixel)
            let located = withView(bytes, width: width, height: height) {
                FaceLocator.locate($0, size: 3)
            }
            guard let located else {
                XCTFail("边长 \(side) 的魔方没找到")
                continue
            }
            let value = iou(located.guide, normalized(pixel, in: frame))
            print("[定位] 边长 \(side)：IoU=\(String(format: "%.2f", value))")
            XCTAssertGreaterThan(value, 0.5, "边长 \(side) 框得不准，IoU=\(value)")
        }
    }

    /// 手持会晃，魔方不会永远在正中
    func test_locateToleratesOffCenterCube() {
        let frame = CGSize(width: 1280, height: 720)
        let width = Int(frame.width)
        let height = Int(frame.height)
        let grid = faceGrid(size: 3, seed: 11)
        // 中心偏离画面中心约 (60, −60) 像素，是手持晃动的量级。
        // 再大就超出 `offsetVariants` 的搜索范围了——那种情况用户在取景框里自己会先纠正。
        let pixel = CGRect(x: 490, y: 90, width: 420, height: 420)

        let bytes = makeFrame(width: width, height: height, background: (150, 110, 70),
                              grid: grid, gridRect: pixel)
        let located = withView(bytes, width: width, height: height) {
            FaceLocator.locate($0, size: 3)
        }
        guard let located else { return XCTFail("偏右下的魔方没找到") }
        let value = iou(located.guide, normalized(pixel, in: frame))
        let g = located.guide
        print("[定位] 偏右下：IoU=\(String(format: "%.2f", value))"
              + " 框像素=(\(String(format: "%.0f", g.minX * frame.width)),\(String(format: "%.0f", g.minY * frame.height)) "
              + "\(String(format: "%.0f", g.width * frame.width))x\(String(format: "%.0f", g.height * frame.height)))"
              + " 真值=(\(Int(pixel.minX)),\(Int(pixel.minY)) \(Int(pixel.width))x\(Int(pixel.height)))")
        XCTAssertGreaterThan(value, 0.5, "偏移的魔方框得不准，IoU=\(value)")
    }

    /// 2/4 阶都要能定位
    func test_locateWorksForEverySize() {
        let frame = CGSize(width: 1280, height: 720)
        let width = Int(frame.width)
        let height = Int(frame.height)
        for size in [2, 3, 4] {
            let grid = faceGrid(size: size, seed: 5)
            let side = 420
            let pixel = CGRect(x: (frame.width - CGFloat(side)) / 2,
                               y: (frame.height - CGFloat(side)) / 2,
                               width: CGFloat(side), height: CGFloat(side))
            let bytes = makeFrame(width: width, height: height, background: (90, 90, 95),
                                  grid: grid, gridRect: pixel)
            let located = withView(bytes, width: width, height: height) {
                FaceLocator.locate($0, size: size)
            }
            guard let located else { XCTFail("\(size) 阶没找到"); continue }
            XCTAssertEqual(located.samples.count, size * size, "\(size) 阶采样格数不对")
            let value = iou(located.guide, normalized(pixel, in: frame))
            print("[定位] \(size) 阶：IoU=\(String(format: "%.2f", value))")
            XCTAssertGreaterThan(value, 0.5, "\(size) 阶框得不准，IoU=\(value)")
        }
    }

    // MARK: - 拒绝背景

    /// 画面里没有魔方时必须返回 nil，不能拿一堆背景色去喂分类器。
    ///
    /// 四种光照都测：光照会整体拉低评分，靠绝对阈值是挡不住的（见
    /// `FaceLocator.contrastThreshold` 里为什么用相对判据）。
    func test_locateRejectsUniformBackgroundUnderAnyLight() {
        let width = 1280
        let height = 720
        let walls: [(String, (UInt8, UInt8, UInt8))] = [
            ("米色墙", (205, 198, 185)),
            ("白墙", (250, 250, 250)),
            ("木桌", (150, 110, 70)),
            ("深灰", (80, 80, 80)),
        ]
        let lights: [(String, (Double, Double, Double))] = [
            ("理想光", (1, 1, 1)),
            ("暖光", (1.10, 1.0, 0.78)),
            ("暗光", (0.70, 0.70, 0.72)),
            ("冷光", (0.86, 0.94, 1.18)),
        ]
        for (lightName, tint) in lights {
            for (wallName, wall) in walls {
                let bytes = makeFrame(width: width, height: height, background: wall, tint: tint)
                let located = withView(bytes, width: width, height: height) {
                    FaceLocator.locate($0, size: 3)
                }
                XCTAssertNil(located, "\(lightName) 下的\(wallName)被当成了魔方")
            }
        }
    }

    /// 多样性奖励是白墙场景唯一能救场的信号。
    ///
    /// 白墙离"白"参考色极近，光看距离（不加多样性）时两者的差只有 0.5，
    /// 加了之后拉到十几。
    func test_varietyBonusIsWhatSeparatesCubeFromWhiteWall() {
        let width = 1280
        let height = 720
        let grid = faceGrid(size: 3, seed: 7)
        let pixel = CGRect(x: 454, y: 174, width: 372, height: 372)
        let bytes = makeFrame(width: width, height: height, background: (250, 250, 250),
                              grid: grid, gridRect: pixel)

        // 关掉多样性奖励，模拟"只比距离"的老写法
        let cubeSamples = withView(bytes, width: width, height: height) {
            StickerSampler.sampleGrid($0, normalizedGuide: normalized(pixel, in: CGSize(width: width, height: height)), size: 3)
        }!
        let wallSamples = withView(bytes, width: width, height: height) {
            StickerSampler.sampleGrid($0, normalizedGuide: CGRect(x: 0.02, y: 0.05, width: 0.12, height: 0.21), size: 3)
        }!
        func distanceOnly(_ samples: [LabColor]) -> Double {
            samples.reduce(0.0) { $0 + FaceLocator.distanceToNearestReference($1) } / Double(samples.count)
        }
        let cubeByDistance = distanceOnly(cubeSamples)
        let wallByDistance = distanceOnly(wallSamples)
        let cubeScored = FaceLocator.score(cubeSamples)
        let wallScored = FaceLocator.score(wallSamples)

        print("[白墙] 只比距离：魔方 \(String(format: "%.1f", cubeByDistance)) vs 墙 \(String(format: "%.1f", wallByDistance)) 差 \(String(format: "%.1f", wallByDistance - cubeByDistance))")
        print("[白墙] 加多样性：魔方 \(String(format: "%.1f", cubeScored)) vs 墙 \(String(format: "%.1f", wallScored)) 差 \(String(format: "%.1f", cubeScored - wallScored))")

        // 只比距离时魔方甚至"更差"：魔方里有饱和色，离参考色反而不如纯白墙近。
        // 加了多样性奖励之后，区分度必须反过来变成魔方明显更好。
        XCTAssertGreaterThan(cubeScored - wallScored, 0,
                             "加了多样性奖励，魔方仍然没能比白墙得分高")
        XCTAssertGreaterThan(cubeScored - wallScored, cubeByDistance - wallByDistance,
                             "多样性奖励没有提升区分度")
    }

    /// 相对判据免疫光照：有魔方时的对比度在四种光照下都明显大于 0
    func test_contrastIsImmuneToLighting() {
        let width = 1280
        let height = 720
        let grid = faceGrid(size: 3, seed: 7)
        let pixel = CGRect(x: 454, y: 174, width: 372, height: 372)
        let lights: [(String, (Double, Double, Double))] = [
            ("理想光", (1, 1, 1)),
            ("暖光", (1.10, 1.0, 0.78)),
            ("暗光", (0.70, 0.70, 0.72)),
            ("冷光", (0.86, 0.94, 1.18)),
        ]
        for (name, tint) in lights {
            let bytes = makeFrame(width: width, height: height, background: (205, 198, 185),
                                  grid: grid, gridRect: pixel, tint: tint)
            let measured = withView(bytes, width: width, height: height) { contrast($0, size: 3) }
            let gap = measured.best - measured.median
            print("[对比度] \(name)：\(String(format: "%.1f", gap))")
            XCTAssertGreaterThan(gap, FaceLocator.contrastThreshold,
                                 "\(name) 下对比度只有 \(gap)，会把正常帧当背景丢掉")
        }
    }

    // MARK: - 帧间漂移

    /// 转动中的帧是糊的，必须能靠 `drift` 认出来
    func test_driftDetectsChange() {
        let a = faceGrid(size: 3, seed: 3).map { StickerClassifier.references[$0]! }
        let same = a
        var different = a
        different[0] = StickerClassifier.references[.red]!
        XCTAssertEqual(FaceLocator.drift(a, same), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(FaceLocator.drift(a, different), 0)
        XCTAssertEqual(FaceLocator.drift(a, Array(a.dropLast())), .infinity, "格数不同应视为完全不同")
    }
}
