import SwiftUI
import CubeKit
import CubeSolve

/// 还原功能的入口容器：录入 → 求解 → 步骤。
///
/// 以全屏 cover 从练习页拉起，而不是新开 Tab——功能内聚，也不占 Tab 位。
/// 录入有两条路：手动点格子，或者拍照识别。拍照那条走 `ScanView`，
/// 认出来的状态灌进同一个 `RestoreModel`，回到录入页给用户复核——识别再准
/// 也可能有光线捣乱，最后一眼必须由人过。
struct RestoreView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model = RestoreModel()
    @State private var path: [SolutionPayload] = []
    @State private var isScanning = false
    /// 拍照识别回来时带的把握度提醒。只提醒不拦截——回录入手改一格比重拍六个面便宜。
    @State private var scanHint: String?

    var body: some View {
        NavigationStack(path: $path) {
            FaceEntryView(model: model, onScan: { isScanning = true }, scanHint: $scanHint) { state, solution in
                path.append(SolutionPayload(state: state, solution: solution))
            }
            .navigationTitle("还原")
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
            ScanView { state, hint in
                model.load(state: state)
                scanHint = hint
            }
        }
    }
}

/// 导航路由载荷：录入状态 + 解。
/// 两者都是值类型且 `Hashable`，直接当 `navigationDestination` 的路由值用。
struct SolutionPayload: Hashable {
    let state: CubeState
    let solution: CubeSolution
}
