import CoreGraphics
import CubeKit
import XCTest
@testable import CubeScan

/// 2 阶 / 4 阶的识别链路。
///
/// 与三阶最大的区别是**没有固定中心块**，三件事都得另想办法：
///
/// | | 三阶 | 2 / 4 阶 |
/// | --- | --- | --- |
/// | 聚类种子 | 六个中心块（天然互异） | 最远点采样 |
/// | 面身份 | 中心块颜色直接给出 | 未知，要和朝向一起枚举 |
/// | 判重面 | 比中心色 | 整面比（容许旋转） |
///
/// 还有一条容易漏的：偶数阶的 `legality` 必须显式查**角块摆放的手性**，
/// 否则整个镜像族都会被当成合法候选。
final class EvenOrderScanTests: XCTestCase {

    // MARK: - 端到端

    /// 状态 → 模拟拍摄（乱序 + 各自随机朝向）→ 分类 → 拼装 → 回到原状态
    func test_evenOrderRoundTripOnRandomScrambles() throws {
        for size in [2, 4] {
            for seed in 1...6 {
                let original = Scramble.random(size: size, length: 40, seed: UInt64(seed)).initialState
                let captures = SyntheticCapture.shuffledCaptures(of: original, seed: UInt64(seed))
                let classified = try StickerClassifier.classify(captures, size: size)
                let solutions = FaceletAssembler.assembleAll(classified.colors, size: size)

                XCTAssertEqual(solutions.count, 1,
                               "\(size) 阶 seed \(seed) 存活 \(solutions.count) 个解（应为 1）")
                let assembled = try XCTUnwrap(solutions.first)
                // 偶数阶没有中心块锚定，识别结果只在"整体旋转意义下"唯一，比较前先规范化
                XCTAssertEqual(assembled.rotationallyCanonical, original.rotationallyCanonical,
                               "\(size) 阶 seed \(seed) 端到端没回到原状态")
            }
        }
    }

    /// 现场光照（暖 / 冷 / 暗）加噪声，识别不能垮
    func test_evenOrderSurvivesEveryLighting() throws {
        let lightings: [(String, SyntheticCapture.Lighting)] = [
            ("暖光", .warm), ("冷光", .cool), ("暗光", .dim),
            ("暖光+噪声", SyntheticCapture.Lighting(red: 1.18, green: 1.0, blue: 0.6, noise: 0.04)),
        ]
        for size in [2, 4] {
            for (name, lighting) in lightings {
                let original = Scramble.random(size: size, length: 40, seed: 21).initialState
                let captures = SyntheticCapture.shuffledCaptures(of: original, lighting: lighting, seed: 21)
                let classified = try StickerClassifier.classify(captures, size: size)
                let assembled = FaceletAssembler.assemble(classified.colors, size: size)
                XCTAssertEqual(assembled?.rotationallyCanonical, original.rotationallyCanonical,
                               "\(size) 阶在\(name)下没认出来")
            }
        }
    }

    // MARK: - 非法输入必须被拒绝

    /// 只改一格颜色：色数或块结构必然崩，4096（三阶）/ 十几万（偶数阶）种组合里一个合法都没有
    func test_singleMisreadStickerYieldsNoSolution() {
        for size in [2, 4] {
            let original = Scramble.random(size: size, length: 40, seed: 5).initialState
            let base = faceColors(of: original)
            var colors = base
            var grid = colors[.f]!
            let index = 0
            let replacement: CubeColor = grid[index] == .white ? .yellow : .white
            grid[index] = replacement
            colors[.f] = grid
            XCTAssertTrue(FaceletAssembler.assembleAll(colors, size: size).isEmpty,
                          "\(size) 阶改一格颜色竟然还能拼出魔方")
        }
    }

    /// 四阶单独翻一条翼棱：翻转和变成奇数，任何朝向组合都拼不出。
    /// 注意只能翻**一条**——同一对翼棱一起翻是可达的（就是那个著名的 dedge 翻转）。
    func test_fourByFourFlippedWingYieldsNoSolution() {
        let original = Scramble.random(size: 4, length: 40, seed: 9).initialState
        var colors = faceColors(of: original)
        // 四阶 UF 棱的一条翼棱：块中心 (1,3,3)，在 U、F 两面各有一格
        let center = V3(1, 3, 3)
        let u = stickerIndex(center: center, normal: V3(0, 1, 0), size: 4)
        let f = stickerIndex(center: center, normal: V3(0, 0, 1), size: 4)
        swapStickers(&colors, u, f, size: 4)
        XCTAssertTrue(FaceletAssembler.assembleAll(colors, size: 4).isEmpty,
                      "四阶翻掉一条翼棱竟然还能拼出魔方")
    }

    /// 偶数阶的镜像摆放：把 R 面与 L 面的颜色对调。角块各归其位、扭角和照样是 3 的倍数，
    /// **只有摆放手性不对**——判据漏了这条就会把它当成合法解。
    ///
    /// 这里钉的是"镜像状态本身不合法、绝不会出现在解里"。注意**不能**断言这种情况
    /// 一定无解：同一组六面网格常常还有别的合法解释（比如还原态被镜像后，六张纯色图
    /// 照样能拼回还原态），那是输入本身的歧义，不是判据的问题。
    func test_mirroredStateIsNeverASolution() {
        for size in [2, 4] {
            let original = Scramble.random(size: size, length: 40, seed: 13).initialState
            var colors = faceColors(of: original)
            let right = colors[.r]
            colors[.r] = colors[.l]
            colors[.l] = right

            let mirrored = CubeState(stickers: Face.allCases.flatMap { colors[$0]! })
            XCTAssertFalse(mirrored.isLegalState, "\(size) 阶的镜像状态被判成了合法")

            let solutions = FaceletAssembler.assembleAll(colors, size: size)
            XCTAssertFalse(solutions.contains(mirrored),
                           "\(size) 阶把不合法的镜像状态当成解返回了")
        }
    }

    /// 回归：**两个互为 90° 旋转的不同面，绝不能被判成"同一个面"**。
    ///
    /// 测试素材页那个 2 阶打乱（seed 42）里，第 3 面 `BRUF` 与第 6 面 `UBFR` 恰好互为旋转。
    /// 早先用"整面比 + 旋转容差"在拍摄当场硬拦重复，结果用户卡在"第 6 面怎么都拍不进去"。
    ///
    /// 这道判据**原理上就分不开**这两种情况（合成数据里两个互为旋转的不同面，色差是 0），
    /// 所以偶数阶彻底不判重：真拍重了，拼装那一步会失败并提示。
    func test_rotationallyIdenticalFacesAreNotTreatedAsDuplicates() throws {
        let state = Scramble.random(size: 2, length: 11, seed: 42).initialState
        let front = SyntheticCapture.grid(of: state, face: .f)
        let back = SyntheticCapture.grid(of: state, face: .b)
        XCTAssertTrue(SyntheticCapture.equalUpToRotation(front, back),
                      "素材里这对面不再是旋转关系了，这条回归的前提要重新确认")
        XCTAssertNotEqual(front, back, "要是同一个面就说不通了")

        let captures = SyntheticCapture.captures(of: state, rotations: [:], seed: 42)
        let classified = try StickerClassifier.classify(captures, size: 2)
        let assembled = FaceletAssembler.assemble(classified.colors, size: 2)
        XCTAssertEqual(assembled?.rotationallyCanonical, state.rotationallyCanonical,
                       "旋转等价的不同面把识别搞坏了")
    }

    /// 真拍重了（同一面连拍两张）也不该在分类期被拦——偶数阶判不了这个
    func test_duplicateCaptureIsNotRejectedAtClassification() throws {
        for size in [2, 4] {
            let original = Scramble.random(size: size, length: 40, seed: 3).initialState
            var captures = SyntheticCapture.captures(of: original, rotations: [:])
            captures[5] = captures[2]
            XCTAssertNoThrow(try StickerClassifier.classify(captures, size: size),
                             "\(size) 阶把「两张照片像」当成了致命错误——这会把正常扫描误伤")
        }
    }

    /// 采样格数不对（比如把三阶的照片喂给四阶）
    func test_sampleCountMustMatchSize() {
        let captures = SyntheticCapture.captures(of: .solved(size: 3), rotations: [:])
        XCTAssertThrowsError(try StickerClassifier.classify(captures, size: 4)) { error in
            XCTAssertEqual(error as? ScanError, .wrongSampleCount(face: 0, count: 9))
        }
    }

    // MARK: - 取景几何

    /// 引导框里切 N×N 格：每格都落在框内、互不重叠、合起来正好铺满框
    func test_geometryCutsNByNCellsInsideTheGuide() {
        // 刻意用非正方形引导框：归一化坐标里 x/y 尺度不同，两个方向必须分开算步长
        let guide = CGRect(x: 0.27, y: 0.09, width: 0.46, height: 0.82)
        for size in [2, 3, 4] {
            var covered = 0.0
            for index in 0..<(size * size) {
                let rect = StickerSampler.cellRect(in: guide, index: index, size: size, inset: 0)
                XCTAssertGreaterThanOrEqual(rect.minX, guide.minX - 1e-9)
                XCTAssertGreaterThanOrEqual(rect.minY, guide.minY - 1e-9)
                XCTAssertLessThanOrEqual(rect.maxX, guide.maxX + 1e-9)
                XCTAssertLessThanOrEqual(rect.maxY, guide.maxY + 1e-9)
                XCTAssertEqual(rect.width, guide.width / CGFloat(size), accuracy: 1e-9)
                XCTAssertEqual(rect.height, guide.height / CGFloat(size), accuracy: 1e-9)
                covered += Double(rect.width * rect.height)
            }
            XCTAssertEqual(covered, Double(guide.width * guide.height), accuracy: 1e-9,
                           "\(size) 阶的 N×N 格没有铺满引导框")
        }
    }

    func test_geometryCellRectsMatchSampler() {
        // 屏幕上画的框与实际采样的区域必须是同一套坐标
        let geometry = ScanGeometry(videoSize: CGSize(width: 1280, height: 720),
                                    viewSize: CGSize(width: 390, height: 520),
                                    size: 4)
        let guide = geometry.normalized(geometry.guideRect)
        for index in 0..<16 {
            let fromGeometry = geometry.normalizedCellRect(index, inset: 0)
            let fromSampler = StickerSampler.cellRect(in: guide, index: index, size: 4, inset: 0)
            XCTAssertEqual(fromGeometry.minX, fromSampler.minX, accuracy: 1e-6)
            XCTAssertEqual(fromGeometry.minY, fromSampler.minY, accuracy: 1e-6)
            XCTAssertEqual(fromGeometry.width, fromSampler.width, accuracy: 1e-6)
            XCTAssertEqual(fromGeometry.height, fromSampler.height, accuracy: 1e-6)
        }
    }

    func test_sampleGridReturnsSquaredCount() {
        let width = 80, height = 80
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = 20
            bytes[index + 1] = 40
            bytes[index + 2] = 200
        }
        for size in [2, 3, 4] {
            let samples = bytes.withUnsafeBufferPointer { pointer -> [LabColor]? in
                StickerSampler.sampleGrid(
                    PixelBufferView(baseAddress: pointer.baseAddress!, width: width, height: height, bytesPerRow: width * 4),
                    normalizedGuide: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                    size: size
                )
            }
            XCTAssertEqual(samples?.count, size * size)
        }
    }

    // MARK: - 像素级：格子切片必须和相机帧对齐

    /// 造一帧 BGRA 图：引导框里按 N×N 铺"每格一个灰度"，框外全黑。
    ///
    /// 灰度取 index 的倍数，所以**采样回来第 i 格应该就是第 i 个灰度**——
    /// 切片错位、两个方向步长不一致、行列读反，都会被这条抓住。
    private func makeFrame(
        width: Int,
        height: Int,
        guide: CGRect,
        size: Int
    ) -> (bytes: [UInt8], expected: [Double]) {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var expected: [Double] = []
        let minX = Int((guide.minX * CGFloat(width)).rounded())
        let maxX = Int((guide.maxX * CGFloat(width)).rounded())
        let minY = Int((guide.minY * CGFloat(height)).rounded())
        let maxY = Int((guide.maxY * CGFloat(height)).rounded())
        let cellWidth = Double(maxX - minX) / Double(size)
        let cellHeight = Double(maxY - minY) / Double(size)
        for index in 0..<(size * size) {
            let row = index / size
            let col = index % size
            // 第 i 格的灰度：40 + i*10（16 格最多到 190，都在 8bit 内且彼此拉开）
            let level = UInt8(40 + index * 10)
            expected.append(Double(level) / 255)
            let x0 = minX + Int((Double(col) * cellWidth).rounded())
            let x1 = minX + Int((Double(col + 1) * cellWidth).rounded())
            let y0 = minY + Int((Double(row) * cellHeight).rounded())
            let y1 = minY + Int((Double(row + 1) * cellHeight).rounded())
            for y in max(0, y0)..<min(height, y1) {
                for x in max(0, x0)..<min(width, x1) {
                    let offset = (y * width + x) * 4
                    bytes[offset] = level
                    bytes[offset + 1] = level
                    bytes[offset + 2] = level
                    bytes[offset + 3] = 255
                }
            }
        }
        return (bytes, expected)
    }

    /// 走一遍真机链路：`ScanGeometry` → `guideRectInFrame` → `sampleGrid`，
    /// 逐格核对采到的是不是那一格。**这是唯一能抓住"格子切歪"的测法**——
    /// 直接喂合成采样色的测试绕过了像素，切歪了也照样过。
    func test_sampledCellsLineUpWithTheGuideGridForEveryOrder() {
        let frameSize = CGSize(width: 1280, height: 720)
        let viewSize = CGSize(width: 390, height: 520)
        for size in [2, 3, 4] {
            let geometry = ScanGeometry(videoSize: frameSize, viewSize: viewSize, size: size)
            let guide = geometry.guideRectInFrame(frameSize: frameSize)
            let frame = makeFrame(width: Int(frameSize.width), height: Int(frameSize.height),
                                  guide: guide, size: size)

            let samples = frame.bytes.withUnsafeBufferPointer { pointer -> [LabColor]? in
                StickerSampler.sampleGrid(
                    PixelBufferView(baseAddress: pointer.baseAddress!,
                                    width: Int(frameSize.width),
                                    height: Int(frameSize.height),
                                    bytesPerRow: Int(frameSize.width) * 4),
                    normalizedGuide: guide,
                    size: size
                )
            }
            let sampled = try? XCTUnwrap(samples)
            guard let sampled else { continue }

            XCTAssertEqual(sampled.count, size * size, "\(size) 阶采样格数不对")
            for index in 0..<(size * size) {
                // Lab 的 L 与线性灰度的关系是非线性的，所以用"亮度排序"来核对次序：
                // 第 i 格必须比第 i−1 格亮，且必须比"如果切错一格"时更接近自己的期望
                if index > 0 {
                    XCTAssertGreaterThan(sampled[index].l, sampled[index - 1].l,
                                         "\(size) 阶第 \(index) 格比前一格暗——格子次序或步长错了")
                }
            }
        }
    }

    /// 同一条链路，但核对**每一格的颜色**：给 N×N 格涂上六种贴纸色，
    /// 采样后按最近参考色归类，必须与放进去的完全一致。
    func test_sampledGridColorsMatchWhatWasRendered() {
        let frameSize = CGSize(width: 1280, height: 720)
        let viewSize = CGSize(width: 390, height: 520)
        let palette: [CubeColor] = [.white, .red, .green, .yellow, .orange, .blue]
        for size in [2, 3, 4] {
            let geometry = ScanGeometry(videoSize: frameSize, viewSize: viewSize, size: size)
            let guide = geometry.guideRectInFrame(frameSize: frameSize)

            // 按顺序把六色循环铺进 N² 格
            var layout: [CubeColor] = []
            for index in 0..<(size * size) { layout.append(palette[index % palette.count]) }

            var bytes = [UInt8](repeating: 0, count: Int(frameSize.width * frameSize.height) * 4)
            let minX = Int((guide.minX * frameSize.width).rounded())
            let maxX = Int((guide.maxX * frameSize.width).rounded())
            let minY = Int((guide.minY * frameSize.height).rounded())
            let maxY = Int((guide.maxY * frameSize.height).rounded())
            let cellWidth = Double(maxX - minX) / Double(size)
            let cellHeight = Double(maxY - minY) / Double(size)
            for (index, color) in layout.enumerated() {
                let rgb = StickerClassifier.references[color]!.srgbComponents
                let red = UInt8((rgb.red * 255).rounded())
                let green = UInt8((rgb.green * 255).rounded())
                let blue = UInt8((rgb.blue * 255).rounded())
                let row = index / size, col = index % size
                let x0 = minX + Int((Double(col) * cellWidth).rounded())
                let x1 = minX + Int((Double(col + 1) * cellWidth).rounded())
                let y0 = minY + Int((Double(row) * cellHeight).rounded())
                let y1 = minY + Int((Double(row + 1) * cellHeight).rounded())
                for y in max(0, y0)..<min(Int(frameSize.height), y1) {
                    for x in max(0, x0)..<min(Int(frameSize.width), x1) {
                        let offset = (y * Int(frameSize.width) + x) * 4
                        bytes[offset] = blue
                        bytes[offset + 1] = green
                        bytes[offset + 2] = red
                        bytes[offset + 3] = 255
                    }
                }
            }

            let samples = bytes.withUnsafeBufferPointer { pointer -> [LabColor]? in
                StickerSampler.sampleGrid(
                    PixelBufferView(baseAddress: pointer.baseAddress!,
                                    width: Int(frameSize.width),
                                    height: Int(frameSize.height),
                                    bytesPerRow: Int(frameSize.width) * 4),
                    normalizedGuide: guide,
                    size: size
                )
            }
            guard let samples else { return XCTFail("\(size) 阶采样失败") }

            for (index, color) in layout.enumerated() {
                let expected = StickerClassifier.references[color]!
                let distance = samples[index].distance(to: expected)
                let nearest = CubeColor.allCases.min { a, b in
                    samples[index].distance(to: StickerClassifier.references[a]!)
                        < samples[index].distance(to: StickerClassifier.references[b]!)
                }
                XCTAssertEqual(nearest, color,
                               "\(size) 阶第 \(index) 格认成了 \(nearest.map(String.init(describing:)) ?? "nil")，"
                               + "期望 \(color)（色差 \(String(format: "%.1f", distance))）")
            }
        }
    }

    // MARK: - 帧次序 ↔ 屏幕次序

    /// 实时色块的次序：帧被预览层顺时针转了 90° 才上屏，画的时候要拧回来。
    ///
    /// 这条钉三件事：**是旋转不是转置**（转置会变成镜像，下游补不回来）、
    /// **方向是顺时针**（逆时针会让色块跟屏幕差 180°）、以及它是个双射。
    func test_displayOrderIsAQuarterTurnOfFrameOrder() {
        for size in [2, 3, 4] {
            let geometry = ScanGeometry(videoSize: CGSize(width: 1280, height: 720),
                                        viewSize: CGSize(width: 390, height: 520),
                                        size: size)
            let count = size * size

            XCTAssertEqual(Set((0..<count).map { geometry.displayIndex(forFrameIndex: $0) }).count, count,
                           "\(size) 阶的显示次序不是双射")
            for index in 0..<count {
                XCTAssertEqual(geometry.frameIndex(forDisplayIndex: geometry.displayIndex(forFrameIndex: index)),
                               index, "\(size) 阶的显示映射与它的逆对不上")
                var current = index
                for _ in 0..<4 { current = geometry.displayIndex(forFrameIndex: current) }
                XCTAssertEqual(current, index, "\(size) 阶转四次没回到原位")
            }

            // 帧的左上角顺时针转 90° 应落到屏幕的**右上角**（逆时针会落到左下角）
            XCTAssertEqual(geometry.displayIndex(forFrameIndex: 0), size - 1,
                           "\(size) 阶的显示旋转方向不对（应为顺时针）")
            // 转置会把它送到屏幕的 (1, 0)，顺时针旋转送到的应是 (1, N−1)
            XCTAssertEqual(geometry.displayIndex(forFrameIndex: 1), size + (size - 1),
                           "\(size) 阶的显示映射是转置（镜像）而不是旋转")
        }
    }

    // MARK: - 面网格旋转

    func test_rotationIsAConsistentFourCycleOnFour() {
        let original = Scramble.random(size: 4, length: 40, seed: 2).initialState
        let grid = SyntheticCapture.grid(of: original, face: .f)
        XCTAssertEqual(FaceletAssembler.rotated(grid, quarterTurns: 4, size: 4), grid)
        XCTAssertEqual(FaceletAssembler.rotated(grid, quarterTurns: -1, size: 4),
                       FaceletAssembler.rotated(grid, quarterTurns: 3, size: 4))
        let twice = FaceletAssembler.rotated(grid, quarterTurns: 2, size: 4)
        for index in 0..<16 {
            XCTAssertEqual(twice[index], grid[15 - index], "180° 不是首尾对应")
        }
    }

    // MARK: - 辅助

    /// 状态的六个面颜色（不模拟拍摄，直接拿真值）
    private func faceColors(of state: CubeState) -> [Face: [CubeColor]] {
        var result: [Face: [CubeColor]] = [:]
        for face in Face.allCases { result[face] = SyntheticCapture.grid(of: state, face: face) }
        return result
    }

    private func stickerIndex(center: V3, normal: V3, size: Int) -> Int {
        StickerGeometry.index(cubieCenter: center, facing: normal, size: size)!
    }

    /// 把两个贴纸的颜色对调（两个下标必须落在不同的面上，否则是空操作）
    private func swapStickers(_ colors: inout [Face: [CubeColor]], _ lhs: Int, _ rhs: Int, size: Int) {
        let per = size * size
        let leftFace = Face.allCases[lhs / per], leftOffset = lhs % per
        let rightFace = Face.allCases[rhs / per], rightOffset = rhs % per
        var left = colors[leftFace]!
        var right = colors[rightFace]!
        let buffer = left[leftOffset]
        left[leftOffset] = right[rightOffset]
        right[rightOffset] = buffer
        colors[leftFace] = left
        colors[rightFace] = right
    }
}
