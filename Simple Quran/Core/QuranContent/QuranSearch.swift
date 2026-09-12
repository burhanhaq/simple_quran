import Foundation

nonisolated enum SurahAliasTable {
    static func aliases(for number: Int, englishName: String) -> [String] {
        var values = [
            englishName,
            englishName.replacingOccurrences(of: "-", with: " "),
            strippedArticle(englishName)
        ]
        values.append(contentsOf: extra[number] ?? [])
        return Array(Set(values.map(normalize))).filter { !$0.isEmpty }
    }

    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = folded.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(allowed)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func strippedArticle(_ name: String) -> String {
        let prefixes = ["Al-", "Ash-", "Ad-", "An-", "As-", "At-", "Az-", "Ar-"]
        for prefix in prefixes where name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }

    private static let extra: [Int: [String]] = [
        1: ["fatiha", "fatihah", "al fatiha", "opening", "الفاتحة"],
        2: ["baqara", "baqarah", "al baqarah", "cow", "البقرة", "kursi"],
        18: ["kahf", "al kahf", "cave", "surat al kahf", "الكهف"],
        36: ["yasin", "yaseen", "ya sin", "يس"],
        55: ["rahman", "ar rahman", "الرحمن"],
        56: ["waqiah", "waqia", "الواقعة"],
        67: ["mulk", "al mulk", "الملك"],
        78: ["naba", "amma", "النبأ"],
        112: ["ikhlas", "ikhlaas", "sincerity", "الإخلاص"],
        113: ["falaq", "الفلق"],
        114: ["nas", "naas", "mankind", "الناس"]
    ]
}

nonisolated struct QuranSearchIndex: Sendable {
    let catalog: BundledQuranCatalog

    func search(_ rawQuery: String) -> QuranSearchResult {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return QuranSearchResult(hits: []) }

        if let parsed = parseReference(query) {
            return QuranSearchResult(hits: [parsed])
        }

        let normalized = SurahAliasTable.normalize(query)
        var hits: [QuranSearchHit] = []

        if normalized.hasPrefix("juz") || normalized == "amma" {
            hits.append(contentsOf: juzHits(normalized))
        }
        if normalized.hasPrefix("page") || normalized.hasPrefix("pg") {
            hits.append(contentsOf: pageHits(normalized))
        }

        for surah in catalog.surahs {
            let haystack = ([surah.englishName, surah.translation, surah.arabicName] + surah.aliases)
                .map(SurahAliasTable.normalize)
            if haystack.contains(where: { $0.contains(normalized) || normalized.contains($0) && !$0.isEmpty }) {
                hits.append(
                    QuranSearchHit(
                        id: "surah-\(surah.number)",
                        kind: .surah(surah.number),
                        title: surah.displayName,
                        subtitle: "\(surah.arabicName) · \(surah.ayahCount) ayahs"
                    )
                )
            }
        }

        return QuranSearchResult(hits: unique(hits))
    }

    private func parseReference(_ query: String) -> QuranSearchHit? {
        let compact = query.replacingOccurrences(of: " ", with: "")
        let pattern = #"^(\d{1,3}):(\d{1,3})(?:-(\d{1,3}))?$"#
        guard let match = compact.range(of: pattern, options: .regularExpression) else { return nil }
        let parts = String(compact[match]).split(separator: ":")
        guard let surahNumber = Int(parts[0]) else { return nil }
        let ayahParts = parts[1].split(separator: "-")
        guard let start = Int(ayahParts[0]) else { return nil }
        let end = ayahParts.count > 1 ? Int(ayahParts[1]) ?? start : start
        guard let range = try? catalog.range(surah: surahNumber, startAyah: start, endAyah: end),
              let surah = catalog.surah(number: surahNumber)
        else { return nil }

        if start == end {
            return QuranSearchHit(
                id: "verse-\(range.startGlobalAyah)",
                kind: .verse(range.startGlobalAyah),
                title: "\(surah.englishName) \(start)",
                subtitle: surah.arabicName
            )
        }
        return QuranSearchHit(
            id: "range-\(range.startGlobalAyah)-\(range.endGlobalAyah)",
            kind: .range(range),
            title: "\(surah.englishName) \(start)–\(end)",
            subtitle: surah.arabicName
        )
    }

    private func juzHits(_ normalized: String) -> [QuranSearchHit] {
        if normalized == "amma" || normalized.contains("amma") {
            return [juzHit(30)]
        }
        let digits = normalized.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let number = digits.first, catalog.juzs.contains(where: { $0.number == number }) else { return [] }
        return [juzHit(number)]
    }

    private func pageHits(_ normalized: String) -> [QuranSearchHit] {
        let digits = normalized.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let number = digits.first, catalog.pages.contains(where: { $0.number == number }) else { return [] }
        return [
            QuranSearchHit(
                id: "page-\(number)",
                kind: .page(number),
                title: String(localized: "Page \(number)"),
                subtitle: String(localized: "604-page Madani Hafs layout")
            )
        ]
    }

    private func juzHit(_ number: Int) -> QuranSearchHit {
        let subtitle = number == 30 ? String(localized: "Juz Amma") : String(localized: "Juz \(number)")
        return QuranSearchHit(
            id: "juz-\(number)",
            kind: .juz(number),
            title: subtitle,
            subtitle: String(localized: "Standard 30 juz division")
        )
    }

    private func unique(_ hits: [QuranSearchHit]) -> [QuranSearchHit] {
        var seen = Set<String>()
        return hits.filter { seen.insert($0.id).inserted }
    }
}
