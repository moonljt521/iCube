import CoreGraphics
import XCTest
@testable import CubeScan

final class ScanGeometryTests: XCTestCase {

    func test_videoRectLetterboxesAWideVideoInATallView() {
        // 1920×1080 的视频放进 400×800 的竖屏视图：等比缩到宽 400，高 225，上下留黑边
        let rect = ScanGeometry.fit(
            videoSize: CGSize(width: 1920, height: 1080),
            into: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(rect.width, 400, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 225, accuracy: 1e-9)
        XCTAssertEqual(rect.midX, 200, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, 400, accuracy: 1e-9)
    }

    func test_videoRectLetterboxesATallVideoInAWideView() {
        let rect = ScanGeometry.fit(
            videoSize: CGSize(width: 1080, height: 1920),
            into: CGSize(width: 800, height: 400)
        )
        XCTAssertEqual(rect.height, 400, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 225, accuracy: 1e-9)
        XCTAssertEqual(rect.midX, 400, accuracy: 1e-9)
    }

    func test_degenerateSizesDoNotProduceNaN() {
        let zeroVideo = ScanGeometry(videoSize: .zero, viewSize: CGSize(width: 100, height: 100))
        XCTAssertFalse(zeroVideo.guideRect.width.isNaN)
        let zeroView = ScanGeometry(videoSize: CGSize(width: 100, height: 100), viewSize: .zero)
        XCTAssertFalse(zeroView.guideRect.width.isNaN)
    }

    func test_guideIsACenteredSquareInsideTheVideoRect() {
        let geometry = ScanGeometry(
            videoSize: CGSize(width: 1920, height: 1080),
            viewSize: CGSize(width: 400, height: 800)
        )
        XCTAssertEqual(geometry.guideRect.width, geometry.guideRect.height, accuracy: 1e-9)
        XCTAssertEqual(geometry.guideRect.midX, geometry.videoRect.midX, accuracy: 1e-9)
        XCTAssertEqual(geometry.guideRect.midY, geometry.videoRect.midY, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(geometry.guideRect.width, geometry.videoRect.width + 1e-9)
        XCTAssertLessThanOrEqual(geometry.guideRect.height, geometry.videoRect.height + 1e-9)
    }

    func test_guideRatioScalesTheGuide() {
        let small = ScanGeometry(videoSize: CGSize(width: 1000, height: 1000),
                                 viewSize: CGSize(width: 500, height: 500), guideRatio: 0.5)
        let large = ScanGeometry(videoSize: CGSize(width: 1000, height: 1000),
                                 viewSize: CGSize(width: 500, height: 500), guideRatio: 1.0)
        XCTAssertEqual(small.guideRect.width, 250, accuracy: 1e-9)
        XCTAssertEqual(large.guideRect.width, 500, accuracy: 1e-9)
    }

    func test_nineCellsTileTheGuideInRowMajorOrder() {
        let geometry = ScanGeometry(videoSize: CGSize(width: 1000, height: 1000),
                                    viewSize: CGSize(width: 500, height: 500))
        let guide = geometry.guideRect
        let side = guide.width / 3
        for index in 0..<9 {
            let rect = geometry.cellRect(index, inset: 0)
            let row = index / 3
            let col = index % 3
            XCTAssertEqual(rect.minX, guide.minX + CGFloat(col) * side, accuracy: 1e-9)
            XCTAssertEqual(rect.minY, guide.minY + CGFloat(row) * side, accuracy: 1e-9)
            XCTAssertEqual(rect.width, side, accuracy: 1e-9)
        }
    }

    func test_normalizedCellRectIsInsideTheUnitSquare() {
        let geometry = ScanGeometry(videoSize: CGSize(width: 1920, height: 1080),
                                    viewSize: CGSize(width: 400, height: 800))
        for index in 0..<9 {
            let rect = geometry.normalizedCellRect(index)
            XCTAssertGreaterThanOrEqual(rect.minX, 0)
            XCTAssertGreaterThanOrEqual(rect.minY, 0)
            XCTAssertLessThanOrEqual(rect.maxX, 1)
            XCTAssertLessThanOrEqual(rect.maxY, 1)
        }
    }

    func test_normalizedCellRectsTileTheGuideRegion() {
        // 归一化之后九格仍然铺满引导框对应的区域，不重不漏
        let geometry = ScanGeometry(videoSize: CGSize(width: 1000, height: 1000),
                                    viewSize: CGSize(width: 500, height: 700))
        let guide = geometry.normalized(geometry.guideRect)
        var rects: [CGRect] = []
        for index in 0..<9 { rects.append(geometry.normalizedCellRect(index, inset: 0)) }
        let total = rects.reduce(0.0) { $0 + $1.width * $1.height }
        XCTAssertEqual(total, guide.width * guide.height, accuracy: 1e-9)
        XCTAssertEqual(rects[0].minX, guide.minX, accuracy: 1e-9)
        XCTAssertEqual(rects[8].maxY, guide.maxY, accuracy: 1e-9)
    }

    func test_normalizedPointMapsCornersToCorners() {
        let geometry = ScanGeometry(videoSize: CGSize(width: 1920, height: 1080),
                                    viewSize: CGSize(width: 400, height: 800))
        let topLeft = geometry.normalized(geometry.videoRect.origin)
        XCTAssertEqual(topLeft.x, 0, accuracy: 1e-9)
        XCTAssertEqual(topLeft.y, 0, accuracy: 1e-9)
        let bottomRight = geometry.normalized(
            CGPoint(x: geometry.videoRect.maxX, y: geometry.videoRect.maxY)
        )
        XCTAssertEqual(bottomRight.x, 1, accuracy: 1e-9)
        XCTAssertEqual(bottomRight.y, 1, accuracy: 1e-9)
    }

    func test_cellCentreMapsToExpectedNormalizedPosition() {
        // 第 4 格（正中）的中心应当落在归一化画面的正中央
        let geometry = ScanGeometry(videoSize: CGSize(width: 1000, height: 1000),
                                    viewSize: CGSize(width: 500, height: 500))
        let centre = geometry.normalized(geometry.cellRect(4, inset: 0).center)
        XCTAssertEqual(centre.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 0.5, accuracy: 1e-9)
    }

    // MARK: - 引导框 → 相机原始帧

    func test_landscapeFrameIsSwappedToPortrait() {
        // 400×800 的竖屏视图 + 720×1280 的显示画面 → 缩放 400/720，引导框边长 328 点
        // 帧是横的 1280×720：旋转不改变长度，328 点在帧里仍是 590.4 像素
        let geometry = ScanGeometry(videoSize: CGSize(width: 720, height: 1280),
                                    viewSize: CGSize(width: 400, height: 800))
        let rect = geometry.guideRectInFrame(frameSize: CGSize(width: 1280, height: 720))
        XCTAssertEqual(rect.midX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 590.4 / 1280, accuracy: 1e-6)
        XCTAssertEqual(rect.height, 590.4 / 720, accuracy: 1e-6)
    }

    func test_portraitFrameIsNotSwapped() {
        // 帧本来就是竖的：显示尺寸就是帧尺寸，同一个正方形按另一组比例归一化
        let geometry = ScanGeometry(videoSize: CGSize(width: 720, height: 1280),
                                    viewSize: CGSize(width: 400, height: 800))
        let rect = geometry.guideRectInFrame(frameSize: CGSize(width: 720, height: 1280))
        XCTAssertEqual(rect.width, 590.4 / 720, accuracy: 1e-6)
        XCTAssertEqual(rect.height, 590.4 / 1280, accuracy: 1e-6)
        // 两种帧朝向采到的是同一块物理区域，只是归一化坐标互为转置
        let landscape = geometry.guideRectInFrame(frameSize: CGSize(width: 1280, height: 720))
        XCTAssertEqual(rect.width, landscape.height, accuracy: 1e-9)
        XCTAssertEqual(rect.height, landscape.width, accuracy: 1e-9)
    }

    func test_frameGuideNeverLeavesTheFrame() {
        for frame in [CGSize(width: 1280, height: 720), CGSize(width: 720, height: 1280),
                      CGSize(width: 1920, height: 1080), CGSize(width: 480, height: 360)] {
            let geometry = ScanGeometry(videoSize: CGSize(width: 720, height: 1280),
                                        viewSize: CGSize(width: 400, height: 800))
            let rect = geometry.guideRectInFrame(frameSize: frame)
            XCTAssertGreaterThanOrEqual(rect.minX, 0)
            XCTAssertGreaterThanOrEqual(rect.minY, 0)
            XCTAssertLessThanOrEqual(rect.maxX, 1)
            XCTAssertLessThanOrEqual(rect.maxY, 1)
        }
    }

    func test_degenerateFrameSizeFallsBackInsteadOfNaN() {
        let geometry = ScanGeometry(videoSize: CGSize(width: 720, height: 1280),
                                    viewSize: CGSize(width: 400, height: 800))
        let rect = geometry.guideRectInFrame(frameSize: .zero)
        XCTAssertFalse(rect.width.isNaN)
        XCTAssertGreaterThan(rect.width, 0)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
