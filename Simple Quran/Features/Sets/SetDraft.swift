import Foundation
import Observation

@Observable
final class SetDraft {
    var existingID: UUID?
    var title: String = ""
    var titleHint: String = ""
    var passages: [OrderedPassage] = []
    var settings: PracticeSettings = .default

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !titleHint.isEmpty { return titleHint }
        return String(localized: "Untitled collection")
    }

    var ayahCount: Int {
        passages.map(\.range.count).reduce(0, +)
    }

    func append(_ range: VerseRange, titleHint: String? = nil) {
        passages.append(OrderedPassage(order: passages.count, range: range))
        if self.titleHint.isEmpty {
            if let titleHint, !titleHint.isEmpty {
                self.titleHint = titleHint
            } else {
                self.titleHint = "\(range.startGlobalAyah)–\(range.endGlobalAyah)"
            }
        }
    }

    func summary(catalog: BundledQuranCatalog) -> String {
        if passages.count == 1, let range = passages.first?.range,
           let first = catalog.verse(globalAyah: range.startGlobalAyah),
           let last = catalog.verse(globalAyah: range.endGlobalAyah),
           let surah = catalog.surah(number: first.surahNumber) {
            if first.globalAyah == last.globalAyah {
                return "\(surah.englishName) \(first.ayahInSurah)"
            }
            if first.surahNumber == last.surahNumber {
                return "\(surah.englishName) \(first.ayahInSurah)–\(last.ayahInSurah)"
            }
        }
        return String(localized: "\(passages.count) passages · \(ayahCount) ayahs")
    }
}
