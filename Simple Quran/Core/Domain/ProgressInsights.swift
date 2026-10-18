import Foundation

nonisolated struct InProgressSurah: Equatable, Sendable {
    var surah: Surah
    var memorizedCount: Int
    var learningCount: Int

    var ayahCount: Int { surah.ayahCount }
}

/// Memorization counts come only from explicit user claims; activity (days practiced)
/// is reported separately so the two never blur together.
nonisolated struct ProgressInsights: Equatable, Sendable {
    static let juz30SurahRange = 78...114
    static var juz30SurahCount: Int { juz30SurahRange.count }

    var memorizedCount: Int
    var learningCount: Int
    var needsRevisionCount: Int
    var practicedToday: Bool
    var lastSevenDays: [Bool]
    var completedSurahs: [Surah]
    var closestInProgress: InProgressSurah?
    var juz30CompletedCount: Int
    var juz30HasProgress: Bool

    var daysPracticedThisWeek: Int { lastSevenDays.filter { $0 }.count }

    static func make(
        snapshots: [VerseProgressSnapshot],
        activityDates: [Date] = [],
        surahs: [Surah],
        cycle: RevisionCycle = .default,
        now: Date,
        calendar: Calendar
    ) -> ProgressInsights {
        let index = ProgressIndex(snapshots)
        var memorizedCount = 0
        var learningCount = 0
        var needsRevisionCount = 0
        for snapshot in snapshots {
            switch snapshot.status {
            case .memorized: memorizedCount += 1
            case .learning: learningCount += 1
            case .notStarted: break
            }
            if snapshot.freshness(cycle: cycle, now: now) == .needsRevision { needsRevisionCount += 1 }
        }

        let practicedDays = Set((snapshots.compactMap(\.lastPractisedAt) + activityDates).map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        let lastSevenDays = (0..<7).map { offset in
            practicedDays.contains(calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today)
        }

        var completedSurahs: [Surah] = []
        var inProgress: [InProgressSurah] = []
        var juz30CompletedCount = 0
        var juz30HasProgress = false
        for surah in surahs {
            let memorized = index.count(.memorized, in: surah.range)
            let learning = index.count(.learning, in: surah.range)
            guard memorized + learning > 0 else { continue }
            let isJuz30 = juz30SurahRange.contains(surah.number)
            if isJuz30 { juz30HasProgress = true }
            if memorized == surah.ayahCount {
                completedSurahs.append(surah)
                if isJuz30 { juz30CompletedCount += 1 }
            } else {
                inProgress.append(InProgressSurah(surah: surah, memorizedCount: memorized, learningCount: learning))
            }
        }

        let closestInProgress = inProgress.max { lhs, rhs in
            let leftRatio = ratio(lhs.memorizedCount, of: lhs.ayahCount)
            let rightRatio = ratio(rhs.memorizedCount, of: rhs.ayahCount)
            if leftRatio != rightRatio { return leftRatio < rightRatio }
            let leftStarted = lhs.memorizedCount + lhs.learningCount
            let rightStarted = rhs.memorizedCount + rhs.learningCount
            if leftStarted != rightStarted { return leftStarted < rightStarted }
            return lhs.surah.number > rhs.surah.number
        }

        return ProgressInsights(
            memorizedCount: memorizedCount,
            learningCount: learningCount,
            needsRevisionCount: needsRevisionCount,
            practicedToday: practicedDays.contains(today),
            lastSevenDays: lastSevenDays,
            completedSurahs: completedSurahs,
            closestInProgress: closestInProgress,
            juz30CompletedCount: juz30CompletedCount,
            juz30HasProgress: juz30HasProgress
        )
    }

    static func dueAyahCount(
        in ranges: [VerseRange],
        snapshots: [VerseProgressSnapshot],
        now: Date
    ) -> Int {
        let ayahs = Set(ranges.flatMap(\.globalAyahs))
        return snapshots.filter { ayahs.contains($0.globalAyah) && $0.isDue(at: now) }.count
    }

    private static func ratio(_ count: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }
}
