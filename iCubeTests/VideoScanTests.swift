import CoreVideo
import CubeKit
import CubeScan
import XCTest
@testable import iCube

/// 视频识别的挑帧链路：帧流 → 六个面 → 状态。
///
/// 不真去录一段视频——那既慢又没法钉住具体情形。这里直接造一段**合成的帧序列**
/// （每个面停留几帧、下一面切换），喂给 `FaceCollector`，再走真实的识别。
/// 真正要验证的是"挑得对不对"，抽帧本身（`FrameExtractor`）是 AVFoundation 的活。
final class VideoScanTests: XCTestCase {

    private static func byteRGB(of color: CubeColor) -> (UInt8, UInt8, UInt8) {
        let srgb = StickerClassifier.references[color]!.srgbComponents
        return (
            UInt8((srgb.red * 255).rounded(.toNearestOrAwayFromZero)),
            UInt8((srgb.green * 255).rounded(.toNearestOrAwayFromZero)),
            UInt8((srgb.blue * 255).rounded(.toNearestOrAwayFromZero))
        )
    }

    /// 造一帧：米色背景 + 画面中央一块 N×N 的魔方色。
    ///
    /// 传 `grid: nil` 得到一张**没有魔方**的帧——用来模拟"转到侧面 / 被手挡住"。
    private func makeFrame(grid: [CubeColor]?, size: Int, side: Int = 420) -> CVPixelBuffer? {
        let width = 1280
        let height = 720
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer
        ) == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixel = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                pixel[offset] = 185
                pixel[offset + 1] = 198
                pixel[offset + 2] = 205
                pixel[offset + 3] = 255
            }
        }
        guard let grid else { return buffer }

        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let cell = side / size
        for index in 0..<grid.count {
            let row = index / size
            let col = index % size
            let rgb = Self.byteRGB(of: grid[index])
            let left = originX + col * cell + 2
            let right = originX + (col + 1) * cell - 2
            let top = originY + row * cell + 2
            let bottom = originY + (row + 1) * cell - 2
            for y in top..<bottom {
                for x in left..<right {
                    let offset = y * rowBytes + x * 4
                    pixel[offset] = rgb.2
                    pixel[offset + 1] = rgb.1
                    pixel[offset + 2] = rgb.0
                }
            }
        }
        return buffer
    }

    private func grid(of state: CubeState, face: Face) -> [CubeColor] {
        let size = state.size
        return (0..<(size * size)).map { state.color(at: face, row: $0 / size, col: $0 % size) }
    }

    /// 主链路：六个面各停留 3 帧 → 收集器挑出六个面 → 识别结果与真值一致
    func test_collectorPicksSixFacesAndRecognisesTheState() throws {
        for size in [2, 3] {
            let truth = Scramble.random(size: size, length: 40, seed: 21).initialState
            let collector = FaceCollector(size: size, useVision: false)

            for face in Face.allCases {
                guard let buffer = makeFrame(grid: grid(of: truth, face: face), size: size) else {
                    return XCTFail("\(size) 阶造不出帧")
                }
                // 同一个面连续三帧——模拟用户展示时停留的那一下
                for _ in 0..<3 { collector.feed(buffer) }
            }

            let faces = collector.finish()
            XCTAssertEqual(faces.count, 6, "\(size) 阶应挑出 6 个面，实际 \(faces.count)")

            let outcome = ScanAnalysis.analyse(faces, size: size)
            guard case .assembled(let result) = outcome else {
                if case .failed(let message) = outcome { XCTFail("\(size) 阶识别失败：\(message)") }
                continue
            }
            // 偶数阶只在整体旋转意义下唯一，必须规范化后比
            XCTAssertEqual(result.state.rotationallyCanonical, truth.rotationallyCanonical,
                           "\(size) 阶识别结果与真值不符")
        }
    }

    /// 转到侧面 / 被手挡住的那一帧（画面里没有魔方）不该把当前段打断。
    ///
    /// 否则每挡一下就多收一个面，最后凑出来的六个面里混着重复。
    func test_framesWithoutACubeDoNotBreakTheCurrentFace() throws {
        let truth = Scramble.random(size: 3, length: 40, seed: 33).initialState
        let collector = FaceCollector(size: 3)
        let blank = try XCTUnwrap(makeFrame(grid: nil, size: 3), "造不出空帧")

        for face in Face.allCases {
            guard let buffer = makeFrame(grid: grid(of: truth, face: face), size: 3) else {
                return XCTFail("造不出帧")
            }
            collector.feed(buffer)
            collector.feed(blank)      // 中间挡一下
            collector.feed(buffer)
            collector.feed(buffer)
        }
        XCTAssertEqual(collector.finish().count, 6, "空帧不该多收面，也不该打断当前面")
    }

    /// 只停留一帧的面不算数——那通常是转动途中碰巧接近的一帧
    func test_aFaceShownForOnlyOneFrameIsIgnored() throws {
        let truth = Scramble.random(size: 3, length: 40, seed: 44).initialState
        let collector = FaceCollector(size: 3)
        guard let buffer = makeFrame(grid: grid(of: truth, face: .u), size: 3) else {
            return XCTFail("造不出帧")
        }
        collector.feed(buffer)     // 只出现一帧
        XCTAssertEqual(collector.finish().count, 0, "只停留一帧不该被收成一面")
    }

    func test_shortageMessageNeverShowsNegativeRemainingFaces() {
        let message = VideoScanModel.shortageMessage(found: 9, size: 3)
        XCTAssertFalse(message.contains("还差 -"), "超过 6 个面不能显示负数：\(message)")
        XCTAssertTrue(message.contains("9 段画面"), "应说明超过 6 段无法确定：\(message)")
    }

    /// 同一个面反复展示，只该收一次
    func test_theSameFaceShownTwiceIsCollectedOnce() throws {
        let truth = Scramble.random(size: 3, length: 40, seed: 55).initialState
        let collector = FaceCollector(size: 3)
        let up = grid(of: truth, face: .u)
        let right = grid(of: truth, face: .r)
        guard let upFrame = makeFrame(grid: up, size: 3),
              let rightFrame = makeFrame(grid: right, size: 3)
        else { return XCTFail("造不出帧") }

        for _ in 0..<3 { collector.feed(upFrame) }
        for _ in 0..<3 { collector.feed(rightFrame) }
        for _ in 0..<3 { collector.feed(upFrame) }   // 又把 U 面转回来

        XCTAssertEqual(collector.finish().count, 2, "同一个面展示两次只该收一次")
    }
}
