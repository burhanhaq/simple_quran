import Foundation

nonisolated struct VerseRange: Equatable, Hashable, Sendable, Codable {
    var startGlobalAyah: Int
    var endGlobalAyah: Int

    var count: Int { max(0, endGlobalAyah - startGlobalAyah + 1) }

    var globalAyahs: [Int] {
        Array(startGlobalAyah...endGlobalAyah)
    }

    func contains(_ globalAyah: Int) -> Bool {
        globalAyah >= startGlobalAyah && globalAyah <= endGlobalAyah
    }

    init(startGlobalAyah: Int, endGlobalAyah: Int) throws {
        guard startGlobalAyah >= 1,
              endGlobalAyah <= QuranCatalogMetrics.ayahCount,
              endGlobalAyah >= startGlobalAyah
        else {
            throw AppError.invalidRange
        }
        self.init(validatedStart: startGlobalAyah, end: endGlobalAyah)
    }

    static func clamped(start: Int, end: Int) -> VerseRange {
        let start = min(max(start, 1), QuranCatalogMetrics.ayahCount)
        let end = min(max(end, start), QuranCatalogMetrics.ayahCount)
        return VerseRange(validatedStart: start, end: end)
    }

    private init(validatedStart: Int, end: Int) {
        self.startGlobalAyah = validatedStart
        self.endGlobalAyah = end
    }
}

nonisolated struct OrderedPassage: Equatable, Hashable, Sendable, Codable, Identifiable {
    var id: UUID
    var order: Int
    var range: VerseRange

    init(id: UUID = UUID(), order: Int, range: VerseRange) {
        self.id = id
        self.order = order
        self.range = range
    }
}

nonisolated enum QuranCatalogMetrics {
    static let surahCount = 114
    static let ayahCount = 6236
    static let pageCount = 604
    static let juzCount = 30
    static let sajdahCount = 15

    static let surahAyahCounts: [Int] = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128,
        111, 110, 98, 135, 112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73,
        54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60,
        49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52,
        44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19,
        26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5, 4, 7, 3,
        6, 3, 5, 4, 5, 6
    ]
}
