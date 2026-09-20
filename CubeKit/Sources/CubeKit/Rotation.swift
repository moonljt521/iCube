import Foundation

/// 整数旋转矩阵（列向量为 x̂/ŷ/ẑ 旋转后的像）。
/// 渲染层用它记录每个小立方体的当前姿态：转动提交时只做整数复合，
/// 姿态由矩阵重新推导，因此连续转几百步也不会浮点漂移。
public struct Rotation: Hashable, Sendable {
    public let xAxis: V3
    public let yAxis: V3
    public let zAxis: V3

    public init(xAxis: V3, yAxis: V3, zAxis: V3) {
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    public static let identity = Rotation(xAxis: .posX, yAxis: .posY, zAxis: .posZ)

    /// 绕 +axis 右手旋转 turns*90°
    public init(axis: CubeAxis, quarterTurns turns: Int) {
        func image(of unit: V3) -> V3 { unit.rotated(axis: axis, quarterTurns: turns) }
        self.init(xAxis: image(of: .posX), yAxis: image(of: .posY), zAxis: image(of: .posZ))
    }

    public func applying(to vector: V3) -> V3 {
        xAxis * vector.x + yAxis * vector.y + zAxis * vector.z
    }

    /// 先施加 self 再施加 other
    public func then(_ other: Rotation) -> Rotation {
        Rotation(xAxis: other.applying(to: xAxis), yAxis: other.applying(to: yAxis), zAxis: other.applying(to: zAxis))
    }

    /// 正交矩阵的逆 = 转置
    public var inverse: Rotation {
        Rotation(xAxis: V3(xAxis.x, yAxis.x, zAxis.x),
                 yAxis: V3(xAxis.y, yAxis.y, zAxis.y),
                 zAxis: V3(xAxis.z, yAxis.z, zAxis.z))
    }
}
