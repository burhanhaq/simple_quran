import Foundation

/// What Siri was asked to play, worked out before anything plays so a wrong ayah number gets a clear answer.
nonisolated enum SiriListening {
    enum Problem: Error, Equatable, Sendable {
        /// The surah has `ayahCount` ayahs, so it has no ayah `asked`.
        case ayahOutOfRange(surah: Int, ayahCount: Int, asked: Int)
        case countNotPositive
    }

    /// `count` ayahs of `surah` from `startAyah`. Asking for more than are left stops at the surah's end.
    static func ayahs(of surah: Surah, from startAyah: Int, count: Int) throws(Problem) -> VerseRange {
        guard count > 0 else { throw .countNotPositive }
        let start = try globalAyah(of: surah, ayah: startAyah)
        return .clamped(start: start, end: min(start + count - 1, surah.endGlobalAyah))
    }

    /// The global ayah number of `ayah` in `surah`.
    static func globalAyah(of surah: Surah, ayah: Int) throws(Problem) -> Int {
        guard (1...surah.ayahCount).contains(ayah) else {
            throw .ayahOutOfRange(surah: surah.number, ayahCount: surah.ayahCount, asked: ayah)
        }
        return surah.startGlobalAyah + ayah - 1
    }
}

/// Other ways people say a surah or juz, so Siri matches what they speak, not only the catalog's spelling.
nonisolated enum SpokenNames {
    /// Arabic articles that open transliterated names ("Al-Mulk", "An-Naba", "Ash-Shams").
    private static let articles: Set<String> = ["al", "an", "ar", "as", "at", "ad", "ash", "az", "adh", "ath"]
    private static let doubledVowels = [("aa", "a"), ("ee", "i"), ("oo", "u"), ("ii", "i"), ("uu", "u")]

    /// "Al-Mulk" → "Al Mulk", "Mulk", "Tabarak", "The Sovereignty"…, never repeating the catalog name.
    static func surah(_ surah: Surah) -> [String] {
        var names: [String] = []
        for name in [surah.englishName] + surah.aliases {
            let plain = simplified(name)
            names += [name, spaced(name), plain, spaced(plain)]
            if let bare = withoutArticle(name) { names += [bare, simplified(bare)] }
            if let bare = withoutArticle(plain) { names.append(bare) }
        }
        names.append(surah.translation)
        return unique(names, excluding: surah.englishName)
    }

    /// "Juz 18" → "Juz eighteen", "Para 18", "18"…, plus the juz's traditional names.
    static func juz(_ number: Int) -> [String] {
        let words = spelledOut(number)
        var names: [String] = []
        for prefix in ["Juz", "Para", "Sipara"] {
            names += ["\(prefix) \(number)", "\(prefix) \(words)"]
        }
        names += ["\(number)", words]
        names += JuzNames.names(for: number)
        return unique(names, excluding: "Juz \(number)")
    }

    static func spelledOut(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private static func spaced(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "'", with: "")
    }

    /// Long vowels written once, the way most people spell them: "Al-Faatiha" → "Al-Fatiha".
    private static func simplified(_ name: String) -> String {
        doubledVowels.reduce(name) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func withoutArticle(_ name: String) -> String? {
        let parts = name.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, articles.contains(parts[0].lowercased()) else { return nil }
        return spaced(String(parts[1]))
    }

    private static func unique(_ names: [String], excluding title: String) -> [String] {
        var seen: Set<String> = [title.lowercased()]
        return names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
