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
                    .parchmentNavigationBar()
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
            .tint(Color.bronze)
            .symbolRenderingMode(.hierarchical)
            .background(Color.parchment.ignoresSafeArea())
            .tabViewBottomAccessory(isEnabled: environment.playback.snapshot.currentGlobalAyah != nil) {
                if let ayah = environment.playback.snapshot.currentGlobalAyah {
                    GlobalMiniPlayer(ayah: ayah)
                }
            }
        }
    }
}

private struct GlobalMiniPlayer: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let ayah: Int
    @State private var showPlayer = false
    @State private var practiceSet: PracticeSet?

    private var isInline: Bool { placement == .inline }

    var body: some View {
        let verse = environment.quran.verse(globalAyah: ayah)
        HStack(spacing: 12) {
            Button {
                if let activeSet = environment.playback.activeSet { practiceSet = activeSet }
                else { showPlayer = true }
            } label: {
                HStack(spacing: 10) {
                    if !isInline { WarmSymbol(systemName: "waveform", size: 34) }
                    MiniPlayerMetadata(
                        title: environment.playback.snapshot.setTitle,
                        reference: environment.playback.userMessage != nil ? String(localized: "Audio unavailable · open player") : verse.map { String(localized: "Ayah \($0.ayahInSurah)") } ?? "",
                        showsTitle: !isInline
                    )
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Open player"))
            .accessibilityIdentifier("playback.open")
            Spacer(minLength: 8)
            MiniPlayerTransport(showsSkipButtons: !isInline)
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showPlayer) { ListeningPlayerView() }
        .fullScreenCover(item: $practiceSet) { PracticeView(practiceSet: $0) }
    }
}

private struct MiniPlayerMetadata: View {
    let title: String
    let reference: String
    let showsTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appBrownText)
                    .lineLimit(1)
            }
            Text(reference)
                .font(.caption)
                .foregroundStyle(Color.secondaryWarm)
                .lineLimit(1)
        }
    }
}

private struct MiniPlayerTransport: View {
    @Environment(AppEnvironment.self) private var environment
    let showsSkipButtons: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsSkipButtons {
                Button {
                    environment.playback.skipBack()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Previous ayah"))
                .accessibilityIdentifier("playback.previous")
            }

            Button(action: togglePlayback) {
                ZStack {
                    PlayGlyph(
                        systemName: (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading) ? "pause.fill" : "play.fill",
                        size: 36
                    )
                    .opacity(environment.playback.snapshot.isLoading ? 0.35 : 1)
                    if environment.playback.snapshot.isLoading {
                        ProgressView()
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(
                (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading)
                    ? String(localized: "Pause")
                    : String(localized: "Play")
            )
            .accessibilityIdentifier("playback.toggle")

            if showsSkipButtons {
                Button {
                    environment.playback.skipForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Next ayah"))
                .accessibilityIdentifier("playback.next")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.bronze)
    }

    private func togglePlayback() {
        if environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading {
            environment.playback.pause()
        } else {
            environment.playback.resume()
        }
    }
}
