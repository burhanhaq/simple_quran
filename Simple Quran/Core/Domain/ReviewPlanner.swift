import Foundation

/// Turns memorized ayahs into short passages to revise: consecutive ayahs in the same surah
/// are grouped, ayahs flagged as forgotten come first, then the longest-waiting.
nonisolated enum ReviewPlanner {
    static let maxPassageLength = 5

    static func duePassages(snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog, now: Date = .now) -> [VerseRange] {
        let groups = group(snapshots.filter { $0.isDue(at: now) }, catalog: catalog)
        return groups.sorted { lhs, rhs in
            let leftFlagged = lhs.contains(where: \.isFlaggedForRevision)
            let rightFlagged = rhs.contains(where: \.isFlaggedForRevision)
            if leftFlagged != rightFlagged { return leftFlagged }
            let leftDue = lhs.compactMap(\.nextReviewAt).min() ?? .distantPast
            let rightDue = rhs.compactMap(\.nextReviewAt).min() ?? .distantPast
            if leftDue != rightDue { return leftDue < rightDue }
            return lhs[0].globalAyah < rhs[0].globalAyah
        }.map(passageRange)
    }

    /// Every memorized ayah inside `range`, in reading order, so revising never asks about unmemorized ayahs.
    static func memorizedPassages(in range: VerseRange, snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog) -> [VerseRange] {
        group(snapshots.filter { range.contains($0.globalAyah) && $0.status == .memorized }, catalog: catalog).map(passageRange)
    }

    private static func group(_ snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog) -> [[VerseProgressSnapshot]] {
        let byAyah = Dictionary(snapshots.map { ($0.globalAyah, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [[VerseProgressSnapshot]] = []
        for ayah in byAyah.keys.sorted() {
            guard let snapshot = byAyah[ayah] else { continue }
            if let last = groups.last?.last, last.globalAyah == ayah - 1, groups[groups.count - 1].count < maxPassageLength,
               catalog.verse(globalAyah: ayah)?.surahNumber == catalog.verse(globalAyah: last.globalAyah)?.surahNumber {
                groups[groups.count - 1].append(snapshot)
            } else {
                groups.append([snapshot])
            }
        }
        return groups
    }

    private static func passageRange(_ group: [VerseProgressSnapshot]) -> VerseRange {
        .clamped(start: group[0].globalAyah, end: group[group.count - 1].globalAyah)
    }
}

/// Everything to revise, as one list: pieces the scheduler brought back (just memorized, or
/// flagged as forgotten) need revision now; then surahs gone too long without a revision.
nonisolated struct RevisionList: Sendable {
    /// Due pieces, most urgent first.
    let pieces: [VerseRange]
    /// Surahs to revise that don't already have a due piece.
    let surahs: [SurahRevision]

    var count: Int { pieces.count + surahs.count }
    var isEmpty: Bool { count == 0 }

    init(snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog, cycle: RevisionCycle, now: Date = .now) {
        pieces = ReviewPlanner.duePassages(snapshots: snapshots, catalog: catalog, now: now)
        let duePieces = pieces
        surahs = ProgressIndex(snapshots).surahsToRevise(catalog.surahs, cycle: cycle, now: now)
            .filter { surah in !duePieces.contains { surah.surah.range.contains($0.startGlobalAyah) } }
    }
}
