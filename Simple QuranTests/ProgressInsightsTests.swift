import Foundation
import Testing
@testable import Simple_Quran

struct ProgressInsightsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func listenOnlyIsActivityNotMemorization() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var listenOnly = VerseProgressSnapshot.fresh(globalAyah: 1)
        listenOnly.lastPractisedAt = now
        listenOnly.exposureCount = 4

        let insights = ProgressInsights.make(snapshots: [listenOnly], surahs: catalog.surahs, now: now, calendar: calendar)
        #expect(insights.practicedToday)
        #expect(insights.memorizedCount == 0)
        #expect(insights.learningCount == 0)
        #expect(insights.completedSurahs.isEmpty)
        #expect(insights.closestInProgress == nil)
    }

    @Test func countsSplitByStatusAndNeedsRefresh() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var refresh = memorizedAyah(3)
        refresh.isWeak = true
        let snapshots = [memorizedAyah(1), memorizedAyah(2), refresh, learningAyah(4), learningAyah(5, state: .strengthening)]

        let insights = ProgressInsights.make(snapshots: snapshots, surahs: catalog.surahs, now: now, calendar: calendar)
        #expect(insights.memorizedCount == 3)
        #expect(insights.learningCount == 2)
        #expect(insights.needsRefreshCount == 1)
    }

    @Test func completedSurahRequiresEveryAyahMemorized() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihah = try #require(catalog.surah(number: 1))
        let almost = fatihah.range.globalAyahs.map { ayah in
            ayah == fatihah.endGlobalAyah ? learningAyah(ayah) : memorizedAyah(ayah)
        }

        let incomplete = ProgressInsights.make(snapshots: almost, surahs: catalog.surahs, now: now, calendar: calendar)
        #expect(incomplete.completedSurahs.isEmpty)
        #expect(incomplete.closestInProgress?.surah.number == 1)
        #expect(incomplete.closestInProgress?.memorizedCount == 6)
        #expect(incomplete.closestInProgress?.learningCount == 1)

        let complete = ProgressInsights.make(snapshots: fatihah.range.globalAyahs.map(memorizedAyah), surahs: catalog.surahs, now: now, calendar: calendar)
        #expect(complete.completedSurahs.map(\.number) == [1])
        #expect(complete.memorizedCount == 7)
        #expect(complete.closestInProgress == nil)
    }

    @Test func closestInProgressRanksByMemorizedRatioThenStartedCount() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihah = try #require(catalog.surah(number: 1))
        let nas = try #require(catalog.surah(number: 114))
        var snapshots = (0..<3).map { memorizedAyah(fatihah.startGlobalAyah + $0) }
        snapshots += (0..<2).map { memorizedAyah(nas.startGlobalAyah + $0) }
        snapshots += (2..<5).map { learningAyah(nas.startGlobalAyah + $0) }

        let insights = ProgressInsights.make(snapshots: snapshots, surahs: catalog.surahs, now: now, calendar: calendar)
        let closest = try #require(insights.closestInProgress)
        #expect(closest.surah.number == 1)
        #expect(closest.memorizedCount == 3)
        #expect(insights.juz30HasProgress)
        #expect(insights.juz30CompletedCount == 0)
    }

    @Test func juz30CountUsesSurahs78To114() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(ProgressInsights.juz30SurahRange == 78...114)
        #expect(ProgressInsights.juz30SurahCount == 37)

        let nas = try #require(catalog.surah(number: 114))
        let insights = ProgressInsights.make(snapshots: nas.range.globalAyahs.map(memorizedAyah), surahs: catalog.surahs, now: now, calendar: calendar)
        #expect(insights.completedSurahs.map(\.number) == [114])
        #expect(insights.juz30CompletedCount == 1)
    }

    @Test func lastSevenDaysCombineAyahAndSessionActivity() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: today))
        let lastWeek = try #require(calendar.date(byAdding: .day, value: -9, to: today))

        let insights = ProgressInsights.make(
            snapshots: [practised(1, on: yesterday)],
            activityDates: [threeDaysAgo, lastWeek],
            surahs: catalog.surahs, now: now, calendar: calendar
        )
        #expect(insights.practicedToday == false)
        #expect(insights.lastSevenDays == [false, false, false, true, false, true, false])
        #expect(insights.daysPracticedThisWeek == 2)
    }

    @Test func dueCountOnlyIncludesDueAyahsInsideTheRange() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 7)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))

        var dueInside = memorizedAyah(2)
        dueInside.nextReviewAt = yesterday
        var notYet = memorizedAyah(3)
        notYet.nextReviewAt = tomorrow
        var dueOutside = memorizedAyah(20)
        dueOutside.nextReviewAt = yesterday

        let count = ProgressInsights.dueAyahCount(in: [range], snapshots: [dueInside, notYet, dueOutside], now: now)
        #expect(count == 1)
    }

    private func memorizedAyah(_ ayah: Int) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.recallState = .review
        item.lastRating = .solid
        item.lastPractisedAt = now
        return item
    }

    private func learningAyah(_ ayah: Int, state: RecallState = .learning) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.recallState = state
        item.lastPractisedAt = now
        return item
    }

    private func practised(_ ayah: Int, on day: Date) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.lastPractisedAt = day
        return item
    }
}
