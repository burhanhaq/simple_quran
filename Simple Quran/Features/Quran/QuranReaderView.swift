import SwiftUI

struct QuranReaderView: View {
    @Environment(AppEnvironment.self) private var environment
    let destination: QuranDestination
    @State private var selection = PassageSelection()
    @State private var showHint = false

    var body: some View {
        let verses = visibleVerses
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if shouldShowHint {
                        hintBanner
                    }
                    if environment.isCollectingAyahs {
                        collectBanner
                    }
                    ForEach(verses) { verse in
                        Button {
                            handleTap(verse)
                        } label: {
                            VStack(spacing: 2) {
                                if verse.showsBasmalaBefore {
                                    BasmalaHeader()
                                }
                                QuranAyahText(
                                    verse: verse,
                                    isCurrent: isPlaying(verse),
                                    isInPassage: isCollected(verse),
                                    hidden: false
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .id(verse.globalAyah)
                        .accessibilityIdentifier("ayah.\(verse.globalAyah)")
                        .accessibilityHint(
                            environment.isCollectingAyahs
                                ? collectHint
                                : String(localized: "Play from this ayah")
                        )
                    }
                }
                .padding()
            }
            .onAppear {
                if !environment.settings.hasSeenQuranHint {
                    showHint = true
                    environment.settings.hasSeenQuranHint = true
                }
            }
            .task(id: destination.scrollToAyah) {
                if let ayah = destination.scrollToAyah {
                    proxy.scrollTo(ayah, anchor: .center)
                }
            }
            .onChange(of: destination) { _, _ in
                selection.reset()
            }
        }
        .background(Color.parchment.ignoresSafeArea())
        .navigationTitle(destination.title(in: environment.quran))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: playSystemImage)
                }
                .accessibilityIdentifier("quran.play")
                .accessibilityLabel(playTitle)

                Button(
                    environment.isCollectingAyahs
                        ? String(localized: "Collecting")
                        : String(localized: "Collect ayahs")
                ) {
                    toggleCollecting()
                }
                .accessibilityIdentifier("quran.collect")
                .accessibilityLabel(
                    environment.isCollectingAyahs
                        ? String(localized: "Finish collecting ayahs")
                        : String(localized: "Collect ayahs")
                )

                Menu {
                    Button(destination.collectWholeTitle, systemImage: "plus.rectangle.on.rectangle") {
                        collectWholeVisibleRange()
                    }
                    if !environment.collectionDraft.passages.isEmpty {
                        Button(String(localized: "Save collection"), systemImage: "square.and.arrow.down") {
                            environment.presentCollectionEditor()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowTray {
                PassageTrayView(
                    summary: environment.collectionDraft.summary(catalog: environment.quran),
                    onListen: listenToDraft,
                    onSave: { environment.presentCollectionEditor() }
                )
            }
        }
    }

    private var visibleRange: VerseRange? {
        destination.range(in: environment.quran)
    }

    private var visibleVerses: [QuranVerse] {
        guard let visibleRange else { return [] }
        return environment.quran.verses(in: visibleRange)
    }

    private var visiblePassages: [VerseRange] {
        visibleRange.map { [$0] } ?? []
    }

    private var shouldShowHint: Bool {
        showHint && !environment.isCollectingAyahs
    }

    private var shouldShowTray: Bool {
        environment.isCollectingAyahs && !environment.collectionDraft.passages.isEmpty
    }

    private var isThisPassagePlaying: Bool {
        environment.playback.isPrepared(for: visiblePassages)
            && (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading)
    }

    private var playTitle: String {
        isThisPassagePlaying ? String(localized: "Pause") : String(localized: "Play")
    }

    private var playSystemImage: String {
        isThisPassagePlaying ? "pause.fill" : "play.fill"
    }

    private var collectHint: String {
        if selection.isSelecting {
            String(localized: "Choose the last ayah in this passage")
        } else {
            String(localized: "Choose the first ayah in this passage")
        }
    }

    private var hintBanner: some View {
        Text(String(localized: "Listen here. When you want to memorize or review, collect ayahs."))
            .font(.footnote)
            .foregroundStyle(Color.secondaryWarm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("quran.hint")
    }

    private var collectBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "A collection is a group of ayahs you practice together."))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.appBrownText)
            Text(collectInstruction)
                .font(.footnote)
                .foregroundStyle(Color.secondaryWarm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.olive.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous))
        .accessibilityIdentifier("quran.collectBanner")
    }

    private var collectInstruction: String {
        if let start = selection.startGlobalAyah, let verse = environment.quran.verse(globalAyah: start) {
            String(localized: "Starts at \(verse.reference). Tap the last ayah, or tap \(verse.reference) again for only this ayah.")
        } else {
            String(localized: "Tap the first ayah, then the last.")
        }
    }

    private func isPlaying(_ verse: QuranVerse) -> Bool {
        verse.globalAyah == environment.playback.snapshot.currentGlobalAyah
    }

    private func isCollected(_ verse: QuranVerse) -> Bool {
        selection.highlights(verse.globalAyah, collected: environment.collectionDraft.passages.map(\.range))
    }

    private func handleTap(_ verse: QuranVerse) {
        if environment.isCollectingAyahs {
            collect(verse)
        } else {
            play(from: verse.globalAyah)
        }
    }

    private func collect(_ verse: QuranVerse) {
        if let range = selection.tap(verse.globalAyah) {
            environment.collectionDraft.append(range, titleHint: titleHint(for: range))
        }
    }

    private func toggleCollecting() {
        environment.isCollectingAyahs.toggle()
        selection.reset()
    }

    private func collectWholeVisibleRange() {
        guard let range = visibleRange else { return }
        environment.collectionDraft.append(range, titleHint: destination.title(in: environment.quran))
        environment.isCollectingAyahs = true
        selection.reset()
    }

    private func togglePlay() {
        if environment.playback.isPrepared(for: visiblePassages) {
            if isThisPassagePlaying {
                environment.playback.pause()
            } else {
                environment.playback.resume()
            }
            return
        }
        play(from: visibleRange?.startGlobalAyah)
    }

    private func play(from globalAyah: Int?) {
        let passages = visiblePassages
        guard !passages.isEmpty else { return }
        if environment.playback.isPrepared(for: passages),
           let globalAyah,
           environment.playback.containsAyah(globalAyah) {
            if environment.playback.snapshot.currentGlobalAyah != globalAyah {
                environment.playback.move(to: globalAyah)
            }
            if !environment.playback.snapshot.isPlaying {
                environment.playback.resume()
            }
            return
        }
        environment.playback.startListening(
            title: destination.title(in: environment.quran),
            passages: passages,
            fromAyah: globalAyah,
            catalog: environment.quran,
            allowStreaming: environment.settings.streamWhenMissing
        )
        environment.playback.resume()
    }

    private func listenToDraft() {
        let passages = environment.collectionDraft.passages
            .sorted { $0.order < $1.order }
            .map(\.range)
        guard !passages.isEmpty else { return }
        environment.playback.startListening(
            title: environment.collectionDraft.resolvedTitle,
            passages: passages,
            fromAyah: passages.first?.startGlobalAyah,
            catalog: environment.quran,
            allowStreaming: environment.settings.streamWhenMissing
        )
        environment.playback.resume()
    }

    private func titleHint(for range: VerseRange) -> String {
        guard let first = environment.quran.verse(globalAyah: range.startGlobalAyah),
              let last = environment.quran.verse(globalAyah: range.endGlobalAyah),
              let surah = environment.quran.surah(number: first.surahNumber)
        else {
            return destination.title(in: environment.quran)
        }
        if first.globalAyah == last.globalAyah {
            return "\(surah.englishName) \(first.ayahInSurah)"
        }
        if first.surahNumber == last.surahNumber {
            return "\(surah.englishName) \(first.ayahInSurah)–\(last.ayahInSurah)"
        }
        return destination.title(in: environment.quran)
    }
}
