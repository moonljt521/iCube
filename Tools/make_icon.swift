import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// iCube App Icon 渲染脚本 v3：
// 深色底 + 底部橙色光晕 + 等距魔方，顶层旋转 28°（"正在拧"的瞬间），
// 贴纸圆角带高光、侧面按受光分级明暗。输出 1024x1024 PNG。
//
// 用法：swift Tools/make_icon.swift <输出路径.png>
// 产物与 iCube/Assets.xcassets/AppIcon.appiconset/AppIcon.png 逐字节一致。

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: 0, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// CG 位图上下文原点在左下角，先翻成"y 向下"的屏幕坐标
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// MARK: - 几何基元

struct V3 { let x: CGFloat, y: CGFloat, z: CGFloat
    func scaled(_ s: CGFloat) -> V3 { V3(x: x*s, y: y*s, z: z*s) }
    func add(_ o: V3) -> V3 { V3(x: x+o.x, y: y+o.y, z: z+o.z) }
}

func project(_ v: V3) -> CGPoint {
    let sx = (v.x - v.z) * 0.866
    let sy = (v.x + v.z) * 0.5 - v.y
    return CGPoint(x: 512 + sx * 104, y: 512 + sy * 104)
}

let bodyColor = CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
let edgeColor = CGColor(red: 0.03, green: 0.03, blue: 0.045, alpha: 1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ shade: CGFloat) -> CGColor {
    CGColor(red: min(1, r*shade), green: min(1, g*shade), blue: min(1, b*shade), alpha: 1)
}

/// 画一枚圆角贴纸：c 为网格中心，u/v 为整个网格的跨度向量，
/// iu/nu、iv/nv 指定网格中的格位。贴纸八边形逼近圆角，上缘加一条高光。
func sticker(_ c: V3, _ u: V3, _ v: V3, _ iu: Int, _ nu: Int, _ iv: Int, _ nv: Int,
             _ tint: (CGFloat, CGFloat, CGFloat), _ shade: CGFloat) {
    let inset: CGFloat = 0.075   // 半格收缩比例（缝宽）
    let k: CGFloat = 0.30        // 切角比例
    let cellU = u.scaled(1 / CGFloat(nu)), cellV = v.scaled(1 / CGFloat(nv))
    let center = c
        .add(u.scaled((CGFloat(iu) + 0.5) / CGFloat(nu) - 0.5))
        .add(v.scaled((CGFloat(iv) + 0.5) / CGFloat(nv) - 0.5))
    let hw = cellU.scaled(0.5 - inset / 2), hh = cellV.scaled(0.5 - inset / 2)

    func cornerPoint(_ su: CGFloat, _ sv: CGFloat) -> CGPoint {
        project(center.add(hw.scaled(su)).add(hh.scaled(sv)))
    }
    let pts = [
        cornerPoint(-1 + k, -1), cornerPoint(1 - k, -1),
        cornerPoint(1, -1 + k), cornerPoint(1, 1 - k),
        cornerPoint(1 - k, 1), cornerPoint(-1 + k, 1),
        cornerPoint(-1, 1 - k), cornerPoint(-1, -1 + k),
    ]
    let path = CGMutablePath()
    path.move(to: pts[0])
    for p in pts.dropFirst() { path.addLine(to: p) }
    path.closeSubpath()
    ctx.setFillColor(color(tint.0, tint.1, tint.2, shade))
    ctx.addPath(path); ctx.fillPath()

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addLines(between: [cornerPoint(-1 + k, -1), cornerPoint(1 - k, -1)])
    ctx.strokePath()
}

func fillQuad(_ a: V3, _ b: V3, _ c: V3, _ d: V3, _ fill: CGColor) {
    let path = CGMutablePath()
    path.move(to: project(a)); path.addLine(to: project(b))
    path.addLine(to: project(c)); path.addLine(to: project(d)); path.closeSubpath()
    ctx.setFillColor(fill)
    ctx.addPath(path); ctx.fillPath()
}

// MARK: - 背景：整幅底色 + 径向渐变 + 底部橙色光晕

ctx.setFillColor(CGColor(red: 0.035, green: 0.035, blue: 0.055, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let bgColors = [CGColor(red: 0.115, green: 0.115, blue: 0.155, alpha: 1),
                CGColor(red: 0.035, green: 0.035, blue: 0.055, alpha: 1)] as CFArray
let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1])!
ctx.drawRadialGradient(bgGrad,
                       startCenter: CGPoint(x: 512, y: 430), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 640, options: [])

let glowColors = [CGColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 0.20),
                  CGColor(red: 1.0, green: 0.45, blue: 0.05, alpha: 0)] as CFArray
let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1])!
ctx.drawRadialGradient(glowGrad,
                       startCenter: CGPoint(x: 512, y: 830), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 830), endRadius: 480, options: [])

// MARK: - 参数

let white = (CGFloat(0.97), CGFloat(0.97), CGFloat(0.97))
let green = (CGFloat(0.10), CGFloat(0.68), CGFloat(0.24))
let red   = (CGFloat(0.86), CGFloat(0.13), CGFloat(0.13))
let orange = (CGFloat(0.98), CGFloat(0.45), CGFloat(0.05))
let blue  = (CGFloat(0.09), CGFloat(0.36), CGFloat(0.86))

// 顶层旋转角（绕 y 轴）
let theta: CGFloat = 28 * .pi / 180
let ct = cos(theta), st = sin(theta)
let ex = V3(x: ct, y: 0, z: -st)    // 旋转层局部轴
let ez = V3(x: st, y: 0, z: ct)

// MARK: - 下层（未旋转，y ∈ [-1.5, 0.5]）

// 顶盖：y=0.5 的内面（顶层转开后露出的黑缝）
fillQuad(V3(x: -1.5, y: 0.5, z: -1.5), V3(x: 1.5, y: 0.5, z: -1.5),
         V3(x: 1.5, y: 0.5, z: 1.5), V3(x: -1.5, y: 0.5, z: 1.5), bodyColor)

// F 面（z=+1.5，绿）：本体 + 两排贴纸（上层那排随顶层转走了）
fillQuad(V3(x: -1.5, y: 0.5, z: 1.5), V3(x: 1.5, y: 0.5, z: 1.5),
         V3(x: 1.5, y: -1.5, z: 1.5), V3(x: -1.5, y: -1.5, z: 1.5), bodyColor)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        0, 3, 0, 2, green, 0.80)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        1, 3, 0, 2, green, 0.80)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        2, 3, 0, 2, green, 0.80)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        0, 3, 1, 2, green, 0.80)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        1, 3, 1, 2, green, 0.80)
sticker(V3(x: 0, y: -0.5, z: 1.5), V3(x: 3, y: 0, z: 0), V3(x: 0, y: -2, z: 0),
        2, 3, 1, 2, green, 0.80)

// R 面（x=+1.5，红）：本体 + 两排贴纸
fillQuad(V3(x: 1.5, y: 0.5, z: 1.5), V3(x: 1.5, y: 0.5, z: -1.5),
         V3(x: 1.5, y: -1.5, z: -1.5), V3(x: 1.5, y: -1.5, z: 1.5), bodyColor)
let rC = V3(x: 1.5, y: -0.5, z: 0)
let rU = V3(x: 0, y: 0, z: -3), rV = V3(x: 0, y: -2, z: 0)
for col in 0..<3 { for row in 0..<2 {
    sticker(rC, rU, rV, col, 3, row, 2, red, 0.88)
} }

// F/R 之间的竖棱
fillQuad(V3(x: -1.5, y: -1.5, z: 1.5), V3(x: 1.5, y: -1.5, z: 1.5),
         V3(x: 1.5, y: -1.5, z: -1.5), V3(x: 1.5, y: -1.5, z: 1.5), edgeColor)

// MARK: - 顶层（旋转 theta，y ∈ [0.5, 1.5]）

// 旋转后截面角点（边长 3 的正方形绕中心转 theta）
let radius = CGFloat(1.5) * CGFloat(2).squareRoot()
func corner(_ k: Int) -> V3 {
    let a = CGFloat(45 + 90 * k - 28) * .pi / 180
    return V3(x: radius * cos(a), y: 0, z: radius * sin(a))
}
// 每条侧棱的原始颜色：k=0 F绿 / k=1 L橙 / k=2 B蓝 / k=3 R红
let stripTints = [green, orange, blue, red]

for k in 0..<4 {
    let c0 = corner(k), c1 = corner((k + 1) % 4)
    let phi = CGFloat(90 * (k + 1) - 28) * .pi / 180   // 旋转后的外法向
    let nx = cos(phi), nz = sin(phi)
    guard nx + nz > 0.1 else { continue }              // 只画朝向观察者的侧面
    let shade = 0.70 + 0.18 * nx + 0.12 * nz

    // 侧面本体
    fillQuad(V3(x: c0.x, y: 0.5, z: c0.z), V3(x: c1.x, y: 0.5, z: c1.z),
             V3(x: c1.x, y: 1.5, z: c1.z), V3(x: c0.x, y: 1.5, z: c0.z), bodyColor)
    // 三枚侧贴纸：网格中心 = 棱中点 (y=1.0)
    let mid = V3(x: (c0.x + c1.x) / 2, y: 1.0, z: (c0.z + c1.z) / 2)
    let edge = V3(x: c1.x - c0.x, y: 0, z: c1.z - c0.z)
    for col in 0..<3 {
        sticker(mid, edge, V3(x: 0, y: -1, z: 0), col, 3, 0, 1, stripTints[k], shade)
    }
}

// 顶层顶盖（y=1.5 的旋转正方形）
let t0 = corner(0).add(V3(x: 0, y: 1.5, z: 0)), t1 = corner(1).add(V3(x: 0, y: 1.5, z: 0))
let t2 = corner(2).add(V3(x: 0, y: 1.5, z: 0)), t3 = corner(3).add(V3(x: 0, y: 1.5, z: 0))
fillQuad(t0, t1, t2, t3, bodyColor)

// 顶面 3x3 白贴纸（网格中心 = (0,1.5,0)，跨度沿旋转后的局部轴）
for i in 0..<3 { for j in 0..<3 {
    sticker(V3(x: 0, y: 1.5, z: 0), ex.scaled(3), ez.scaled(3), i, 3, j, 3, white, 0.97)
} }

// MARK: - 顶面柔光高光

ctx.saveGState()
let clip = CGMutablePath()
clip.move(to: project(t0)); clip.addLine(to: project(t1))
clip.addLine(to: project(t2)); clip.addLine(to: project(t3)); clip.closeSubpath()
ctx.addPath(clip); ctx.clip()
let hlColors = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.16),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
let hl = CGGradient(colorsSpace: colorSpace, colors: hlColors, locations: [0, 1])!
let hc = project(V3(x: -0.6, y: 1.5, z: -0.6))
ctx.drawRadialGradient(hl, startCenter: hc, startRadius: 0,
                       endCenter: hc, endRadius: 300, options: [])
ctx.restoreGState()

// MARK: - 输出 PNG

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1] : "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("written: \(url.path)")
