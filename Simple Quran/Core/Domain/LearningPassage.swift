import Foundation

/// Suggestions are deliberately small and always end at an ayah boundary.
/// They are editable, not a fixed curriculum or a claim about thematic divisions.
nonisolated enum LearningPassage {
    static func suggested(from start: Int, catalog: some QuranCatalog) -> VerseRange? {
        guard let first = catalog.verse(globalAyah: start),
              let surah = catalog.surah(number: first.surahNumber) else { return nil }
        let remaining = catalog.verses(in: .clamped(start: start, end: surah.endGlobalAyah))
        let wholeIsSmall = start == surah.startGlobalAyah && surah.ayahCount <= 7
            && remaining.reduce(0, { $0 + wordCount($1) }) <= 45
        if wholeIsSmall { return .clamped(start: start, end: surah.endGlobalAyah) }
        var end = start
        var words = 0
        for verse in remaining.prefix(3) {
            let count = wordCount(verse)
            if words > 0 && words + count > 40 { break }
            words += count
            end = verse.globalAyah
        }
        return .clamped(start: start, end: end)
    }

    static func next(after range: VerseRange, catalog: some QuranCatalog, byPage: Bool = false) -> VerseRange? {
        guard let last = catalog.verse(globalAyah: range.endGlobalAyah),
              let surah = catalog.surah(number: last.surahNumber),
              range.endGlobalAyah < surah.endGlobalAyah else { return nil }
        let start = range.endGlobalAyah + 1
        if byPage, let verse = catalog.verse(globalAyah: start),
           let page = catalog.pages.first(where: { $0.number == verse.page }) {
            return .clamped(start: start, end: page.endGlobalAyah)
        }
        return suggested(from: start, catalog: catalog)
    }

    static func ayahLabel(_ range: VerseRange, catalog: some QuranCatalog) -> String {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah) else { return "" }
        guard first.surahNumber == last.surahNumber else { return PassageLabel.passage(range, catalog: catalog) }
        return first.globalAyah == last.globalAyah
            ? String(localized: "Ayah \(first.ayahInSurah)")
            : String(localized: "Ayahs \(first.ayahInSurah)–\(last.ayahInSurah)")
    }

    static func referenceLabel(_ range: VerseRange, catalog: some QuranCatalog) -> String {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah),
              let firstSurah = catalog.surah(number: first.surahNumber),
              let lastSurah = catalog.surah(number: last.surahNumber) else { return "" }
        if first.surahNumber == last.surahNumber {
            return "\(firstSurah.englishName) · \(ayahLabel(range, catalog: catalog))"
        }
        return "\(firstSurah.englishName) \(first.ayahInSurah) – \(lastSurah.englishName) \(last.ayahInSurah)"
    }

    private static func wordCount(_ verse: QuranVerse) -> Int {
        verse.text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
