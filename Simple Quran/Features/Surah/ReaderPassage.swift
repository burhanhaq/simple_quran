import Foundation

/// The reader's verses in reading order, with lookups the controls need on every render.
struct ReaderPassage {
    var verses: [QuranVerse] = []
    var ayahIDs: [Int] = []
    var indexByAyah: [Int: Int] = [:]

    init() {}

    init(ranges: [VerseRange], catalog: some QuranCatalog) {
        var seen = Set<Int>()
        verses = ranges.flatMap { catalog.verses(in: $0) }.filter { seen.insert($0.globalAyah).inserted }
        ayahIDs = verses.map(\.globalAyah)
        indexByAyah = Dictionary(uniqueKeysWithValues: ayahIDs.enumerated().map { ($1, $0) })
    }
}

/// Rebuilds the passage only when the ranges change. Holding it in a class keeps the
/// cache out of SwiftUI's state tracking, so filling it during a render is safe.
@MainActor
final class ReaderPassageCache {
    private var ranges: [VerseRange]?
    private var cached = ReaderPassage()

    func passage(for ranges: [VerseRange], catalog: some QuranCatalog) -> ReaderPassage {
        if ranges != self.ranges {
            cached = ReaderPassage(ranges: ranges, catalog: catalog)
            self.ranges = ranges
        }
        return cached
    }
}
