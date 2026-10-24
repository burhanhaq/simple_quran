import Foundation

/// Name indexes for surahs, juz and well-known passages, built once with the catalog.
nonisolated struct QuranNameIndex: Sendable {
    let surahs: NameIndex<Int>
    let juzs: NameIndex<Int>
    /// Keyed by position in `NamedPassage.all`.
    let passages: NameIndex<Int>

    init(surahs: [Surah]) {
        self.surahs = NameIndex(surahs.map { .init(id: $0.number, names: [$0.englishName, $0.arabicName] + $0.aliases, translations: [$0.translation]) })
        self.juzs = NameIndex((1...QuranCatalogMetrics.juzCount).map { .init(id: $0, names: JuzNames.names(for: $0)) })
        self.passages = NameIndex(NamedPassage.all.enumerated().map { .init(id: $0.offset, names: $0.element.names) })
    }
}

/// Answers what someone typed into a search box: references ("2:255", "Taha 5", "20"),
/// juz and page keywords ("juz 30", "para amma", "page 12"), and names in any common spelling.
nonisolated struct QuranSearch {
    let catalog: BundledQuranCatalog

    /// Everything the query could mean, most likely first.
    func search(_ raw: String) -> QuranSearchResult {
        let query = SearchQuery(raw)
        guard !query.isEmpty else { return QuranSearchResult(hits: []) }

        switch Intent(query) {
        case .reference(let surah, let ayahs):
            return QuranSearchResult(hits: [passageHit(surah: surah, ayahs: ayahs)].compactMap { $0 })
        case .namedReference(let name, let ayahs):
            guard let surah = bestSurah(name) else { return nameResults(query) }
            return QuranSearchResult(hits: [passageHit(surah: surah.number, ayahs: ayahs), surahHit(surah)].compactMap { $0 })
        case .number(let number):
            let hits = [catalog.surah(number: number).map(surahHit), juzHit(number), pageHit(number)]
            return QuranSearchResult(hits: hits.compactMap { $0 })
        case .juz(let target):
            return QuranSearchResult(hits: juzNumbers(target).compactMap(juzHit))
        case .page(let number):
            return QuranSearchResult(hits: [pageHit(number)].compactMap { $0 })
        case .names:
            return nameResults(query)
        }
    }

    /// Surahs for a surah list's search box, best match first.
    func surahs(matching raw: String) -> [Surah] {
        let query = SearchQuery(raw)
        guard !query.isEmpty else { return [] }
        switch Intent(query) {
        case .reference(let number, _), .number(let number):
            return [catalog.surah(number: number)].compactMap { $0 }
        case .namedReference(let name, _):
            return [bestSurah(name)].compactMap { $0 }
        case .juz, .page:
            return []
        case .names:
            return catalog.names.surahs.matches(query).compactMap { catalog.surah(number: $0.id) }
        }
    }

    /// Juz for a juz list's search box: by number, traditional name, or a verse inside it.
    func juzs(matching raw: String) -> [JuzSection] {
        let query = SearchQuery(raw)
        guard !query.isEmpty else { return [] }
        let numbers: [Int] = switch Intent(query) {
        case .reference(let surah, let ayahs):
            [juzNumber(surah: surah, ayah: ayahs.lowerBound)].compactMap { $0 }
        case .namedReference(let name, let ayahs):
            [bestSurah(name).flatMap { juzNumber(surah: $0.number, ayah: ayahs.lowerBound) }].compactMap { $0 }
        case .number(let number):
            [number]
        case .juz(let target):
            juzNumbers(target)
        case .page(let number):
            [catalog.pages.first { $0.number == number }.flatMap { catalog.verse(globalAyah: $0.startGlobalAyah)?.juz }].compactMap { $0 }
        case .names:
            catalog.names.juzs.matches(query).map(\.id)
        }
        return numbers.compactMap { number in catalog.juzs.first { $0.number == number } }
    }

    // MARK: - Names

    private func nameResults(_ query: SearchQuery) -> QuranSearchResult {
        let passages = catalog.names.passages.matches(query).compactMap { match in
            namedPassageHit(NamedPassage.all[match.id]).map { Ranked(hit: $0, strength: match.strength) }
        }
        let surahs = catalog.names.surahs.matches(query).compactMap { match in
            catalog.surah(number: match.id).map { Ranked(hit: surahHit($0), strength: match.strength) }
        }
        let juzs = catalog.names.juzs.matches(query).compactMap { match in
            juzHit(match.id).map { Ranked(hit: $0, strength: match.strength) }
        }
        let ranked = (surahs + passages + juzs).enumerated().sorted { lhs, rhs in
            if lhs.element.strength != rhs.element.strength { return lhs.element.strength > rhs.element.strength }
            return lhs.offset < rhs.offset
        }
        return QuranSearchResult(hits: unique(ranked.map(\.element.hit)))
    }

    /// The surah a name most likely means, if the match is better than a loose guess.
    private func bestSurah(_ name: SearchQuery) -> Surah? {
        guard let best = catalog.names.surahs.matches(name).first, best.strength >= .fuzzy else { return nil }
        return catalog.surah(number: best.id)
    }

    private func juzNumbers(_ target: Intent.JuzTarget) -> [Int] {
        switch target {
        case .all: catalog.juzs.map(\.number)
        case .number(let number): [number]
        case .named(let name): catalog.names.juzs.matches(name).map(\.id)
        }
    }

    private func juzNumber(surah: Int, ayah: Int) -> Int? {
        guard let start = catalog.surah(number: surah)?.startGlobalAyah else { return nil }
        return catalog.verse(globalAyah: start + ayah - 1)?.juz
    }

    // MARK: - Hits

    private func surahHit(_ surah: Surah) -> QuranSearchHit {
        QuranSearchHit(
            id: "surah-\(surah.number)",
            kind: .surah(surah.number),
            title: surah.displayName,
            subtitle: "\(surah.arabicName) · \(surah.ayahCount) ayahs"
        )
    }

    private func passageHit(surah surahNumber: Int, ayahs: ClosedRange<Int>) -> QuranSearchHit? {
        guard let range = try? catalog.range(surah: surahNumber, startAyah: ayahs.lowerBound, endAyah: ayahs.upperBound),
              let surah = catalog.surah(number: surahNumber)
        else { return nil }
        return passageHit(range, title: PassageLabel.passage(range, catalog: catalog), subtitle: surah.arabicName)
    }

    private func namedPassageHit(_ passage: NamedPassage) -> QuranSearchHit? {
        guard let name = passage.names.first,
              let range = try? catalog.range(surah: passage.surah, startAyah: passage.startAyah, endAyah: passage.endAyah)
        else { return nil }
        return passageHit(range, title: name, subtitle: PassageLabel.passage(range, catalog: catalog))
    }

    private func passageHit(_ range: VerseRange, title: String, subtitle: String) -> QuranSearchHit {
        if range.startGlobalAyah == range.endGlobalAyah {
            return QuranSearchHit(id: "verse-\(range.startGlobalAyah)", kind: .verse(range.startGlobalAyah), title: title, subtitle: subtitle)
        }
        return QuranSearchHit(
            id: "range-\(range.startGlobalAyah)-\(range.endGlobalAyah)",
            kind: .range(range),
            title: title,
            subtitle: subtitle
        )
    }

    private func juzHit(_ number: Int) -> QuranSearchHit? {
        guard catalog.juzs.contains(where: { $0.number == number }) else { return nil }
        let names = JuzNames.names(for: number)
        let title = number == 30 ? String(localized: "Juz Amma") : String(localized: "Juz \(number)")
        return QuranSearchHit(
            id: "juz-\(number)",
            kind: .juz(number),
            title: title,
            subtitle: number == 30 ? String(localized: "Juz 30") : names.first ?? String(localized: "Standard 30 juz division")
        )
    }

    private func pageHit(_ number: Int) -> QuranSearchHit? {
        guard catalog.pages.contains(where: { $0.number == number }) else { return nil }
        return QuranSearchHit(
            id: "page-\(number)",
            kind: .page(number),
            title: String(localized: "Page \(number)"),
            subtitle: String(localized: "604-page Madani Hafs layout")
        )
    }

    private func unique(_ hits: [QuranSearchHit]) -> [QuranSearchHit] {
        var seen = Set<String>()
        return hits.filter { seen.insert($0.id).inserted }
    }

    private struct Ranked {
        var hit: QuranSearchHit
        var strength: MatchStrength
    }
}

/// What kind of thing a query asks for, decided before any name matching.
private nonisolated enum Intent {
    enum JuzTarget {
        case all
        case number(Int)
        case named(SearchQuery)
    }

    /// "2:255", "20 5", "18:1-10"
    case reference(surah: Int, ayahs: ClosedRange<Int>)
    /// "baqara 255", "ta-ha:5", "yasin 1-12"
    case namedReference(name: SearchQuery, ayahs: ClosedRange<Int>)
    /// "20"
    case number(Int)
    /// "juz 5", "para amma", "juz"
    case juz(JuzTarget)
    /// "page 12"
    case page(Int)
    case names

    init(_ query: SearchQuery) {
        let text = query.text
        if let keywordIntent = Self.keyword(query) {
            self = keywordIntent
        } else if let match = text.wholeMatch(of: #/(\d{1,3})\s*[:.\s]\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?/#),
                  let surah = Int(match.1), let ayahs = Self.ayahs(match.2, match.3) {
            self = .reference(surah: surah, ayahs: ayahs)
        } else if let match = text.wholeMatch(of: #/\d{1,3}/#), let number = Int(match.output) {
            self = .number(number)
        } else if let match = text.wholeMatch(of: #/(.*[^\d\s:.\-])\s*[:.]?\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?/#),
                  let ayahs = Self.ayahs(match.2, match.3) {
            self = .namedReference(name: SearchQuery(String(match.1)), ayahs: ayahs)
        } else {
            self = .names
        }
    }

    private static func ayahs(_ start: Substring, _ end: Substring?) -> ClosedRange<Int>? {
        guard let first = Int(start) else { return nil }
        let last = end.flatMap { Int($0) } ?? first
        return last >= first ? first...last : nil
    }

    /// A leading "juz", "para" or "page" word, then a number or (for juz) a name.
    private static func keyword(_ query: SearchQuery) -> Intent? {
        guard let first = query.words.first,
              let match = query.text.prefixMatch(of: #/\p{L}+/#)
        else { return nil }
        let rest = query.text[match.range.upperBound...].trimmingCharacters(in: .whitespaces)
        let number = Int(rest)
        if Keyword.juz.contains(first) {
            if rest.isEmpty { return .juz(.all) }
            if let number { return .juz(.number(number)) }
            return .juz(.named(SearchQuery(rest)))
        }
        if Keyword.page.contains(first), let number {
            return .page(number)
        }
        return nil
    }

    private enum Keyword {
        static let juz: Set<String> = Set(["juz", "juzz", "para", "parah", "sipara", "siparah", "جزء", "پارہ"].map(SearchKey.word))
        static let page: Set<String> = Set(["page", "pg", "p", "صفحة"].map(SearchKey.word))
    }
}
