import Foundation

/// 魔方阶数。本体坐标约定：块中心落在 {-N+1, -N+3, …, N-1}（间隔 2 的整数格），
/// 三阶即 {-2, 0, 2}，四阶即 {-3, -1, 1, 3}——与既有三阶几何完全兼容。
public enum CubeSize: Int, CaseIterable, Sendable, Codable {
    case two = 2
    case three = 3
    case four = 4

    /// 支持任意层深运算的阶数集合
    public static let supported = allCases.map(\.rawValue)

    /// 全局阶数在 UserDefaults 里的键（练习/教程共用）
    public static let defaultsKey = "cubeSize"

    public var dimension: Int { rawValue }

    /// 第 index 层（0..<N，从 -N+1 侧数起）在本体坐标上的投影值
    public func coordinate(_ index: Int) -> Int {
        2 * index - dimension + 1
    }

    /// 从 face 外侧数第 depth 层（1 = 最外层）的投影值，带方向符号
    public func layerCoordinate(depth: Int, toward face: Face) -> Int {
        face.sign * (dimension - 1 - 2 * (depth - 1))
    }

    public var faceletsPerFace: Int { dimension * dimension }
    public var facelets: Int { 6 * dimension * dimension }
    /// 可见块数：N³ - (N-2)³
    public var cubieCount: Int {
        let n = dimension
        return n * n * n - max(0, n - 2) * max(0, n - 2) * max(0, n - 2)
    }
}
