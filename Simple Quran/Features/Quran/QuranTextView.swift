import SwiftUI

/// Quran text in the user's chosen layout for the surah screen, reading or memorizing a piece.
struct QuranTextView<AyahMenu: View>: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let verses: [QuranVerse]
    let currentAyah: Int?
    var hiddenAyahs: Set<Int> = []
    var selectionEnabled = true
    var focusedAyah: Int? = nil
    var scrollToAyah: Int? = nil
    /// The piece being memorized; everything else fades back.
    var focusRange: VerseRange? = nil
    /// Ayahs marked as slipped while testing.
    var markedAyahs: Set<Int> = []
    /// Shown under the surah banner in ayah-by-ayah layout.
    var caption: String? = nil
    let onSelect: (Int) -> Void
    @ViewBuilder var ayahMenu: (QuranVerse) -> AyahMenu

    /// The ayah centered in ayah-by-ayah layout. Seeded before the first layout so a deep
    /// ayah opens in place instead of jumping there after the list appears.
    @State private var listPosition: Int?
    @State private var seededListPosition = false

    /// Translation always shows ayah by ayah; continuous text stays Arabic only.
    private var translation: BundledTranslation? {
        environment.settings.showsTranslation ? environment.translations.current : nil
    }

    /// Playback moves within this many ayahs scroll with animation; longer jumps go straight
    /// there, since animating through hundreds of lazy rows stutters.
    private static var animatedFollowDistance: Int { 3 }

    var body: some View {
        Group {
            if environment.settings.displayedReadingLayout == .mushaf {
                MushafFlowView(
                    verses: verses,
                    currentGlobalAyah: currentAyah,
                    hiddenAyahs: hiddenAyahs,
                    basmala: environment.quran.basmala,
                    selectionEnabled: selectionEnabled,
                    focusedAyah: focusedAyah,
                    focusRange: focusRange,
                    markedAyahs: markedAyahs,
                    onSelect: onSelect
                )
            } else { ayahList }
        }
        // Switching layouts, such as turning translation on, keeps the place instead of reopening the surah.
        .onChange(of: environment.settings.displayedReadingLayout) { _, _ in seededListPosition = true }
    }

    private var ayahList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let first = verses.first, let surah = environment.quran.surah(number: first.surahNumber) {
                    VStack(spacing: 8) {
                        ReadingBanner(title: surah.arabicName, isArabic: true)
                        Text(caption ?? "\(surah.translation) · \(surah.ayahCount) ayahs")
                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                    }.padding(.vertical, 20)
                }
                ForEach(verses) { verse in
                    Button { onSelect(verse.globalAyah) } label: {
                        VStack(spacing: 0) {
                            if verse.showsBasmalaBefore { BasmalaHeader() }
                            QuranAyahText(verse: verse, isCurrent: verse.globalAyah == currentAyah,
                                          hidden: hiddenAyahs.contains(verse.globalAyah),
                                          marked: markedAyahs.contains(verse.globalAyah),
                                          translation: translation?.text(globalAyah: verse.globalAyah))
                        }
                        .opacity(focusRange.map { $0.contains(verse.globalAyah) ? 1 : MushafTextBuilder.dimmedAlpha } ?? 1)
                    }
                    .buttonStyle(.plain).disabled(!selectionEnabled)
                    .id(verse.globalAyah)
                    .accessibilityIdentifier("ayah.\(verse.globalAyah)")
                    .accessibilityHint("Select this ayah")
                    .contextMenu { ayahMenu(verse) }
                }
                Color.clear.frame(height: 12)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 22)
            .frame(maxWidth: 740).frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: focusRange)
        .scrollPosition(id: $listPosition, anchor: .center)
        .onAppear(perform: seedListPosition)
        .task(id: environment.settings.showsTranslation) {
            if environment.settings.showsTranslation { await environment.translations.loadIfNeeded() }
        }
        .onChange(of: currentAyah) { previous, ayah in
            guard let ayah else { return }
            let distance = previous.map { abs($0 - ayah) } ?? .max
            if reduceMotion || distance > Self.animatedFollowDistance {
                listPosition = ayah
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { listPosition = ayah }
            }
        }
    }

    /// Opens at the requested ayah. After a switch from continuous text it keeps the ayah being
    /// played or memorized in view, the way continuous text does.
    private func seedListPosition() {
        let target = seededListPosition ? currentAyah ?? focusedAyah : scrollToAyah
        seededListPosition = true
        // The first ayah is already at the top; centering it would hide the surah banner.
        guard let target, target != verses.first?.globalAyah else { return }
        listPosition = target
    }
}
