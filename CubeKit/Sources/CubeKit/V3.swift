import Foundation

/// 整数三维向量。魔方所有几何都用整数表达，90° 旋转保持整数，因此状态推导没有浮点误差。
public struct V3: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(_ x: Int, _ y: Int, _ z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = V3(0, 0, 0)
    public static let posX = V3(1, 0, 0)
    public static let negX = V3(-1, 0, 0)
    public static let posY = V3(0, 1, 0)
    public static let negY = V3(0, -1, 0)
    public static let posZ = V3(0, 0, 1)
    public static let negZ = V3(0, 0, -1)

    public static func + (lhs: V3, rhs: V3) -> V3 {
        V3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: V3, rhs: V3) -> V3 {
        V3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static prefix func - (value: V3) -> V3 {
        V3(-value.x, -value.y, -value.z)
    }

    public static func * (lhs: V3, rhs: Int) -> V3 {
        V3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public func dot(_ other: V3) -> Int {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: V3) -> V3 {
        V3(y * other.z - z * other.y,
           z * other.x - x * other.z,
           x * other.y - y * other.x)
    }

    /// 绕 +axis 右手旋转 turns*90°（turns 取模 4，支持负数）
    public func rotated(axis: CubeAxis, quarterTurns turns: Int) -> V3 {
        var result = self
        var remaining = ((turns % 4) + 4) % 4
        while remaining > 0 {
            switch axis {
            case .x: result = V3(result.x, -result.z, result.y)
            case .y: result = V3(result.z, result.y, -result.x)
            case .z: result = V3(-result.y, result.x, result.z)
            }
            remaining -= 1
        }
        return result
    }
}

public enum CubeAxis: Int, CaseIterable, Sendable {
    case x = 0
    case y
    case z

    /// 该轴正方向的单位向量
    public var unit: V3 {
        switch self {
        case .x: return .posX
        case .y: return .posY
        case .z: return .posZ
        }
    }

    /// 给定 ±单位轴向，返回它所在的轴；不是坐标轴向时返回 nil
    public static func axis(of direction: V3) -> CubeAxis? {
        allCases.first { $0.unit == direction || $0.unit == -direction }
    }
}
