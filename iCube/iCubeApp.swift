import SwiftUI
import SwiftData
import CubeSolve

@main
struct iCubeApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    // 预热求解器：把 21MB 查找表从包内拷进 Caches 并首次加载（约 50ms）。
                    // 丢到后台队列，不卡首屏。iOS 会清 Caches，所以每次启动都要跑，
                    // 不能只跑一次——表没了会退化成从零建表（数秒起）。
                    await Task.detached(priority: .utility) { try? CubeSolve.prepare() }.value
                }
        }
        .modelContainer(for: SolveRecord.self)
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { PracticeView() }
                .tabItem { Label("练习", systemImage: "cube") }

            NavigationStack { HistoryView() }
                .tabItem { Label("记录", systemImage: "stopwatch") }

            NavigationStack { TutorialView() }
                .tabItem { Label("教程", systemImage: "book") }
        }
        .tint(.orange)
    }
}
