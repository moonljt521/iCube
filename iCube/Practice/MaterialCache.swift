import UIKit
import RealityKit
import CubeKit

/// 魔方涂装皮肤：贴纸 6 色 + 本体塑料的质感参数。
/// 颜色用 SIMD3 便于直接喂 RealityKit，也方便 Hashable 做缓存键。
/// 灵感取自市面流行品牌的经典涂装，数值均做了调整以避开花色版权。
struct CubeSkin: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    /// 本体塑料色
    let bodyColor: SIMD3<Float>
    let bodyRoughness: Float
    /// 六色贴纸（键 = CubeColor）
    let stickers: [CubeColor: SIMD3<Float>]
    let stickerRoughness: Float
    let stickerClearcoat: Float
    let stickerMetallic: Float

    func color(of cubeColor: CubeColor) -> SIMD3<Float> {
        stickers[cubeColor] ?? SIMD3<Float>(0.9, 0.9, 0.9)
    }

    /// 预览小色卡（换肤菜单用）
    var previewColors: [UIColor] {
        [CubeColor.white, .yellow, .green, .blue, .red, .orange].map { UIColor(red: CGFloat(color(of: $0).x), green: CGFloat(color(of: $0).y), blue: CGFloat(color(of: $0).z), alpha: 1) }
    }
}

extension CubeSkin {

    /// 经典纯色：最传统的黑底亮面贴纸
    static let classic = CubeSkin(
        id: "classic",
        name: "经典",
        subtitle: "黑底亮面贴纸",
        bodyColor: SIMD3<Float>(repeating: 0.19),
        bodyRoughness: 0.55,
        stickers: [
            .white: SIMD3<Float>(repeating: 0.97),
            .yellow: SIMD3<Float>(1.0, 0.82, 0.04),
            .green: SIMD3<Float>(0.10, 0.68, 0.24),
            .blue: SIMD3<Float>(0.09, 0.36, 0.86),
            .red: SIMD3<Float>(0.86, 0.13, 0.13),
            .orange: SIMD3<Float>(0.98, 0.45, 0.05),
        ],
        stickerRoughness: 0.32,
        stickerClearcoat: 0.4,
        stickerMetallic: 0.0)

    /// 竞速无贴：亮面一体成型风，高饱和高光泽
    static let race = CubeSkin(
        id: "race",
        name: "竞速",
        subtitle: "亮面一体色 · 高光泽",
        bodyColor: SIMD3<Float>(repeating: 0.07),
        bodyRoughness: 0.22,
        stickers: [
            .white: SIMD3<Float>(repeating: 0.99),
            .yellow: SIMD3<Float>(1.0, 0.86, 0.0),
            .green: SIMD3<Float>(0.05, 0.78, 0.28),
            .blue: SIMD3<Float>(0.05, 0.42, 0.95),
            .red: SIMD3<Float>(0.94, 0.08, 0.10),
            .orange: SIMD3<Float>(1.0, 0.38, 0.0),
        ],
        stickerRoughness: 0.14,
        stickerClearcoat: 0.85,
        stickerMetallic: 0.0)

    /// 霜面：哑光低饱和，磨砂手感动人
    static let frost = CubeSkin(
        id: "frost",
        name: "霜面",
        subtitle: "哑光低饱和 · 磨砂",
        bodyColor: SIMD3<Float>(repeating: 0.42),
        bodyRoughness: 0.7,
        stickers: [
            .white: SIMD3<Float>(0.94, 0.95, 0.97),
            .yellow: SIMD3<Float>(0.93, 0.82, 0.28),
            .green: SIMD3<Float>(0.36, 0.72, 0.48),
            .blue: SIMD3<Float>(0.38, 0.56, 0.82),
            .red: SIMD3<Float>(0.82, 0.42, 0.42),
            .orange: SIMD3<Float>(0.90, 0.60, 0.34),
        ],
        stickerRoughness: 0.62,
        stickerClearcoat: 0.0,
        stickerMetallic: 0.0)

    /// 糖果：半透糖果色，清漆层拉满
    static let candy = CubeSkin(
        id: "candy",
        name: "糖果",
        subtitle: "半透糖果色 · 清漆",
        bodyColor: SIMD3<Float>(repeating: 0.12),
        bodyRoughness: 0.3,
        stickers: [
            .white: SIMD3<Float>(0.97, 0.99, 1.0),
            .yellow: SIMD3<Float>(1.0, 0.92, 0.20),
            .green: SIMD3<Float>(0.20, 0.90, 0.45),
            .blue: SIMD3<Float>(0.25, 0.55, 1.0),
            .red: SIMD3<Float>(1.0, 0.25, 0.35),
            .orange: SIMD3<Float>(1.0, 0.55, 0.15),
        ],
        stickerRoughness: 0.1,
        stickerClearcoat: 1.0,
        stickerMetallic: 0.04)

    /// 曜石：深色金属质感，暗夜风
    static let obsidian = CubeSkin(
        id: "obsidian",
        name: "曜石",
        subtitle: "暗夜金属 · 低反射",
        bodyColor: SIMD3<Float>(repeating: 0.05),
        bodyRoughness: 0.35,
        stickers: [
            .white: SIMD3<Float>(0.88, 0.90, 0.95),
            .yellow: SIMD3<Float>(0.85, 0.70, 0.10),
            .green: SIMD3<Float>(0.10, 0.52, 0.22),
            .blue: SIMD3<Float>(0.12, 0.28, 0.68),
            .red: SIMD3<Float>(0.62, 0.10, 0.12),
            .orange: SIMD3<Float>(0.72, 0.32, 0.06),
        ],
        stickerRoughness: 0.25,
        stickerClearcoat: 0.3,
        stickerMetallic: 0.55)

    static let all: [CubeSkin] = [.classic, .race, .frost, .candy, .obsidian]
}

/// 皮肤持久化 + 材质缓存。材质按皮肤 id 分桶复用，切肤零成本。
enum MaterialCache {
    static let defaultsKey = "cubeSkinID"

    /// 当前皮肤：UserDefaults 记 id，找不到回落经典
    static var current: CubeSkin {
        let id = UserDefaults.standard.string(forKey: defaultsKey)
        return CubeSkin.all.first { $0.id == id } ?? .classic
    }

    static func skin(id: String) -> CubeSkin {
        CubeSkin.all.first { $0.id == id } ?? .classic
    }

    private static var stickerCache: [String: [CubeColor: PhysicallyBasedMaterial]] = [:]
    private static var bodyCache: [String: PhysicallyBasedMaterial] = [:]

    static var body: PhysicallyBasedMaterial {
        if let cached = bodyCache[current.id] { return cached }
        let material = bodyMaterial(for: current)
        bodyCache[current.id] = material
        return material
    }

    static func material(for color: CubeColor) -> PhysicallyBasedMaterial {
        material(for: color, skin: current)
    }

    static func material(for color: CubeColor, skin: CubeSkin) -> PhysicallyBasedMaterial {
        var bucket = stickerCache[skin.id] ?? [:]
        if let cached = bucket[color] { return cached }
        var material = PhysicallyBasedMaterial()
        let tint = skin.color(of: color)
        material.baseColor = .init(tint: UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1))
        material.roughness = .init(floatLiteral: skin.stickerRoughness)
        material.clearcoat = .init(floatLiteral: skin.stickerClearcoat)
        material.metallic = .init(floatLiteral: skin.stickerMetallic)
        bucket[color] = material
        stickerCache[skin.id] = bucket
        return material
    }

    static func bodyMaterial(for skin: CubeSkin) -> PhysicallyBasedMaterial {
        if let cached = bodyCache[skin.id] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: CGFloat(skin.bodyColor.x), green: CGFloat(skin.bodyColor.y), blue: CGFloat(skin.bodyColor.z), alpha: 1))
        material.roughness = .init(floatLiteral: skin.bodyRoughness)
        bodyCache[skin.id] = material
        return material
    }

    /// 兼容旧调用：默认涂装的平面 UI 色
    static func uiColor(of color: CubeColor) -> UIColor {
        let tint = CubeSkin.classic.color(of: color)
        return UIColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
    }
}
