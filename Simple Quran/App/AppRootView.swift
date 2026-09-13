import SwiftUI

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        if let error = environment.persistenceLoadError {
            NavigationStack {
                FriendlyErrorView(message: error)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.parchment.ignoresSafeArea())
                    .navigationTitle(String(localized: "Simple Quran"))
            }
        } else {
            TabView(selection: $environment.selectedTab) {
                Tab(String(localized: "Today"), systemImage: "sun.max", value: AppTab.home) {
                    HomeView()
                }
                Tab(String(localized: "Quran"), systemImage: "book", value: AppTab.quran) {
                    QuranBrowserView()
                }
                Tab(String(localized: "Collections"), systemImage: "rectangle.stack", value: AppTab.sets) {
                    SetListView()
                }
                Tab(String(localized: "Progress"), systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                    ProgressViewScreen()
                }
            }
            .tint(Color.gold)
            .background(Color.parchment.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let ayah = environment.playback.snapshot.currentGlobalAyah {
                    GlobalMiniPlayer(ayah: ayah)
                }
            }
        }
    }
}

private struct GlobalMiniPlayer: View {
    @Environment(AppEnvironment.self) private var environment
    let ayah: Int

    var body: some View {
        let verse = environment.quran.verse(globalAyah: ayah)
        HStack {
            VStack(alignment: .leading) {
                Text(environment.playback.snapshot.setTitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryWarm)
                Text(verse?.reference ?? "")
                    .font(.headline)
                    .foregroundStyle(Color.appBrownText)
            }
            Spacer()
            if environment.playback.snapshot.isLoading {
                ProgressView()
            }
            Button {
                if environment.playback.snapshot.isPlaying {
                    environment.playback.pause()
                } else {
                    environment.playback.resume()
                }
            } label: {
                Image(systemName: environment.playback.snapshot.isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(environment.playback.snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
