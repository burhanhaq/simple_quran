import SwiftUI

/// Reading and listening only. Memorizing happens in its own session, reached from a long-press.
struct QuranReaderView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let destination: QuranDestination
    var resumesPlayback = false
    @State private var readingRanges: [VerseRange]?
    @State private var readingName: String?
    @State private var selectedAyah: Int?
    @State private var initialized = false
    @State private var errorMessage: UserFacingMessage?

    private var ranges: [VerseRange] {
        readingRanges ?? destination.range(in: environment.quran).map { [$0] } ?? []
    }
    private var verses: [QuranVerse] {
        var seen = Set<Int>()
        return ranges.flatMap { environment.quran.verses(in: $0) }.filter { seen.insert($0.globalAyah).inserted }
    }
    private var ownsPlayback: Bool { environment.playback.activeSet == nil && environment.playback.isPrepared(for: ranges) }
    private var currentAyah: Int? {
        ownsPlayback ? environment.playback.snapshot.currentGlobalAyah : selectedAyah ?? verses.first?.globalAyah
    }
    private var downloading: Bool {
        verses.contains { environment.downloads.jobs[$0.globalAyah]?.status == .downloading }
    }
    private var audioDownloaded: Bool {
        !verses.isEmpty && environment.downloads.downloadedCount(in: verses.map(\.globalAyah)) == verses.count
    }
    private var playing: Bool { ownsPlayback && (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading) }
    private var title: String { readingName ?? destination.title(in: environment.quran) }

    var body: some View {
        NavigationStack {
            Group {
                if verticalSizeClass == .compact {
                    HStack(spacing: 0) { text; controls.frame(width: 290) }
                } else {
                    VStack(spacing: 0) { text; controls }
                }
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 32, height: 32) }
                        .accessibilityLabel("Close reader").accessibilityIdentifier("reader.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ReadingLayoutMenu()
                        Button(audioDownloaded ? "Audio saved on this device" : downloading ? "Saving audio…" : "Download this audio", systemImage: audioDownloaded ? "checkmark.circle" : "arrow.down.circle") {
                            environment.downloads.download(ayahs: verses.map(\.globalAyah))
                        }.disabled(audioDownloaded || downloading)
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .accessibilityLabel("Reader options")
                }
            }
            .onAppear { initialize() }
            .onDisappear { savePosition() }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, ayah in
                guard ownsPlayback, let ayah else { return }
                selectedAyah = ayah
                savePosition()
            }
            .alert(errorMessage?.title ?? environment.playback.userMessage?.title ?? environment.downloads.userMessage?.title ?? "", isPresented: Binding(
                get: { errorMessage != nil || environment.playback.userMessage != nil || environment.downloads.userMessage != nil },
                set: { if !$0 { errorMessage = nil; environment.playback.userMessage = nil; environment.downloads.userMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(errorMessage?.message ?? environment.playback.userMessage?.message ?? environment.downloads.userMessage?.message ?? "")
            }
        }
        .tint(Color.bronze)
    }

    private var text: some View {
        QuranTextView(
            verses: verses,
            currentAyah: currentAyah,
            focusedAyah: selectedAyah,
            scrollToAyah: destination.scrollToAyah,
            onSelect: select
        ) { verse in
            Button("Memorize from here", systemImage: "leaf") {
                savePosition()
                if let range = LearningPassage.suggested(from: verse.globalAyah, catalog: environment.quran) {
                    environment.openSession(range)
                }
            }
            Button("I know this ayah", systemImage: MemorizationStatus.memorized.systemImage) {
                do { try environment.store.markMemorized(ayahs: [verse.globalAyah]) }
                catch { errorMessage = .from(.persistenceFailure) }
            }
            if let surah = environment.quran.surah(number: verse.surahNumber), environment.settings.activePlan?.range != surah.range {
                Button("Make \(surah.englishName) my plan", systemImage: "bookmark") {
                    environment.settings.setActivePlan(LearningTarget(range: surah.range))
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                Button { moveAyah(by: -1) } label: {
                    Image(systemName: "backward.end.fill").font(.title3).frame(width: 48, height: 48)
                }.accessibilityLabel("Previous ayah").accessibilityIdentifier("reader.previous")
                    .disabled(currentAyah == verses.first?.globalAyah)
                Button { togglePlayback() } label: {
                    ZStack {
                        PlayGlyph(systemName: playing ? "pause.fill" : "play.fill", size: 56)
                        if ownsPlayback && environment.playback.snapshot.isLoading { ProgressView().tint(Color.goldButtonText) }
                    }
                }.accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("quran.play")
                Button { moveAyah(by: 1) } label: {
                    Image(systemName: "forward.end.fill").font(.title3).frame(width: 48, height: 48)
                }.accessibilityLabel("Next ayah").accessibilityIdentifier("reader.next")
                    .disabled(currentAyah == verses.last?.globalAyah)
            }.frame(maxWidth: .infinity)
            if let ayah = currentAyah, let index = verses.firstIndex(where: { $0.globalAyah == ayah }) {
                Text("Ayah \(index + 1) of \(verses.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(Color.secondaryWarm)
            }
            if downloading {
                HStack(spacing: 8) { ProgressView(); Text("Saving audio for offline use…").font(.caption) }
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.bronze)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 740)
        .background(Color.appWarmSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color.warmBorder.opacity(0.6)).frame(height: 0.5) }
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        selectedAyah = destination.scrollToAyah ?? ranges.first?.startGlobalAyah
        if resumesPlayback {
            readingRanges = environment.playback.passageRanges
            readingName = environment.playback.snapshot.setTitle
            selectedAyah = environment.playback.snapshot.currentGlobalAyah
        } else if !ownsPlayback {
            environment.playback.pause()
        }
    }

    private func moveAyah(by offset: Int) {
        guard let ayah = currentAyah, let index = verses.firstIndex(where: { $0.globalAyah == ayah }), verses.indices.contains(index + offset) else { return }
        select(verses[index + offset].globalAyah)
    }

    private func savePosition() {
        if let ayah = currentAyah { environment.settings.readingAyah = ayah }
    }

    private func togglePlayback() {
        if playing { environment.playback.pause(); return }
        if !ownsPlayback {
            environment.playback.startListening(title: title, passages: ranges, fromAyah: currentAyah,
                                                catalog: environment.quran, allowStreaming: environment.settings.streamWhenMissing)
        }
        environment.playback.resume()
    }

    private func select(_ ayah: Int) {
        selectedAyah = ayah
        if ownsPlayback { environment.playback.move(to: ayah) }
        savePosition()
    }
}
