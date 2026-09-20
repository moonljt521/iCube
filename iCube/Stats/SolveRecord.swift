import Foundation
import SwiftData

enum SolvePenalty: String, CaseIterable, Codable {
    case plain = "无"
    case plusTwo = "+2"
    case dnf = "DNF"
}

@Model
final class SolveRecord {
    var startedAt: Date
    var rawSeconds: Double
    var penaltyRaw: String
    var scramble: String
    var moveCount: Int
    /// 阶数（2/3/4）。轻量迁移：老记录默认 3 阶
    var cubeSize: Int = 3

    init(startedAt: Date, rawSeconds: Double, penalty: SolvePenalty, scramble: String, moveCount: Int, cubeSize: Int = 3) {
        self.startedAt = startedAt
        self.rawSeconds = rawSeconds
        self.penaltyRaw = penalty.rawValue
        self.scramble = scramble
        self.moveCount = moveCount
        self.cubeSize = cubeSize
    }

    var penalty: SolvePenalty {
        get { SolvePenalty(rawValue: penaltyRaw) ?? .plain }
        set { penaltyRaw = newValue.rawValue }
    }

    var isDNF: Bool { penalty == .dnf }

    /// 计入统计的成绩：+2 罚时后取值，DNF 不参与
    var effectiveSeconds: Double? {
        switch penalty {
        case .dnf: return nil
        case .plain: return rawSeconds
        case .plusTwo: return rawSeconds + 2
        }
    }
}

enum SolveStats {

    static func best(_ records: [SolveRecord]) -> Double? {
        records.compactMap(\.effectiveSeconds).min()
    }

    /// WCA 均值：去掉一个最快和一个最慢后取平均。
    /// 这里把 DNF 排除在样本外（严格规则下含 DNF 的均值应记为 DNF），
    /// 首版取宽松口径，UI 上标注样本数以免误读。
    static func average(of size: Int, _ records: [SolveRecord]) -> Double? {
        let samples = records.compactMap(\.effectiveSeconds)
        guard samples.count >= size else { return nil }
        let window = Array(samples.prefix(size)).sorted()
        let trimmed = window.dropFirst().dropLast()
        guard !trimmed.isEmpty else { return window.first }
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    static func format(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let minutes = Int(clamped) / 60
        let remainder = clamped.truncatingRemainder(dividingBy: 60)
        return minutes > 0
            ? String(format: "%d:%05.2f", minutes, remainder)
            : String(format: "%.2f", remainder)
    }
}
