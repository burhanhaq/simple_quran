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
    @State private var passageCache = ReaderPassageCache()
    /// Checking files is a filesystem call per ayah, so it runs when downloads finish, not on every render.
    @State private var audioDownloaded = false

    private var ranges: [VerseRange] {
        readingRanges ?? destination.range(in: environment.quran).map { [$0] } ?? []
    }
    private var passage: ReaderPassage { passageCache.passage(for: ranges, catalog: environment.quran) }
    private var verses: [QuranVerse] { passage.verses }
    private var ownsPlayback: Bool { environment.playback.activeSet == nil && environment.playback.isPrepared(for: ranges) }
    private var currentAyah: Int? {
        ownsPlayback ? environment.playback.snapshot.currentGlobalAyah : selectedAyah ?? verses.first?.globalAyah
    }
    private var downloading: Bool {
        passage.ayahIDs.contains { environment.downloads.jobs[$0]?.status == .downloading }
    }
    private var readyJobCount: Int {
        passage.ayahIDs.reduce(0) { $0 + (environment.downloads.jobs[$1]?.status == .ready ? 1 : 0) }
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
                        Button(audioDownloaded ? "Audio downloaded" : downloading ? "Downloading audio…" : "Download this audio", systemImage: audioDownloaded ? "checkmark.circle" : "arrow.down.circle") {
                            environment.downloads.download(ayahs: passage.ayahIDs)
                        }.disabled(audioDownloaded || downloading)
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .accessibilityLabel("Reader options")
                }
            }
            .onAppear { initialize() }
            .task(id: AudioCheck(ayahIDs: passage.ayahIDs, readyJobs: readyJobCount)) { refreshAudioDownloaded() }
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
                if let range = LearningPassage.piece(from: verse.globalAyah, size: environment.settings.pieceSize, catalog: environment.quran) {
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
            if let ayah = currentAyah, let index = passage.indexByAyah[ayah] {
                Text("Ayah \(index + 1) of \(verses.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(Color.secondaryWarm)
            }
            if downloading {
                HStack(spacing: 8) { ProgressView(); Text("Downloading audio for offline use…").font(.caption) }
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
        guard let ayah = currentAyah, let index = passage.indexByAyah[ayah], verses.indices.contains(index + offset) else { return }
        select(verses[index + offset].globalAyah)
    }

    private func refreshAudioDownloaded() {
        let ids = passage.ayahIDs
        audioDownloaded = !ids.isEmpty && environment.downloads.downloadedCount(in: ids) == ids.count
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

/// The reader's verses in reading order, with lookups the controls need on every render.
struct ReaderPassage {
    var verses: [QuranVerse] = []
    var ayahIDs: [Int] = []
    var indexByAyah: [Int: Int] = [:]

    init() {}

    init(ranges: [VerseRange], catalog: some QuranCatalog) {
        var seen = Set<Int>()
        verses = ranges.flatMap { catalog.verses(in: $0) }.filter { seen.insert($0.globalAyah).inserted }
        ayahIDs = verses.map(\.globalAyah)
        indexByAyah = Dictionary(uniqueKeysWithValues: ayahIDs.enumerated().map { ($1, $0) })
    }
}

/// Rebuilds the passage only when the ranges change. Holding it in a class keeps the
/// cache out of SwiftUI's state tracking, so filling it during a render is safe.
@MainActor
final class ReaderPassageCache {
    private var ranges: [VerseRange]?
    private var cached = ReaderPassage()

    func passage(for ranges: [VerseRange], catalog: some QuranCatalog) -> ReaderPassage {
        if ranges != self.ranges {
            cached = ReaderPassage(ranges: ranges, catalog: catalog)
            self.ranges = ranges
        }
        return cached
    }
}

private struct AudioCheck: Equatable {
    var ayahIDs: [Int]
    var readyJobs: Int
}
