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

    var body: some View {
        if environment.settings.quranReadingLayout == .mushaf {
            MushafFlowView(
                verses: verses.map { verse in
                    guard hiddenAyahs.contains(verse.globalAyah) else { return verse }
                    var hidden = verse
                    hidden.text = MushafTextBuilder.hiddenPlaceholder
                    return hidden
                },
                currentGlobalAyah: currentAyah,
                hidesCurrentAyah: false,
                selectionEnabled: selectionEnabled,
                focusedAyah: focusedAyah,
                onSelect: onSelect
            )
        } else { ayahList }
    }

    private var ayahList: some View {
        ScrollViewReader { proxy in
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
                .padding(.horizontal, 22)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .onChange(of: currentAyah) { _, ayah in
                if let ayah { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(ayah, anchor: .center) } }
            }
            .task { if let scrollToAyah { proxy.scrollTo(scrollToAyah, anchor: .center) } }
        }
    }
}
