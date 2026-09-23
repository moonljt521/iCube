import CubeKit
import Foundation

/// 一次拍摄的 9 个采样色，按"正视该面时的 row-major"排。下标 4 是中心块。
///
/// 这里**不记录这是哪个面**——面的身份由中心块的颜色决定，而中心块的颜色要等
/// 六个面凑齐、一起做完聚类才知道。用户按什么顺序、什么角度拍都不影响结果。
public struct FaceCapture: Hashable, Sendable {
    public let samples: [LabColor]

    public init(samples: [LabColor]) {
        self.samples = samples
    }

    /// 中心块采样
    public var center: LabColor? {
        samples.count == 9 ? samples[4] : nil
    }
}

/// 一次识别的结果
public struct ClassifiedFaces: Hashable, Sendable {
    /// 每个面的 9 格颜色，次序是**拍摄时的读入次序**，可能相对该面的标准朝向转了 90°/180°/270°。
    /// 摆正由 `FaceletAssembler` 负责。
    public let colors: [Face: [CubeColor]]

    /// 把握程度：所有样本"到本簇距离"与"到次近簇距离"之差的最小十分位（Lab 单位）。
    /// 越小说明越有样本骑在两个颜色中间。低于 `lowConfidenceThreshold` 就该重拍。
    public let margin: Double

    /// `margin` 低于这个值，这次识别的把握就不够。
    ///
    /// 取 4：干净输入（合成、日光）实测 margin 大于 15，留了足够余量；低到 4 以下说明
    /// 确实有格子骑在两个颜色中间。这里只给判据，**不替调用方决定**是拦下重拍还是
    /// 只提示一句——把握度低不等于结果一定错，那是应用层该权衡的事。
    public static let lowConfidenceThreshold: Double = 4
}

public enum ScanError: Error, Equatable, Sendable {
    case wrongFaceCount(Int)
    case wrongSampleCount(face: Int, count: Int)
    /// 两个面的中心块颜色太接近——多半是同一面拍了两次
    case duplicateCenter(first: Int, second: Int, distance: Double)
    /// 两个面被判成了同一种颜色。理论上命名是双射，走到这里说明聚类退化了
    case duplicateFace(Face)
    /// 六种颜色没能分开
    case ambiguousColors
}

/// 把 54 个采样色归成 6 种颜色。
///
/// ## 为什么不能直接拿固定参考色做最近邻
///
/// 现场光照、白平衡、贴纸材质都会让同一种颜色拍出不同的 Lab，偏差常常比
/// 红与橙之间的差距还大。所以这里**自带标定**：六个中心块在物理上必然互异，
/// 是六种颜色的天然锚点，直接拿它们当聚类种子，颜色空间就跟着这次拍摄走。
///
/// ## 流程
///
/// 1. 六个中心块采样作种子，把其余 48 个样本迭代分配到最近的簇
/// 2. 用"每色恰好 9 个"这条硬约束修掉边界误判——簇大小不对就搬最骑墙的那个样本
/// 3. 认出哪一簇是白（彩度最低的那个），用它做白点校正
/// 4. 剩下五簇按校正后的 Lab 距离对到黄/绿/蓝/红/橙
public enum StickerClassifier {

    /// 两个中心块采样近到这个程度，就认为用户把同一面拍了两遍
    public static let duplicateCenterDistance = 10.0

    /// 聚类迭代上限。实测两三次就收敛，留余量
    public static let maxIterations = 12

    /// 六种颜色的参考值。取自应用内"经典"皮肤，作为白点校正后的对齐目标。
    /// 它们是**相对**基准，不是绝对标准——材质的差异靠后续的合法性判定兜底。
    public static let references: [CubeColor: LabColor] = [
        .white: LabColor(srgbRed: 0.97, green: 0.97, blue: 0.97),
        .yellow: LabColor(srgbRed: 1.00, green: 0.82, blue: 0.04),
        .green: LabColor(srgbRed: 0.10, green: 0.68, blue: 0.24),
        .blue: LabColor(srgbRed: 0.09, green: 0.36, blue: 0.86),
        .red: LabColor(srgbRed: 0.86, green: 0.13, blue: 0.13),
        .orange: LabColor(srgbRed: 0.98, green: 0.45, blue: 0.05),
    ]

    public static func classify(_ captures: [FaceCapture]) throws -> ClassifiedFaces {
        guard captures.count == 6 else { throw ScanError.wrongFaceCount(captures.count) }
        for (index, capture) in captures.enumerated() where capture.samples.count != 9 {
            throw ScanError.wrongSampleCount(face: index, count: capture.samples.count)
        }
        let centers = captures.map { $0.samples[4] }

        // 中心块两两拉开距离：太近说明同一面拍了两次，或者有面没拍到
        for first in 0..<6 {
            for second in (first + 1)..<6 {
                let distance = centers[first].distance(to: centers[second])
                if distance < duplicateCenterDistance {
                    throw ScanError.duplicateCenter(first: first, second: second, distance: distance)
                }
            }
        }

        // 非中心样本：capture * 8 + offset，offset 跳过下标 4
        var samples: [LabColor] = []
        samples.reserveCapacity(48)
        for capture in captures {
            for index in 0..<9 where index != 4 { samples.append(capture.samples[index]) }
        }

        var assignment = assign(samples, seeds: centers)
        var clusterCenters = centroids(samples: samples, centers: centers, assignment: assignment)
        for _ in 0..<maxIterations {
            let next = assign(samples, seeds: clusterCenters)
            let nextCenters = centroids(samples: samples, centers: centers, assignment: next)
            if next == assignment, nextCenters == clusterCenters { break }
            assignment = next
            clusterCenters = nextCenters
        }

        // 硬约束：每簇除中心块外恰好 8 个
        repair(&assignment, samples: samples, centroids: clusterCenters)

        let names = name(centroids: clusterCenters)
        let confidence = margin(samples: samples, centroids: clusterCenters, assignment: assignment)

        // 每个中心块落在哪一簇，那一簇就代表这个面的颜色
        var colors: [Face: [CubeColor]] = [:]
        for index in captures.indices {
            guard let color = names[index] else { throw ScanError.ambiguousColors }
            let face = Face.allCases.first { $0.defaultColor == color }!
            guard colors[face] == nil else { throw ScanError.duplicateFace(face) }
            var grid = [CubeColor]()
            grid.reserveCapacity(9)
            // `samples` 按 capture 顺序铺开，每个 capture 占 8 格（跳过中心）
            var cursor = index * 8
            for position in 0..<9 {
                if position == 4 {
                    grid.append(color)
                } else {
                    guard let name = names[assignment[cursor]] else { throw ScanError.ambiguousColors }
                    grid.append(name)
                    cursor += 1
                }
            }
            colors[face] = grid
        }

        return ClassifiedFaces(colors: colors, margin: confidence)
    }

    // MARK: - 聚类

    /// 每个样本归到最近的种子
    private static func assign(_ samples: [LabColor], seeds: [LabColor]) -> [Int] {
        samples.map { sample in
            var best = 0
            var bestDistance = Double.infinity
            for (index, seed) in seeds.enumerated() {
                let distance = sample.distance(to: seed)
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return best
        }
    }

    /// 重算各簇中心：中心块采样是固定的，永远属于自己那一簇
    private static func centroids(
        samples: [LabColor],
        centers: [LabColor],
        assignment: [Int]
    ) -> [LabColor] {
        var sums = Array(repeating: (l: 0.0, a: 0.0, b: 0.0), count: 6)
        var counts = Array(repeating: 0, count: 6)
        for (index, sample) in samples.enumerated() {
            let cluster = assignment[index]
            sums[cluster].l += sample.l
            sums[cluster].a += sample.a
            sums[cluster].b += sample.b
            counts[cluster] += 1
        }
        return (0..<6).map { cluster in
            let total = counts[cluster] + 1
            return LabColor(
                l: (sums[cluster].l + centers[cluster].l) / Double(total),
                a: (sums[cluster].a + centers[cluster].a) / Double(total),
                b: (sums[cluster].b + centers[cluster].b) / Double(total)
            )
        }
    }

    /// 把簇大小修到恰好 8：从超员的簇里挑"搬走代价最小"的样本，塞进缺员的簇。
    ///
    /// 这条约束不是启发式，是物理事实——三阶魔方每种颜色正好 9 个贴纸。
    /// 它能把边界上偶尔判错的一两个样本拉回来。
    private static func repair(_ assignment: inout [Int], samples: [LabColor], centroids: [LabColor]) {
        let target = 8
        while true {
            var counts = Array(repeating: 0, count: 6)
            for cluster in assignment { counts[cluster] += 1 }
            guard let surplus = counts.indices.filter({ counts[$0] > target }).max(by: { counts[$0] < counts[$1] }),
                  let deficit = counts.indices.filter({ counts[$0] < target }).min(by: { counts[$0] < counts[$1] })
            else { return }

            var bestIndex = -1
            var bestCost = Double.infinity
            for (index, cluster) in assignment.enumerated() where cluster == surplus {
                let cost = samples[index].distance(to: centroids[deficit])
                    - samples[index].distance(to: centroids[surplus])
                if cost < bestCost {
                    bestCost = cost
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { return }
            assignment[bestIndex] = deficit
        }
    }

    // MARK: - 命名

    /// 六簇 → 六色。
    ///
    /// 先认白：白色是唯一彩度接近 0 的，五个人眼可辨的颜色彩度都在 60 以上，
    /// 这一步比"最亮的那个"稳得多（黄在暗光下可能比白还亮）。
    ///
    /// 判据是**相对**的，不是"彩度小于某个绝对值"。暖光会给白块染上明显的黄味，
    /// 实测暖光下白块彩度能到 26、冷光下到 28，写死一个 25 就会把白块当彩色丢掉；
    /// 而同一场景里彩度最低的彩色块也有 40 以上。所以只要比第二低的低一大截就算白。
    private static func whiteCluster(of centroids: [LabColor]) -> Int? {
        guard centroids.count == 6 else { return nil }
        let ranked = centroids.indices.sorted { centroids[$0].chroma < centroids[$1].chroma }
        let candidate = centroids[ranked[0]].chroma
        let runnerUp = centroids[ranked[1]].chroma
        guard candidate < 0.7 * runnerUp else { return nil }
        return ranked[0]
    }

    /// 认出白之后做白点校正，再拿校正过的簇心去对五个彩色参考值——不校正的话
    /// 一盏暖光就能把红和橙换个个儿。
    private static func name(centroids: [LabColor]) -> [CubeColor?] {
        guard let whiteIndex = whiteCluster(of: centroids) else {
            return Array(repeating: nil, count: 6)
        }

        // 校正目标取"白"的参考值本身，而不是某个抽象的参考白：
        // 这样校正后的白簇心与 references[.white] 严丝合缝，其余颜色也对得齐
        let observedWhite = centroids[whiteIndex]
        let whiteReference = references[.white]!
        let chromatic: [CubeColor] = [.yellow, .green, .blue, .red, .orange]

        // 校正后的簇心与参考值
        var adapted: [(cluster: Int, color: LabColor)] = []
        for cluster in centroids.indices where cluster != whiteIndex {
            adapted.append((cluster, centroids[cluster].adapted(fromWhite: observedWhite, toWhite: whiteReference)))
        }

        // 贪心配对：每轮取"距离最小的一对"定下来，保证是双射
        var remaining = Set(adapted.map(\.cluster))
        var result = Array(repeating: CubeColor?.none, count: 6)
        result[whiteIndex] = .white
        while !remaining.isEmpty {
            var best: (cluster: Int, color: CubeColor, distance: Double)?
            for entry in adapted where remaining.contains(entry.cluster) {
                for color in chromatic where !result.contains(color) {
                    let distance = entry.color.distance(to: references[color]!)
                    if best == nil || distance < best!.distance {
                        best = (entry.cluster, color, distance)
                    }
                }
            }
            guard let choice = best else { break }
            result[choice.cluster] = choice.color
            remaining.remove(choice.cluster)
        }
        return result
    }

    /// 把握程度：每个样本"到次近簇"与"到本簇"距离之差的最小十分位（Lab 单位）。
    /// 取最小十分位而不是均值——只要有一格骑在两个颜色中间，整次识别就不该被信任。
    private static func margin(samples: [LabColor], centroids: [LabColor], assignment: [Int]) -> Double {
        var margins: [Double] = []
        margins.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            let own = sample.distance(to: centroids[assignment[index]])
            var other = Double.infinity
            for (cluster, centroid) in centroids.enumerated() where cluster != assignment[index] {
                other = min(other, sample.distance(to: centroid))
            }
            margins.append(other - own)
        }
        margins.sort()
        return margins[margins.count / 10]
    }
}
