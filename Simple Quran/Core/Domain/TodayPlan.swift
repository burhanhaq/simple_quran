import Foundation

/// What the user finished today from the Memorize checklist. It starts over each day.
nonisolated struct DailyLog: Codable, Equatable, Sendable {
    var day: Date
    /// The last passage of what they're memorizing that they worked on today.
    var learned: VerseRange?
    var revised = false

    static func empty(on day: Date, calendar: Calendar = .current) -> DailyLog {
        DailyLog(day: calendar.startOfDay(for: day))
    }

    /// This log while it's still the same day, otherwise an empty one for today.
    func forToday(now: Date = .now, calendar: Calendar = .current) -> DailyLog {
        calendar.isDate(day, inSameDayAs: now) ? self : .empty(on: now, calendar: calendar)
    }
}

/// Today's checklist on the Memorize screen: at most one row to learn and one to revise.
nonisolated struct TodayPlan: Sendable {
    enum LearnRow: Equatable, Sendable {
        /// The next passage of what the user is memorizing.
        case next(passage: VerseRange, targetID: UUID, started: Bool)
        /// Already done today; `next` is there for anyone who wants to keep going.
        case done(learned: VerseRange, next: VerseRange?)
        /// What they were memorizing is all memorized, and the next one is waiting.
        case beginNext(LearningTarget, passage: VerseRange)
        /// Everything they set out to memorize is memorized.
        case finished(LearningTarget)
    }

    enum ReviseRow: Equatable, Sendable {
        /// The most urgent thing to revise, with how many more are waiting after it.
        /// `ayahs` names the part of the surah when it isn't the whole of what's memorized there.
        case due(surahName: String, ayahs: String?, passages: [VerseRange], freshness: Freshness, more: Int)
        /// Nothing left to revise, and the user revised today.
        case done
    }

    /// Nil when the user hasn't chosen anything to memorize yet.
    let learn: LearnRow?
    let revise: ReviseRow?

    var isAllDone: Bool {
        guard case .done = learn else { return false }
        if case .due = revise { return false }
        return true
    }

    init(targets: [LearningTarget], active: LearningTarget?, snapshots: [VerseProgressSnapshot], catalog: some QuranCatalog,
         size: PieceSize, cycle: RevisionCycle, log: DailyLog, now: Date = .now, calendar: Calendar = .current) {
        let index = ProgressIndex(snapshots)
        let isMemorized = { (range: VerseRange) in index.status(of: range) == .memorized }
        let log = log.forToday(now: now, calendar: calendar)

        if let active {
            let next = active.nextPassage(catalog: catalog, size: size, isMemorized: isMemorized)
            if let learned = log.learned {
                learn = .done(learned: learned, next: next)
            } else if let next {
                learn = .next(passage: next, targetID: active.id, started: index.status(of: active.range) != .notStarted)
            } else if let upcoming = Self.upNext(targets, after: active).lazy
                .compactMap({ target in target.nextPassage(catalog: catalog, size: size, isMemorized: isMemorized).map { (target, $0) } })
                .first {
                learn = .beginNext(upcoming.0, passage: upcoming.1)
            } else {
                learn = .finished(active)
            }
        } else {
            learn = nil
        }

        let toRevise = RevisionList(snapshots: snapshots, catalog: catalog, cycle: cycle, now: now)
        if let piece = toRevise.pieces.first {
            let surahName = catalog.verse(globalAyah: piece.startGlobalAyah).flatMap { catalog.surah(number: $0.surahNumber) }?.englishName ?? ""
            revise = .due(surahName: surahName, ayahs: LearningPassage.ayahLabel(piece, catalog: catalog), passages: toRevise.pieces,
                          freshness: .needsRevision, more: toRevise.count - 1)
        } else if let surah = toRevise.surahs.first {
            revise = .due(surahName: surah.surah.englishName, ayahs: nil,
                          passages: ReviewPlanner.memorizedPassages(in: surah.surah.range, snapshots: snapshots, catalog: catalog),
                          freshness: surah.freshness, more: toRevise.count - 1)
        } else {
            revise = log.revised ? .done : nil
        }
    }

    /// The other targets in the order they come up: the ones added after `active` first, then the rest.
    static func upNext(_ targets: [LearningTarget], after active: LearningTarget) -> [LearningTarget] {
        guard let position = targets.firstIndex(where: { $0.id == active.id }) else { return targets }
        return Array(targets[(position + 1)...] + targets[..<position])
    }
}
