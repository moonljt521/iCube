import Foundation

/// 一次转动对全部贴纸槽位的置换：newStickers[i] = oldStickers[source[i]]
public struct TurnPermutation: Hashable, Sendable {
    public let source: [Int]
    /// 实际被移动的槽位（外层 90° 为 20 个），渲染层用它只刷新受影响的部分
    public let movedIndices: [Int]
}

enum TurnTable {
    /// 12 种转动（6 外层 + 3 中层 + 3 整体旋转）× 3 种角度，启动时一次性由几何推导。
    static let all: [Move: TurnPermutation] = table(for: 3)

    /// 2/3/4 阶各一张表，随首查惰性推导并常驻
    private static let tables: [Int: [Move: TurnPermutation]] = {
        var result = [Int: [Move: TurnPermutation]]()
        for size in [2, 3, 4] { result[size] = table(for: size) }
        return result
    }()

    static func table(for size: Int) -> [Move: TurnPermutation] {
        var table = [Move: TurnPermutation]()
        let maxDepth = (size + 1) / 2
        for kind in MoveKind.all {
            let depths = kind.isWholeCube ? [1] : Array(1...max(1, maxDepth))
            for depth in depths {
                for amount in MoveAmount.allCases {
                    table[Move(kind, amount, depth: depth)] = derive(for: Move(kind, amount, depth: depth), size: size)
                }
            }
        }
        return table
    }

    static func permutation(for move: Move, size: Int = 3) -> TurnPermutation {
        if let cached = tables[size]?[move] { return cached }
        return derive(for: move, size: size)
    }

    private static func derive(for move: Move, size: Int) -> TurnPermutation {
        let geometry = StickerGeometry.all(size: size)
        let lookup = StickerGeometry.indexByGeometry(size: size)
        let count = 6 * size * size
        let turns = move.quarterTurns

        // destination[i] = 贴纸 i 转动后落在哪个槽位
        var destination = Array(0..<count)
        for index in 0..<count {
            let sticker = geometry[index]
            // 层归属按块中心判定：贴纸中心比块中心沿外法向多 1
            let blockCenter = sticker.center - sticker.normal
            guard move.affectsLayer(of: blockCenter, size: size) else { continue }
            let rotatedCenter = sticker.center.rotated(axis: move.kind.referenceFace.axis, quarterTurns: turns)
            let rotatedNormal = sticker.normal.rotated(axis: move.kind.referenceFace.axis, quarterTurns: turns)
            let target = StickerGeometry(center: rotatedCenter, normal: rotatedNormal)
            guard let mapped = lookup[target] else {
                preconditionFailure("转动 \(move.notation) 把贴纸 \(index) 送到了不存在的槽位 target=\(target.center)@\(target.normal)")
            }
            destination[index] = mapped
        }

        var source = Array(0..<count)
        for index in 0..<count {
            source[destination[index]] = index
        }
        let moved = source.indices.filter { source[$0] != $0 }
        return TurnPermutation(source: source, movedIndices: moved)
    }
}

/// 魔方状态：6N² 个贴纸槽位上的颜色，槽位随刚体固定。
/// 因此整块魔方在空间里怎么转都不影响状态，`isSolved` 只比较贴纸归属。
/// 阶数不落盘，由贴纸总数反推（6N² = count），旧数据 Codable 完全兼容。
public struct CubeState: Hashable, Sendable, Codable {
    public private(set) var stickers: [CubeColor]

    /// 阶数：2/3/4……由贴纸数开方推出
    public var size: Int {
        let value = Int((Double(stickers.count) / 6.0).squareRoot().rounded())
        precondition(value * value * 6 == stickers.count, "贴纸数 \(stickers.count) 不是合法的 6N²")
        return value
    }

    public init(stickers: [CubeColor]? = nil) {
        precondition(stickers == nil || stickers!.count % 6 == 0, "贴纸数必须是 6 的倍数")
        self.stickers = stickers ?? CubeState.solvedColors
    }

    /// N 阶还原态
    public init(size: Int) {
        precondition((2...6).contains(size), "仅支持 2~6 阶")
        self.stickers = CubeState.solvedColors(size: size)
    }

    static func solvedColors(size: Int = 3) -> [CubeColor] {
        Face.allCases.flatMap { face in
            Array(repeating: face.defaultColor, count: size * size)
        }
    }

    static let solvedColors: [CubeColor] = solvedColors(size: 3)

    public static let solved = CubeState()

    public static func solved(size: Int) -> CubeState {
        CubeState(size: size)
    }

    public var isSolved: Bool {
        let n = size
        for face in Face.allCases {
            let color = face.defaultColor
            let base = face.rawValue * n * n
            for offset in 0..<(n * n) where stickers[base + offset] != color {
                return false
            }
        }
        return true
    }

    public mutating func apply(_ move: Move) {
        let permutation = TurnTable.permutation(for: move, size: size).source
        var next = stickers
        for index in stickers.indices {
            next[index] = stickers[permutation[index]]
        }
        stickers = next
    }

    public func applying(_ move: Move) -> CubeState {
        var copy = self
        copy.apply(move)
        return copy
    }

    public mutating func apply(_ algorithm: Algorithm) {
        for move in algorithm.moves { apply(move) }
    }

    public func applying(_ algorithm: Algorithm) -> CubeState {
        var copy = self
        copy.apply(algorithm)
        return copy
    }

    /// 正视网格读法：`row`/`col` 均为 0..N-1，(0,0) 是正视该面时的左上角
    public func color(at face: Face, row: Int, col: Int) -> CubeColor {
        stickers[faceletIndex(face, row: row, col: col, size: size)]
    }

    /// 三阶专用：该面正中贴纸（奇数阶才有真正中心块）
    public func centerColor(of face: Face) -> CubeColor {
        let n = size
        let mid = (n - 1) / 2
        return stickers[faceletIndex(face, row: mid, col: mid, size: n)]
    }

    /// 渲染层入口：给出某个块中心与朝外方向，取该贴纸颜色；非表面位置返回 nil
    public func color(at center: V3, facing normal: V3) -> CubeColor? {
        guard let index = StickerGeometry.index(cubieCenter: center, facing: normal, size: size) else { return nil }
        return stickers[index]
    }

    /// 每个颜色出现次数，用于不变量自检
    public func colorCounts() -> [CubeColor: Int] {
        var counts = [CubeColor: Int]()
        for color in stickers { counts[color, default: 0] += 1 }
        return counts
    }
}
