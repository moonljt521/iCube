import CoreGraphics
import Foundation

/// CIE L*a*b* 颜色（D65 白点）。
///
/// 拍照识别全程在这个空间里做距离比较，而不是 sRGB：
///
/// - sRGB 的欧氏距离与"看起来像不像"对不上——同样差 30 个码值，
///   深蓝之间的差别肉眼几乎看不出，而浅黄之间的差别已经很明显。
/// - Lab 把**明度 L\*** 和**色度 (a\*, b\*)** 拆开了。现场光照主要影响明度，
///   色相和彩度相对稳定，分开之后就能针对性地做白点校正。
public struct LabColor: Hashable, Sendable {

    /// 明度，0（黑）~ 100（白）
    public var l: Double
    /// 绿(−) ↔ 红(+)
    public var a: Double
    /// 蓝(−) ↔ 黄(+)
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    // MARK: - 构造

    /// 从 sRGB 分量构造，分量取值 0...1
    public init(srgbRed red: Double, green: Double, blue: Double) {
        self = Self.fromXYZ(Self.xyz(red: red, green: green, blue: blue))
    }

    /// 从 8 位 sRGB 构造
    public init(byteRed red: UInt8, green: UInt8, blue: UInt8) {
        self.init(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    // MARK: - 派生量

    /// 彩度：到中性轴的距离。中性灰接近 0，饱和度越高越大
    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// 色相角，0°...360°。彩度接近 0 时无意义
    public var hueAngle: Double {
        let degrees = atan2(b, a) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// CIE76 色差。不是最精确的色差公式，但对"选最近的参考色"这件事够用，
    /// 且比 CIEDE2000 便宜一个数量级——识别时要在几十个样本上反复调用。
    public func distance(to other: LabColor) -> Double {
        let dl = l - other.l
        let da = a - other.a
        let db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// 白点校正：把观察到的白映射到参考白，其余颜色按分量等比缩放。
    ///
    /// 这是拍照识别里最要紧的一步。不同灯光下同一块魔方拍出来的 Lab 能差出二十几个
    /// 单位（实测暖光下白块离参考白 26 个单位），直接拿固定参考色做最近邻，
    /// 白/黄、红/橙会成片地判错。
    ///
    /// **校正在线性 RGB 里做，不是 XYZ。** 这不是随手选的：一束光打在同色贴纸上，
    /// 在相机看来就是线性 RGB 三个通道各乘一个系数——这正是相机白平衡在做的事，
    /// 也是唯一能精确抵消的光照模型。经典做法（von Kries 对角校正）放在 XYZ 里做，
    /// 只是它的近似：实测暖光下平均残差还有 9 个 Lab 单位，而线性 RGB 里做完是 0。
    ///
    /// 结果**不夹到 0...1**：校正后可能略微越界，而这里只用来比距离，越界不影响判定。
    public func adapted(fromWhite observed: LabColor, toWhite reference: LabColor = .referenceWhite) -> LabColor {
        let source = observed.linearComponents
        let target = reference.linearComponents
        let mine = linearComponents
        // 分母加下限：观测到纯黑时别把整片放大
        return LabColor(
            linearRed: mine.red * target.red / max(source.red, 1e-6),
            green: mine.green * target.green / max(source.green, 1e-6),
            blue: mine.blue * target.blue / max(source.blue, 1e-6)
        )
    }

    // MARK: - 线性 RGB

    /// 显示用的 sRGB 分量（含 gamma），已夹到 0...1。
    ///
    /// 和 `linearComponents` 分开：显示要 gamma 编码，光照运算要线性，混用会算错。
    public var srgbComponents: (red: Double, green: Double, blue: Double) {
        let linear = linearComponents
        return (Self.delinearize(linear.red), Self.delinearize(linear.green), Self.delinearize(linear.blue))
    }

    /// 线性 sRGB 分量（未做 gamma 编码）。光照、白平衡这类**线性**运算必须在这个空间里做。
    var linearComponents: (red: Double, green: Double, blue: Double) {
        let value = Self.xyz(from: self)
        return (
            3.2404542 * value.x - 1.5371385 * value.y - 0.4985314 * value.z,
            -0.9692660 * value.x + 1.8760108 * value.y + 0.0415560 * value.z,
            0.0556434 * value.x - 0.2040259 * value.y + 1.0572252 * value.z
        )
    }

    /// 从线性 sRGB 分量构造
    init(linearRed red: Double, green: Double, blue: Double) {
        self = Self.fromXYZ(Self.xyz(linearRed: red, green: green, blue: blue))
    }

    // MARK: - 参考色

    /// 参考白（D65）
    public static let referenceWhite = LabColor(srgbRed: 0.95, green: 0.95, blue: 0.95)

    // MARK: - sRGB ↔ XYZ ↔ Lab

    struct XYZ {
        var x: Double
        var y: Double
        var z: Double
    }

    /// sRGB（0...1，含 gamma）→ CIE XYZ，D65
    static func xyz(red: Double, green: Double, blue: Double) -> XYZ {
        xyz(linearRed: linearize(red), green: linearize(green), blue: linearize(blue))
    }

    /// 线性 sRGB → CIE XYZ，D65
    static func xyz(linearRed red: Double, green: Double, blue: Double) -> XYZ {
        XYZ(
            x: 0.4124564 * red + 0.3575761 * green + 0.1804375 * blue,
            y: 0.2126729 * red + 0.7151522 * green + 0.0721750 * blue,
            z: 0.0193339 * red + 0.1191920 * green + 0.9503041 * blue
        )
    }

    static func xyz(from color: LabColor) -> XYZ {
        // Lab → XYZ（D65），参考白取 sRGB 白
        let reference = xyz(red: 1, green: 1, blue: 1)
        let fy = (color.l + 16) / 116
        let fx = fy + color.a / 500
        let fz = fy - color.b / 200
        return XYZ(
            x: reference.x * inverseLabCurve(fx),
            y: reference.y * inverseLabCurve(fy),
            z: reference.z * inverseLabCurve(fz)
        )
    }

    static func fromXYZ(_ xyz: XYZ) -> LabColor {
        let reference = LabColor.xyz(red: 1, green: 1, blue: 1)
        let fx = labCurve(xyz.x / reference.x)
        let fy = labCurve(xyz.y / reference.y)
        let fz = labCurve(xyz.z / reference.z)
        return LabColor(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// sRGB 传输函数的逆（去 gamma）
    static func linearize(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// sRGB 传输函数（加 gamma），夹到 0...1
    private static func delinearize(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    private static func labCurve(_ value: Double) -> Double {
        let epsilon = 216.0 / 24389
        let kappa = 24389.0 / 27
        return value > epsilon ? pow(value, 1.0 / 3) : (kappa * value + 16) / 116
    }

    private static func inverseLabCurve(_ value: Double) -> Double {
        let epsilon = 216.0 / 24389
        let kappa = 24389.0 / 27
        let cube = value * value * value
        return cube > epsilon ? cube : (116 * value - 16) / kappa
    }
}

extension LabColor: CustomStringConvertible {
    public var description: String {
        String(format: "Lab(%.1f, %.1f, %.1f)", l, a, b)
    }
}
