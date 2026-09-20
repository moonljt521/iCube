import Foundation

/// 贴纸颜色。6 色一一对应 6 个面的中心，还原态下每色恰好 9 个。
public enum CubeColor: Int, CaseIterable, Hashable, Sendable, Codable {
    case white = 0
    case yellow
    case green
    case blue
    case red
    case orange
}

public enum MoveAmount: Int, CaseIterable, Sendable {
    case cw = 0
    case ccw
    case half

    public var suffix: String {
        switch self {
        case .cw: return ""
        case .ccw: return "'"
        case .half: return "2"
        }
    }

    public var inverse: MoveAmount {
        switch self {
        case .cw: return .ccw
        case .ccw: return .cw
        case .half: return .half
        }
    }
}

/// 中层切片，记法 M / E / S。方向分别跟随 L / D / F。
public enum SliceKind: Int, CaseIterable, Hashable, Sendable {
    case m = 0
    case e
    case s

    /// 该轴上唯一的中层切片记法
    public init(axisOf axis: CubeAxis) {
        switch axis {
        case .x: self = .m
        case .y: self = .e
        case .z: self = .s
        }
    }

    public var referenceFace: Face {
        switch self {
        case .m: return .l
        case .e: return .d
        case .s: return .f
        }
    }

    public var letter: String {
        switch self {
        case .m: return "M"
        case .e: return "E"
        case .s: return "S"
        }
    }
}

/// 整体旋转，记法 x / y / z。方向分别跟随 R / U / F。
public enum CubeRotation: Int, CaseIterable, Hashable, Sendable {
    case x = 0
    case y
    case z

    public var referenceFace: Face {
        switch self {
        case .x: return .r
        case .y: return .u
        case .z: return .f
        }
    }

    public var letter: String {
        switch self {
        case .x: return "x"
        case .y: return "y"
        case .z: return "z"
        }
    }
}

public enum MoveKind: Hashable, Sendable {
    /// 外层转动，记法 U D L R F B
    case face(Face)
    /// 中层切片 M E S
    case slice(SliceKind)
    /// 整体旋转 x y z
    case rotation(CubeRotation)

    /// 定义转动方向与所作用层的那个面
    public var referenceFace: Face {
        switch self {
        case .face(let face): return face
        case .slice(let slice): return slice.referenceFace
        case .rotation(let rotation): return rotation.referenceFace
        }
    }

    public var axis: CubeAxis { referenceFace.axis }

    public var letter: String {
        switch self {
        case .face(let face): return String(face.letter)
        case .slice(let slice): return slice.letter
        case .rotation(let rotation): return rotation.letter
        }
    }

    /// 该转动作用的本体层：按贴纸中心在 referenceFace 法向上的投影筛选（三阶）
    public func affectsLayer(of center: V3) -> Bool {
        affectsLayer(of: center, depth: 1, size: 3)
    }

    /// 多阶版本：face 按 depth 从基准面外侧数层；slice 只在奇数阶存在（正中层）
    public func affectsLayer(of center: V3, depth: Int, size: Int) -> Bool {
        // 投影取的是沿法向的距离（非负），与基准面朝向无关
        let projection = center.dot(referenceFace.normal)
        switch self {
        case .face:
            return projection == size - 1 - 2 * (depth - 1)
        case .slice:
            return size % 2 == 1 && projection == 0
        case .rotation:
            return true
        }
    }

    /// 整体旋转不改变任何块的相对层，故不参与"这层该记作什么"的反推
    public var isWholeCube: Bool {
        if case .rotation = self { return true }
        return false
    }
}

public extension MoveKind {
    /// 12 种规范转动：6 外层 + 3 中层 + 3 整体旋转
    static let all: [MoveKind] = Face.allCases.map { MoveKind.face($0) }
        + SliceKind.allCases.map { .slice($0) }
        + CubeRotation.allCases.map { .rotation($0) }
}

public extension Move {
    /// 该转动作用的本体层（自动携带自身 depth）
    func affectsLayer(of center: V3, size: Int = 3) -> Bool {
        kind.affectsLayer(of: center, depth: depth, size: size)
    }

    /// 由几何反推记法：绕 axis 施加 rotation，且只转 center 所在的那一层。
    /// 手势层判出"往哪个方向转了哪一层"后用它换回记法，省掉一张手写符号对照表。
    /// 多阶传 size 才能反推出内层 depth（如四阶的 2R）
    static func layerTurn(axis: CubeAxis, rotation: Rotation, affecting center: V3, size: Int = 3) -> Move? {
        let projection = center.dot(axis.unit)
        if projection == 0 {
            guard size % 2 == 1 else { return nil }
            let slice = SliceKind(axisOf: axis)
            for amount in MoveAmount.allCases {
                let candidate = Move(.slice(slice), amount)
                if Rotation(axis: axis, quarterTurns: candidate.quarterTurns) == rotation { return candidate }
            }
            return nil
        }
        let sign = projection > 0 ? 1 : -1
        guard let face = Face.facing(axis.unit * sign) else { return nil }
        let depth = (size - 1 - abs(projection)) / 2 + 1
        for amount in MoveAmount.allCases {
            let candidate = Move(.face(face), amount, depth: depth)
            if Rotation(axis: axis, quarterTurns: candidate.quarterTurns) == rotation { return candidate }
        }
        return nil
    }
}

/// 一次转动。置换关系全部由本体坐标的整数 90° 旋转推导，不写手抄表。
/// depth 表示从基准面外侧数第几层（1 = 最外层），2 阶以上的内层用 "2R" 这类记法。
public struct Move: Hashable, Sendable {
    public let kind: MoveKind
    public let amount: MoveAmount
    public let depth: Int

    public init(_ kind: MoveKind, _ amount: MoveAmount = .cw, depth: Int = 1) {
        precondition(depth >= 1, "层深从 1 开始")
        self.kind = kind
        self.amount = amount
        self.depth = depth
    }

    public var inverse: Move {
        Move(kind, amount.inverse, depth: depth)
    }

    /// 绕 referenceFace 轴向正方向旋转的 90° 步数。
    /// "从该面外侧看顺时针" = 绕其法向 -90°；法向与轴反向时符号翻转。
    public var quarterTurns: Int {
        if amount == .half { return 2 }
        let clockwise = kind.referenceFace.sign > 0 ? 3 : 1
        return amount == .cw ? clockwise : 4 - clockwise
    }

    public var notation: String {
        (depth > 1 ? String(depth) : "") + kind.letter + amount.suffix
    }
}

public extension Move {
    static let u = Move(.face(.u))
    static let uPrime = Move(.face(.u), .ccw)
    static let u2 = Move(.face(.u), .half)
    static let d = Move(.face(.d))
    static let dPrime = Move(.face(.d), .ccw)
    static let d2 = Move(.face(.d), .half)
    static let f = Move(.face(.f))
    static let fPrime = Move(.face(.f), .ccw)
    static let f2 = Move(.face(.f), .half)
    static let b = Move(.face(.b))
    static let bPrime = Move(.face(.b), .ccw)
    static let b2 = Move(.face(.b), .half)
    static let r = Move(.face(.r))
    static let rPrime = Move(.face(.r), .ccw)
    static let r2 = Move(.face(.r), .half)
    static let l = Move(.face(.l))
    static let lPrime = Move(.face(.l), .ccw)
    static let l2 = Move(.face(.l), .half)
    static let m = Move(.slice(.m))
    static let mPrime = Move(.slice(.m), .ccw)
    static let e = Move(.slice(.e))
    static let ePrime = Move(.slice(.e), .ccw)
    static let s = Move(.slice(.s))
    static let sPrime = Move(.slice(.s), .ccw)
    static let x = Move(.rotation(.x))
    static let y = Move(.rotation(.y))
    static let z = Move(.rotation(.z))
}

/// 算法 / 打乱串：一串转动。
public struct Algorithm: Hashable, Sendable {
    public let moves: [Move]

    public init(_ moves: [Move]) {
        self.moves = moves
    }

    public var count: Int { moves.count }
    public var isEmpty: Bool { moves.isEmpty }

    public var notation: String {
        moves.map(\.notation).joined(separator: " ")
    }

    public var inverse: Algorithm {
        Algorithm(moves.reversed().map(\.inverse))
    }

    /// 解析记法，支持 `R U2 R' F'`、`M E S`、`x y z`、宽层 `Rw` / `Rw'` / `R2w`，大小写不敏感。
    /// 任一词元无法识别时返回 nil。多阶传 size：宽层在 N≥4 展开为 [R, 2R]，在二阶退化为单层。
    public static func parse(_ text: String, size: Int = 3) -> Algorithm? {
        var result: [Move] = []
        for rawToken in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," }) {
            guard let moves = parseToken(String(rawToken), size: size) else { return nil }
            result.append(contentsOf: moves)
        }
        return Algorithm(result)
    }

    private static func parseToken(_ token: String, size: Int = 3) -> [Move]? {
        var body = Substring(token)
        var primeCount = 0
        var sawDouble = false

        // 前缀数字 = 层深（多阶记法：2R、3R'）
        var depth = 1
        var prefixDigits = ""
        while let first = body.first, first.isNumber {
            prefixDigits.append(first)
            body = body.dropFirst()
        }
        if !prefixDigits.isEmpty {
            guard let parsed = Int(prefixDigits), (2...6).contains(parsed) else { return nil }
            depth = parsed
        }

        // 后缀是 ' 与 2 的组合。R2' 等同 R2；R'' 即 R2
        while let last = body.last, last == "'" || last == "2" {
            if last == "'" { primeCount += 1 } else { sawDouble = true }
            body = body.dropLast()
        }

        guard let first = body.first, primeCount <= 2 else { return nil }
        let amount: MoveAmount
        if sawDouble || primeCount == 2 {
            amount = .half
        } else if primeCount == 1 {
            amount = .ccw
        } else {
            amount = .cw
        }

        let upper = body.uppercased()
        if upper.count == 2, upper.last == "W", let face = outerFace(first) {
            return wideMoves(for: face, amount: amount, size: size)
        }
        guard upper.count == 1 else { return nil }

        if let face = outerFace(first) {
            if depth > 1 { return [Move(.face(face), amount, depth: depth)] }
            return [Move(.face(face), amount)]
        }
        guard depth == 1 else { return nil }
        if let slice = sliceKind(first) { return [Move(.slice(slice), amount)] }
        if let rotation = cubeRotation(first) { return [Move(.rotation(rotation), amount)] }
        return nil
    }

    private static func outerFace(_ letter: Character) -> Face? {
        switch letter.uppercased() {
        case "U": return .u
        case "D": return .d
        case "F": return .f
        case "B": return .b
        case "R": return .r
        case "L": return .l
        default: return nil
        }
    }

    private static func sliceKind(_ letter: Character) -> SliceKind? {
        switch letter.uppercased() {
        case "M": return .m
        case "E": return .e
        case "S": return .s
        default: return nil
        }
    }

    private static func cubeRotation(_ letter: Character) -> CubeRotation? {
        switch letter.uppercased() {
        case "X": return .x
        case "Y": return .y
        case "Z": return .z
        default: return nil
        }
    }

    /// 宽层 = 外层 + 相邻内层同向。
    /// 三阶沿用 R M' 记法习惯（Rw = R M'）；四阶及以上第二层直接用 depth 表达（Rw = R 2R）。
    static func wideMoves(for face: Face, amount: MoveAmount, size: Int = 3) -> [Move] {
        if size == 3 {
            let slice: SliceKind
            switch face.axis {
            case .x: slice = .m
            case .y: slice = .e
            case .z: slice = .s
            }
            let reference = slice.referenceFace
            let sliceAmount = face.sign == reference.sign ? amount : amount.inverse
            return [Move(.face(face), amount), Move(.slice(slice), sliceAmount)]
        }
        guard 2 <= (size + 1) / 2 else { return [Move(.face(face), amount)] }
        return [Move(.face(face), amount, depth: 1), Move(.face(face), amount, depth: 2)]
    }
}
