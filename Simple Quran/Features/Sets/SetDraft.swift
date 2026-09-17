import Foundation
import Observation

@Observable
final class SetDraft {
    var existingID: UUID?
    var title: String = ""
    var hasCustomTitle = false
    var passages: [OrderedPassage] = []
    var settings: PracticeSettings = .default

    var ayahCount: Int {
        passages.map(\.range.count).reduce(0, +)
    }

    func append(_ range: VerseRange) {
        passages.append(OrderedPassage(order: passages.count, range: range))
    }

    func displayTitle(catalog: some QuranCatalog) -> String {
        if hasCustomTitle { return title }
        return generatedTitle(catalog: catalog)
    }

    func resolvedTitle(catalog: some QuranCatalog) -> String {
        if hasCustomTitle {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let generated = generatedTitle(catalog: catalog)
        return generated.isEmpty ? String(localized: "Untitled collection") : generated
    }

    func setTitle(_ value: String, catalog: some QuranCatalog) {
        let generated = generatedTitle(catalog: catalog)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || value == generated {
            hasCustomTitle = false
            title = ""
        } else {
            hasCustomTitle = true
            title = value
        }
    }

    func summary(catalog: some QuranCatalog) -> String {
        if passages.count == 1 {
            return resolvedTitle(catalog: catalog)
        }
        return String(localized: "\(passages.count) passages · \(ayahCount) ayahs")
    }

    private func generatedTitle(catalog: some QuranCatalog) -> String {
        PassageLabel.collection(
            passages.sorted { $0.order < $1.order }.map(\.range),
            catalog: catalog
        )
    }
}
