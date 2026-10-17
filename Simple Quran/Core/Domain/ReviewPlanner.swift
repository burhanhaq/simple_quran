import Foundation

/// Turns due ayahs into short review passages: consecutive ayahs in the same surah
/// are grouped, ayahs needing a refresh come first, then the longest-waiting.
nonisolated enum ReviewPlanner {
    static let maxPassageLength = 5

    static func duePassages(snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog, now: Date = .now) -> [VerseRange] {
        let due = snapshots.filter { $0.isDue(at: now) }
        guard !due.isEmpty else { return [] }
        let byAyah = Dictionary(due.map { ($0.globalAyah, $0) }, uniquingKeysWith: { first, _ in first })

        var groups: [[VerseProgressSnapshot]] = []
        for ayah in byAyah.keys.sorted() {
            let snapshot = byAyah[ayah]!
            if let last = groups.last?.last, last.globalAyah == ayah - 1, groups[groups.count - 1].count < maxPassageLength,
               catalog.verse(globalAyah: ayah)?.surahNumber == catalog.verse(globalAyah: last.globalAyah)?.surahNumber {
                groups[groups.count - 1].append(snapshot)
            } else {
                groups.append([snapshot])
            }
        }

        return groups.sorted { lhs, rhs in
            let leftRefresh = lhs.contains(where: \.needsRefresh)
            let rightRefresh = rhs.contains(where: \.needsRefresh)
            if leftRefresh != rightRefresh { return leftRefresh }
            let leftDue = lhs.compactMap(\.nextReviewAt).min() ?? .distantPast
            let rightDue = rhs.compactMap(\.nextReviewAt).min() ?? .distantPast
            if leftDue != rightDue { return leftDue < rightDue }
            return lhs[0].globalAyah < rhs[0].globalAyah
        }.map { .clamped(start: $0[0].globalAyah, end: $0[$0.count - 1].globalAyah) }
    }
}
