import XCTest
import CubeKit

@testable import iCube

/// 展开图的坐标映射。这层是纯几何，值得单独钉死——
/// 触点落错一格，用户看到的就是"我明明点的是白格，结果填成绿的了"。
final class CubeNetLayoutTests: XCTestCase {

    private let container = CGSize(width: 400, height: 300)

    func test_eachFaceAppearsExactlyOnce() {
        let faces = CubeNetLayout.slots.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(faces.count, 6)
        XCTAssertEqual(Set(faces), Set(Face.allCases))
    }

    /// U 在 F 上方、D 在 F 下方、L F R B 横排——标准展开图
    func test_slotsMatchStandardNet() {
        XCTAssertEqual(CubeNetLayout.slot(of: .u).row, 0)
        XCTAssertEqual(CubeNetLayout.slot(of: .d).row, 2)
        for (face, col) in [(Face.l, 0), (.f, 1), (.r, 2), (.b, 3)] {
            let slot = CubeNetLayout.slot(of: face)
            XCTAssertEqual(slot.row, 1, "\(face) 应在中排")
            XCTAssertEqual(slot.col, col, "\(face) 的列不对")
        }
    }

    /// 每面正中心应落在该面 (1, 1)
    func test_faceCenterMapsToMiddleCell() {
        let layout = CubeNetLayout(in: container)
        for face in Face.allCases {
            let rect = layout.faceRect(face)
            let hit = layout.sticker(at: CGPoint(x: rect.midX, y: rect.midY))
            XCTAssertEqual(hit?.face, face)
            XCTAssertEqual(hit?.row, 1)
            XCTAssertEqual(hit?.col, 1)
        }
    }

    /// 面的左上角一格是 (0, 0)，右下角一格是 (2, 2)
    func test_cornerCells() {
        let layout = CubeNetLayout(in: container)
        for face in Face.allCases {
            let rect = layout.faceRect(face)
            let inset = layout.cellSize / 2
            let topLeft = layout.sticker(at: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            XCTAssertEqual(topLeft?.face, face)
            XCTAssertEqual(topLeft?.row, 0)
            XCTAssertEqual(topLeft?.col, 0)

            let bottomRight = layout.sticker(at: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            XCTAssertEqual(bottomRight?.face, face)
            XCTAssertEqual(bottomRight?.row, 2)
            XCTAssertEqual(bottomRight?.col, 2)
        }
    }

    /// 展开图的空格处（例如 U 左边、D 右边）不该命中任何格子
    func test_emptySlotsReturnNil() {
        let layout = CubeNetLayout(in: container)
        let topRow = CubeNetLayout.slot(of: .u).row
        let leftOfU = layout.sticker(at: CGPoint(
            x: layout.origin.x + layout.cellSize * 0.5,
            y: layout.origin.y + (CGFloat(topRow * 3) + 1.5) * layout.cellSize))
        XCTAssertNil(leftOfU, "U 左侧是空格")

        let rightOfD = layout.sticker(at: CGPoint(
            x: layout.origin.x + layout.cellSize * 11.5,
            y: layout.origin.y + (CGFloat(CubeNetLayout.slot(of: .d).row * 3) + 1.5) * layout.cellSize))
        XCTAssertNil(rightOfD, "D 右侧是空格")
    }

    func test_outsideContainerReturnsNil() {
        let layout = CubeNetLayout(in: container)
        XCTAssertNil(layout.sticker(at: CGPoint(x: -1, y: 10)))
        XCTAssertNil(layout.sticker(at: CGPoint(x: 10, y: -1)))
        XCTAssertNil(layout.sticker(at: CGPoint(x: container.width + 1, y: 10)))
        XCTAssertNil(layout.sticker(at: CGPoint(x: 10, y: container.height + 1)))
    }

    /// 容器尺寸退化时不该崩，也不该命中
    func test_degenerateSizeReturnsNil() {
        let layout = CubeNetLayout(in: .zero)
        XCTAssertEqual(layout.cellSize, 0)
        XCTAssertNil(layout.sticker(at: .zero))
    }

    /// 展开图居中，且六面矩形互不重叠
    func test_netIsCenteredAndFacesDoNotOverlap() {
        let layout = CubeNetLayout(in: container)
        XCTAssertEqual(layout.netSize.width, layout.cellSize * 12, accuracy: 0.001)
        XCTAssertEqual(layout.netSize.height, layout.cellSize * 9, accuracy: 0.001)

        let rects = Face.allCases.map { layout.faceRect($0) }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "\(a) 与 \(b) 重叠")
            }
        }
        // 最左的面贴着展开图左沿，最右的面贴着右沿
        let minX = rects.map(\.minX).min()!
        let maxX = rects.map(\.maxX).max()!
        XCTAssertEqual(minX, layout.origin.x, accuracy: 0.001)
        XCTAssertEqual(maxX, layout.origin.x + layout.netSize.width, accuracy: 0.001)
    }

    /// 宽高比不同时取较小的一边，保证展开图完整放得下
    func test_cellSizeFitsBothDimensions() {
        for size in [CGSize(width: 400, height: 300), CGSize(width: 200, height: 600)] {
            let layout = CubeNetLayout(in: size)
            XCTAssertLessThanOrEqual(layout.netSize.width, size.width + 0.001)
            XCTAssertLessThanOrEqual(layout.netSize.height, size.height + 0.001)
        }
    }
}
