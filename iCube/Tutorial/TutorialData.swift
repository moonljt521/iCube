import Foundation
import CubeKit

/// 教程案型：一条公式 + 讲解。
/// 案型画面 = 还原态先施加公式的逆；播放公式本体后恰好回到还原态
/// （该约定由 TutorialDataTests 逐条校验，公式写错会直接挂测试）。
struct TutorialCase: Identifiable, Hashable {
    let id: String
    let name: String
    /// 标准记法，支持 Rw 宽层 / M E S 切片 / x y z 整体旋转 / ' 与 2
    let formula: String
    let tips: String

    /// 按阶数解析公式：宽层记法（Rw/Fw）随阶数展开（三阶 = R+M'，四阶 = R+2R，二阶退化为单层）。
    /// 缺省三阶，教程测试与三阶教学文案都基于它。
    func algorithm(size: Int = 3) -> Algorithm? { Algorithm.parse(formula, size: size) }
}

/// 教程阶段：层先法的一步，或一组进阶案型
struct TutorialStage: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let cases: [TutorialCase]
}

extension TutorialStage {

    static let all: [TutorialStage] = [
        TutorialStage(
            id: "lbl-cross",
            title: "第 1 步 · 白色十字",
            summary: "以白色为底，把 4 条带白色的棱块绕底面中心拼成十字。这一步没有固定公式：先在顶层把棱块转到与侧心同色对齐，再 180° 翻下来；翻错方向的就重新顶起来调整。下面的步骤都默认十字已在底层。",
            cases: []
        ),
        TutorialStage(
            id: "lbl-first-layer",
            title: "第 2 步 · 第一层角块",
            summary: "把带白色的角块逐一送进底层。先把目标角转到底层槽位的正上方，再按白色朝向选公式。",
            cases: [
                TutorialCase(
                    id: "lbl-corner-white-right",
                    name: "白角在上 · 白色朝右",
                    formula: "U R U' R'",
                    tips: "让白角悬在目标槽位右上方，白色贴纸朝右侧时用这组：先把它转开再翻回槽里。"
                ),
                TutorialCase(
                    id: "lbl-corner-white-front",
                    name: "白角在上 · 白色朝前",
                    formula: "U' F' U F",
                    tips: "与上一种镜像：白色朝前时往左边翻。两种情况覆盖了角块插入的全部朝向。"
                ),
                TutorialCase(
                    id: "lbl-corner-in-slot",
                    name: "白角卡在槽里但方向不对",
                    formula: "R U R' U'",
                    tips: "先用一次这组把角顶出到顶层（右手‘勾上回下’），再按上面两种朝向重新插入。"
                )
            ]
        ),
        TutorialStage(
            id: "lbl-second-layer",
            title: "第 3 步 · 中层棱块",
            summary: "把顶层不含黄色的棱块插进中层。先在顶层把棱块的侧面颜色与中心对齐成正对着你的面，再看顶面颜色决定往左还是往右插。",
            cases: [
                TutorialCase(
                    id: "lbl-edge-right",
                    name: "棱块往右插",
                    formula: "U R U' R' U' F' U F",
                    tips: "顶面颜色与右心同色时用：先‘上来拆下’把角让开，再用镜像动作把它送进右槽。"
                ),
                TutorialCase(
                    id: "lbl-edge-left",
                    name: "棱块往左插",
                    formula: "U' L' U L U F U' F'",
                    tips: "顶面颜色与左心同色时用，是右插的镜像。"
                ),
                TutorialCase(
                    id: "lbl-edge-stuck",
                    name: "棱块卡在槽里但方向不对",
                    formula: "U R U' R' U' F' U F",
                    tips: "随便用一次插入公式把它顶到顶层（会带入一个黄棱也无所谓），再对色重新插入。"
                )
            ]
        ),
        TutorialStage(
            id: "lbl-yellow-cross",
            title: "第 4 步 · 黄色十字",
            summary: "只看黄色贴纸的分布，用一条六步公式反复生成黄色十字。每次拧完要重新判断形状再下公式。",
            cases: [
                TutorialCase(
                    id: "oll-edge-line",
                    name: "黄边一字",
                    formula: "F R U R' U' F'",
                    tips: "把一字横着放（左右方向）再拧，直接得到十字。"
                ),
                TutorialCase(
                    id: "oll-edge-l",
                    name: "黄边 L 形",
                    formula: "F U R U' R' F'",
                    tips: "把 L 摆在左后方（9 点钟方向）再拧。"
                ),
                TutorialCase(
                    id: "oll-edge-dot",
                    name: "黄边只有一个点",
                    formula: "F R U R' U' F' Fw R U R' U' Fw'",
                    tips: "点状需要拧两轮：先用一字公式变出 L，再用 L 公式收十字。Fw 是前双层宽转。"
                )
            ]
        ),
        TutorialStage(
            id: "lbl-yellow-face",
            title: "第 5 步 · 黄色面（角块定向）",
            summary: "这一步与 2-look OLL 的角块定向完全相同。演示时留意黄色贴纸的图案——这就是实战中辨认情况的依据。",
            cases: [
                TutorialCase(
                    id: "oll-sune",
                    name: "小鱼 Sune",
                    formula: "R U R' U R U2 R'",
                    tips: "只有一角黄朝上、且左前方角块黄色朝左时是标准小鱼。"
                ),
                TutorialCase(
                    id: "oll-antisune",
                    name: "反小鱼 Anti-Sune",
                    formula: "R U2 R' U' R U' R'",
                    tips: "小鱼镜像，黄色朝向相反时用它。"
                ),
                TutorialCase(
                    id: "oll-h",
                    name: "双横 H 形",
                    formula: "R U R' U R U' R' U R U2 R'",
                    tips: "黄块都朝侧面、无角朝上，相当于做两次小鱼。"
                ),
                TutorialCase(
                    id: "oll-pi",
                    name: "坦克 Pi 形",
                    formula: "R U2 R2 U' R2 U' R2 U2 R",
                    tips: "黄块分布像 π。把两个黄朝上的角块放在左侧。"
                ),
                TutorialCase(
                    id: "oll-l",
                    name: "小拐角 L 形",
                    formula: "F' Rw U R' U' Rw' F R",
                    tips: "两个黄朝上的角相邻成 L。Rw 是右双层宽转。"
                ),
                TutorialCase(
                    id: "oll-t",
                    name: "双箭头 T 形",
                    formula: "Rw U R' U' Rw' F R F'",
                    tips: "黄贴纸分布像字母 T，两个黄朝上的角放在右侧。"
                ),
                TutorialCase(
                    id: "oll-u",
                    name: "闪电视 U 形",
                    formula: "R2 D R' U2 R D' R' U2 R'",
                    tips: "两个黄朝上的角成一斜线，先摆好方向再拧。"
                )
            ]
        ),
        TutorialStage(
            id: "lbl-corner-permute",
            title: "第 6 步 · 顶层角块归位",
            summary: "黄色面朝上后，先找有两条同色角块的边（‘眉毛’），把它朝后，再用三角换公式循环角块。",
            cases: [
                TutorialCase(
                    id: "pll-corner-cycle-cw",
                    name: "三角换 · 顺时针",
                    formula: "U R U' L' U R' U' L",
                    tips: "眉毛朝后时，三个待换角块按公式方向循环。"
                ),
                TutorialCase(
                    id: "pll-corner-cycle-ccw",
                    name: "三角换 · 逆时针",
                    formula: "U' L' U R U' L U R'",
                    tips: "顺时针公式的镜像，方向相反时用它。"
                ),
                TutorialCase(
                    id: "pll-y",
                    name: "对角互换（Y-perm）",
                    formula: "F R U' R' U' R U R' F' R U R' U' R' F R F'",
                    tips: "找不到眉毛说明两对角块都对角互换，用 Y-perm 一步到位（也是 CFOP 常用公式）。"
                )
            ]
        ),
        TutorialStage(
            id: "lbl-edge-permute",
            title: "第 7 步 · 顶层棱块归位",
            summary: "最后一步：角块已归位，只剩棱块转圈。观察哪条棱已归位（或没有），选对应公式。M 是中层切片，方向跟随 L。",
            cases: [
                TutorialCase(
                    id: "pll-ua",
                    name: "三棱换 · 顺时针（Ua）",
                    formula: "R U' R U R U R U' R' U' R2",
                    tips: "已归位的棱朝后，其余三条棱顺时针轮转。"
                ),
                TutorialCase(
                    id: "pll-ub",
                    name: "三棱换 · 逆时针（Ub）",
                    formula: "R2 U R U R' U' R' U' R' U R'",
                    tips: "Ua 的镜像，逆时针轮转。"
                ),
                TutorialCase(
                    id: "pll-h",
                    name: "四棱对换（H-perm）",
                    formula: "M2 U M2 U2 M2 U M2",
                    tips: "两组对面棱互换，没有棱已归位。全程保持黄色朝上。"
                ),
                TutorialCase(
                    id: "pll-z",
                    name: "四棱邻换（Z-perm）",
                    formula: "M2 U M2 U M' U2 M2 U2 M'",
                    tips: "两组相邻棱互换。与 H-perm 一样用 M 切片，手不用换握法。"
                )
            ]
        ),
        TutorialStage(
            id: "cfop-pll-corners",
            title: "进阶 · 2-look PLL 换角",
            summary: "CFOP 的 2-look PLL 先换角再换棱。换棱公式与第 7 步相同（Ua / Ub / H / Z），这里补上专用的角块置换公式。",
            cases: [
                TutorialCase(
                    id: "pll-aa",
                    name: "三角换 Aa（顺时针）",
                    formula: "x R' U R' D2 R U' R' D2 R2",
                    tips: "三个角块顺时针轮转。x 是整体旋转，公式开头会自动把视角转过去。"
                ),
                TutorialCase(
                    id: "pll-ab",
                    name: "三角换 Ab（逆时针）",
                    formula: "x R2 D2 R U R' D2 R U' R",
                    tips: "Aa 的反向版本，指法几乎相同，只需判断方向。"
                ),
                TutorialCase(
                    id: "pll-e",
                    name: "对角互换 E-perm",
                    formula: "x' R U' R' D R U R' D' R U' R' D R U R' D'",
                    tips: "没有眉毛（两对角块同时对角互换）时一步到位，相当于 Aa 的两次循环压缩。"
                )
            ]
        )
    ]
}
