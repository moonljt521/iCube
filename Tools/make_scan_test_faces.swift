import Foundation

// iCube 拍照识别测试素材生成器：产出 build/scan-test-faces.html。
//
// 页面上按"阶数 × 状态"给出六面图，用另一台设备打开、iPhone 对着屏幕拍，
// 用来验证识别链路。每个状态都由 CubeKit 从还原态施加真实转动生成，
// **必然是可达状态**——这一点很关键：拿网上找的六面图来测，多半拼不出真实魔方，
// 识别报"拼不出一个真实的魔方"时根本分不清是算法坏了还是素材是假的。
//
// 用法（CubeKit 是 SwiftPM 包，脚本要连它的源码一起编译；
// 而顶层语句只允许落在名为 main.swift 的文件里，所以先改个名）：
//
//   mkdir -p /tmp/faces && cp Tools/make_scan_test_faces.swift /tmp/faces/main.swift
//   xcrun swiftc -O -o /tmp/faces/make /tmp/faces/main.swift CubeKit/Sources/CubeKit/*.swift
//   /tmp/faces/make build/scan-test-faces.html
//
// 颜色与「经典」皮肤同源；改皮肤记得同步 `StickerClassifier.references` 那一侧的量级。

// MARK: - 面位串

/// 转成页面用的面位串：面顺序 `U R F D L B`，每面 row-major，字母代表颜色
/// （U=白 R=红 F=绿 D=黄 L=橙 B=蓝）。与 `CubeKit.FaceletNotation` 同一套约定，
/// 只是这里要支持任意阶数。
func facelets(of state: CubeState) -> String {
    let n = state.size
    var chars: [Character] = []
    chars.reserveCapacity(6 * n * n)
    for face in FaceletNotation.faceOrder {
        for row in 0..<n {
            for col in 0..<n {
                chars.append(FaceletNotation.letter(for: state.color(at: face, row: row, col: col)))
            }
        }
    }
    return String(chars)
}

/// 面位串 → 状态。只用来给生成的素材做自检，证明它真的是个可达状态。
func state(fromFacelets text: String) -> CubeState? {
    let chars = Array(text)
    guard chars.count % 6 == 0 else { return nil }
    let per = chars.count / 6
    let size = Int(Double(per).squareRoot().rounded())
    guard size * size == per else { return nil }
    var stickers = [CubeColor](repeating: .white, count: 6 * per)
    for (block, face) in FaceletNotation.faceOrder.enumerated() {
        for offset in 0..<per {
            guard let color = FaceletNotation.color(for: chars[block * per + offset]) else { return nil }
            stickers[face.rawValue * per + offset] = color
        }
    }
    return CubeState(stickers: stickers)
}

// MARK: - 素材

struct Sample {
    let name: String
    let note: String
    let facelets: String
}

/// 短打乱：只转三步，用来核对"格子的行列读法"与"面与面的对应关系"
let shortAlgorithm = "R U F"
let sizes = [2, 3, 4]

/// 与「经典」皮肤一致的六色
let stickerColors: [String: String] = [
    "U": "#F7F7F7", "R": "#DB2121", "F": "#1AAD3D",
    "D": "#FFD10A", "L": "#FA730D", "B": "#175CDB",
]

func samples(for size: Int) -> [Sample] {
    let solved = CubeState.solved(size: size)
    let short = solved.applying(Algorithm.parse(shortAlgorithm, size: size)!)
    // 完整打乱用固定 seed，保证每次生成的素材一模一样
    let length = Scramble.defaultLength(for: size)
    let full = Scramble.random(size: size, length: length, seed: 42).initialState

    let solvedNote = size == 3
        ? "六面纯色。只要颜色识别链路是通的就必然成功——先拿它确认链路。"
        : "六面纯色。\(size) 阶没有固定中心块，识别结果的朝向可能整体转过，核对配色即可。"
    let shortNote = "只转了 3 步（\(shortAlgorithm)）。用来验证格子读法与面的对应关系。"
    let fullNote = "\(length) 步 WCA 风格打乱（seed 42）。前两个都过了再用它做最终验证。"

    return [
        Sample(name: "还原态", note: solvedNote, facelets: facelets(of: solved)),
        Sample(name: "简单打乱", note: shortNote, facelets: facelets(of: short)),
        Sample(name: "完整打乱", note: fullNote, facelets: facelets(of: full)),
    ]
}

// MARK: - 页面数据

func dataLiteral() -> String {
    var orderLines: [String] = []
    for size in sizes {
        var caseLines: [String] = []
        for sample in samples(for: size) {
            caseLines.append("      { name: \"\(sample.name)\", note: \"\(sample.note)\", "
                             + "facelets: \"\(sample.facelets)\" }")
        }
        orderLines.append("  \"\(size)\": {\n    size: \(size),\n    cases: [\n"
                          + caseLines.joined(separator: ",\n") + "\n    ]\n  }")
    }
    return "{\n" + orderLines.joined(separator: ",\n") + "\n}"
}

func colorsLiteral() -> String {
    let entries = stickerColors.keys.sorted().map { "\($0): \"\(stickerColors[$0]!)\"" }
    return "{\n  " + entries.joined(separator: ", ") + "\n}"
}

// MARK: - 页面

let html = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>iCube 拍照识别 · 测试用六面图</title>
<style>
  :root { --bg: #8A8A8A; --ink: #1A1A1A; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; }
  body {
    background: var(--bg);
    color: var(--ink);
    font: 14px/1.5 -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    gap: 12px; padding: 16px;
    -webkit-user-select: none; user-select: none;
    overflow: hidden;
  }
  .tabs { display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; align-items: center; }
  .tabs .caption { font-size: 12px; opacity: .62; margin-right: 2px; }
  .tab {
    border: 0; border-radius: 999px; padding: 7px 15px;
    background: rgba(255,255,255,.5); color: var(--ink);
    font: inherit; font-weight: 500; cursor: pointer;
  }
  .tab[aria-pressed="true"] { background: #1A1A1A; color: #fff; }
  #label { font-weight: 500; font-size: 15px; }
  #label small { font-weight: 400; opacity: .62; margin-left: 7px; }
  /* 方块**必须是正方形**，两个方向由同一个变量给死。
     为什么较真：App 里的引导框是正方形，用户要拿它框住这一面。方块一旦被压成长方形，
     就再也框不满那个正方形，采样格子整体错位——4 阶格子最小，最先崩成"认错颜色"。
     之前的写法是 width/height 各写一个 min(68vmin, 540px)，而它在 flex 列里，
     窗口一矮 flex 就把 height 压小（flex-shrink 默认 1），实测 1280×700 下
     方块是 476×391、格子 125.7×99.2。所以：边长只给一个变量 + flex: 0 0 auto 不许压。 */
  #cube {
    /* 边长只由这一个变量给死，两个方向共用——正方形是硬要求（见下）。
       末尾那一项给上下那些控件留位置（实测固定占高 271px 起、状态说明多一行还会涨，取 300 留足余量，
       免得状态说明多一行就把底部裁掉）；max() 兜住极矮的窗口。 */
    --side: max(180px, min(68vmin, 540px, calc(100vh - 300px)));
    width: var(--side); height: var(--side);
    flex: 0 0 auto;
    display: grid;
    gap: 3%; padding: 3%;
    background: #141414;
    border-radius: 3%;
    cursor: pointer;
  }
  #cube div { border-radius: 9%; aspect-ratio: 1 / 1; }
  #dots { display: flex; gap: 7px; }
  #dots i { width: 10px; height: 10px; border-radius: 50%; background: rgba(255,255,255,.45); }
  #dots i[aria-current="true"] { background: #1A1A1A; }
  #nav { display: flex; gap: 10px; }
  #nav button {
    border: 0; border-radius: 10px; padding: 10px 24px;
    background: #1A1A1A; color: #fff;
    font: inherit; font-weight: 500; cursor: pointer;
  }
  #nav button:active { background: #000; }
  #hint { font-size: 12px; line-height: 1.7; opacity: .72; text-align: center; max-width: 620px; }
</style>
</head>
<body>
  <header class="tabs" id="orders"><span class="caption">阶数</span></header>
  <header class="tabs" id="cases"><span class="caption">状态</span></header>
  <div id="label"></div>
  <div id="cube" role="img" aria-label="魔方的一个面"></div>
  <div id="dots"></div>
  <div id="nav">
    <button id="prev" type="button">上一面</button>
    <button id="next" type="button">下一面</button>
  </div>
  <div id="hint"></div>
<script>
const COLORS = \(colorsLiteral());
const FACES = [
  ["U", "上 · 白"], ["R", "右 · 红"], ["F", "前 · 绿"],
  ["D", "下 · 黄"], ["L", "左 · 橙"], ["B", "后 · 蓝"]
];
const DATA = \(dataLiteral());

// 必须是 var：翻面/切 tab 都要改这三个游标（旧版写成 let，点一下就抛 TypeError）
var orderKey = "3", caseIndex = 0, faceIndex = 0;

const ordersEl = document.getElementById("orders");
const casesEl = document.getElementById("cases");
const cubeEl = document.getElementById("cube");
const labelEl = document.getElementById("label");
const dotsEl = document.getElementById("dots");
const hintEl = document.getElementById("hint");

function render() {
  const order = DATA[orderKey];
  const size = order.size;
  const sample = order.cases[caseIndex];
  const per = size * size;
  const cells = sample.facelets.slice(faceIndex * per, faceIndex * per + per);

  // 注意：JS 模板串的插值写法是美元符加大括号；Swift 里美元符不特殊，直接写即可
  cubeEl.style.gridTemplateColumns = `repeat(${size}, 1fr)`;
  cubeEl.style.gridTemplateRows = `repeat(${size}, 1fr)`;
  cubeEl.innerHTML = "";
  for (const ch of cells) {
    const cell = document.createElement("div");
    cell.style.background = COLORS[ch] || "#000";
    cubeEl.appendChild(cell);
  }

  labelEl.innerHTML = `${size} 阶 · 第 ${faceIndex + 1} / 6 面 · ${FACES[faceIndex][0]}`
    + `<small>${FACES[faceIndex][1]}</small>`;

  dotsEl.innerHTML = "";
  FACES.forEach((_, i) => {
    const dot = document.createElement("i");
    dot.setAttribute("aria-current", i === faceIndex ? "true" : "false");
    dotsEl.appendChild(dot);
  });

  hintEl.innerHTML = sample.note
    + "<br>用下面的「上一面 / 下一面」翻面（点画面、空格、← → 也行，但键盘要先获得焦点）"
    + "<br>用另一台设备打开本页、iPhone 对着屏幕拍。手机离屏幕 20~30cm 并稍微倾斜，能避开摩尔纹。"
    + (size === 3 ? "" : "<br>注意：" + size + " 阶没有固定中心块，识别结果的朝向可能整体转过，核对配色即可。");

  [...ordersEl.querySelectorAll("button")].forEach((tab) => {
    tab.setAttribute("aria-pressed", tab.dataset.key === orderKey ? "true" : "false");
  });
  [...casesEl.querySelectorAll("button")].forEach((tab, index) => {
    tab.setAttribute("aria-pressed", index === caseIndex ? "true" : "false");
  });
}

function selectOrder(key) {
  orderKey = key;
  caseIndex = 0;
  faceIndex = 0;
  render();
}

function step(delta) {
  faceIndex = (faceIndex + delta + 6) % 6;
  render();
}

for (const key of Object.keys(DATA)) {
  const tab = document.createElement("button");
  tab.className = "tab";
  tab.dataset.key = key;
  tab.textContent = key + " 阶";
  tab.onclick = () => selectOrder(key);
  ordersEl.appendChild(tab);
}

DATA["3"].cases.forEach((sample, index) => {
  const tab = document.createElement("button");
  tab.className = "tab";
  tab.textContent = sample.name;
  tab.onclick = () => { caseIndex = index; faceIndex = 0; render(); };
  casesEl.appendChild(tab);
});

cubeEl.onclick = () => step(1);
document.getElementById("prev").onclick = () => step(-1);
document.getElementById("next").onclick = () => step(1);
window.addEventListener("keydown", (event) => {
  if (event.key === " " || event.key === "ArrowRight" || event.key === "ArrowDown") {
    event.preventDefault();
    step(1);
  } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
    event.preventDefault();
    step(-1);
  } else if (event.key >= "1" && event.key <= "6") {
    faceIndex = Number(event.key) - 1;
    render();
  }
});

render();
</script>
</body>
</html>
"""

// MARK: - 自检与写出

// 素材必须是**可达状态**，否则真机测出来的是素材的锅，白折腾
for size in sizes {
    for sample in samples(for: size) {
        precondition(sample.facelets.count == 6 * size * size,
                     "\(size) 阶 \(sample.name) 的面位串长度不对")
        guard let state = state(fromFacelets: sample.facelets) else {
            preconditionFailure("\(size) 阶 \(sample.name) 的面位串解析不了")
        }
        precondition(state.isLegalState, "\(size) 阶 \(sample.name) 不是可达状态")
    }
    print("\(size) 阶：\(samples(for: size).map { $0.name + "(\($0.facelets.count)字符)" }.joined(separator: " / ")) 已自检")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/scan-test-faces.html"
let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try html.write(to: outputURL, atomically: true, encoding: .utf8)
print("已写出 \(outputURL.path)")
