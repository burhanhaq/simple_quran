import Foundation

nonisolated enum MasteryStrength: String, Equatable, Hashable, Sendable, CaseIterable {
    case needsWork
    case growing
    case strong

    var title: String {
        switch self {
        case .needsWork: String(localized: "Needs work")
        case .growing: String(localized: "Growing")
        case .strong: String(localized: "Strong")
        }
    }
}

extension VerseProgressSnapshot {
    nonisolated var masteryStrength: MasteryStrength? {
        if isWeak || recallState == .learning {
            return .needsWork
        }
        switch recallState {
        case .new:
            return nil
        case .learning:
            return .needsWork
        case .strengthening:
            return .growing
        case .review:
            return .strong
        }
    }
}

nonisolated struct InProgressSurah: Equatable, Sendable {
    var surah: Surah
    var knownCount: Int
    var strongCount: Int

    var ayahCount: Int { surah.ayahCount }
}

nonisolated struct ProgressInsights: Equatable, Sendable {
    static let juz30SurahRange = 78...114
    static var juz30SurahCount: Int { juz30SurahRange.count }
    static let weakAyahLimit = 10

    var knownCount: Int
    var needsWorkCount: Int
    var growingCount: Int
    var strongCount: Int
    var practicedCount: Int
    var practicedToday: Bool
    var currentStreak: Int
    var lastSevenDays: [Bool]
    var completedSurahs: [Surah]
    var closestInProgress: InProgressSurah?
    var juz30CompletedCount: Int
    var juz30HasProgress: Bool
    var surahsWithKnownAyahs: Int
    var weakAyahs: [VerseProgressSnapshot]

    func count(of strength: MasteryStrength) -> Int {
        switch strength {
        case .needsWork: needsWorkCount
        case .growing: growingCount
        case .strong: strongCount
        }
    }

    static func make(
        snapshots: [VerseProgressSnapshot],
        surahs: [Surah],
        now: Date,
        calendar: Calendar
    ) -> ProgressInsights {
        var needsWorkCount = 0
        var growingCount = 0
        var strongCount = 0
        var practicedCount = 0
        var strengthByAyah: [Int: MasteryStrength] = [:]
        strengthByAyah.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            if snapshot.lastPractisedAt != nil {
                practicedCount += 1
            }
            guard let strength = snapshot.masteryStrength else { continue }
            strengthByAyah[snapshot.globalAyah] = strength
            switch strength {
            case .needsWork: needsWorkCount += 1
            case .growing: growingCount += 1
            case .strong: strongCount += 1
            }
        }

        let knownCount = needsWorkCount + growingCount + strongCount
        let practicedDays = Set(
            snapshots.compactMap { snapshot in
                snapshot.lastPractisedAt.map { calendar.startOfDay(for: $0) }
            }
        )
        let today = calendar.startOfDay(for: now)
        let practicedToday = practicedDays.contains(today)
        let currentStreak = streak(endingOn: today, practicedDays: practicedDays, calendar: calendar)
        let lastSevenDays = (0..<7).map { index in
            let day = calendar.date(byAdding: .day, value: index - 6, to: today) ?? today
            return practicedDays.contains(day)
        }

        var completedSurahs: [Surah] = []
        var inProgress: [InProgressSurah] = []
        var surahsWithKnownAyahs = 0
        var juz30CompletedCount = 0
        var juz30HasProgress = false

        for surah in surahs {
            var known = 0
            var strong = 0
            for ayah in surah.startGlobalAyah...surah.endGlobalAyah {
                switch strengthByAyah[ayah] {
                case .strong:
                    strong += 1
                    known += 1
                case .growing, .needsWork:
                    known += 1
                case nil:
                    break
                }
            }

            guard known > 0 else { continue }
            surahsWithKnownAyahs += 1
            let isJuz30 = Self.juz30SurahRange.contains(surah.number)
            if isJuz30 {
                juz30HasProgress = true
            }

            if strong == surah.ayahCount, surah.ayahCount > 0 {
                completedSurahs.append(surah)
                if isJuz30 {
                    juz30CompletedCount += 1
                }
            } else {
                inProgress.append(
                    InProgressSurah(surah: surah, knownCount: known, strongCount: strong)
                )
            }
        }

        let closestInProgress = inProgress.max { lhs, rhs in
            let leftRatio = Self.ratio(lhs.strongCount, of: lhs.ayahCount)
            let rightRatio = Self.ratio(rhs.strongCount, of: rhs.ayahCount)
            if leftRatio != rightRatio {
                return leftRatio < rightRatio
            }
            if lhs.knownCount != rhs.knownCount {
                return lhs.knownCount < rhs.knownCount
            }
            return lhs.surah.number > rhs.surah.number
        }

        let weakAyahs = snapshots
            .filter { $0.masteryStrength == .needsWork }
            .sorted { ($0.lastPractisedAt ?? .distantPast) > ($1.lastPractisedAt ?? .distantPast) }
            .prefix(Self.weakAyahLimit)

        return ProgressInsights(
            knownCount: knownCount,
            needsWorkCount: needsWorkCount,
            growingCount: growingCount,
            strongCount: strongCount,
            practicedCount: practicedCount,
            practicedToday: practicedToday,
            currentStreak: currentStreak,
            lastSevenDays: lastSevenDays,
            completedSurahs: completedSurahs,
            closestInProgress: closestInProgress,
            juz30CompletedCount: juz30CompletedCount,
            juz30HasProgress: juz30HasProgress,
            surahsWithKnownAyahs: surahsWithKnownAyahs,
            weakAyahs: Array(weakAyahs)
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

    private static func streak(
        endingOn today: Date,
        practicedDays: Set<Date>,
        calendar: Calendar
    ) -> Int {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let endDay: Date
        if practicedDays.contains(today) {
            endDay = today
        } else if practicedDays.contains(yesterday) {
            endDay = yesterday
        } else {
            return 0
        }

        var count = 0
        var cursor = endDay
        while practicedDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func ratio(_ count: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }
}
