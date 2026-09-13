import Foundation

nonisolated enum SajdahKind: Int, Sendable, Codable {
    case none = 0
    case recommended = 1
    case obligatory = 2
}

nonisolated struct QuranVerse: Equatable, Hashable, Sendable, Identifiable {
    var globalAyah: Int
    var surahNumber: Int
    var ayahInSurah: Int
    var text: String
    var showsBasmalaBefore: Bool = false
    var juz: Int
    var page: Int
    var sajdah: SajdahKind

    var id: Int { globalAyah }

    var reference: String { "\(surahNumber):\(ayahInSurah)" }
}

nonisolated struct Surah: Equatable, Hashable, Sendable, Identifiable {
    var number: Int
    var arabicName: String
    var englishName: String
    var translation: String
    var revelation: String
    var ayahCount: Int
    var startGlobalAyah: Int
    var endGlobalAyah: Int
    var aliases: [String]

    var id: Int { number }

    var displayName: String { "\(number). \(englishName)" }
}

nonisolated struct JuzSection: Equatable, Hashable, Sendable, Identifiable {
    var number: Int
    var startGlobalAyah: Int
    var endGlobalAyah: Int
    var id: Int { number }
}

nonisolated struct PageSection: Equatable, Hashable, Sendable, Identifiable {
    var number: Int
    var startGlobalAyah: Int
    var endGlobalAyah: Int
    var id: Int { number }
}

nonisolated protocol QuranCatalog: Sendable {
    var surahs: [Surah] { get }
    var verses: [QuranVerse] { get }
    var juzs: [JuzSection] { get }
    var pages: [PageSection] { get }

    func verse(globalAyah: Int) -> QuranVerse?
    func surah(number: Int) -> Surah?
    func verses(in range: VerseRange) -> [QuranVerse]
    func range(surah: Int, startAyah: Int, endAyah: Int) throws -> VerseRange
    func search(_ query: String) -> QuranSearchResult
}

nonisolated struct QuranSearchHit: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable {
        case surah(Int)
        case juz(Int)
        case page(Int)
        case verse(Int)
        case range(VerseRange)
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
}

nonisolated struct QuranSearchResult: Equatable, Sendable {
    var hits: [QuranSearchHit]
}
