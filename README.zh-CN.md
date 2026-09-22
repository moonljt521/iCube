[English](README.md) | [简体中文](README.zh-CN.md)
# iCube

一款基于 SwiftUI 与 RealityKit 的 iOS 魔方竞速练习应用，支持 2/3/4 阶魔方、多套涂装皮肤、手势拧动、竞速计时与成绩统计，并内置可交互的图文 + 3D 演示教程。

## 功能特性

### 魔方练习

- **多阶支持**：2/3/4 阶魔方完整功能对等——手势、打乱、计时、还原判定、成绩记录全链路支持，阶数全局切换
- **官方规则打乱**：对齐 WCA 规则的随机打乱（2 阶 11 步 / 3 阶 20 步 / 4 阶 40 步，四阶含 2R 类内层转动），打乱步骤逐条回放动画
- **竞速计时**：按住待命、松手开表的竞速起手流程，支持 +2 / DNF 罚则
- **成绩统计**：最佳成绩、WCA 口径均值（ao5 / ao12）、按阶筛选的历史记录

### 手势交互

- **触摸即拧**：手指落在魔方贴纸上，沿滑动方向转动对应层；多指可同时转动互不相干的层
- **空域旋转**：手指落在魔方轮廓外拖动即旋转视角，两套手势按命中结果自动仲裁
- **双指捏合**：空白区域双指捏合缩放魔方（0.7x–1.5x，带阈值钳制）

### 涂装皮肤

- 内置 5 套皮肤：经典、竞速、霜面、糖果、曜石（配色灵感取自市面流行品牌涂装，色值与质感均经独立调整）
- 全局即时切换，无需重建场景；选择持久化保存

### 图文教程

- 三阶层先法 7 步 + 2-look OLL / PLL，覆盖 8 个阶段、20+ 个案型
- 每个案型配有 3D 魔方演示：自动摆出案型、逐步播放公式动画直至还原
- 案型与公式经过单元测试逐条校验（案型 = 还原态 + 公式逆，播放公式必可还原）
- 演示模型跟随全局阶数与当前皮肤

## 技术栈与架构

| 层级 | 技术 |
|------|------|
| UI | SwiftUI（iOS 18+） |
| 3D 渲染 | RealityKit（`RealityView` + 相机内容） |
| 持久化 | SwiftData（成绩记录）、UserDefaults（皮肤 / 阶数偏好） |
| 核心算法 | CubeKit（本地 SwiftPM 包） |

### CubeKit 内核设计

CubeKit 是与应用层完全解耦的纯 Swift 算法包，无 UIKit / RealityKit 依赖：

- **纯几何推导**：所有转动置换由整数格点坐标绕轴 90° 旋转实时推导，不含任何手抄置换表，正确性由几何不变量保证
- **N 阶泛化**：状态、层归属、记法（含 `2R` 内层与 `Rw` 宽层）、打乱均按阶数参数化；阶数由贴纸数量（6N²）反推，数据模型天然向后兼容
- **确定性打乱**：SplitMix64 种子化随机，同一 seed 可复现，符合 WCA 间隔规则（无同面连步、无同轴三连）

### 应用层设计

- **手势仲裁**：基于 raycast 命中结果的会话式多指手势追踪——贴纸命中转层、轮廓外旋转视角、空白双指捏合缩放，三者互不打断
- **场景复用**：同阶状态变化走场景内重建，换阶重建整个场景；材质按皮肤分桶缓存，换肤零重建成本
- **碰撞体约束**：贴纸碰撞体采用"整格覆盖、与表面齐平"策略，规避透视下误触邻面的经典问题

## 工程结构

```
iCube/
├── project.yml              # XcodeGen 工程定义（唯一工程事实源）
├── CubeKit/                 # 核心算法包（SwiftPM）
│   ├── Sources/CubeKit/     # 魔方状态 / 转动 / 记法 / 打乱 / 朝向
│   └── Tests/CubeKitTests/  # 79 条单元测试
├── iCube/                   # 应用层
│   ├── Practice/            # 练习页：场景、手势、计时、皮肤
│   ├── Tutorial/            # 教程：数据、演示模型、界面
│   ├── Stats/               # 成绩记录与统计
│   └── Assets.xcassets/     # App 图标等资源
├── iCubeTests/              # 应用层单元测试（40 条）
└── Tools/                   # 资源生成脚本（见下）
```

### 重新生成资源

```bash
# App 图标（1024px PNG）——产物与已入库的图标逐字节一致
swift Tools/make_icon.swift iCube/Assets.xcassets/AppIcon.appiconset/AppIcon.png

# 转动音效——注意：该脚本已被取代，详见脚本头部说明
swift Tools/make_sounds.swift <输出目录>
```

`make_icon.swift` 是现行图标的生成器。`make_sounds.swift` 仅作历史参考保留：
App 内三条 `turn_*.wav` 取自真实磁吸魔方录音，**无法**由该脚本复现。

## 快速开始

### 环境要求

- macOS 14+
- Xcode 16+（含 iOS 18 SDK）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- 真机调试需配置开发者签名（修改 `project.yml` 中的 `DEVELOPMENT_TEAM`）

### 构建运行

```bash
# 1. 生成 Xcode 工程（工程文件不入库，改动 project.yml 后需重新生成）
xcodegen generate

# 2. 打开工程
open iCube.xcodeproj

# 3. 选择目标设备，Cmd+R 运行
```

命令行构建真机包：

```bash
xcodebuild -project iCube.xcodeproj -scheme iCube \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

### 运行测试

```bash
# CubeKit 算法包测试（macOS 直接跑，最快）
cd CubeKit && swift test

# 全量测试（含应用层，需模拟器）
xcodebuild test -project iCube.xcodeproj -scheme iCube \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 测试策略

- **CubeKit（79 条）**：几何与贴纸索引不变量、各阶转动置换正确性、层深记法解析往返、宽层多阶展开语义、打乱可还原性与间隔规则、多阶随机转动颜色守恒
- **应用层（38 条）**：手势意图仲裁（含背向命中过滤）、场景构建与贴纸对账、教程案型/公式逐条校验、练习流程状态机

## 设计细节

- 魔方姿态使用整数旋转矩阵（`Rotation`）累积，渲染时一次性转换为四元数，彻底避免浮点漂移导致的贴纸错位
- 层归属判定基于块中心在面法向上的投影（内层即 `depth` 记法），与基准面朝向无关
- 计时器使用 `TimelineView` 按帧驱动，暂停态零开销

## 许可

项目代码版权归作者所有，未附带开源许可协议。
