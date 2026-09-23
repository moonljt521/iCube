import CubeKit
import Foundation

/// 一次拍摄的 N² 个采样色，按"正视该面时的 row-major"排。
///
/// 这里**不记录这是哪个面**——奇数阶的面身份由中心块的颜色决定，而中心块的颜色
/// 要等六个面凑齐、一起做完聚类才知道。用户按什么顺序、什么角度拍都不影响结果。
///
/// 偶数阶连中心块都没有，面身份更是无从判断，只能先按拍摄次序占位，
/// 真正的"哪张照片对应哪个面"交给 `FaceletAssembler` 枚举。
public struct FaceCapture: Hashable, Sendable {
    public let samples: [LabColor]

    public init(samples: [LabColor]) {
        self.samples = samples
    }

    /// 阶数：由采样格数 N² 反推（和 `CubeState.size` 同一套"不落盘"的做法）
    public var size: Int {
        let value = Int(Double(samples.count).squareRoot().rounded())
        precondition(value * value == samples.count, "采样格数 \(samples.count) 不是平方数")
        return value
    }

    /// 中心块采样。**偶数阶没有中心块**，返回 nil
    public var center: LabColor? {
        let n = size
        guard n % 2 == 1 else { return nil }
        return samples[(n * n - 1) / 2]
    }
}

/// 一次识别的结果
public struct ClassifiedFaces: Hashable, Sendable {
    /// 每个面的 N² 格颜色，次序是**拍摄时的读入次序**，可能相对该面的标准朝向转了 90°/180°/270°。
    /// 摆正由 `FaceletAssembler` 负责。
    ///
    /// 键的含义随阶数不同：**奇数阶是真正的面**（由中心块颜色定出）；
    /// **偶数阶只是"第几张照片"的占位**（按 `Face.allCases` 的次序）。
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
    /// 两个面的中心块颜色太接近——多半是同一面拍了两次（奇数阶）
    case duplicateCenter(first: Int, second: Int, distance: Double)
    /// 两个面被判成了同一种颜色。理论上命名是双射，走到这里说明聚类退化了
    case duplicateFace(Face)
    /// 六种颜色没能分开
    case ambiguousColors
}

/// 把 6N² 个采样色归成 6 种颜色。
///
/// ## 为什么不能直接拿固定参考色做最近邻
///
/// 现场光照、白平衡、贴纸材质都会让同一种颜色拍出不同的 Lab，偏差常常比
/// 红与橙之间的差距还大。所以这里**自带标定**，直接拿现场样本当聚类种子，
/// 颜色空间就跟着这次拍摄走。
///
/// ## 种子从哪来（奇数阶与偶数阶的分岔）
///
/// **奇数阶**：六个中心块在物理上必然互异，是六种颜色的天然锚点，直接当种子。
/// 而且中心块永不换面，聚类过程中把它们钉死在自己那一簇，结果更稳。
///
/// **偶数阶**：没有中心块。改用**最远点采样**——先取彩度最低的样本当白
/// （白色是唯一接近无彩的，这比"最亮的那个"稳），再反复取"离已选种子最远"的
/// 样本补足六个。与 k-means++ 的初始化同一路子，无随机数、确定性强。
///
/// ## 硬约束
///
/// 无论哪种阶数，每种颜色恰好 N² 个（物理事实）。簇大小不对就搬最骑墙的样本，
/// 能把边界上偶尔判错的一两个样本拉回来。
public enum StickerClassifier {

    /// 两个中心块采样近到这个程度，就认为用户把同一面拍了两遍（奇数阶）
    public static let duplicateCenterDistance = 10.0

    /// 两张照片整面平均色差小于这个程度，就认为"很像"。**只用来提醒，不用来拒绝**。
    ///
    /// 为什么不能拿它拦：偶数阶没有中心块，只能整面比，而"两个**不同的**面互为 90° 旋转"
    /// 是家常便饭——二阶一面只有 4 格，实测测试素材页里第 3 面（`BRUF`）与第 6 面（`UBFR`）
    /// 就完全互为旋转，色差 5.2。真机上照这个拦，用户会卡在"第 6 面怎么都拍不进去"。
    ///
    /// 而且这道判据**原理上就分不开**：两张照片的差别只来自光照与磨损，跟"是不是同一个面"
    /// 没有必然关系（合成数据里两个互为旋转的不同面，色差是 0）。所以偶数阶只在拍摄当场
    /// 提一句"很像"，收不收由用户决定；真的拍重了，最后拼装会失败并提示。
    public static let duplicateCaptureDistance = 3.0

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

    /// - Parameter size: 阶数。缺省 3，保持旧调用不变。
    public static func classify(_ captures: [FaceCapture], size: Int = 3) throws -> ClassifiedFaces {
        guard captures.count == Face.count else { throw ScanError.wrongFaceCount(captures.count) }
        let per = size * size
        for (index, capture) in captures.enumerated() where capture.samples.count != per {
            throw ScanError.wrongSampleCount(face: index, count: capture.samples.count)
        }

        let centerIndex = size % 2 == 1 ? (per - 1) / 2 : nil

        // 判重面只在奇数阶做：中心块两两互异是硬事实，比中心色判得准。
        // 偶数阶没有中心块，整面比**原理上分不开**"同一个面"与"两个互为旋转的不同面"
        // （见 `duplicateCaptureDistance`），判错了会把一次正常扫描直接毙掉，
        // 所以干脆不判——真拍重了，拼装那一步自然会失败。
        if let centerIndex {
            try rejectDuplicateCenters(captures, centerIndex: centerIndex)
        }

        // 自由样本：capture * per + offset，奇数阶跳过被钉死的中心块
        var samples: [LabColor] = []
        samples.reserveCapacity(captures.count * per)
        for capture in captures {
            for offset in 0..<per where offset != centerIndex {
                samples.append(capture.samples[offset])
            }
        }

        let pinned: [LabColor?]
        let seeds: [LabColor]
        if let centerIndex {
            let centers = captures.map { $0.samples[centerIndex] }
            seeds = centers
            pinned = centers.map { Optional($0) }
        } else {
            let picked = farthestPointSeeds(samples)
            guard picked.count == Face.count else { throw ScanError.ambiguousColors }
            seeds = picked
            pinned = Array(repeating: nil, count: Face.count)
        }

        var assignment = assign(samples, seeds: seeds)
        var clusterCenters = centroids(samples: samples, seeds: seeds, pinned: pinned, assignment: assignment)
        for _ in 0..<maxIterations {
            let next = assign(samples, seeds: clusterCenters)
            let nextCenters = centroids(samples: samples, seeds: seeds, pinned: pinned, assignment: next)
            if next == assignment, nextCenters == clusterCenters { break }
            assignment = next
            clusterCenters = nextCenters
        }

        // 硬约束：每簇恰好 N² 个（奇数阶的中心块已经钉死在簇里，从自由样本里少算一个）
        let target = per - (centerIndex == nil ? 0 : 1)
        repair(&assignment, samples: samples, centroids: clusterCenters, target: target)

        let names = name(centroids: clusterCenters)
        let confidence = margin(samples: samples, centroids: clusterCenters, assignment: assignment)

        var colors: [Face: [CubeColor]] = [:]
        if let centerIndex {
            // 奇数阶：每个中心块落在哪一簇，那一簇就代表这个面的颜色
            for index in captures.indices {
                guard let color = names[index] else { throw ScanError.ambiguousColors }
                let face = Face.allCases.first { $0.defaultColor == color }!
                guard colors[face] == nil else { throw ScanError.duplicateFace(face) }
                var grid = [CubeColor]()
                grid.reserveCapacity(per)
                // `samples` 按 capture 顺序铺开，每个 capture 占 per−1 格（跳过中心）
                var cursor = index * (per - 1)
                for position in 0..<per {
                    if position == centerIndex {
                        grid.append(color)
                    } else {
                        guard let name = names[assignment[cursor]] else { throw ScanError.ambiguousColors }
                        grid.append(name)
                        cursor += 1
                    }
                }
                colors[face] = grid
            }
        } else {
            // 偶数阶：面身份无从判断，先按拍摄次序占位
            for index in captures.indices {
                var grid = [CubeColor]()
                grid.reserveCapacity(per)
                var cursor = index * per
                for _ in 0..<per {
                    guard let name = names[assignment[cursor]] else { throw ScanError.ambiguousColors }
                    grid.append(name)
                    cursor += 1
                }
                colors[Face.allCases[index]] = grid
            }
        }

        return ClassifiedFaces(colors: colors, margin: confidence)
    }

    // MARK: - 判重面

    /// 奇数阶：中心块两两拉开距离。太近说明同一面拍了两次，或者有面没拍到
    private static func rejectDuplicateCenters(_ captures: [FaceCapture], centerIndex: Int) throws {
        let centers = captures.map { $0.samples[centerIndex] }
        for first in 0..<centers.count {
            for second in (first + 1)..<centers.count {
                let distance = centers[first].distance(to: centers[second])
                if distance < duplicateCenterDistance {
                    throw ScanError.duplicateCenter(first: first, second: second, distance: distance)
                }
            }
        }
    }

    /// 两个面网格在"各自转过 90° 的整数倍"下最接近时的逐格平均色差。
    ///
    /// 偶数阶的判重面用不上它（见 `duplicateCaptureDistance` 里为什么分不开），
    /// 只给应用层在拍摄当场提一句"很像"用。
    public static func closestRotationDistance(_ lhs: [LabColor], _ rhs: [LabColor]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        let size = Int(Double(lhs.count).squareRoot().rounded())
        guard size * size == lhs.count else { return .infinity }
        var best = Double.infinity
        for turns in 0..<FaceletAssembler.rotationsPerFace {
            let rotated = FaceletAssembler.rotated(lhs, quarterTurns: turns, size: size)
            var total = 0.0
            for (a, b) in zip(rotated, rhs) { total += a.distance(to: b) }
            best = min(best, total / Double(lhs.count))
        }
        return best
    }

    // MARK: - 聚类

    /// 偶数阶的种子：最远点采样（k-means++ 那一路子，但确定性的）
    private static func farthestPointSeeds(_ samples: [LabColor]) -> [LabColor] {
        guard samples.count >= Face.count else { return [] }
        var seeds: [LabColor] = []
        // 白是唯一彩度接近 0 的，先把它挑出来当第一个种子
        if let whitest = samples.min(by: { $0.chroma < $1.chroma }) { seeds.append(whitest) }
        while seeds.count < Face.count {
            var best: LabColor?
            var bestDistance = -1.0
            for sample in samples {
                let nearest = seeds.map { sample.distance(to: $0) }.min() ?? .infinity
                if nearest > bestDistance {
                    bestDistance = nearest
                    best = sample
                }
            }
            guard let best, bestDistance > 0 else { return [] }
            seeds.append(best)
        }
        return seeds
    }

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

    /// 重算各簇中心：`pinned` 里给了固定成员的簇（奇数阶的中心块），那份采样永远属于自己那一簇
    private static func centroids(
        samples: [LabColor],
        seeds: [LabColor],
        pinned: [LabColor?],
        assignment: [Int]
    ) -> [LabColor] {
        let count = seeds.count
        var sums = Array(repeating: (l: 0.0, a: 0.0, b: 0.0), count: count)
        var counts = Array(repeating: 0, count: count)
        for (index, sample) in samples.enumerated() {
            let cluster = assignment[index]
            sums[cluster].l += sample.l
            sums[cluster].a += sample.a
            sums[cluster].b += sample.b
            counts[cluster] += 1
        }
        return (0..<count).map { cluster in
            var l = sums[cluster].l
            var a = sums[cluster].a
            var b = sums[cluster].b
            var total = counts[cluster]
            if let fixed = pinned[cluster] {
                l += fixed.l
                a += fixed.a
                b += fixed.b
                total += 1
            }
            guard total > 0 else { return seeds[cluster] }
            return LabColor(l: l / Double(total), a: a / Double(total), b: b / Double(total))
        }
    }

    /// 把簇大小修到恰好 `target`：从超员的簇里挑"搬走代价最小"的样本，塞进缺员的簇。
    ///
    /// 这条约束不是启发式，是物理事实——每种颜色正好 N² 个贴纸。
    /// 它能把边界上偶尔判错的一两个样本拉回来。
    private static func repair(_ assignment: inout [Int], samples: [LabColor], centroids: [LabColor], target: Int) {
        while true {
            var counts = Array(repeating: 0, count: centroids.count)
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
        guard !margins.isEmpty else { return 0 }
        margins.sort()
        return margins[margins.count / 10]
    }
}
