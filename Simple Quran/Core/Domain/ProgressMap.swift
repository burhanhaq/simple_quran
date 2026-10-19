import Foundation

/// Which end of the Quran the progress screen starts from. Most people begin memorizing with
/// An-Nas and work back toward Al-Fatiha, so that end comes first unless they choose otherwise.
nonisolated enum ProgressOrder: String, CaseIterable, Identifiable, Sendable {
    case fromAnNas
    case fromAlFatiha

    static let storageKey = "progress.order"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromAnNas: String(localized: "An-Nas")
        case .fromAlFatiha: String(localized: "Al-Fatiha")
        }
    }

    /// Items in mushaf order, arranged to start from this end.
    func arranged<Item>(_ items: [Item]) -> [Item] {
        self == .fromAnNas ? items.reversed() : items
    }
}

/// A surah as it appears in one juz: only the ayahs that juz holds, so its tile shows that part's progress.
nonisolated struct JuzSurah: Equatable, Sendable, Identifiable {
    var surah: Surah
    var range: VerseRange
    /// Whether the surah begins in this juz rather than continuing from an earlier one.
    var startsHere: Bool

    var id: Int { surah.number }
}

/// One line of the progress map: a juz with its surahs, or a run of juz not started yet folded into one line.
nonisolated enum ProgressMapRow: Equatable, Sendable, Identifiable {
    case juz(JuzSection)
    case unstarted(ClosedRange<Int>)

    var id: String {
        switch self {
        case .juz(let juz): "juz.\(juz.number)"
        case .unstarted(let numbers): "unstarted.\(numbers.lowerBound)"
        }
    }
}

nonisolated enum ProgressMap {
    /// The surahs a juz touches, each clipped to the ayahs inside it, in mushaf order.
    static func surahs(in juz: JuzSection, from surahs: [Surah]) -> [JuzSurah] {
        surahs.compactMap { surah in
            let start = max(surah.startGlobalAyah, juz.startGlobalAyah)
            let end = min(surah.endGlobalAyah, juz.endGlobalAyah)
            guard start <= end else { return nil }
            return JuzSurah(surah: surah, range: .clamped(start: start, end: end), startsHere: surah.startGlobalAyah >= juz.startGlobalAyah)
        }
    }

    /// Every juz in display order, with each run of juz not started yet folded into one line unless the user opened it.
    /// Nothing folds before anything is started, so a newcomer still sees the whole Quran.
    static func rows(_ juzs: [JuzSection], order: ProgressOrder, revealed: Set<Int>, isStarted: (JuzSection) -> Bool) -> [ProgressMapRow] {
        let started = Set(juzs.filter(isStarted).map(\.number))
        var rows: [ProgressMapRow] = []
        var run: [Int] = []
        func endRun() {
            if let first = run.min(), let last = run.max() { rows.append(.unstarted(first...last)) }
            run = []
        }
        for juz in order.arranged(juzs) {
            if !started.isEmpty, !started.contains(juz.number), !revealed.contains(juz.number) {
                run.append(juz.number)
            } else {
                endRun()
                rows.append(.juz(juz))
            }
        }
        endRun()
        return rows
    }
}
