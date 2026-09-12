import SwiftUI

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        TabView(selection: $environment.selectedTab) {
            Tab(String(localized: "Home"), systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab(String(localized: "Quran"), systemImage: "book", value: AppTab.quran) {
                QuranBrowserView()
            }
            Tab(String(localized: "My Sets"), systemImage: "rectangle.stack", value: AppTab.sets) {
                SetListView()
            }
            Tab(String(localized: "Progress"), systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressViewScreen()
            }
        }
        .tint(Color.gold)
        .background(Color.parchment.ignoresSafeArea())
    }
}
