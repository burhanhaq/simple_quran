import Foundation

/// Folds the many ways a name gets typed into one comparable key.
///
/// Transliterations disagree on long vowels (Taa-Haa / Taha), endings (Baqarah / Baqara),
/// articles (Ash-Shams / As-Shams / Shams) and letters (Qadr / Kadr, Dhuha / Duha), and Arabic
/// input may or may not carry vowel marks or a particular alef. Both sides of a comparison go
/// through the same rules, so the keys only need to agree with each other, not look like English.
nonisolated enum SearchKey {
    /// The key of the whole text, and the key with a leading article dropped when it had one.
    static func keys(_ text: String) -> [String] {
        let words = tokens(text)
        var keys = [join(words)]
        if let bare = withoutArticle(words) { keys.append(join(bare)) }
        return unique(keys.filter { !$0.isEmpty })
    }

    /// The keys of each meaningful word, used to match the start of any word in a longer name.
    static func wordKeys(_ text: String) -> [String] {
        let words = tokens(text).filter { !articles.contains($0) }.map(Word.withoutArabicArticle)
        return unique(words.map(collapse).filter { $0.count >= 3 })
    }

    /// Words folded and spelled the same way keys are, with filler words like "surah" and "the" removed.
    static func tokens(_ text: String) -> [String] {
        splitWords(fold(text)).map(phonetic).filter { !fillers.contains($0) }
    }

    /// Converts Arabic-Indic digits so "٢:٢٥٥" reads as "2:255".
    static func westernDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x0660...0x0669: Unicode.Scalar(scalar.value - 0x0660 + 0x30) ?? scalar
            case 0x06F0...0x06F9: Unicode.Scalar(scalar.value - 0x06F0 + 0x30) ?? scalar
            default: scalar
            }
        }))
    }

    /// The same spelling rules applied to a single word, for comparing against keyword lists.
    static func word(_ text: String) -> String { collapse(tokens(text).joined()) }

    // MARK: - Folding

    private static func fold(_ text: String) -> String {
        let scalars = westernDigits(text).unicodeScalars.compactMap(foldArabic)
        return String(String.UnicodeScalarView(scalars))
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// Drops Arabic vowel and Quranic marks and treats letter variants the way a keyboard user would type them.
    private static func foldArabic(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
        case 0x064B...0x065F, 0x0670, 0x06D6...0x06ED, 0x0640: nil
        case 0x0622, 0x0623, 0x0625, 0x0671: "\u{0627}"
        case 0x0629, 0x06C1, 0x06C3: "\u{0647}"
        case 0x0649, 0x06CC, 0x0626: "\u{064A}"
        case 0x0624: "\u{0648}"
        case 0x06A9: "\u{0643}"
        default: scalar
        }
    }

    /// Splits on anything that isn't a letter or digit, and between letters and digits ("juz5").
    /// Apostrophes and ayn/hamza marks join a word instead of splitting it (Shu'araa, ʿAbasa).
    private static func splitWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var currentIsDigit = false
        for character in text {
            if joiners.contains(character) { continue }
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if !current.isEmpty, character.isNumber != currentIsDigit {
                words.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = character.isNumber
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static let joiners: Set<Character> = ["'", "’", "‘", "`", "ʿ", "ʾ", "ʻ", "ʼ"]

    // MARK: - Spelling

    /// Spelling rules for one Latin word. Arabic words pass through unchanged.
    private static func phonetic(_ word: String) -> String {
        guard word.contains(where: \.isASCII), !word.allSatisfy(\.isNumber) else { return word }
        var key = word
        for (spelling, replacement) in spellings {
            key = key.replacingOccurrences(of: spelling, with: replacement)
        }
        key = collapse(key)
        if key.count > 2, key.hasSuffix("h"), let beforeLast = key.dropLast().last, vowels.contains(beforeLast) {
            key.removeLast()
        }
        return key
    }

    /// Applied in order: Qadr/Kadr, Dhuha/Duha, Yaseen/Yasin, Noor/Nur, Tawbah/Taubah, Layl/Lail.
    private static let spellings: KeyValuePairs<String, String> = [
        "q": "k",
        "dh": "d",
        "e": "i",
        "o": "u",
        "aw": "au",
        "ay": "ai"
    ]

    private static let vowels: Set<Character> = ["a", "i", "u"]

    /// Collapses repeated letters, so long vowels and doubled consonants (Muzzammil/Muzammil) agree.
    private static func collapse(_ text: String) -> String {
        var result = ""
        for character in text where character != result.last || character.isNumber {
            result.append(character)
        }
        return result
    }

    private static func join(_ words: [String]) -> String { collapse(words.joined()) }

    private static func withoutArticle(_ words: [String]) -> [String]? {
        guard let first = words.first else { return nil }
        if words.count > 1, articles.contains(first) { return Array(words.dropFirst()) }
        let bare = Word.withoutArabicArticle(first)
        return bare == first ? nil : [bare] + words.dropFirst()
    }

    private enum Word {
        static let arabicArticle = "ال"
        /// "الفاتحه" → "فاتحه". Very short words are left alone, since the letters may be the word itself.
        static func withoutArabicArticle(_ word: String) -> String {
            guard word.hasPrefix(arabicArticle), word.count > arabicArticle.count + 1 else { return word }
            return String(word.dropFirst(arabicArticle.count))
        }
    }

    /// Latin articles, already spelled as keys. They only count as a separate first word.
    private static let articles: Set<String> = Set(
        ["al", "el", "an", "ash", "as", "ad", "adh", "at", "az", "ar", "ul", "ut", "us", "un", "ur", "ush", "ud", "uz"].map(phonetic)
    )

    /// Article prefixes typed without a separator ("alshams"), tried only for exact matches.
    static let gluedArticles: [String] = ["al", "il", "ul", "an", "ar", "as", "ash", "at", "ad", "az"]

    private static let fillers: Set<String> = Set(
        ["surah", "surat", "sura", "suratul", "soorah", "chapter", "the", "سوره"].map(phonetic)
    )

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// How closely a query matched a name. Higher is better.
nonisolated enum MatchStrength: Int, Comparable, Sendable {
    case fuzzyPrefix
    case fuzzy
    case contains
    case wordPrefix
    case prefix
    case exact

    static func < (lhs: MatchStrength, rhs: MatchStrength) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A query prepared once and matched against every name index.
nonisolated struct SearchQuery: Sendable {
    /// Lowercased, trimmed, with Western digits, for reference patterns like "2:255".
    let text: String
    /// Folded words, for spotting a leading keyword like "juz" or "page".
    let words: [String]
    /// Keys that may match at any strength.
    let keys: [String]
    /// Keys guessed by removing a glued article ("alshams"), trusted only for exact matches.
    let exactOnlyKeys: [String]

    init(_ raw: String) {
        text = SearchKey.westernDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        words = SearchKey.tokens(text)
        keys = SearchKey.keys(text)
        let full = keys.first ?? ""
        exactOnlyKeys = SearchKey.gluedArticles.compactMap { article in
            guard full.hasPrefix(article), full.count - article.count >= 3 else { return nil }
            return String(full.dropFirst(article.count))
        }
    }

    var isEmpty: Bool { keys.isEmpty }
}

/// Names for a set of items (surahs, juz, well-known verses), with keys worked out once.
nonisolated struct NameIndex<ID: Hashable & Comparable & Sendable>: Sendable {
    nonisolated struct Item: Sendable {
        var id: ID
        var names: [String]
        /// English meanings ("The Cow"). They match like names but rank below a name matched as well.
        var translations: [String] = []
    }

    nonisolated struct Match: Sendable {
        let id: ID
        let strength: MatchStrength
        fileprivate let byName: Bool
    }

    private struct Keys: Sendable {
        var keys: [String]
        var wordKeys: [String]

        init(_ texts: [String]) {
            keys = Array(Set(texts.flatMap(SearchKey.keys)))
            wordKeys = Array(Set(texts.flatMap(SearchKey.wordKeys)))
        }
    }

    private struct Entry: Sendable {
        var id: ID
        var names: Keys
        var translations: Keys
    }

    private let entries: [Entry]

    init(_ items: [Item]) {
        entries = items.map { Entry(id: $0.id, names: Keys($0.names), translations: Keys($0.translations)) }
    }

    /// Every item the query matches: strongest first, a name before a translation, then in ID order.
    func matches(_ query: SearchQuery) -> [Match] {
        guard !query.isEmpty else { return [] }
        return entries.compactMap { match(query, $0) }.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            if lhs.byName != rhs.byName { return lhs.byName }
            return lhs.id < rhs.id
        }
    }

    private func match(_ query: SearchQuery, _ entry: Entry) -> Match? {
        let byName = strength(of: query, against: entry.names)
        let byTranslation = strength(of: query, against: entry.translations)
        if let byName, byName >= byTranslation ?? byName {
            return Match(id: entry.id, strength: byName, byName: true)
        }
        return byTranslation.map { Match(id: entry.id, strength: $0, byName: false) }
    }

    private func strength(of query: SearchQuery, against keys: Keys) -> MatchStrength? {
        if query.exactOnlyKeys.contains(where: keys.keys.contains) { return .exact }
        return query.keys.compactMap { strength(of: $0, against: keys) }.max()
    }

    private func strength(of query: String, against keys: Keys) -> MatchStrength? {
        if keys.keys.contains(query) { return .exact }
        if keys.keys.contains(where: { $0.hasPrefix(query) }) { return .prefix }
        if query.count >= 2, keys.wordKeys.contains(where: { $0.hasPrefix(query) }) { return .wordPrefix }
        if query.count >= 3, keys.keys.contains(where: { $0.contains(query) }) { return .contains }
        return fuzzyStrength(of: query, against: keys.keys + keys.wordKeys)
    }

    /// Allows one typo in a short name and two in a long one (Baqra, Kahaf, Rehman).
    private func fuzzyStrength(of query: String, against keys: [String]) -> MatchStrength? {
        guard let allowed = Self.allowedEdits(query), !query.contains(where: \.isNumber) else { return nil }
        let typed = Array(query)
        if keys.contains(where: { EditDistance.between(typed, Array($0), atMost: allowed) }) { return .fuzzy }
        guard typed.count >= 5 else { return nil }
        let isPrefixTypo = keys.contains { key in
            key.count > typed.count && EditDistance.between(typed, Array(key.prefix(typed.count)), atMost: allowed)
        }
        return isPrefixTypo ? .fuzzyPrefix : nil
    }

    /// Arabic is written without short vowels, so its words are shorter and one edit goes further.
    private static func allowedEdits(_ query: String) -> Int? {
        let isLatin = query.allSatisfy(\.isASCII)
        switch query.count {
        case ..<4: return nil
        case 4...6: return isLatin ? 1 : nil
        default: return isLatin ? 2 : 1
        }
    }
}

nonisolated enum EditDistance {
    /// Whether two strings are within `limit` insertions, deletions, substitutions or adjacent swaps.
    static func between(_ a: [Character], _ b: [Character], atMost limit: Int) -> Bool {
        guard abs(a.count - b.count) <= limit else { return false }
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) <= limit }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            if current.min() ?? 0 > limit { return false }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count] <= limit
    }
}
