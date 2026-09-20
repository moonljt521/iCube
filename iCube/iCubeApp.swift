import SwiftUI
import SwiftData

@main
struct iCubeApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
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
