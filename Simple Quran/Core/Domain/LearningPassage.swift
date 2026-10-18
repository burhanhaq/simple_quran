import Foundation

/// Memorize passages follow the mushaf page (see `QuranPieces`) and always end at an ayah boundary.
/// They are editable, not a fixed curriculum or a claim about thematic divisions.
nonisolated enum LearningPassage {
    /// The piece starting at `start`. Starting partway into a piece runs to its end, and when only
    /// a sliver of it is left the passage carries on through the next piece in the same surah.
    static func piece(from start: Int, size: PieceSize, catalog: some QuranCatalog) -> VerseRange? {
        guard let piece = catalog.piece(containing: start, size: size) else { return nil }
        let remaining = piece.endGlobalAyah - start + 1
        if start != piece.startGlobalAyah, remaining * 2 < piece.count,
           let first = catalog.verse(globalAyah: start),
           let next = catalog.piece(containing: piece.endGlobalAyah + 1, size: size),
           catalog.verse(globalAyah: next.startGlobalAyah)?.surahNumber == first.surahNumber {
            return .clamped(start: start, end: next.endGlobalAyah)
        }
        return .clamped(start: start, end: piece.endGlobalAyah)
    }

    static func ayahLabel(_ range: VerseRange, catalog: some QuranCatalog) -> String {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah) else { return "" }
        guard first.surahNumber == last.surahNumber else { return PassageLabel.passage(range, catalog: catalog) }
        return first.globalAyah == last.globalAyah
            ? String(localized: "Ayah \(first.ayahInSurah)")
            : String(localized: "Ayahs \(first.ayahInSurah)–\(last.ayahInSurah)")
    }

    static func referenceLabel(_ range: VerseRange, catalog: some QuranCatalog) -> String {
        guard let first = catalog.verse(globalAyah: range.startGlobalAyah),
              let last = catalog.verse(globalAyah: range.endGlobalAyah),
              let firstSurah = catalog.surah(number: first.surahNumber),
              let lastSurah = catalog.surah(number: last.surahNumber) else { return "" }
        if first.surahNumber == last.surahNumber {
            return "\(firstSurah.englishName) · \(ayahLabel(range, catalog: catalog))"
        }
        return "\(firstSurah.englishName) \(first.ayahInSurah) – \(lastSurah.englishName) \(last.ayahInSurah)"
    }
}
