import CoreGraphics
import CubeKit

/// 标准魔方展开图的几何。
///
/// ```
///         U
///     L   F   R   B
///         D
/// ```
///
/// 每面都按"正视该面"画，所以格子 `(row, col)` 与 `CubeState.color(at:row:col:)`
/// 是同一套读法——画出来的图与 `CubeState` 一一对应，中间不需要任何翻转。
/// 展开图本身也自洽：正视 L 时 F 在右侧，所以 L 的右边缘贴着 F 的左边缘；
/// 正视 B 时 R 在左侧，所以 B 的左边缘贴着 R 的右边缘。
///
/// 纯几何、无 UI 依赖，可直接单测。
struct CubeNetLayout {

    /// 面网格：3 行 × 4 列，空格为 nil
    static let slots: [[Face?]] = [
        [nil, .u, nil, nil],
        [.l, .f, .r, .b],
        [nil, .d, nil, nil],
    ]

    static let faceColumns = 4
    static let faceRows = 3

    /// 每面 N×N 格（随阶数变化）
    let faceSize: Int
    let cellSize: CGFloat
    /// 整张展开图在容器坐标系里的左上角（容器大于展开图时居中）
    let origin: CGPoint
    let netSize: CGSize

    init(in size: CGSize, faceSize: Int = 3) {
        self.faceSize = faceSize
        let cell = max(0, min(size.width / CGFloat(Self.faceColumns * faceSize),
                              size.height / CGFloat(Self.faceRows * faceSize)))
        cellSize = cell
        netSize = CGSize(width: cell * CGFloat(Self.faceColumns * faceSize),
                         height: cell * CGFloat(Self.faceRows * faceSize))
        origin = CGPoint(x: (size.width - netSize.width) / 2,
                         y: (size.height - netSize.height) / 2)
    }

    /// 某面在面网格里的位置
    static func slot(of face: Face) -> (row: Int, col: Int) {
        for (row, faces) in slots.enumerated() {
            if let col = faces.firstIndex(of: face) { return (row, col) }
        }
        preconditionFailure("\(face) 不在展开图里")
    }

    /// 某面左上角在容器坐标系里的位置
    func faceOrigin(_ face: Face) -> CGPoint {
        let slot = Self.slot(of: face)
        return CGPoint(x: origin.x + CGFloat(slot.col * faceSize) * cellSize,
                       y: origin.y + CGFloat(slot.row * faceSize) * cellSize)
    }

    /// 某面整体在容器坐标系里的矩形
    func faceRect(_ face: Face) -> CGRect {
        let side = cellSize * CGFloat(faceSize)
        return CGRect(origin: faceOrigin(face), size: CGSize(width: side, height: side))
    }

    /// 触点落在哪个贴纸上。落在空格、容器外、或容器尺寸退化时返回 nil。
    func sticker(at point: CGPoint) -> (face: Face, row: Int, col: Int)? {
        guard cellSize > 0 else { return nil }
        let x = point.x - origin.x
        let y = point.y - origin.y
        guard x >= 0, y >= 0 else { return nil }
        let cellCol = Int(x / cellSize)
        let cellRow = Int(y / cellSize)
        guard cellCol < Self.faceColumns * faceSize,
              cellRow < Self.faceRows * faceSize else { return nil }
        guard let face = Self.slots[cellRow / faceSize][cellCol / faceSize] else { return nil }
        return (face, cellRow % faceSize, cellCol % faceSize)
    }
}
