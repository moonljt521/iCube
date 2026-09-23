import CubeKit
import Foundation

/// 把六个面拼成一个 `CubeState`。
///
/// ## 要解决的问题
///
/// 用户拿着手机绕着魔方拍，每个面拍进去时"哪一边朝上"是随机的——同一个面可以
/// 被拍成 4 种朝向之一。所以 `StickerClassifier` 交出来的每个面，其 9 格次序
/// 都只是**拍摄时的读入次序**，跟该面在本体坐标系里的标准朝向差一个 0/90/180/270°
/// 的旋转，而且这个旋转量事先无从知道。
///
/// ## 怎么解
///
/// 不去猜朝向，而是**枚举 + 验证**：6 个面各 4 种朝向，共 4⁶ = 4096 种组合，
/// 逐一拼成状态，用 `CubeState.isLegalState` 筛。物理上只有一种组合能拼出
/// 可达状态，所以合法的那个就是答案。
///
/// 枚举听起来笨，但快：合法性判定从最便宜的条件开始早退，绝大多数组合在
/// 第一两条棱上就出局了，整体不到 20ms，且可以丢到后台线程。
///
/// 这个做法还有个额外好处——**朝向组合本身不需要用户配合**。拍的时候怎么转
/// 魔方、手机横竖怎么拿，都不影响结果。
public enum FaceletAssembler {

    /// 每个面的读入朝向有 4 种
    public static let rotationsPerFace = 4

    /// 拼出状态；找不到合法组合时返回 nil。
    ///
    /// nil 的含义是"这 54 格拼不出任何一个真实魔方"，最常见的原因有三种：
    /// 有格子认错了颜色、魔方不是标准配色（白对黄、绿对蓝、红对橙）、
    /// 或者有面没拍全。三种都该让用户复核，不该硬猜。
    public static func assemble(_ colors: [Face: [CubeColor]]) -> CubeState? {
        guard let grids = rotations(of: colors) else { return nil }
        let faces = Face.allCases
        var index = [Int](repeating: 0, count: faces.count)
        var stickers = [CubeColor](repeating: .white, count: 54)

        while true {
            for (position, face) in faces.enumerated() {
                let grid = grids[position][index[position]]
                for offset in 0..<9 { stickers[face.rawValue * 9 + offset] = grid[offset] }
            }
            if CubeState(stickers: stickers).isLegalState { return CubeState(stickers: stickers) }

            // 六位四进制的进位
            var digit = 0
            while digit < faces.count {
                index[digit] += 1
                if index[digit] < rotationsPerFace { break }
                index[digit] = 0
                digit += 1
            }
            if digit == faces.count { return nil }
        }
    }

    /// 所有能拼出的合法状态（去重）。
    ///
    /// 正常情况恰好 1 个。多于 1 个意味着这些状态互相只差一个整体旋转——
    /// 对求解没有影响（解会以该状态的朝向给出，3D 演示也按同一朝向画），
    /// 但值得在测试里钉住"打乱态不会有第二个"。
    public static func assembleAll(_ colors: [Face: [CubeColor]]) -> Set<CubeState> {
        guard let grids = rotations(of: colors) else { return [] }
        let faces = Face.allCases
        var index = [Int](repeating: 0, count: faces.count)
        var stickers = [CubeColor](repeating: .white, count: 54)
        var found: Set<CubeState> = []

        while true {
            for (position, face) in faces.enumerated() {
                let grid = grids[position][index[position]]
                for offset in 0..<9 { stickers[face.rawValue * 9 + offset] = grid[offset] }
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

    /// 把某面的 9 格按读取方向旋转 90° 的整数倍
    public static func rotated(_ grid: [CubeColor], quarterTurns: Int) -> [CubeColor] {
        precondition(grid.count == 9, "只处理 3×3 的面")
        var result = grid
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            var next = result
            for row in 0..<3 {
                for col in 0..<3 {
                    // 顺时针：新图的 (r, c) 来自原图的 (2 − c, r)
                    next[row * 3 + col] = result[(2 - col) * 3 + row]
                }
            }
            result = next
        }
        return result
    }

    /// 每面展开成 4 种读入朝向；输入不完整时返回 nil
    private static func rotations(of colors: [Face: [CubeColor]]) -> [[[CubeColor]]]? {
        var result: [[[CubeColor]]] = []
        for face in Face.allCases {
            guard let grid = colors[face], grid.count == 9 else { return nil }
            result.append((0..<rotationsPerFace).map { rotated(grid, quarterTurns: $0) })
        }
        return result
    }
}
