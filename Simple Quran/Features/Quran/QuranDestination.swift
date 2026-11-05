import Foundation

/// Which way the reader moves from what's on screen, in mushaf order.
nonisolated enum ReaderNeighbor: CaseIterable, Hashable, Sendable {
    case next
    case previous

    var step: Int { self == .next ? 1 : -1 }
}

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
        case .juz: String(localized: "Practice this juz")
        case .page: String(localized: "Practice this page")
        }
    }

    /// The surah, juz, or page beside this one. Nil past Al-Fatiha and An-Nas, the first and
    /// last juz, and the first and last page. A surah opens at its start, not at an ayah.
    func neighbor(_ side: ReaderNeighbor, in catalog: BundledQuranCatalog) -> QuranDestination? {
        switch self {
        case .surah(let number, _):
            let neighbor = number + side.step
            return catalog.surah(number: neighbor) == nil ? nil : .surah(number: neighbor)
        case .juz(let number):
            let neighbor = number + side.step
            return catalog.juzs.contains { $0.number == neighbor } ? .juz(neighbor) : nil
        case .page(let number):
            let neighbor = number + side.step
            return catalog.pages.contains { $0.number == neighbor } ? .page(neighbor) : nil
        }
    }

    /// Where the reader belongs after paging to a mushaf page, keeping to the same kind: nil while
    /// the page still shows some of this surah or juz (or is this page). Otherwise, going forward,
    /// the first surah on the page, and going back, the last, opened at its first ayah there.
    /// - Parameter ayahs: the page's ayahs in order, including one running on from the page before.
    func settling(
        onPage page: Int,
        holding ayahs: [Int],
        toward side: ReaderNeighbor,
        in catalog: BundledQuranCatalog
    ) -> QuranDestination? {
        if case .page(let number) = self { return number == page ? nil : .page(page) }
        if let range = range(in: catalog), ayahs.contains(where: range.contains) { return nil }
        guard let anchor = side == .next ? ayahs.first : ayahs.last,
              let verse = catalog.verse(globalAyah: anchor)
        else { return nil }
        switch self {
        case .surah:
            let opening = ayahs.first { catalog.verse(globalAyah: $0)?.surahNumber == verse.surahNumber } ?? anchor
            return .surah(number: verse.surahNumber, scrollToAyah: opening)
        case .juz:
            return .juz(verse.juz)
        case .page:
            return .page(page)
        }
    }

    /// The surah's name in Arabic, shown beside its English name.
    func arabicName(in catalog: BundledQuranCatalog) -> String? {
        guard case .surah(let number, _) = self else { return nil }
        return catalog.surah(number: number)?.arabicName
    }

    func neighborCaption(_ side: ReaderNeighbor) -> String {
        switch (self, side) {
        case (.surah, .next): String(localized: "Next surah")
        case (.surah, .previous): String(localized: "Previous surah")
        case (.juz, .next): String(localized: "Next juz")
        case (.juz, .previous): String(localized: "Previous juz")
        case (.page, .next): String(localized: "Next page")
        case (.page, .previous): String(localized: "Previous page")
        }
    }
}
