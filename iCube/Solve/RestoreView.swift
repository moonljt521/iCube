import SwiftUI
import CubeKit
import CubeSolve

/// 还原功能的入口容器：录入 → 求解 → 步骤。
///
/// 以全屏 cover 从练习页拉起，而不是新开 Tab——功能内聚，也不占 Tab 位。
/// 后续接入拍照时，拍照页会作为录入页的另一种输入方式挂在这里面。
struct RestoreView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model = RestoreModel()
    @State private var path: [SolutionPayload] = []

    var body: some View {
        NavigationStack(path: $path) {
            FaceEntryView(model: model) { state, solution in
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
    }
}

/// 导航路由载荷：录入状态 + 解。
/// 两者都是值类型且 `Hashable`，直接当 `navigationDestination` 的路由值用。
struct SolutionPayload: Hashable {
    let state: CubeState
    let solution: CubeSolution
}
