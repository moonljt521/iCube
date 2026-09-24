import CoreGraphics
import CubeKit
import Foundation

/// 在一帧里找到"魔方的那个面在哪"。
///
/// 拍照模式不需要它——引导框是固定的居中正方形，用户自己把魔方填满方框。
/// 但**视频里魔方会晃、会远近变化**，固定框必然采错：用户手持转动时，画面里的
/// 魔方左右偏移十几个像素、大小变一两成是常态。这里是那个"自动对准"的环节。
///
/// ## 为什么不做轮廓检测
///
/// 找魔方轮廓（边缘、直线、网格线）听起来更直接，但现场光照、反光、手指遮挡
/// 都会让轮廓断掉；二阶（2×2）几乎没有内部网格线可抓；而魔方转起来时边缘是虚的。
///
/// 这里改用一个**更强的先验**：魔方的一面是 N×N 个格子，每格必然是六种魔方色之一。
/// 于是"这一框像不像魔方的一个面"可以直接量化成"每格离最近的参考色有多远"——
/// 框对准了距离就小，框落在背景（墙、桌面、手）上就大。
///
/// ## 评分只用参考色，不用 `classify`
///
/// `StickerClassifier.classify` 要**六个面凑齐**才能聚类（它拿现场样本当种子，
/// 颜色空间跟着这次拍摄走），单帧根本调不动它。所以这里只能用
/// `StickerClassifier.references` 这组绝对参考值。
///
/// 光照偏移对所有候选框是**同一份**（同一帧、同一光照），所以拿绝对参考值做
/// **相对比较**是够用的：我们要的是"哪个框最像魔方"，不是"这格到底是什么颜色"。
/// 颜色最终仍由 `classify` 定夺——它那一步有现场标定，比这里准得多。
public enum FaceLocator {

    /// 定位结果
    public struct LocatedFace: Hashable, Sendable {
        /// N² 个采样色，**帧的次序**（row-major）。
        ///
        /// 与拍照模式一致：次序不追画面方向，摆正是 `FaceletAssembler` 的活。
        /// **显示**前要拧，见 `ScanGeometry.displayIndex`。
        public let samples: [LabColor]
        /// 采到它的引导框，归一化视频坐标
        public let guide: CGRect
        /// 评分，越大越好（= 负的平均到最近参考色距离）
        public let score: Double

        public init(samples: [LabColor], guide: CGRect, score: Double) {
            self.samples = samples
            self.guide = guide
            self.score = score
        }
    }

    /// 引导框基准边长占画面短边的比例。与拍照模式的 `ScanGeometry` 默认值一致。
    public static let baseRatio = 0.82

    /// 搜索时试的尺度倍率（乘以画面短边）。
    ///
    /// 覆盖 0.4~1.0 五档：手持魔方时离镜头远近差别很大，画面里魔方可能只占
    /// 三成也可能占满。档位太稀会**框不准**——框明显大于魔方时，边缘那些格子
    /// 采到的是背景，分类必然错。实测三档（0.68/0.82/0.96）在魔方偏小时
    /// 找到的框只覆盖到它下半部分。
    public static let scaleVariants = [0.4, 0.55, 0.7, 0.85, 1.0]

    /// 搜索时中心点的偏移，单位是画面短边的比例。5×5 = 25 个位置。
    ///
    /// ±0.18 换算到 720p 的帧是 ±130 像素，够覆盖手持晃动了。
    ///
    /// **步长必须够密**。曾经只有 3×3（0 与 ±0.18），结果魔方偏 (+60,−60) 像素时
    /// 一个候选都对不上：能对准的大框一偏就采到背景、分数掉光，最后只剩"完全
    /// 落在魔方里"的小框胜出——而小框的采样点全挤在魔方中心，三阶会采出九个
    /// 一模一样的中心块颜色。加密到 0.09 一档（±65 像素）后对得上 (±65,−65)，
    /// 误差只剩几像素。
    public static let offsetVariants: [CGFloat] = [-0.18, -0.09, 0, 0.09, 0.18]

    /// "评分打平"的容差：分差在这个以内就认为是同一个结果，改按框的大小来挑。
    ///
    /// ## 为什么会打平
    ///
    /// 评分只看各格**采样区**（格子中心那 64%）的颜色。于是只要采样区还落在魔方上，
    /// 框大一点小一点分数**一模一样**——实测 2 阶五档框里有四档都是 7.9，只有最大的
    /// 那档掉到 −12.9（它的采样区探出去吃到背景了）。光靠分数根本选不出贴合的那个。
    ///
    /// ## 为什么打平时取**最大**的
    ///
    /// 框偏小的危害比偏大严重得多：采样点会挤在魔方中心那一小块区域上。三阶尤其
    /// 致命——九格的采样点全落进中心格，采出来九个一模一样的中心块颜色。
    /// 框偏大只到"采样区刚碰到背景"为止就会掉分，掉分前的最大框正好就是"采样区
    /// 还完完整整落在魔方里"的最大框，也就是最接近魔方真实大小的那个。
    ///
    /// 分差超过容差说明框确实偏了（采到背景会明显掉分），那就仍按分数选。
    public static let tieTolerance = 1.5

    /// 粗筛阶段每格抽几个点。定位阶段不需要 24×24 那么密，
    /// 用 8×8 先把 20 多个候选排个序，只对最好的那个做完整采样。
    public static let coarseSamplesPerAxis = 8

    /// 颜色多样性的奖励权重（每多出一种颜色加这么多分）。
    ///
    /// ## 为什么光靠距离不够
    ///
    /// 实测（`test_scoreSeparatesCubeFromBackground`）：白墙背景的评分 −0.9，
    /// 带魔方的帧 −0.4，**差距只有 0.5，完全分不开**。原因是白墙离"白"参考色
    /// 极近，而魔方的白格子也一样近——距离这一项拿它没办法。
    ///
    /// ## 为什么多样性救得回来
    ///
    /// 白墙是**一种**颜色，魔方的一面（打乱后）通常有 4~9 种。这一项不区分
    /// 是哪种颜色，只数种类，正好补上距离的盲区。实测加上之后白墙场景的差距
    /// 从 0.5 拉到十几。
    ///
    /// ## 代价
    ///
    /// 还原态的纯色面会因此被扣分——但那种状态本来也不需要求解，而且它和其他
    /// 五个面一起进拼装时会由合法性判定兜底，不会误判成背景。
    public static let varietyBonus = 4.0

    /// 一组 N² 采样"像不像魔方的一个面"，**越大越好**。
    ///
    /// 两项相加：
    /// - **距离**（负的）：每格到最近参考色的平均距离取负。框对准魔方时格子落在
    ///   魔方色附近，距离小；框落在背景上时，墙/桌面/手离六种魔方色都远。
    /// - **多样性**（正的）：这一框里出现了几种不同的魔方色。背景通常是单色，
    ///   魔方的一面通常多色——这一项专治白墙那种"离参考色很近"的背景。
    ///
    /// 取负是为了让调用方可以统一按"越大越好"排序，不用记两套方向。
    public static func score(_ samples: [LabColor]) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        var total = 0.0
        var kinds: Set<CubeColor> = []
        for sample in samples {
            let (color, distance) = nearestReference(sample)
            total += distance
            kinds.insert(color)
        }
        return -total / Double(samples.count) + Double(kinds.count - 1) * varietyBonus
    }

    /// 一个颜色离六种魔方参考色最近的那个，以及距离
    public static func nearestReference(_ color: LabColor) -> (CubeColor, Double) {
        var best: (CubeColor, Double) = (.white, .infinity)
        for (name, reference) in StickerClassifier.references {
            let distance = color.distance(to: reference)
            if distance < best.1 { best = (name, distance) }
        }
        return best
    }

    /// 一个颜色离六种魔方参考色最近有多远
    public static func distanceToNearestReference(_ color: LabColor) -> Double {
        nearestReference(color).1
    }

    /// 两组采样的逐格平均距离。用来判断"这两帧之间画面动没动"。
    ///
    /// 转动中的帧是**模糊**的——转动会同时把两个面的颜色糊进一个格子里，
    /// 采出来的颜色不在任何参考色附近，用这种帧等于主动喂垃圾给分类器。
    public static func drift(_ lhs: [LabColor], _ rhs: [LabColor]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .infinity }
        var total = 0.0
        for (a, b) in zip(lhs, rhs) { total += a.distance(to: b) }
        return total / Double(lhs.count)
    }

    // MARK: - 定位

    /// 最佳框要比"画面里的中位数框"好这么多，才认为画面里真有个魔方。
    ///
    /// ## 为什么是相对判据，不是绝对阈值
    ///
    /// 实测（`test_scoreSeparatesCubeFromBackground`）：光照会把绝对评分**整体**拉低——
    /// 暗光下"框对准魔方"的绝对评分能到 −18.2，比理想光下某些纯背景帧（−0.9）还低。
    /// 固定阈值必然顾此失彼：卡在 −20 会误杀暗光下正常的帧，放松到 −10 又会放过理想光的白墙。
    ///
    /// 而光照对**同一帧里所有候选框**的影响是同一份，所以"最佳框比中位数好多少"
    /// 这个差值天然免疫光照。实测四种光照（理想/暖/暗/冷）× 五种背景：
    ///
    /// | | 有魔方 | 纯背景 |
    /// | --- | --- | --- |
    /// | 对比度 | 6.9 ~ 36.7 | **全部 0.0** |
    ///
    /// 纯背景是均匀的，所有候选框评分一样，差值恰好 0——这个信号干净得不像话。
    /// 最坏情况是暗光下的白墙（6.9），取 5 留一点余量。真实场景背景不会那么均匀
    /// （有家具、阴影、手），如果实测误判偏多就往下调。
    public static let contrastThreshold = 5.0

    /// 在一帧里搜索最佳引导框并采样。画面里找不到像魔方的区域时返回 nil。
    ///
    /// - Parameters:
    ///   - buffer: 帧像素（BGRA）
    ///   - size: 阶数
    ///   - contrastThreshold: 见同名常量。传一个很大的值可以强制"总返回最佳框"
    ///     （测试量区分度时用）。
    public static func locate(
        _ buffer: PixelBufferView,
        size: Int,
        contrastThreshold: Double = contrastThreshold
    ) -> LocatedFace? {
        locateCandidates(buffer, size: size, limit: 1, contrastThreshold: contrastThreshold).first
    }

    /// 返回同一帧里评分最高的多个框。
    ///
    /// 拍照只需要一个最佳框；视频不能只押一个框——魔方倾斜、手指遮挡或一帧里
    /// 同时露出两面时，最佳候选可能只是“最像颜色的错误区域”。视频挑帧会保留
    /// 前几个候选，最后用六面合法性反选组合。
    public static func locateCandidates(
        _ buffer: PixelBufferView,
        size: Int,
        limit: Int = 4,
        contrastThreshold: Double = contrastThreshold
    ) -> [LocatedFace] {
        let frameSize = CGSize(width: buffer.width, height: buffer.height)
        var scored: [(guide: CGRect, score: Double)] = []

        for guide in candidates(frameSize: frameSize) {
            guard let samples = StickerSampler.sampleGrid(
                buffer,
                normalizedGuide: guide,
                size: size,
                samplesPerAxis: coarseSamplesPerAxis
            ) else { continue }
            scored.append((guide, score(samples)))
        }
        guard let top = scored.map(\.score).max() else { return [] }
        let sortedScores = scored.map(\.score).sorted()
        let median = sortedScores[sortedScores.count / 2]
        guard top - median >= contrastThreshold else { return [] }

        let ranked = scored
            .filter { $0.score >= top - tieTolerance * 2 }
            .sorted {
                if abs($0.score - $1.score) > 0.01 { return $0.score > $1.score }
                return area($0.guide, frameSize: frameSize) > area($1.guide, frameSize: frameSize)
            }

        var result: [LocatedFace] = []
        for candidate in ranked.prefix(max(1, limit)) {
            guard let fine = StickerSampler.sampleGrid(
                buffer, normalizedGuide: candidate.guide, size: size
            ) else { continue }
            result.append(LocatedFace(samples: fine, guide: candidate.guide, score: candidate.score))
        }
        return result
    }

    // MARK: - 阶数探测

    /// 一组采样到最近参考色的**平均**距离。不含多样性奖励。
    ///
    /// 跨阶数比较时必须用它而不是 `score`：`score` 含多样性奖励，而格子数不同
    /// （4/9/16）天然会数出不同种类的颜色，比出来的就不是"阶数对不对"了。
    public static func meanReferenceDistance(_ samples: [LabColor]) -> Double {
        guard !samples.isEmpty else { return .infinity }
        var total = 0.0
        for sample in samples { total += distanceToNearestReference(sample) }
        return total / Double(samples.count)
    }

    /// 候选引导框，归一化视频坐标。
    ///
    /// 在**像素空间**里算正方形，再转归一化——反过来算会踩 `StickerSampler.cellRect`
    /// 那个坑：归一化坐标里 x/y 尺度不同（1280×720 的帧），按归一化边长画出来的是长方形。
    public static func candidates(frameSize: CGSize) -> [CGRect] {
        guard frameSize.width > 0, frameSize.height > 0 else { return [] }
        let shortSide = min(frameSize.width, frameSize.height)
        let center = CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)

        var result: [CGRect] = []
        result.reserveCapacity(offsetVariants.count * offsetVariants.count * scaleVariants.count)
        for scale in scaleVariants {
            let side = shortSide * CGFloat(baseRatio * scale)
            for dx in offsetVariants {
                for dy in offsetVariants {
                    let origin = CGPoint(
                        x: center.x + shortSide * dx - side / 2,
                        y: center.y + shortSide * dy - side / 2
                    )
                    let pixel = CGRect(origin: origin, size: CGSize(width: side, height: side))
                    result.append(normalized(pixel, frameSize: frameSize))
                }
            }
        }
        return result
    }

    /// 框的像素面积。
    ///
    /// 不能直接比归一化面积：归一化坐标里 x/y 尺度不同（1280×720 的帧），
    /// 数值上一样的宽高对应的实际像素数差着近一倍。
    private static func area(_ guide: CGRect, frameSize: CGSize) -> Double {
        Double(guide.width * frameSize.width) * Double(guide.height * frameSize.height)
    }

    /// 像素矩形 → 归一化；超出画面的部分夹回来（宁可采到边角，也不要越界）
    private static func normalized(_ rect: CGRect, frameSize: CGSize) -> CGRect {
        let x = min(max(rect.minX / frameSize.width, 0), 1)
        let y = min(max(rect.minY / frameSize.height, 0), 1)
        let width = min(max(rect.width / frameSize.width, 0), 1 - x)
        let height = min(max(rect.height / frameSize.height, 0), 1 - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
