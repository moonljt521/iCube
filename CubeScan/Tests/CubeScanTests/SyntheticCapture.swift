import CubeKit
import XCTest
@testable import CubeScan

/// 测试共用的合成工具：把 `CubeState` 变成"相机拍到的 6 个面"。
enum SyntheticCapture {

    /// 现场光照的粗略模型：**线性 RGB** 上的对角缩放，外加一点噪声。
    ///
    /// 缩放必须在**线性**空间做——真实光照就是这样作用的，相机的白平衡也是这么做的。
    /// 若改成缩放 gamma 编码后的 sRGB，白点校正就再也补不回来：那是模型本身不自洽，
    /// 不是算法有问题。之前正是这个 bug 让"白点校正反而把误差放大"的假象出现。
    struct Lighting {
        var red: Double = 1
        var green: Double = 1
        var blue: Double = 1
        /// 噪声幅度，**相对**值（模拟散粒噪声）。
        ///
        /// 用相对量而不是绝对量：散粒噪声与信号强度成正比。若用绝对量，
        /// 暗光下的暗通道会被噪声整个淹没——那不是被测算法的问题，是模型失真。
        var noise: Double = 0

        static let daylight = Lighting()
        /// 暖光（偏黄）：钨丝灯下白块拍出来明显偏黄
        static let warm = Lighting(red: 1.18, green: 1.00, blue: 0.60)
        /// 冷光（偏蓝）：阴天或冷白 LED
        static let cool = Lighting(red: 0.78, green: 0.95, blue: 1.32)
        /// 偏暗：整体压暗，白平衡没做时明度差得最多
        static let dim = Lighting(red: 0.45, green: 0.45, blue: 0.50)

        func apply(_ color: LabColor, generator: inout SplitMix64) -> LabColor {
            let linear = color.linearComponents
            var r = linear.red * red
            var g = linear.green * green
            var b = linear.blue * blue
            if noise > 0 {
                r *= 1 + jitter(generator: &generator)
                g *= 1 + jitter(generator: &generator)
                b *= 1 + jitter(generator: &generator)
            }
            return LabColor(linearRed: max(r, 0), green: max(g, 0), blue: max(b, 0))
        }

        private func jitter(generator: inout SplitMix64) -> Double {
            Double(Int.random(in: -127...127, using: &generator)) / 127 * noise
        }
    }

    /// 某个面的 9 格颜色（row-major）
    static func grid(of state: CubeState, face: Face) -> [CubeColor] {
        (0..<9).map { state.color(at: face, row: $0 / 3, col: $0 % 3) }
    }

    /// 把一个面"拍"成 9 个采样色。`rotation` 模拟拍摄时该面相对标准朝向转了多少。
    static func capture(
        grid: [CubeColor],
        rotation: Int,
        lighting: Lighting,
        generator: inout SplitMix64
    ) -> FaceCapture {
        let rotated = FaceletAssembler.rotated(grid, quarterTurns: rotation)
        let samples = rotated.map { color in
            lighting.apply(referenceLab(color), generator: &generator)
        }
        return FaceCapture(samples: samples)
    }

    /// 六种颜色的理想 Lab（与分类器的参考值同源，作为"真值"）
    static func referenceLab(_ color: CubeColor) -> LabColor {
        StickerClassifier.references[color]!
    }

    /// 把状态拍成 6 个 capture，每个面各自随机朝向
    static func captures(
        of state: CubeState,
        rotations: [Face: Int],
        lighting: Lighting = .daylight,
        seed: UInt64 = 1
    ) -> [FaceCapture] {
        var generator = SplitMix64(seed: seed)
        return Face.allCases.map { face in
            capture(
                grid: grid(of: state, face: face),
                rotation: rotations[face] ?? 0,
                lighting: lighting,
                generator: &generator
            )
        }
    }

    /// 与 `FaceletAssembler.rotated` 同一套下标变换，作用在采样色上
    static func rotated(_ samples: [LabColor], quarterTurns: Int) -> [LabColor] {
        var result = samples
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            var next = result
            for row in 0..<3 {
                for col in 0..<3 {
                    next[row * 3 + col] = result[(2 - col) * 3 + row]
                }
            }
            result = next
        }
        return result
    }

    static func randomRotations(seed: UInt64 = 7) -> [Face: Int] {
        var generator = SplitMix64(seed: seed)
        var result: [Face: Int] = [:]
        for face in Face.allCases { result[face] = Int.random(in: 0..<4, using: &generator) }
        return result
    }

    /// 两个面网格是否只差一个 90° 的整数倍旋转。
    ///
    /// 分类器只负责认出颜色，**不负责摆正**——每个面拍进去时相对标准朝向转了
    /// 0/90/180/270° 是随机的，分类器无从知道。摆正是 `FaceletAssembler` 的活。
    /// 所以比"认对了没有"时必须容许一个旋转。
    static func equalUpToRotation(_ lhs: [CubeColor], _ rhs: [CubeColor]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return (0..<4).contains { FaceletAssembler.rotated(lhs, quarterTurns: $0) == rhs }
    }
}
