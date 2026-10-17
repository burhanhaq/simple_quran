import SwiftUI

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let error = environment.persistenceLoadError {
            FriendlyErrorView(message: error).padding()
        } else {
            ZStack { tabs }
                .fullScreenCover(isPresented: Binding(get: { !environment.settings.hasCompletedOnboarding }, set: { _ in })) {
                    OnboardingView()
                }
        }
    }

    private var tabs: some View {
        @Bindable var environment = environment
        return TabView(selection: $environment.selectedTab) {
            Tab(AppTab.memorize.title, systemImage: AppTab.memorize.systemImage, value: AppTab.memorize) { MemorizeView() }
            Tab(AppTab.progress.title, systemImage: AppTab.progress.systemImage, value: AppTab.progress) { ProgressTabView() }
            Tab(AppTab.quran.title, systemImage: AppTab.quran.systemImage, value: AppTab.quran) { QuranBrowserView() }
        }
        .tint(Color.bronze)
        .tabViewBottomAccessory(isEnabled: environment.playback.snapshot.currentGlobalAyah != nil) {
            GlobalMiniPlayer()
        }
        .fullScreenCover(item: $environment.route) { route in
            switch route {
            case .reader(let reader): QuranReaderView(destination: reader.destination, resumesPlayback: reader.resumePlayback)
            case .session(let session): MemorizeSessionView(route: session)
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
            .accessibilityLabel(environment.playback.activeSet == nil ? "Return to reader" : "Return to session")
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
