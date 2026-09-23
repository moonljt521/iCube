import CubeKit
import Foundation

/// 把六个面拼成一个 `CubeState`。
///
/// ## 要解决的问题
///
/// 用户拿着手机绕着魔方拍，每个面拍进去时"哪一边朝上"是随机的——同一个面可以
/// 被拍成 4 种朝向之一。所以 `StickerClassifier` 交出来的每个面，其 N² 格次序
/// 都只是**拍摄时的读入次序**，跟该面在本体坐标系里的标准朝向差一个 0/90/180/270°
/// 的旋转，而且这个旋转量事先无从知道。
///
/// ## 怎么解
///
/// 不去猜朝向，而是**枚举 + 验证**：逐面枚举 4 种朝向，拼成状态后用
/// `CubeState.isLegalState` 筛。物理上只有一种组合能拼出可达状态，
/// 所以合法的那个就是答案。枚举听起来笨，但快：合法性判定从最便宜的条件开始
/// 早退，绝大多数组合在第一两步就出局了。
///
/// 这个做法还有个额外好处——**朝向组合本身不需要用户配合**。拍的时候怎么转
/// 魔方、手机横竖怎么拿，都不影响结果。
///
/// ## 奇数阶与偶数阶差一件事：面身份
///
/// **奇数阶（三阶）**：每面中心块的颜色就告诉了我们这是哪个面（白中心必是 U 面），
/// 所以面身份是**已知**的，只需枚举 4⁶ = 4096 种朝向。而且 `legality` 要求中心块
/// 各就各位，整体旋转过的写法会被拒掉，答案唯一。
///
/// **偶数阶（2 / 4 阶）**：没有固定中心块，面身份**未知**，必须把"哪张照片对应哪个面"
/// 一起枚举——6! × 4⁶ 共 295 万种。直接穷举要好几秒，所以用整体旋转对称性砍掉 6 倍：
/// 固定 0 号照片落在 U 面且朝向取 0（同一族解里恰好有一个满足），剩下的
/// 5! × 4⁵ = 122,880 种，实测四阶 0.15 秒。
///
/// 偶数阶的解天然是一族 24 个（整体旋转），这里统一取
/// `CubeState.rotationallyCanonical` 作为代表，`assembleAll` 因此也只剩一个元素。
public enum FaceletAssembler {

    /// 每个面的读入朝向有 4 种
    public static let rotationsPerFace = 4

    /// 拼出状态；找不到合法组合时返回 nil。
    ///
    /// nil 的含义是"这 6N² 格拼不出任何一个真实魔方"，最常见的原因有四种：
    /// 有格子认错了颜色、魔方不是标准配色（白对黄、绿对蓝、红对橙）、
    /// 有面没拍全、或者（偶数阶）拍照角度让某个面的朝向无从确定。四种都该让用户复核，
    /// 不该硬猜。
    ///
    /// - Parameter size: 阶数。缺省 3，保持旧调用不变。
    public static func assemble(_ colors: [Face: [CubeColor]], size: Int = 3) -> CubeState? {
        assembleAll(colors, size: size).first
    }

    /// 所有能拼出的合法状态（只差一个整体旋转的算同一个）。
    ///
    /// 三阶恰好 1 个；偶数阶经 `rotationallyCanonical` 归并后也是 1 个。
    /// **多于 1 个说明输入有歧义**——同一组照片能拼出两颗不同的魔方，
    /// 调用方应当拒绝并让用户重拍，而不是随便挑一个。
    public static func assembleAll(_ colors: [Face: [CubeColor]], size: Int = 3) -> Set<CubeState> {
        guard let grids = rotatedGrids(of: colors, size: size) else { return [] }
        return size == 3 ? oddOrderSolutions(grids) : evenOrderSolutions(grids, size: size)
    }

    /// 把某面的 N² 格按读取方向旋转 90° 的整数倍。
    /// 泛型是为了同时服务 `CubeColor`（拼状态）与 `LabColor`（判重面时整面比对）。
    public static func rotated<T>(_ grid: [T], quarterTurns: Int, size: Int = 3) -> [T] {
        precondition(grid.count == size * size, "只处理 \(size)×\(size) 的面")
        var result = grid
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            var next = result
            for row in 0..<size {
                for col in 0..<size {
                    // 顺时针：新图的 (r, c) 来自原图的 (N−1 − c, r)
                    next[row * size + col] = result[(size - 1 - col) * size + row]
                }
            }
            result = next
        }
        return result
    }

    // MARK: - 奇数阶：面身份已知，只枚举朝向

    /// 4⁶ 种朝向组合，逐位四进制进位
    private static func oddOrderSolutions(_ grids: [[[CubeColor]]]) -> Set<CubeState> {
        let per = grids[0][0].count
        let faces = Face.allCases
        var index = [Int](repeating: 0, count: faces.count)
        var stickers = [CubeColor](repeating: .white, count: faces.count * per)
        var found: Set<CubeState> = []

        while true {
            for (position, face) in faces.enumerated() {
                let grid = grids[position][index[position]]
                for offset in 0..<per { stickers[face.rawValue * per + offset] = grid[offset] }
            }
            let state = CubeState(stickers: stickers)
            if state.isLegalState { found.insert(state) }

            var digit = 0
            while digit < faces.count {
                index[digit] += 1
                if index[digit] < rotationsPerFace { break }
                index[digit] = 0
                digit += 1
            }
            if digit == faces.count { break }
        }
        return found
    }

    // MARK: - 偶数阶：面身份未知，枚举"照片 → 面"的指派 × 朝向

    /// 递归枚举照片到本体面的双射，每张照片再枚举 4 种朝向。
    ///
    /// 第 0 张照片固定落在 U 面、朝向取 0：偶数阶的合法状态在 24 种整体旋转下闭合，
    /// 同一族解里恰好有一个满足这条，所以这样砍掉 6 倍枚举量而不丢解。
    private static func evenOrderSolutions(_ grids: [[[CubeColor]]], size: Int) -> Set<CubeState> {
        let per = size * size
        let count = Face.count
        let faces = Face.allCases
        var stickers = [CubeColor](repeating: .white, count: count * per)
        /// 照片下标 → 本体面的 rawValue
        var assignment = [Int](repeating: -1, count: count)
        var rotation = [Int](repeating: 0, count: count)
        var used = [Bool](repeating: false, count: count)
        var found: Set<CubeState> = []

        func place(_ position: Int) {
            if position == count {
                for photographed in 0..<count {
                    let grid = grids[photographed][rotation[photographed]]
                    let base = assignment[photographed] * per
                    for offset in 0..<per { stickers[base + offset] = grid[offset] }
                }
                let candidate = CubeState(stickers: stickers)
                if candidate.isLegalState { found.insert(candidate.rotationallyCanonical) }
                return
            }

            if position == 0 {
                used[0] = true
                assignment[0] = faces[0].rawValue
                rotation[0] = 0
                place(1)
                used[0] = false
                assignment[0] = -1
                return
            }

            for photographed in 0..<count where !used[photographed] {
                used[photographed] = true
                assignment[photographed] = faces[position].rawValue
                for turns in 0..<rotationsPerFace {
                    rotation[photographed] = turns
                    place(position + 1)
                }
                used[photographed] = false
                assignment[photographed] = -1
            }
        }

        place(0)
        return found
    }

    // MARK: - 输入展开

    /// 每面展开成 4 种读入朝向；输入不完整时返回 nil
    private static func rotatedGrids(of colors: [Face: [CubeColor]], size: Int) -> [[[CubeColor]]]? {
        var result: [[[CubeColor]]] = []
        for face in Face.allCases {
            guard let grid = colors[face], grid.count == size * size else { return nil }
            result.append((0..<rotationsPerFace).map { rotated(grid, quarterTurns: $0, size: size) })
        }
        return result
    }
}
