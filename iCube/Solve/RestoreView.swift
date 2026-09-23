import SwiftUI
import CubeKit
import CubeSolve

/// 还原功能的入口容器：录入 → 求解 → 步骤。
///
/// 以全屏 cover 从练习页拉起，而不是新开 Tab——功能内聚，也不占 Tab 位。
/// 录入有两条路：手动点格子，或者拍照识别。拍照那条走 `ScanView`，
/// 认出来的状态灌进同一个 `RestoreModel`，回到录入页给用户复核——识别再准
/// 也可能有光线捣乱，最后一眼必须由人过。
///
/// 阶数由练习页的全局设置传进来（练习/教程/还原共用同一个开关），
/// 录入格子数、引导框切格、识别算法全都跟着它走。
struct RestoreView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: RestoreModel
    @State private var path: [SolutionPayload] = []
    @State private var isScanning = false
    @State private var isVideoScanning = false
    /// 识别回来时带的把握度提醒。只提醒不拦截——回录入手改一格比重拍六个面便宜。
    @State private var scanHint: String?
    /// 视频识别失败——必须带到录入页显示（红色条），不然用户关掉识别页就什么都不知道了
    @State private var scanError: String?

    init(size: Int) {
        _model = State(initialValue: RestoreModel(size: size))
    }

    var body: some View {
        NavigationStack(path: $path) {
            FaceEntryView(
                model: model,
                onScan: { isScanning = true },
                onVideoScan: { isVideoScanning = true },
                scanHint: $scanHint,
                scanError: $scanError
            ) { state, solution in
                path.append(SolutionPayload(state: state, solution: solution))
            }
            .navigationTitle("还原 · \(model.size) 阶")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationDestination(for: SolutionPayload.self) { payload in
                SolutionView(enteredState: payload.state, solution: payload.solution)
            }
        }
        .tint(.orange)
        .fullScreenCover(isPresented: $isScanning) {
            ScanView(size: model.size) { result in
                // 偶数阶可能拼出不止一种（两个面互为旋转），候选一并带过来让用户挑
                model.load(candidates: result.candidates)
                scanHint = result.hint
            }
        }
        .fullScreenCover(isPresented: $isVideoScanning) {
            VideoScanView(
                size: model.size,
                onFinished: { result in
                    // 与拍照识别同一条出路：候选一并带过来，用户对照魔方挑
                    model.load(candidates: result.candidates)
                    scanHint = result.hint
                },
                onFailed: { message in
                    // 失败消息必须带回来——不然关掉本页就丢了
                    scanError = message
                }
            )
        }
    }
}

/// 导航路由载荷：录入状态 + 解。
/// 两者都是值类型且 `Hashable`，直接当 `navigationDestination` 的路由值用。
struct SolutionPayload: Hashable {
    let state: CubeState
    let solution: CubeSolution
}
