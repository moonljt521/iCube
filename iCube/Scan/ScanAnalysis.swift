import CubeKit
import CubeScan
import Foundation

/// 一次识别的结果。
///
/// 拍照与视频两条输入路径共用——它们的差别只在"六个面从哪来"，凑齐之后的
/// 分类、拼装、歧义处理完全一样，没必要写两份。
struct ScanResult {
    /// 首选状态
    let state: CubeState
    /// 全部候选（只差整体旋转的已归并）。三阶恒为 1 个；
    /// **偶数阶可能多于 1 个**——两个不同的面互为旋转时，照片分不出谁是谁。
    let candidates: [CubeState]
    /// 给用户看的一句提醒（把握度不够 / 有多解），没有则为 nil
    let hint: String?
}

/// 六个面 → 状态，以及配套的用户文案。
///
/// 原来这些都挂在 `ScanModel` 上，但视频识别走的是另一条采集路径，
/// 同样需要"拼装 + 出错诊断 + 歧义提醒"。与其复制一份，不如把这层抽出来共用。
enum ScanAnalysis {

    /// 识别的两种出口。用专门的枚举而不是 `Result<CubeState, String>`——
    /// `Result` 的 Failure 必须实现 `Error`，而这里的失败只需要一句给用户看的话。
    enum Outcome {
        case assembled(ScanResult)
        case failed(String)
    }

    /// 把相机帧次序的采样重排成屏幕次序。
    ///
    /// 帧是横的、屏幕是竖的，预览层把画面**顺时针转了 90°**才上屏。界面凡是画采样色的
    /// 地方都要过这一道：取景框上压的实时色块、下面那排已拍缩略图——**漏了哪一处，
    /// 哪一处就会跟用户看到的贴纸差 90°**（缩略图漏过一次，表现是"拍完缩略图是转的"）。
    ///
    /// **只用于显示**：分类器吃的仍是帧的次序。帧的次序与屏幕次序是"旋转"关系，
    /// `FaceletAssembler` 枚举 4 种朝向能消化；一旦把采样顺序也改了，关系就变成"转置"
    /// （镜像），下游再也补不回来。
    static func reorderedForDisplay(_ samples: [LabColor], size: Int) -> [LabColor] {
        guard samples.count == size * size else { return samples }
        return (0..<samples.count).map { samples[ScanGeometry.frameIndex(forDisplayIndex: $0, size: size)] }
    }

    /// 分类 + 拼装。同步且吃 CPU（三阶几十毫秒，偶数阶要枚举面身份、四阶实测 0.15 秒），
    /// **必须在主线程之外调用**。
    static func analyse(_ captures: [FaceCapture], size: Int) -> Outcome {
        do {
            let classified = try StickerClassifier.classify(captures, size: size)
            let solutions = FaceletAssembler.assembleAll(classified.colors, size: size)
            guard let first = solutions.first else {
                return .failed(assemblyFailureMessage(colors: classified.colors, size: size))
            }
            // 多于一个解不是错误：偶数阶没有中心块，两个不同的面互为旋转时，
            // "哪张照片是哪个面"就真的分不出来（实测二阶约一成状态如此，而且
            // 每个候选都是真能拧出来的状态）。把候选交给用户挑，别替他赌。
            let candidates = solutions.sorted {
                $0.stickers.map(\.rawValue).lexicographicallyPrecedes($1.stickers.map(\.rawValue))
            }
            let hint = ambiguityHint(count: candidates.count) ?? confidenceHint(margin: classified.margin)
            return .assembled(ScanResult(state: first, candidates: candidates, hint: hint))
        } catch let error as ScanError {
            return .failed(error.userMessage)
        } catch {
            return .failed("识别失败，请重来一次")
        }
    }

    /// 拼不出来时尽量说清"哪里不对"。
    ///
    /// 最有用的是**色数**：任何合法魔方每色恒 N² 格。少了说明有面没拍到或拍重了，
    /// 多了说明有格子认错——这两种的下一步动作完全不同（一个重拍、一个改一格），
    /// 只丢一句"拼不出"用户不知道从哪下手。
    static func assemblyFailureMessage(colors: [Face: [CubeColor]], size: Int) -> String {
        var counts: [CubeColor: Int] = [:]
        for grid in colors.values {
            for color in grid { counts[color, default: 0] += 1 }
        }
        let expected = size * size
        let off = CubeColor.allCases.compactMap { color -> String? in
            let count = counts[color] ?? 0
            guard count != expected else { return nil }
            return "\(color.displayName) \(count) 格"
        }
        guard !off.isEmpty else {
            return "这六个面拼不出一个真实的魔方。颜色数看着都对，那多半是格子认错了或者有面拍重了——请重来一次。"
        }
        return "这六个面拼不出一个真实的魔方：\(off.joined(separator: "、"))，本该每色 \(expected) 格。"
            + "多半是有一面拍重了或没拍全——请重来一次。"
    }

    /// 候选多于一个时给一句提醒；只有一个返回 nil。
    ///
    /// 文案要说清"为什么"和"怎么办"：用户得知道这不是识别坏了，而是照片里真的缺这个信息，
    /// 以及下一步该做什么（对照魔方核对，不对就换拼法）。
    static func ambiguityHint(count: Int) -> String? {
        guard count > 1 else { return nil }
        return "这个状态有 \(count) 种拼法（有两个面互为旋转，光看画面分不出来）。"
            + "请对照手上的魔方核对，不对就按下面的「换拼法」。"
    }

    /// 把握度不够时给一句提醒；够有把握返回 nil。
    ///
    /// 文案要说清"哪里可能不对、该怎么办"——只说"把握不大"用户不知道下一步做什么。
    static func confidenceHint(margin: Double) -> String? {
        guard margin < ClassifiedFaces.lowConfidenceThreshold else { return nil }
        return "识别把握不大（把握度 \(String(format: "%.1f", margin))）。"
            + "反光或光线不均时容易有格子认错，建议对照展开图核一遍，不对就改一格或重来一次。"
    }
}
