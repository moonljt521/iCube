import Foundation

/// 可复现的 64 位随机源。打乱只用于生成，落库时以记法字符串为准——
/// 不要把 seed 当成长期可回放的主键。
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 均匀取值 [0, upperBound)，用拒绝采样消除取模偏置
    mutating func int(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        let bound = UInt64(upperBound)
        let limit = UInt64.max - (UInt64.max % bound)
        var value = next()
        while value >= limit { value = next() }
        return Int(value % bound)
    }
}

/// 打乱串。约束对齐 WCA 官方打乱的常用做法：面不连续重复、不出现同轴三连（如 R L R），
/// 三个后缀（顺时针 / 逆时针 / 180°）等概率。
/// 因为始终从还原态生成，结果必然可解，不需要求解器反向验证。
public struct Scramble: Hashable, Sendable {
    public static let wcaLength = 20
    /// 各阶默认打乱步数（对齐 WCA 官方：2 阶 11、3 阶 20、4 阶 40）
    public static func defaultLength(for size: Int) -> Int {
        switch size {
        case 2: return 11
        case 3: return 20
        default: return 40
        }
    }

    public let algorithm: Algorithm
    public let seed: UInt64
    public let size: Int

    public init(algorithm: Algorithm, seed: UInt64? = nil, size: Int = 3) {
        self.algorithm = algorithm
        self.seed = seed ?? 0
        self.size = size
    }

    public var notation: String { algorithm.notation }
    public var moves: [Move] { algorithm.moves }
    public var count: Int { algorithm.count }

    /// 逆序取逆，用于"逐步回看打乱"时反向重放
    public var inverse: Algorithm { algorithm.inverse }

    /// 打乱对应的起始状态（由还原态施加打乱得到）
    public var initialState: CubeState {
        CubeState.solved(size: size).applying(algorithm)
    }

    public static func random(length: Int = wcaLength, seed: UInt64? = nil) -> Scramble {
        random(size: 3, length: length, seed: seed)
    }

    /// 统一入口：size 缺省 3，保持旧调用不变
    public static func random(size: Int, length: Int? = nil, seed: UInt64? = nil) -> Scramble {
        var currentSeed = seed ?? UInt64.random(in: .min ... .max)
        while true {
            if let scramble = generate(size: size, length: length ?? defaultLength(for: size), seed: currentSeed) {
                return scramble
            }
            currentSeed = currentSeed &+ 1
        }
    }

    /// 生成一个打乱；若整串恰好抵消回还原态则返回 nil，由调用方换 seed 重试
    /// 四阶及以上混入 depth 2 内层转动（官方打乱含 2R/2L 等）
    static func generate(size: Int, length: Int, seed: UInt64) -> Scramble? {
        var rng = SplitMix64(seed: seed)
        var chosen: [Move] = []
        chosen.reserveCapacity(length)
        let maxDepth = size >= 4 ? 2 : 1

        while chosen.count < length {
            let face = Face.allCases[rng.int(upperBound: Face.allCases.count)]
            // 规则一：不与上一步同层（同面不同层允许，如 R 2R）
            if let last = chosen.last, last.kind.referenceFace == face, last.depth == 1 { continue }
            // 规则二：不出现同轴三连（例：R L R）
            if chosen.count >= 2 {
                let axis = face.axis
                let previousAxis = chosen[chosen.count - 1].kind.referenceFace.axis
                let beforeAxis = chosen[chosen.count - 2].kind.referenceFace.axis
                if axis == previousAxis, axis == beforeAxis { continue }
            }
            let amount = MoveAmount.allCases[rng.int(upperBound: MoveAmount.allCases.count)]
            let depth = maxDepth > 1 ? rng.int(upperBound: 2) + 1 : 1
            chosen.append(Move(.face(face), amount, depth: depth))
        }

        let scramble = Scramble(algorithm: Algorithm(chosen), seed: seed, size: size)
        return scramble.initialState.isSolved ? nil : scramble
    }
}
