import Foundation

/// The share of a passage that falls in one juz, so the progress map can show where each juz begins and ends.
nonisolated struct JuzSpan: Equatable, Sendable {
    var juz: Int
    /// The portion of the passage's ayahs in this juz, from 0 to 1.
    var fraction: Double
    /// Whether the juz begins inside the passage rather than before it.
    var startsHere: Bool

    /// The juz a passage touches, in order, sized by how many of its ayahs each one holds.
    static func spans(of range: VerseRange, in juzs: [JuzSection]) -> [JuzSpan] {
        juzs.compactMap { juz in
            let start = max(range.startGlobalAyah, juz.startGlobalAyah)
            let end = min(range.endGlobalAyah, juz.endGlobalAyah)
            guard start <= end else { return nil }
            return JuzSpan(
                juz: juz.number,
                fraction: Double(end - start + 1) / Double(max(range.count, 1)),
                startsHere: juz.startGlobalAyah >= range.startGlobalAyah
            )
        }
    }
}
