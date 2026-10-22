import Foundation
import OSLog

nonisolated struct QuranIntegrityReport: Equatable, Sendable {
    var surahCount: Int
    var ayahCount: Int
    var pageCount: Int
    var juzCount: Int
    var sajdahCount: Int
    var uniqueGlobalIDs: Int
    var contiguousIDs: Bool
    var matchingSurahCounts: Bool
    var issues: [String]

    var isValid: Bool { issues.isEmpty }
}

nonisolated struct BundledQuranCatalog: QuranCatalog, Sendable {
    let surahs: [Surah]
    let verses: [QuranVerse]
    let juzs: [JuzSection]
    let pages: [PageSection]
    let pieces: QuranPieces
    let integrity: QuranIntegrityReport

    init(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    init(data: Data, strict: Bool = true) throws {
        let decoded: File
        do {
            decoded = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw AppError.corruptQuranData("Unable to decode bundled Quran text.")
        }

        var verses: [QuranVerse] = []
        verses.reserveCapacity(QuranCatalogMetrics.ayahCount)
        var surahs: [Surah] = []
        var globalCursor = 1

        for fileSurah in decoded.surahs {
            let start = globalCursor
            for ayah in fileSurah.ayahs {
                let verse = QuranVerse(
                    globalAyah: ayah.g,
                    surahNumber: fileSurah.number,
                    ayahInSurah: ayah.n,
                    text: ayah.t,
                    showsBasmalaBefore: Self.showsBasmala(surahNumber: fileSurah.number, ayahInSurah: ayah.n),
                    juz: ayah.j,
                    page: ayah.p,
                    sajdah: SajdahKind(rawValue: ayah.s ?? 0) ?? .none
                )
                verses.append(verse)
                globalCursor += 1
            }
            let end = globalCursor - 1
            surahs.append(
                Surah(
                    number: fileSurah.number,
                    arabicName: fileSurah.arabicName,
                    englishName: fileSurah.englishName,
                    translation: fileSurah.translation,
                    revelation: fileSurah.revelation,
                    ayahCount: fileSurah.ayahs.count,
                    startGlobalAyah: start,
                    endGlobalAyah: end,
                    aliases: SurahAliasTable.aliases(for: fileSurah.number, englishName: fileSurah.englishName)
                )
            )
        }

        self.verses = verses
        self.surahs = surahs
        self.juzs = Self.makeJuzs(from: verses)
        self.pages = Self.makePages(from: verses)
        self.pieces = QuranPieces(verses: verses)
        self.integrity = Self.validate(surahs: surahs, verses: verses, juzs: juzs, pages: pages)

        if strict, !integrity.isValid {
            throw AppError.corruptQuranData(integrity.issues.joined(separator: " "))
        }
    }

    /// The basmala is shown above every surah except Al-Fatiha, where it is the first ayah,
    /// and At-Tawbah, which has none. The King Fahd text never repeats it inside an ayah.
    private static func showsBasmala(surahNumber: Int, ayahInSurah: Int) -> Bool {
        ayahInSurah == 1 && !surahsWithoutBasmalaHeader.contains(surahNumber)
    }

    private static let surahsWithoutBasmalaHeader: Set<Int> = [1, 9]

    /// Al-Fatiha 1:1, the same spelling the bundled text uses.
    var basmala: String { verses.first?.text ?? "" }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> BundledQuranCatalog {
        let candidates = [
            bundle.url(forResource: BundledTextFile.name, withExtension: BundledTextFile.fileExtension, subdirectory: "Resources/Quran"),
            bundle.url(forResource: BundledTextFile.name, withExtension: BundledTextFile.fileExtension, subdirectory: "Quran"),
            bundle.url(forResource: BundledTextFile.name, withExtension: BundledTextFile.fileExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw AppError.missingQuranData
        }
        return try BundledQuranCatalog(from: url)
    }

    func verse(globalAyah: Int) -> QuranVerse? {
        guard globalAyah >= 1, globalAyah <= verses.count else { return nil }
        return verses[globalAyah - 1]
    }

    func surah(number: Int) -> Surah? {
        guard number >= 1, number <= surahs.count else { return nil }
        return surahs[number - 1]
    }

    func verses(in range: VerseRange) -> [QuranVerse] {
        range.globalAyahs.compactMap(verse(globalAyah:))
    }

    func piece(containing globalAyah: Int, size: PieceSize) -> VerseRange? {
        pieces.piece(containing: globalAyah, size: size)
    }

    func range(surah surahNumber: Int, startAyah: Int, endAyah: Int) throws -> VerseRange {
        guard let surah = surah(number: surahNumber) else { throw AppError.invalidRange }
        guard startAyah >= 1, endAyah <= surah.ayahCount, endAyah >= startAyah else {
            throw AppError.invalidRange
        }
        let start = surah.startGlobalAyah + startAyah - 1
        let end = surah.startGlobalAyah + endAyah - 1
        return try VerseRange(startGlobalAyah: start, endGlobalAyah: end)
    }

    func search(_ query: String) -> QuranSearchResult {
        QuranSearchIndex(catalog: self).search(query)
    }

    func versesForJuz(_ number: Int) throws -> VerseRange {
        guard let juz = juzs.first(where: { $0.number == number }) else { throw AppError.invalidRange }
        return try VerseRange(startGlobalAyah: juz.startGlobalAyah, endGlobalAyah: juz.endGlobalAyah)
    }

    func versesForPage(_ number: Int) throws -> VerseRange {
        guard let page = pages.first(where: { $0.number == number }) else { throw AppError.invalidRange }
        return try VerseRange(startGlobalAyah: page.startGlobalAyah, endGlobalAyah: page.endGlobalAyah)
    }

    private static func makeJuzs(from verses: [QuranVerse]) -> [JuzSection] {
        Dictionary(grouping: verses, by: \.juz)
            .map { JuzSection(number: $0.key, startGlobalAyah: $0.value.first?.globalAyah ?? 1, endGlobalAyah: $0.value.last?.globalAyah ?? 1) }
            .sorted { $0.number < $1.number }
    }

    private static func makePages(from verses: [QuranVerse]) -> [PageSection] {
        Dictionary(grouping: verses, by: \.page)
            .map { PageSection(number: $0.key, startGlobalAyah: $0.value.first?.globalAyah ?? 1, endGlobalAyah: $0.value.last?.globalAyah ?? 1) }
            .sorted { $0.number < $1.number }
    }

    static func validate(
        surahs: [Surah],
        verses: [QuranVerse],
        juzs: [JuzSection],
        pages: [PageSection]
    ) -> QuranIntegrityReport {
        var issues: [String] = []
        let ids = verses.map(\.globalAyah)
        let unique = Set(ids)
        let contiguous = ids == Array(1...QuranCatalogMetrics.ayahCount)
        let matchingCounts = surahs.map(\.ayahCount) == QuranCatalogMetrics.surahAyahCounts
        let sajdahs = verses.filter { $0.sajdah != .none }.count

        if surahs.count != QuranCatalogMetrics.surahCount {
            issues.append("Expected 114 surahs, found \(surahs.count).")
        }
        if verses.count != QuranCatalogMetrics.ayahCount {
            issues.append("Expected 6236 ayahs, found \(verses.count).")
        }
        if unique.count != verses.count {
            issues.append("Global ayah IDs are not unique.")
        }
        if !contiguous {
            issues.append("Global ayah IDs are not contiguous from 1 to 6236.")
        }
        if !matchingCounts {
            issues.append("Surah ayah counts do not match the canonical Hafs list.")
        }
        if pages.count != QuranCatalogMetrics.pageCount {
            issues.append("Expected 604 pages, found \(pages.count).")
        }
        if juzs.count != QuranCatalogMetrics.juzCount {
            issues.append("Expected 30 juz, found \(juzs.count).")
        }
        if sajdahs != QuranCatalogMetrics.sajdahCount {
            issues.append("Expected 15 sajdah markers, found \(sajdahs).")
        }
        if let first = verses.first, first.surahNumber != 1 || first.ayahInSurah != 1 {
            issues.append("The first ayah must be 1:1.")
        }
        if let last = verses.last, last.surahNumber != 114 || last.ayahInSurah != 6 {
            issues.append("The last ayah must be 114:6.")
        }
        if verses.contains(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("One or more ayahs have empty text.")
        }
        if surahs.contains(where: { $0.number == 9 && $0.ayahCount != 129 }) {
            issues.append("At-Tawbah must contain 129 ayahs and no counted basmala.")
        }

        return QuranIntegrityReport(
            surahCount: surahs.count,
            ayahCount: verses.count,
            pageCount: pages.count,
            juzCount: juzs.count,
            sajdahCount: sajdahs,
            uniqueGlobalIDs: unique.count,
            contiguousIDs: contiguous,
            matchingSurahCounts: matchingCounts,
            issues: issues
        )
    }
}

/// Built by Scripts/BuildQuranText.swift. Pairs with the font in `QuranScript`.
nonisolated private enum BundledTextFile {
    static let name = "quran-hafs"
    static let fileExtension = "json"
}

nonisolated private struct File: Decodable, Sendable {
    var surahs: [FileSurah]
}

nonisolated private struct FileSurah: Decodable, Sendable {
    var number: Int
    var arabicName: String
    var englishName: String
    var translation: String
    var revelation: String
    var ayahs: [FileAyah]
}

nonisolated private struct FileAyah: Decodable, Sendable {
    var g: Int
    var n: Int
    var t: String
    var j: Int
    var p: Int
    var s: Int?
}

nonisolated enum QuranLog {
    static let catalog = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "quran")
    static let translation = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "translation")
    /// Intervals for Instruments' os_signpost track, to see what opening a long surah costs.
    static let rendering = OSSignposter(subsystem: "com.simpleAzaan.Simple-Quran1", category: "rendering")
}
