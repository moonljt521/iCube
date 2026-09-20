import Foundation

/// 魔方的 6 个**本体**面。槽位随刚体固定：`.u` 永远是初始朝上的那一面（还原态为白色中心），
/// 相机绕着魔方转不改变这里的状态；视图方向到本体面的换算见 `CubeOrientation`。
public enum Face: Int, CaseIterable, Hashable, Sendable, Codable {
    case u = 0
    case d
    case f
    case b
    case r
    case l

    public static let count = 6
    public static let facelets = 54

    /// 面法向（本体坐标系）
    public var normal: V3 {
        switch self {
        case .u: return .posY
        case .d: return .negY
        case .f: return .posZ
        case .b: return .negZ
        case .r: return .posX
        case .l: return .negX
        }
    }

    public var axis: CubeAxis {
        switch self {
        case .u, .d: return .y
        case .f, .b: return .z
        case .r, .l: return .x
        }
    }

    /// +1 表示法向与该轴正方向一致，-1 相反
    public var sign: Int {
        normal.dot(axis.unit)
    }

    /// 正视该面时屏幕"上"方向
    public var up: V3 {
        switch self {
        case .u: return .negZ
        case .d: return .posZ
        case .f, .b, .r, .l: return .posY
        }
    }

    /// 正视该面时屏幕"右"方向。注意 R/L 的右是 ±Z，不是 ±X——它们的法向才是 X。
    public var right: V3 {
        switch self {
        case .u, .d, .f: return .posX
        case .b: return .negX
        case .r: return .negZ
        case .l: return .posZ
        }
    }

    public var letter: Character {
        switch self {
        case .u: return "U"
        case .d: return "D"
        case .f: return "F"
        case .b: return "B"
        case .r: return "R"
        case .l: return "L"
        }
    }

    /// 标准配色（白顶 / 黄底 / 绿前 / 蓝后 / 红右 / 橙左）
    public var defaultColor: CubeColor {
        switch self {
        case .u: return .white
        case .d: return .yellow
        case .f: return .green
        case .b: return .blue
        case .r: return .red
        case .l: return .orange
        }
    }

    /// 本体坐标方向对应的面，方向不是轴向时返回 nil
    public static func facing(_ direction: V3) -> Face? {
        allCases.first { $0.normal == direction }
    }
}

/// 一个贴纸（facelet）的几何：贴纸中心点与它所属面的法向，均在本体坐标系。
/// 立方体占据 [-3,3]^3，小立方体边长 2、中心在 {-2,0,2}^3，贴纸中心 = 块中心 + 法向。
public struct StickerGeometry: Hashable, Sendable {
    public let center: V3
    public let normal: V3

    public init(center: V3, normal: V3) {
        self.center = center
        self.normal = normal
    }
}

public extension StickerGeometry {
    /// 块中心 + 朝外方向 → 贴纸槽位索引；该方向在立方体内部时返回 nil。
    /// 阶数缺省为 3，多阶传入对应 size
    static func index(cubieCenter: V3, facing normal: V3, size: Int = 3) -> Int? {
        guard let face = Face.facing(normal), cubieCenter.dot(normal) == size - 1 else { return nil }
        let tangential = cubieCenter - normal * (size - 1)
        let row = ((size - 1) - tangential.dot(face.up)) / 2
        let col = ((size - 1) + tangential.dot(face.right)) / 2
        guard (0..<size).contains(row), (0..<size).contains(col) else { return nil }
        return faceletIndex(face, row: row, col: col, size: size)
    }
}

extension StickerGeometry {
    /// 某阶数的 6N² 个贴纸槽位，索引 = face.rawValue * N² + row * N + col（row/col 按正视该面，0 为左上）
    static func all(size: Int = 3) -> [StickerGeometry] {
        var result: [StickerGeometry] = []
        result.reserveCapacity(6 * size * size)
        for face in Face.allCases {
            for row in 0..<size {
                for col in 0..<size {
                    let center = face.normal * size
                        + face.up * (size - 1 - 2 * row)
                        + face.right * (2 * col - size + 1)
                    result.append(StickerGeometry(center: center, normal: face.normal))
                }
            }
        }
        return result
    }

    static func indexByGeometry(size: Int = 3) -> [StickerGeometry: Int] {
        var map = [StickerGeometry: Int]()
        map.reserveCapacity(6 * size * size)
        for (index, geometry) in all(size: size).enumerated() {
            map[geometry] = index
        }
        return map
    }

    /// 三阶专用旧入口：既有调用方与测试沿用
    static let all: [StickerGeometry] = all(size: 3)
    static let indexByGeometry: [StickerGeometry: Int] = indexByGeometry(size: 3)
}

/// 贴纸槽位索引。size 缺省 3 保持旧签名兼容
public func faceletIndex(_ face: Face, row: Int, col: Int, size: Int = 3) -> Int {
    face.rawValue * size * size + row * size + col
}

public func face(ofFacelet index: Int) -> Face {
    Face(rawValue: index / 9)!
}
