import Foundation

/// A focus keeps its own practice passage while sharing ayah progress with other focuses.
nonisolated struct LearningTarget: Codable, Identifiable, Equatable {
    var id = UUID()
    var range: VerseRange
    var juzNumber: Int? = nil
    var resumeRange: VerseRange? = nil

    func title(catalog: some QuranCatalog) -> String {
        if let juzNumber { return String(localized: "Juz \(juzNumber)") }
        return PassageLabel.passage(range, catalog: catalog)
    }

    func passage(from start: Int? = nil, catalog: some QuranCatalog, byPage: Bool = false) -> VerseRange? {
        let start = start ?? resumeRange?.startGlobalAyah ?? range.startGlobalAyah
        guard range.contains(start) else { return nil }
        if let resumeRange, start == resumeRange.startGlobalAyah,
           range.contains(resumeRange.endGlobalAyah) { return resumeRange }
        let suggestion: VerseRange?
        if byPage, let verse = catalog.verse(globalAyah: start),
           let page = catalog.pages.first(where: { $0.number == verse.page }) {
            suggestion = .clamped(start: start, end: page.endGlobalAyah)
        } else { suggestion = LearningPassage.suggested(from: start, catalog: catalog) }
        return suggestion.map { .clamped(start: start, end: min($0.endGlobalAyah, range.endGlobalAyah)) }
    }
}
