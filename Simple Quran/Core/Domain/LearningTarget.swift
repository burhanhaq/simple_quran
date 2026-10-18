import Foundation

/// A plan (surah, juz, or ayah range) keeps its own place while sharing ayah progress with every other plan.
nonisolated struct LearningTarget: Codable, Identifiable, Equatable {
    var id = UUID()
    var range: VerseRange
    var juzNumber: Int? = nil
    var resumeRange: VerseRange? = nil

    func title(catalog: some QuranCatalog) -> String {
        if let juzNumber { return String(localized: "Juz \(juzNumber)") }
        return PassageLabel.passage(range, catalog: catalog)
    }

    func passage(from start: Int? = nil, catalog: some QuranCatalog, size: PieceSize = .default) -> VerseRange? {
        let start = start ?? resumeRange?.startGlobalAyah ?? range.startGlobalAyah
        guard range.contains(start) else { return nil }
        if let resumeRange, start == resumeRange.startGlobalAyah,
           range.contains(resumeRange.endGlobalAyah) { return resumeRange }
        return LearningPassage.piece(from: start, size: size, catalog: catalog)
            .map { .clamped(start: start, end: min($0.endGlobalAyah, range.endGlobalAyah)) }
    }

    /// The next passage in this plan that isn't fully memorized, starting where the user left off
    /// and wrapping to the beginning; nil once the whole plan is memorized.
    func nextPassage(catalog: some QuranCatalog, size: PieceSize = .default, isMemorized: (VerseRange) -> Bool) -> VerseRange? {
        let resume = resumeRange?.startGlobalAyah ?? range.startGlobalAyah
        func scan(from start: Int, through end: Int) -> VerseRange? {
            var cursor = start
            while cursor <= end, let candidate = passage(from: cursor, catalog: catalog, size: size) {
                if !isMemorized(candidate) { return candidate }
                cursor = candidate.endGlobalAyah + 1
            }
            return nil
        }
        return scan(from: resume, through: range.endGlobalAyah) ?? scan(from: range.startGlobalAyah, through: resume - 1)
    }
}
