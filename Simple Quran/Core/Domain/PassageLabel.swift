import Foundation

nonisolated enum PassageLabel {
    static func passage(_ range: VerseRange, catalog: some QuranCatalog) -> String {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah)
        else {
            return "\(range.startGlobalAyah)–\(range.endGlobalAyah)"
        }

        if first.surahNumber == last.surahNumber,
           let surah = catalog.surah(number: first.surahNumber) {
            if range.startGlobalAyah == surah.startGlobalAyah,
               range.endGlobalAyah == surah.endGlobalAyah {
                return surah.englishName
            }
            if first.globalAyah == last.globalAyah {
                return "\(surah.englishName) \(first.ayahInSurah)"
            }
            return "\(surah.englishName) \(first.ayahInSurah)–\(last.ayahInSurah)"
        }

        if let juz = catalog.juzs.first(where: {
            $0.startGlobalAyah == range.startGlobalAyah && $0.endGlobalAyah == range.endGlobalAyah
        }) {
            return juzTitle(juz.number)
        }

        if let page = catalog.pages.first(where: {
            $0.startGlobalAyah == range.startGlobalAyah && $0.endGlobalAyah == range.endGlobalAyah
        }) {
            return pageTitle(page.number)
        }

        let firstName = catalog.surah(number: first.surahNumber)?.englishName ?? "\(first.surahNumber)"
        let lastName = catalog.surah(number: last.surahNumber)?.englishName ?? "\(last.surahNumber)"
        return "\(firstName) \(first.ayahInSurah) – \(lastName) \(last.ayahInSurah)"
    }

    static func collection(_ ranges: [VerseRange], catalog: some QuranCatalog) -> String {
        guard !ranges.isEmpty else { return "" }
        if ranges.count == 1 {
            return passage(ranges[0], catalog: catalog)
        }

        let spans = ranges.map { ayahSpan(in: $0, catalog: catalog) }
        if let first = spans.first, let surahNumber = first.surahNumber,
           spans.allSatisfy({ $0.surahNumber == surahNumber }) {
            return "\(first.surahName) \(spans.map(\.text).joined(separator: ", "))"
        }

        return ranges.map { passage($0, catalog: catalog) }.joined(separator: ", ")
    }

    private static func ayahSpan(
        in range: VerseRange,
        catalog: some QuranCatalog
    ) -> (surahNumber: Int?, surahName: String, text: String) {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah),
              first.surahNumber == last.surahNumber,
              let surah = catalog.surah(number: first.surahNumber)
        else {
            return (nil, "", passage(range, catalog: catalog))
        }
        let text = first.globalAyah == last.globalAyah
            ? "\(first.ayahInSurah)"
            : "\(first.ayahInSurah)–\(last.ayahInSurah)"
        return (first.surahNumber, surah.englishName, text)
    }

    private static func juzTitle(_ number: Int) -> String {
        number == 30
            ? String(localized: "Juz \(number) · Amma")
            : String(localized: "Juz \(number)")
    }

    private static func pageTitle(_ number: Int) -> String {
        String(localized: "Page \(number)")
    }
}
