import Foundation

/// 状态是否可达（"合法"）的判定结果。
///
/// 填满 6N² 格、每色恰好 N² 个，**不等于**这个状态拧得出来：单独翻一条棱、
/// 单独扭一个角、或两块互换位置，都会让状态脱离可达群。求解器也能拦住这些
/// （见 `CubeSolveError.illegalState`），但它要先把 21MB 查找表装进内存，
/// 代价远高于这里。拍照识别需要在几千个朝向候选里筛状态，必须有廉价判定。
public enum CubeLegality: Equatable, Sendable {
    case legal

    /// 只对 2/3/4 阶有定义
    case unsupportedSize(Int)

    /// 某面的中心块不是该面的标准色。中心块永不移动，是整局配色的锚点。
    /// **只在奇数阶出现**——偶数阶的中心块本身就会换面。
    case centerMismatch(face: Face)

    /// 某颜色不是恰好 N² 个
    case colorCountMismatch(color: CubeColor, count: Int)

    /// 第 `slot` 个角块不是"三个轴各取一色"
    case invalidCorner(slot: Int)

    /// 同一个角块出现了两次——等价于有角块缺失
    case duplicateCorner

    /// 角块落在"旋转到不了"的位姿上，也就是整块被镜像了。
    ///
    /// 奇数阶靠中心块就挡住了（镜像会把中心块挪走），偶数阶没有中心块兜底，
    /// 只能显式查手性。漏了这条，识别会把魔方和它的镜像都当成候选，
    /// 在 4096 种朝向里挑出一个"看起来合法但拧不出来"的状态。
    case mirroredCorner(slot: Int)

    /// 第 `slot` 个棱块不是"两个轴各取一色"
    case invalidEdge(slot: Int)

    /// 同一个棱块出现了两次
    case duplicateEdge

    /// 第 `slot` 个翼棱的两个贴纸不在两条不同的轴上（四阶及以上）
    case invalidWing(slot: Int)

    /// 第 `group` 个棱组不是恰好两条翼棱（四阶及以上）
    case wingPairMismatch(group: Int, count: Int)

    /// 角朝向和不是 3 的倍数：有角被单独扭转了
    ///
    /// 不带数值：具体和依赖朝向的取法约定，只有"模 3 非零"这一点是客观的。
    case cornerTwistSum

    /// 棱朝向和不是偶数：有棱被单独翻转了。同上，不带数值
    case edgeFlipSum

    /// 翼棱翻转和不是偶数（四阶及以上）。同上，不带数值
    case wingFlipSum

    /// 棱与角的置换奇偶性不一致：恰好有两块互换了位置
    case permutationParity(corner: Int, edge: Int)
}

public extension CubeState {

    /// 该状态是否拧得出来
    var isLegalState: Bool { legality == .legal }

    /// 逐项判定状态合法性，**首个**不满足的条件即返回。
    ///
    /// 检查顺序刻意从便宜到贵、从最可能出错到最不可能。拍照识别会拿它筛
    /// 几万到十几万个候选，绝大多数候选在前两步就出局了。
    var legality: CubeLegality {
        switch size {
        case 3: return threeByThreeLegality
        case 2, 4: return evenOrderLegality
        default: return .unsupportedSize(size)
        }
    }

    // MARK: - 三阶

    /// 三阶判定。**口径**：要求中心块各就各位，也就是"这串能直接喂给求解器"。
    /// 因此整体翻转过的魔方（`x` / `y` / `z` 或 `M` / `E` / `S`）会落到
    /// `.centerMismatch`——它们当然拧得出来，但面位记法不认那个朝向。
    ///
    /// 检查顺序：中心块 → 色数 → 棱 → 角 → 朝向和 → 奇偶性。
    private var threeByThreeLegality: CubeLegality {
        for face in Face.allCases where centerColor(of: face) != face.defaultColor {
            return .centerMismatch(face: face)
        }

        var counts: [CubeColor: Int] = [:]
        counts.reserveCapacity(CubeColor.allCases.count)
        for color in stickers { counts[color, default: 0] += 1 }
        for color in CubeColor.allCases where counts[color] != 9 {
            return .colorCountMismatch(color: color, count: counts[color] ?? 0)
        }

        // 棱有 12 个槽位、角只有 8 个，先查棱早退得更快。
        //
        // 这里刻意沿用 `edgeSigns` / `cornerSigns` 的枚举次序，不走 `slots(for:)`：
        // 下面要算**置换的奇偶性**，而奇偶性依赖槽位的枚举次序（换个次序等价于
        // 右乘一个重排，奇偶性会整体翻转）。次序一改，"角奇偶 == 棱奇偶"这条
        // 不变量就不再成立于可达态了。偶数阶那边只用求和与计数，与次序无关。
        var edgeTaken = [Bool](repeating: false, count: CubieGeometry.edgeSigns.count)
        var edgePermutation = [Int](repeating: 0, count: CubieGeometry.edgeSigns.count)
        var edgeFlips = 0
        for (slot, signs) in CubieGeometry.edgeSigns.enumerated() {
            let center = CubieGeometry.center(of: signs, size: 3)
            let colors = CubieGeometry.edgeColors(of: self, center: center, size: 3)
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
            let center = CubieGeometry.center(of: signs, size: 3)
            let colors = CubieGeometry.cornerColors(of: self, center: center)
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

    // MARK: - 偶数阶（2 阶 / 4 阶）

    /// 偶数阶没有固定中心块，配色朝向无从锚定（同一颗魔方，24 种整体旋转都是
    /// 合法状态），所以判定只能基于**块结构**：
    ///
    /// 1. 角块：摆放手性正确、8 个角块各一次、扭角和 ≡ 0 (mod 3)
    /// 2. 翼棱（四阶起）：两格在两条不同轴上、12 个棱组各恰好两条、翻转和 ≡ 0 (mod 2)
    /// 3. 每色恰好 N² 个
    ///
    /// 三条都不是手推出来的，是用 200 个随机可达态逐条钉住的
    /// （`CubeLegalityTests.test_evenOrderInvariantsHoldOnRandomStates`）。
    ///
    /// **中心块不单独查**：角块贡献每色 4 个、翼棱贡献每色 8 个，色数要求总共
    /// N² = 16 就把中心块的每色 4 个逼出来了。识别时要过十几万个候选，能省则省。
    private var evenOrderLegality: CubeLegality {
        let n = size
        let slots = CubieGeometry.slots(for: n)

        var cornerTaken = [Bool](repeating: false, count: CubieGeometry.cornerSigns.count)
        var cornerTwists = 0
        for (slot, center) in slots.corners.enumerated() {
            // 手性必须先查：`cornerHomeSlot` 只看颜色落在哪条轴上，对镜像摆放是盲的
            guard CubieGeometry.cornerPlacementIsProper(self, center: center) else {
                return .mirroredCorner(slot: slot)
            }
            let colors = CubieGeometry.cornerColors(of: self, center: center)
            guard let home = CubieGeometry.cornerHomeSlot(colors) else { return .invalidCorner(slot: slot) }
            if cornerTaken[home] { return .duplicateCorner }
            cornerTaken[home] = true
            cornerTwists += CubieGeometry.cornerOrientation(colors)
        }
        if cornerTwists % 3 != 0 { return .cornerTwistSum }

        if !slots.wings.isEmpty {
            var groupCounts = [Int](repeating: 0, count: CubieGeometry.edgeSigns.count)
            var wingFlips = 0
            for (slot, center) in slots.wings.enumerated() {
                let colors = CubieGeometry.edgeColors(of: self, center: center, size: n)
                guard let group = CubieGeometry.edgeHomeSlot(colors) else { return .invalidWing(slot: slot) }
                groupCounts[group] += 1
                wingFlips += CubieGeometry.edgeOrientation(colors)
            }
            for (group, count) in groupCounts.enumerated() where count != 2 {
                return .wingPairMismatch(group: group, count: count)
            }
            if wingFlips % 2 != 0 { return .wingFlipSum }
        }

        var counts: [CubeColor: Int] = [:]
        counts.reserveCapacity(CubeColor.allCases.count)
        for color in stickers { counts[color, default: 0] += 1 }
        for color in CubeColor.allCases where counts[color] != n * n {
            return .colorCountMismatch(color: color, count: counts[color] ?? 0)
        }

        return .legal
    }
}

/// 块结构推导：角块 / 棱块（四阶起是翼棱）/ 中心块。
///
/// 槽位、贴纸索引、朝向**全部由整数格点几何运行时推出**，不引入手抄查找表——
/// 与 `TurnTable` 的转动置换同一套做法。
///
/// ## 块怎么认
///
/// 立方体占据 [-N, N]³，小立方体边长 2、中心落在 {-N+1, -N+3, …, N-1}³。
/// 一个块中心若有 **k 个坐标的绝对值等于 N-1**，它就是 k 阶块：
///
/// | k | 块 | 三阶 | 四阶 |
/// | --- | --- | --- | --- |
/// | 3 | 角块 | 8 | 8 |
/// | 2 | 棱块 / 翼棱 | 12 | 24 |
/// | 1 | 中心块 | 6 | 24 |
/// | 0 | 内部（看不见） | — | — |
///
/// 三阶的"棱块恰有一个坐标为零"是这套规则在 N=3 时的特例，别把它当通例——
/// 四阶翼棱三个坐标都非零。
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

    /// 符号三元组 → 某阶数的块中心（块中心落在 {-N+1, -N+3, …, N-1}）
    static func center(of signs: (x: Int, y: Int, z: Int), size: Int) -> V3 {
        V3(signs.x, signs.y, signs.z) * (size - 1)
    }

    /// 某阶数的三类块中心
    struct PieceSlots: Sendable {
        let corners: [V3]
        let wings: [V3]
        let centers: [V3]
    }

    /// 随首查惰性推导并常驻（与 `TurnTable.tables` 同一做法）
    private static let slotCache: [Int: PieceSlots] = {
        var result = [Int: PieceSlots]()
        for size in [2, 3, 4] { result[size] = deriveSlots(size: size) }
        return result
    }()

    static func slots(for size: Int) -> PieceSlots {
        if let cached = slotCache[size] { return cached }
        return deriveSlots(size: size)
    }

    private static func deriveSlots(size: Int) -> PieceSlots {
        let surface = size - 1
        var corners: [V3] = []
        var wings: [V3] = []
        var centers: [V3] = []
        for x in stride(from: -surface, through: surface, by: 2) {
            for y in stride(from: -surface, through: surface, by: 2) {
                for z in stride(from: -surface, through: surface, by: 2) {
                    let center = V3(x, y, z)
                    switch normals(of: center, size: size).count {
                    case 3: corners.append(center)
                    case 2: wings.append(center)
                    case 1: centers.append(center)
                    default: break
                    }
                }
            }
        }
        return PieceSlots(corners: corners, wings: wings, centers: centers)
    }

    /// 该块朝外的贴纸法向：坐标绝对值等于 size-1 的那些轴，符号随坐标
    static func normals(of center: V3, size: Int) -> [V3] {
        let surface = size - 1
        var result: [V3] = []
        for (value, unit) in [(center.x, V3.posX), (center.y, V3.posY), (center.z, V3.posZ)]
        where abs(value) == surface {
            result.append(value > 0 ? unit : -unit)
        }
        return result
    }

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
    static func cornerColors(of state: CubeState, center: V3) -> [CubeColor] {
        let x = V3(center.x > 0 ? 1 : -1, 0, 0)
        let y = V3(0, center.y > 0 ? 1 : -1, 0)
        let z = V3(0, 0, center.z > 0 ? 1 : -1)
        let normals = center.x * center.y * center.z > 0 ? [y, z, x] : [y, x, z]
        return colors(of: state, center: center, normals: normals)
    }

    /// 棱块两个面位的颜色，按法向次序排好（见 `normalRank`）
    static func edgeColors(of state: CubeState, center: V3, size: Int) -> [CubeColor] {
        let normals = normals(of: center, size: size)
            .sorted { normalRank($0) < normalRank($1) }
        return colors(of: state, center: center, normals: normals)
    }

    private static func colors(of state: CubeState, center: V3, normals: [V3]) -> [CubeColor] {
        normals.map { state.color(at: center, facing: $0)! }
    }

    // MARK: - 手性

    /// 角块的摆放是否"正"（不是镜像）。
    ///
    /// ## 为什么需要
    ///
    /// `cornerHomeSlot` 只回答"这个角块属于哪个槽位"，它对**摆放的手性**是盲的：
    /// 把整颗魔方镜像一下，8 个角块照样各归其位、扭角和照样是 3 的倍数。
    /// 奇数阶靠中心块挡住镜像（中心块会被挪走），偶数阶没有中心块，只能显式查。
    ///
    /// ## 判据
    ///
    /// 角块上有三张贴纸，每张贴纸的颜色都归属一条轴（`axisSign`）。记
    /// **归属坐标系** = 三条归属轴上的单位向量按符号拼成的三面角，
    /// **落位坐标系** = 这三张贴纸实际贴在槽位的哪三个面上。
    ///
    /// 摆放是旋转 ⟺ 两个坐标系同手性 ⟺ 行列式相等。
    static func cornerPlacementIsProper(_ state: CubeState, center: V3) -> Bool {
        var homeSigns = [0, 0, 0]
        var faceDirections = [V3.zero, V3.zero, V3.zero]
        for (value, unit) in [(center.x, V3.posX), (center.y, V3.posY), (center.z, V3.posZ)] {
            let direction = value > 0 ? unit : -unit
            guard let color = state.color(at: center, facing: direction) else { return false }
            let (homeAxis, homeSign) = axisSign(of: color)
            // 同一轴出现两张贴纸 ⇒ 这个"角块"根本不成立，交给 cornerHomeSlot 报 invalidCorner
            guard homeSigns[homeAxis] == 0 else { return false }
            homeSigns[homeAxis] = homeSign
            faceDirections[homeAxis] = direction
        }
        let homeDeterminant = homeSigns[0] * homeSigns[1] * homeSigns[2]
        let actualDeterminant = faceDirections[0].dot(faceDirections[1].cross(faceDirections[2]))
        return homeDeterminant == actualDeterminant
    }

    // MARK: - 归属

    /// 该棱块在还原态属于哪个槽位；两色同轴（互为对面色）时返回 nil。
    /// 四阶的翼棱同样走这里——它只关心"两色在哪两条轴上"，与层深无关。
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
    ///
    /// **四阶翼棱复用同一条**：翼棱两个面位也在两条不同轴上，判据一字不改。
    /// 实测 200 个随机可达态翻转和恒为偶数（同一条测试钉住）。
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
