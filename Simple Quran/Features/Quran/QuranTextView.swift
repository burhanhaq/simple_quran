import SwiftUI

/// Quran text in the user's chosen layout, shared by the reader and memorize sessions.
struct QuranTextView<AyahMenu: View>: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let verses: [QuranVerse]
    let currentAyah: Int?
    var hiddenAyahs: Set<Int> = []
    var selectionEnabled = true
    var focusedAyah: Int? = nil
    var scrollToAyah: Int? = nil
    /// Shown under the surah banner in ayah-by-ayah layout.
    var caption: String? = nil
    let onSelect: (Int) -> Void
    @ViewBuilder var ayahMenu: (QuranVerse) -> AyahMenu

    /// The ayah centered in ayah-by-ayah layout. Seeded before the first layout so a deep
    /// ayah opens in place instead of jumping there after the list appears.
    @State private var listPosition: Int?
    @State private var seededListPosition = false

    /// Playback moves within this many ayahs scroll with animation; longer jumps go straight
    /// there, since animating through hundreds of lazy rows stutters.
    private static var animatedFollowDistance: Int { 3 }

    var body: some View {
        if environment.settings.quranReadingLayout == .mushaf {
            MushafFlowView(
                verses: verses,
                currentGlobalAyah: currentAyah,
                hiddenAyahs: hiddenAyahs,
                basmala: environment.quran.basmala,
                selectionEnabled: selectionEnabled,
                focusedAyah: focusedAyah,
                onSelect: onSelect
            )
        } else { ayahList }
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
                                          hidden: hiddenAyahs.contains(verse.globalAyah))
                        }
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
        .scrollPosition(id: $listPosition, anchor: .center)
        .onAppear(perform: seedListPosition)
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

    private func seedListPosition() {
        guard !seededListPosition else { return }
        seededListPosition = true
        // The first ayah is already at the top; centering it would hide the surah banner.
        guard let target = scrollToAyah, target != verses.first?.globalAyah else { return }
        listPosition = target
    }
}
