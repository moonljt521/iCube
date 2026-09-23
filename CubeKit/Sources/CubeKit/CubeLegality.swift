import Foundation

/// 三阶状态是否可达（"合法"）的判定结果。
///
/// 填满 54 格、每色恰好 9 个，**不等于**这个状态拧得出来：单独翻一条棱、
/// 单独扭一个角、或两块互换位置，都会让状态脱离可达群。求解器也能拦住这些
/// （见 `CubeSolveError.illegalState`），但它要先把 21MB 查找表装进内存，
/// 代价远高于这里。拍照识别需要在几千个朝向候选里筛状态，必须有廉价判定。
public enum CubeLegality: Equatable, Sendable {
    case legal

    /// 面位记法与整套判定都只定义在三阶上
    case unsupportedSize(Int)

    /// 某面的中心块不是该面的标准色。中心块永不移动，是整局配色的锚点
    case centerMismatch(face: Face)

    /// 某颜色不是恰好 9 个
    case colorCountMismatch(color: CubeColor, count: Int)

    /// 第 `slot` 个角块不是"三个轴各取一色"
    case invalidCorner(slot: Int)

    /// 同一个角块出现了两次——等价于有角块缺失
    case duplicateCorner

    /// 第 `slot` 个棱块不是"两个轴各取一色"
    case invalidEdge(slot: Int)

    /// 同一个棱块出现了两次
    case duplicateEdge

    /// 角朝向和不是 3 的倍数：有角被单独扭转了
    ///
    /// 不带数值：具体和依赖朝向的取法约定，只有"模 3 非零"这一点是客观的。
    case cornerTwistSum

    /// 棱朝向和不是偶数：有棱被单独翻转了。同上，不带数值
    case edgeFlipSum

    /// 棱与角的置换奇偶性不一致：恰好有两块互换了位置
    case permutationParity(corner: Int, edge: Int)
}

public extension CubeState {

    /// 该状态是否拧得出来（三阶）
    var isLegalState: Bool { legality == .legal }

    /// 逐项判定状态合法性，**首个**不满足的条件即返回。
    ///
    /// 检查顺序刻意从便宜到贵、从最可能出错到最不可能：中心块 → 色数 →
    /// 棱 → 角 → 朝向和 → 奇偶性。拍照识别会拿它筛几千个候选，绝大多数
    /// 候选在前两步就出局了。
    ///
    /// **口径**：要求中心块各就各位，也就是"这串能直接喂给求解器"。
    /// 因此整体翻转过的魔方（`x` / `y` / `z` 或 `M` / `E` / `S`）会落到
    /// `.centerMismatch`——它们当然拧得出来，但面位记法不认那个朝向。
    ///
    /// 三阶以外的阶数直接返回 `.unsupportedSize`——棱角块结构只对三阶定义。
    var legality: CubeLegality {
        guard size == 3 else { return .unsupportedSize(size) }

        for face in Face.allCases where centerColor(of: face) != face.defaultColor {
            return .centerMismatch(face: face)
        }

        var counts: [CubeColor: Int] = [:]
        counts.reserveCapacity(CubeColor.allCases.count)
        for color in stickers { counts[color, default: 0] += 1 }
        for color in CubeColor.allCases where counts[color] != 9 {
            return .colorCountMismatch(color: color, count: counts[color] ?? 0)
        }

        // 棱有 12 个槽位、角只有 8 个，先查棱早退得更快
        var edgeTaken = [Bool](repeating: false, count: CubieGeometry.edgeSigns.count)
        var edgePermutation = [Int](repeating: 0, count: CubieGeometry.edgeSigns.count)
        var edgeFlips = 0
        for (slot, signs) in CubieGeometry.edgeSigns.enumerated() {
            let colors = CubieGeometry.edgeColors(of: self, signs: signs)
            guard let home = CubieGeometry.edgeHomeSlot(colors) else { return .invalidEdge(slot: slot) }
            if edgeTaken[home] { return .duplicateEdge }
            edgeTaken[home] = true
            edgePermutation[slot] = home
            edgeFlips += CubieGeometry.edgeOrientation(colors)
        }
        if edgeFlips % 2 != 0 { return .edgeFlipSum }

        var cornerTaken = [Bool](repeating: false, count: CubieGeometry.cornerSigns.count)
        var cornerPermutation = [Int](repeating: 0, count: CubieGeometry.cornerSigns.count)
        var cornerTwists = 0
        for (slot, signs) in CubieGeometry.cornerSigns.enumerated() {
            let colors = CubieGeometry.cornerColors(of: self, signs: signs)
            guard let home = CubieGeometry.cornerHomeSlot(colors) else { return .invalidCorner(slot: slot) }
            if cornerTaken[home] { return .duplicateCorner }
            cornerTaken[home] = true
            cornerPermutation[slot] = home
            cornerTwists += CubieGeometry.cornerOrientation(colors)
        }
        if cornerTwists % 3 != 0 { return .cornerTwistSum }

        let cornerParity = CubieGeometry.permutationParity(cornerPermutation)
        let edgeParity = CubieGeometry.permutationParity(edgePermutation)
        guard cornerParity == edgeParity else {
            return .permutationParity(corner: cornerParity, edge: edgeParity)
        }

        return .legal
    }
}

/// 棱块与角块的结构推导。
///
/// 槽位、贴纸索引、朝向**全部由整数格点几何运行时推出**，不引入手抄查找表——
/// 与 `TurnTable` 的转动置换同一套做法。块中心落在 {-2, 0, 2}³（三阶），
/// 角块的三个法向是它三个非零坐标的带符号轴向，棱块是两个。
///
/// 各取色函数返回的颜色数组都**带次序**，次序本身就是朝向判定的基准，
/// 调用方不能重排。
enum CubieGeometry {

    /// 角块槽位：三个坐标都非零的块中心。顺序固定为 (sx, sy, sz) 的嵌套枚举
    static let cornerSigns: [(x: Int, y: Int, z: Int)] = {
        var result: [(x: Int, y: Int, z: Int)] = []
        for x in [1, -1] { for y in [1, -1] { for z in [1, -1] { result.append((x, y, z)) } } }
        return result
    }()

    /// 棱块槽位：恰好两个坐标非零。按轴对 (x,y) (x,z) (y,z) 分组枚举
    static let edgeSigns: [(x: Int, y: Int, z: Int)] = {
        var result: [(x: Int, y: Int, z: Int)] = []
        let axes = [0, 1, 2]
        for a in axes {
            for b in axes where b > a {
                for sa in [1, -1] {
                    for sb in [1, -1] {
                        var signs = [0, 0, 0]
                        signs[a] = sa
                        signs[b] = sb
                        result.append((signs[0], signs[1], signs[2]))
                    }
                }
            }
        }
        return result
    }()

    /// 符号三元组 → 槽位下标；0 表示该轴无贴纸。编码成 27 项数组直接查
    private static func code(_ signs: (x: Int, y: Int, z: Int)) -> Int {
        (signs.x + 1) * 9 + (signs.y + 1) * 3 + (signs.z + 1)
    }

    private static func indexTable(_ slots: [(x: Int, y: Int, z: Int)]) -> [Int] {
        var table = [Int](repeating: -1, count: 27)
        for (index, signs) in slots.enumerated() { table[code(signs)] = index }
        return table
    }

    private static let cornerSlotIndex = indexTable(cornerSigns)
    private static let edgeSlotIndex = indexTable(edgeSigns)

    /// 颜色 → 它在还原态所属的轴与方向
    static func axisSign(of color: CubeColor) -> (axis: Int, sign: Int) {
        switch color {
        case .white: return (1, 1)
        case .yellow: return (1, -1)
        case .red: return (0, 1)
        case .orange: return (0, -1)
        case .green: return (2, 1)
        case .blue: return (2, -1)
        }
    }

    /// 该颜色是否属于上/下面（白或黄）
    static func isUpDownColor(_ color: CubeColor) -> Bool {
        color == .white || color == .yellow
    }

    // MARK: - 取贴纸

    /// 角块三个面位的颜色，次序 = 绕该角从外侧看逆时针，且**上/下面那一格固定排在第 0 位**——
    /// 朝向的基准点必须一致，否则总和的模 3 不变量不成立。
    ///
    /// 逆时针序本身是 [sxX, syY, szZ]，但那只在 det = sx·sy·sz = +1 时成立：
    /// 符号积为 -1 时该三元组是左手系，绕外法向的 +120° 旋转给出的环流是
    /// [sxX, szZ, syY]（后两位互换）。这里直接把两种情况都旋到"上/下打头"。
    static func cornerColors(of state: CubeState, signs: (x: Int, y: Int, z: Int)) -> [CubeColor] {
        let x = V3(signs.x, 0, 0)
        let y = V3(0, signs.y, 0)
        let z = V3(0, 0, signs.z)
        let normals = signs.x * signs.y * signs.z > 0 ? [y, z, x] : [y, x, z]
        return colors(of: state, signs: signs, normals: normals)
    }

    /// 棱块两个面位的颜色，按法向次序排好（见 `normalRank`）
    static func edgeColors(of state: CubeState, signs: (x: Int, y: Int, z: Int)) -> [CubeColor] {
        let normals = [V3(signs.x, 0, 0), V3(0, signs.y, 0), V3(0, 0, signs.z)]
            .filter { $0 != .zero }
            .sorted { normalRank($0) < normalRank($1) }
        return colors(of: state, signs: signs, normals: normals)
    }

    private static func colors(
        of state: CubeState,
        signs: (x: Int, y: Int, z: Int),
        normals: [V3]
    ) -> [CubeColor] {
        let center = V3(2 * signs.x, 2 * signs.y, 2 * signs.z)
        return normals.map { normal in
            let index = StickerGeometry.index(cubieCenter: center, facing: normal)!
            return state.stickers[index]
        }
    }

    // MARK: - 归属

    /// 该棱块在还原态属于哪个槽位；两色同轴（互为对面色）时返回 nil
    static func edgeHomeSlot(_ colors: [CubeColor]) -> Int? {
        var signs = [0, 0, 0]
        var usedAxis = -1
        for color in colors {
            let (axis, sign) = axisSign(of: color)
            guard axis != usedAxis else { return nil }
            usedAxis = axis
            signs[axis] = sign
        }
        let index = edgeSlotIndex[code((signs[0], signs[1], signs[2]))]
        return index >= 0 ? index : nil
    }

    /// 该角块在还原态属于哪个槽位；有轴重复或缺轴时返回 nil
    static func cornerHomeSlot(_ colors: [CubeColor]) -> Int? {
        var signs = [0, 0, 0]
        for color in colors {
            let (axis, sign) = axisSign(of: color)
            guard signs[axis] == 0 else { return nil }
            signs[axis] = sign
        }
        guard signs.allSatisfy({ $0 != 0 }) else { return nil }
        let index = cornerSlotIndex[code((signs[0], signs[1], signs[2]))]
        return index >= 0 ? index : nil
    }

    // MARK: - 朝向

    /// 角朝向 ∈ {0,1,2}：上/下色贴纸在逆时针环流里相对"上/下面那一格"偏移了几格。
    /// 那一格固定排在第 0 位，所以朝向就是它的下标。还原态恒为 0；
    /// 合法状态总和 ≡ 0 (mod 3)。
    static func cornerOrientation(_ colors: [CubeColor]) -> Int {
        colors.firstIndex { isUpDownColor($0) } ?? 0
    }

    /// 法向的固定次序：+X, −X, +Y, −Y, +Z, −Z
    static func normalRank(_ direction: V3) -> Int {
        let axis = direction.x != 0 ? 0 : (direction.y != 0 ? 1 : 2)
        return axis * 2 + (direction.x + direction.y + direction.z > 0 ? 0 : 1)
    }

    /// 颜色在还原态所属面的法向次序。与 `normalRank` 同一套编号：
    /// 红 0 / 橙 1 / 白 2 / 黄 3 / 绿 4 / 蓝 5
    static func colorRank(_ color: CubeColor) -> Int {
        switch color {
        case .red: return 0
        case .orange: return 1
        case .white: return 2
        case .yellow: return 3
        case .green: return 4
        case .blue: return 5
        }
    }

    /// 棱朝向 ∈ {0,1}。
    ///
    /// 取法只有一句话：**把槽位的两个面位、棱块的两张贴纸各自按法向次序排好，
    /// 朝向 = 1 当且仅当"还原态次序靠前的那张贴纸"落在了"槽位次序靠后的面位"上。**
    /// 因为比较的只是两个颜色的次序，不必先把棱块认出来。
    ///
    /// **守恒性**：某次转动让某条棱的朝向翻转，当且仅当该槽位靠前的面位没有被
    /// 转到目标槽位靠前的面位上——这个条件**只取决于槽位，与块无关**。逐个外层
    /// 转动数一遍：R / L 的四个面位同为 +X / −X，且该轴被转动保持，翻转 0 条；
    /// F / B 的面位恰好首尾相接，翻转 0 条；U 的面位是 +Y +X +Y −X，D 同理，
    /// 各翻转 4 条。六个生成元翻转数全为偶数，故总和模 2 守恒。
    /// `CubeLegalityTests` 用 18 个外层转动 × 200 个打乱态钉住了这一点。
    ///
    /// 注：这与教科书里"F 翻 4 条棱"的取法不是同一个函数，但两者只差一个每槽
    /// 固定的偏移，判定合法性完全等价。
    static func edgeOrientation(_ colors: [CubeColor]) -> Int {
        guard colors.count == 2 else { return 0 }
        return colorRank(colors[0]) < colorRank(colors[1]) ? 0 : 1
    }

    // MARK: - 奇偶性

    /// 置换的奇偶性：0 = 偶，1 = 奇。按轮换分解，交换次数 = 各轮换长度减一之和
    static func permutationParity(_ permutation: [Int]) -> Int {
        var visited = [Bool](repeating: false, count: permutation.count)
        var swaps = 0
        for start in permutation.indices where !visited[start] {
            var length = 0
            var node = start
            while !visited[node] {
                visited[node] = true
                node = permutation[node]
                length += 1
            }
            swaps += length - 1
        }
        return swaps % 2
    }
}
