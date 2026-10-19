import SwiftUI

struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

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
            Tab(value: AppTab.memorize) { MemorizeView() } label: { tabLabel(.memorize) }
            Tab(value: AppTab.progress) { ProgressTabView() } label: { tabLabel(.progress) }
            Tab(value: AppTab.quran) { QuranBrowserView() } label: { tabLabel(.quran) }
        }
        .tint(Color.bronze)
        .tabViewBottomAccessory(isEnabled: environment.playback.snapshot.currentGlobalAyah != nil) {
            GlobalMiniPlayer()
        }
        .fullScreenCover(item: $environment.route) { route in
            SurahScreen(route: route, environment: environment)
        }
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        let color = unselectedTabColor(tab)
        return Label {
            Text(tab.title).foregroundStyle(color.map(Color.init(uiColor:)) ?? .primary)
        } icon: {
            if let color, let symbol = UIImage(systemName: tab.systemImage + ".fill") ?? UIImage(systemName: tab.systemImage) {
                Image(uiImage: symbol.withTintColor(color, renderingMode: .alwaysOriginal))
            } else {
                Image(systemName: tab.systemImage)
            }
        }
    }

    /// The glass tab bar ignores UIKit's unselected tint and draws other tabs in plain black in light mode,
    /// so they're pre-colored there. Dark mode keeps the system's light icons.
    private func unselectedTabColor(_ tab: AppTab) -> UIColor? {
        guard colorScheme == .light, environment.selectedTab != tab else { return nil }
        return UIColor(named: "SecondaryText")?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
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
