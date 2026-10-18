import Foundation

/// How often the user means to go over everything they've memorized.
nonisolated enum RevisionCycle: Int, CaseIterable, Identifiable, Sendable {
    case oneWeek = 1
    case twoWeeks = 2
    case fourWeeks = 4

    static let `default` = RevisionCycle.twoWeeks
    /// Past this many cycles without a revision, fading becomes needing revision.
    static let fadingCycles = 3

    var id: Int { rawValue }
    var days: Int { rawValue * 7 }

    var title: String {
        switch self {
        case .oneWeek: String(localized: "Every week")
        case .twoWeeks: String(localized: "Every 2 weeks")
        case .fourWeeks: String(localized: "Every 4 weeks")
        }
    }
}

/// How recently a memorized ayah was revised. It only colors progress; it never changes
/// what counts as memorized.
nonisolated enum Freshness: Int, Comparable, CaseIterable, Sendable {
    case fresh
    case fading
    case needsRevision

    static func < (lhs: Freshness, rhs: Freshness) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .fresh: String(localized: "Fresh")
        case .fading: String(localized: "Fading")
        case .needsRevision: String(localized: "Needs revision")
        }
    }

    /// "Memorized", with how fresh it is once it's no longer fresh.
    var memorizedLabel: String {
        self == .fresh ? MemorizationStatus.memorized.title : String(localized: "Memorized · \(title)")
    }

    static func make(lastTouchedAt: Date?, isWeak: Bool, cycle: RevisionCycle, now: Date, calendar: Calendar = .current) -> Freshness {
        guard !isWeak, let lastTouchedAt else { return .needsRevision }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastTouchedAt), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= cycle.days { return .fresh }
        if days <= cycle.days * RevisionCycle.fadingCycles { return .fading }
        return .needsRevision
    }
}

extension VerseProgressSnapshot {
    /// The last time this ayah was heard, recited, or revised. Practice sessions from before
    /// these were recorded count too.
    nonisolated var lastTouchedAt: Date? {
        [lastHeardAt, lastRecitedAt, lastRevisedAt, lastPractisedAt].compactMap { $0 }.max()
    }

    /// Nil unless the ayah is memorized.
    nonisolated func freshness(cycle: RevisionCycle, now: Date) -> Freshness? {
        guard status == .memorized else { return nil }
        return Freshness.make(lastTouchedAt: lastTouchedAt, isWeak: isWeak, cycle: cycle, now: now)
    }
}

/// When a range was last heard, recited, or revised, across its ayahs.
nonisolated struct RevisionHistory: Equatable, Sendable {
    var lastHeardAt: Date?
    var lastRecitedAt: Date?
    var lastRevisedAt: Date?

    var isEmpty: Bool { lastHeardAt == nil && lastRecitedAt == nil && lastRevisedAt == nil }
}

extension ProgressIndex {
    /// The least fresh memorized ayah in the range, since revision is about the weakest spot.
    /// Nil when nothing in the range is memorized.
    nonisolated func freshness(of range: VerseRange, cycle: RevisionCycle, now: Date = .now) -> Freshness? {
        var worst: Freshness?
        for ayah in range.startGlobalAyah...range.endGlobalAyah {
            guard let freshness = snapshot(for: ayah)?.freshness(cycle: cycle, now: now) else { continue }
            if freshness == .needsRevision { return freshness }
            worst = max(worst ?? freshness, freshness)
        }
        return worst
    }

    /// Memorized ayahs in the range that need revision.
    nonisolated func needsRevisionCount(in range: VerseRange, cycle: RevisionCycle, now: Date = .now) -> Int {
        count(in: range) { $0.freshness(cycle: cycle, now: now) == .needsRevision }
    }

    /// The longest any memorized ayah in the range has gone without a revision: what makes it fade.
    nonisolated func oldestRevision(in range: VerseRange) -> Date? {
        (range.startGlobalAyah...range.endGlobalAyah)
            .compactMap { ayah in snapshot(for: ayah).flatMap { $0.status == .memorized ? $0.lastTouchedAt : nil } }
            .min()
    }

    /// The most recent of each kind of revision anywhere in the range.
    nonisolated func history(of range: VerseRange) -> RevisionHistory {
        var history = RevisionHistory()
        for ayah in range.startGlobalAyah...range.endGlobalAyah {
            guard let snapshot = snapshot(for: ayah) else { continue }
            history.lastHeardAt = [history.lastHeardAt, snapshot.lastHeardAt].compactMap { $0 }.max()
            history.lastRecitedAt = [history.lastRecitedAt, snapshot.lastRecitedAt].compactMap { $0 }.max()
            history.lastRevisedAt = [history.lastRevisedAt, snapshot.lastRevisedAt].compactMap { $0 }.max()
        }
        return history
    }
}

/// A surah with memorized ayahs that are fading or need revision.
nonisolated struct SurahRevision: Identifiable, Sendable {
    let surah: Surah
    let freshness: Freshness
    var id: Int { surah.number }
}

extension ProgressIndex {
    /// Surahs to revise, the ones needing revision first, then in mushaf order.
    nonisolated func surahsToRevise(_ surahs: [Surah], cycle: RevisionCycle, now: Date = .now) -> [SurahRevision] {
        surahs.compactMap { surah in
            guard let freshness = freshness(of: surah.range, cycle: cycle, now: now), freshness != .fresh else { return nil }
            return SurahRevision(surah: surah, freshness: freshness)
        }
        .sorted { $0.freshness != $1.freshness ? $0.freshness > $1.freshness : $0.surah.number < $1.surah.number }
    }
}
