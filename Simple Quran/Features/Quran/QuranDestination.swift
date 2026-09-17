import Foundation

nonisolated enum QuranDestination: Hashable, Sendable {
    case surah(number: Int, scrollToAyah: Int? = nil)
    case juz(Int)
    case page(Int)

    func title(in catalog: BundledQuranCatalog) -> String {
        switch self {
        case .surah(let number, _):
            catalog.surah(number: number)?.englishName ?? String(localized: "Surah \(number)")
        case .juz(let number):
            number == 30
                ? String(localized: "Juz \(number) · Amma")
                : String(localized: "Juz \(number)")
        case .page(let number):
            String(localized: "Page \(number)")
        }
    }

    func range(in catalog: BundledQuranCatalog) -> VerseRange? {
        switch self {
        case .surah(let number, _):
            guard let surah = catalog.surah(number: number) else { return nil }
            return try? VerseRange(startGlobalAyah: surah.startGlobalAyah, endGlobalAyah: surah.endGlobalAyah)
        case .juz(let number):
            return try? catalog.versesForJuz(number)
        case .page(let number):
            return try? catalog.versesForPage(number)
        }
    }

    var scrollToAyah: Int? {
        switch self {
        case .surah(_, let ayah): ayah
        case .juz, .page: nil
        }
    }

    var collectWholeTitle: String {
        switch self {
        case .surah: String(localized: "Practice this surah")
        case .juz: String(localized: "Collect this juz")
        case .page: String(localized: "Collect this page")
        }
    }
}
