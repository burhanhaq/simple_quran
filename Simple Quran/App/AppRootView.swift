import SwiftUI

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment
        if let error = environment.persistenceLoadError {
            FriendlyErrorView(message: error).padding()
        } else {
            TabView(selection: $environment.selectedTab) {
                Tab(AppTab.memorize.title, systemImage: AppTab.memorize.systemImage, value: AppTab.memorize) { MemorizeView() }
                Tab(AppTab.progress.title, systemImage: AppTab.progress.systemImage, value: AppTab.progress) { ProgressTabView() }
                Tab(AppTab.quran.title, systemImage: AppTab.quran.systemImage, value: AppTab.quran) { QuranBrowserView() }
            }
            .tint(Color.bronze)
            .tabViewBottomAccessory(isEnabled: environment.playback.snapshot.currentGlobalAyah != nil) {
                GlobalMiniPlayer()
            }
            .fullScreenCover(item: $environment.readerRoute) { route in
                QuranReaderView(destination: route.destination, initialPracticeRange: route.practiceRange,
                                savedPractice: route.savedPractice, resumesPlayback: route.resumePlayback, isReview: route.isReview, targetID: route.targetID)
            }
        }
    }
}

private struct GlobalMiniPlayer: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 12) {
            Button { environment.reopenPlayer() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform").foregroundStyle(Color.bronze)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(environment.playback.snapshot.setTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if let ayah = environment.playback.snapshot.currentGlobalAyah,
                           let verse = environment.quran.verse(globalAyah: ayah) {
                            Text("Ayah \(verse.ayahInSurah)").font(.caption).foregroundStyle(Color.secondaryWarm)
                        }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .accessibilityIdentifier("playback.open")
            .accessibilityLabel("Return to reader")
            Button {
                if environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading {
                    environment.playback.pause()
                } else { environment.playback.resume() }
            } label: {
                Image(systemName: environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(environment.playback.snapshot.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("playback.toggle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appBrownText)
        .padding(.horizontal, 20)
    }
}
