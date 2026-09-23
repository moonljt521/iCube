import Foundation

/// Kociemba 面位记法：三阶魔方状态的 54 字符字符串表示，是两阶段求解器等
/// 外部工具的事实标准。本文件负责它与 `CubeState` 之间的双向转换。
///
/// 与本项目内部约定有两处差异，转换时必须处理：
///
/// 1. **面的排列顺序不同**。外部约定是 `U R F D L B`；本项目 `Face` 的
///    rawValue 顺序是 `u d f b r l`。故需要一次块重排。
///
/// 2. **字符是"面的字母"而非颜色名**。`U` 代表白色、`R` 代表红色……
///    即该颜色在还原态下所属的那一面。这与 `Face.defaultColor` 是同一套
///    映射，所以颜色侧不需要额外换算。
///
/// 好消息是**每个面内部的读法一致**：都是"正视该面时 row-major，从左上起"，
/// 与 `CubeState.color(at:row:col:)` 相同。因此只需重排块顺序，不必翻转行列。
public enum FaceletNotation {

    /// 外部约定的面顺序：U R F D L B
    public static let faceOrder: [Face] = [.u, .r, .f, .d, .l, .b]

    /// 每个面的贴纸数（三阶）
    public static let faceletsPerFace = 9

    /// 总字符数
    public static let length = 54

    /// 颜色 → 字母：取该颜色在还原态所属面的字母
    public static func letter(for color: CubeColor) -> Character {
        switch color {
        case .white: return "U"
        case .yellow: return "D"
        case .green: return "F"
        case .blue: return "B"
        case .red: return "R"
        case .orange: return "L"
        }
    }

    /// 字母 → 颜色。大小写不敏感；非面字母返回 nil
    public static func color(for letter: Character) -> CubeColor? {
        switch Character(letter.uppercased()) {
        case "U": return .white
        case "D": return .yellow
        case "F": return .green
        case "B": return .blue
        case "R": return .red
        case "L": return .orange
        default: return nil
        }
    }
}

public extension CubeState {

    /// 三阶专用：转成 Kociemba 面位串（54 字符）。
    /// 非三阶返回 nil——该记法只定义在三阶上。
    var faceletString: String? {
        guard size == 3 else { return nil }
        var chars: [Character] = []
        chars.reserveCapacity(FaceletNotation.length)
        for face in FaceletNotation.faceOrder {
            for row in 0..<3 {
                for col in 0..<3 {
                    chars.append(FaceletNotation.letter(for: color(at: face, row: row, col: col)))
                }
            }
        }
        return String(chars)
    }

    /// 三阶专用：从 Kociemba 面位串还原状态。
    /// 长度不是 54、或含非法字符时返回 nil。
    ///
    /// 注意：这里**只做格式解析，不校验状态是否合法**（每色是否恰好 9 个、
    /// 棱角朝向与奇偶性等）。合法性请用 `isLegalState`。
    init?(faceletString: String) {
        let chars = Array(faceletString)
        guard chars.count == FaceletNotation.length else { return nil }

        // 先按外部顺序解出每面的 9 个颜色
        var colorsByFace: [Face: [CubeColor]] = [:]
        for (blockIndex, face) in FaceletNotation.faceOrder.enumerated() {
            var colors: [CubeColor] = []
            colors.reserveCapacity(FaceletNotation.faceletsPerFace)
            for offset in 0..<FaceletNotation.faceletsPerFace {
                let char = chars[blockIndex * FaceletNotation.faceletsPerFace + offset]
                guard let color = FaceletNotation.color(for: char) else { return nil }
                colors.append(color)
            }
            colorsByFace[face] = colors
        }

        // 再摆回本项目的槽位顺序（face.rawValue * 9 + row * 3 + col）
        var stickers: [CubeColor] = []
        stickers.reserveCapacity(FaceletNotation.length)
        for face in Face.allCases {
            guard let colors = colorsByFace[face] else { return nil }
            stickers.append(contentsOf: colors)
        }
        self.init(stickers: stickers)
    }
}
