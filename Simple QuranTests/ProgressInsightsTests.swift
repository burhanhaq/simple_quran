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

    @Test func strengthMappingTable() {
        #expect(VerseProgressSnapshot.fresh(globalAyah: 1).masteryStrength == nil)

        var listenOnly = VerseProgressSnapshot.fresh(globalAyah: 2)
        listenOnly.lastPractisedAt = now
        #expect(listenOnly.masteryStrength == nil)

        var learning = VerseProgressSnapshot.fresh(globalAyah: 3)
        learning.recallState = .learning
        learning.lastRating = .again
        #expect(learning.masteryStrength == .needsWork)

        var markedWeak = VerseProgressSnapshot.fresh(globalAyah: 4)
        markedWeak.isWeak = true
        #expect(markedWeak.masteryStrength == .needsWork)

        var growing = VerseProgressSnapshot.fresh(globalAyah: 5)
        growing.recallState = .strengthening
        growing.lastRating = .comfortable
        #expect(growing.masteryStrength == .growing)

        var strong = VerseProgressSnapshot.fresh(globalAyah: 6)
        strong.recallState = .review
        strong.lastRating = .solid
        #expect(strong.masteryStrength == .strong)

        var weakReview = strong
        weakReview.globalAyah = 7
        weakReview.isWeak = true
        #expect(weakReview.masteryStrength == .needsWork)
    }

    @Test func listenOnlyDoesNotCountAsKnown() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var listenOnly = VerseProgressSnapshot.fresh(globalAyah: 1)
        listenOnly.lastPractisedAt = now

        let insights = ProgressInsights.make(
            snapshots: [listenOnly],
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(insights.practicedCount == 1)
        #expect(insights.knownCount == 0)
        #expect(insights.completedSurahs.isEmpty)
        #expect(insights.closestInProgress == nil)
    }

    @Test func completedSurahRequiresEveryAyahStrong() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihah = try #require(catalog.surah(number: 1))
        let almost = (fatihah.startGlobalAyah...fatihah.endGlobalAyah).map { ayah in
            strongAyah(ayah, practised: now, except: ayah == fatihah.endGlobalAyah)
        }

        let incomplete = ProgressInsights.make(
            snapshots: almost,
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(incomplete.completedSurahs.isEmpty)
        #expect(incomplete.closestInProgress?.surah.number == 1)
        #expect(incomplete.closestInProgress?.knownCount == 6)
        #expect(incomplete.closestInProgress?.strongCount == 6)

        let completeSnapshots = (fatihah.startGlobalAyah...fatihah.endGlobalAyah).map {
            strongAyah($0, practised: now)
        }
        let complete = ProgressInsights.make(
            snapshots: completeSnapshots,
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(complete.completedSurahs.map(\.number) == [1])
        #expect(complete.knownCount == 7)
        #expect(complete.closestInProgress == nil)
    }

    @Test func closestInProgressRanksByStrongRatioThenKnownCount() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatihah = try #require(catalog.surah(number: 1))
        let nas = try #require(catalog.surah(number: 114))

        var snapshots: [VerseProgressSnapshot] = []
        snapshots.append(contentsOf: (0..<3).map {
            strongAyah(fatihah.startGlobalAyah + $0, practised: now)
        })
        snapshots.append(contentsOf: (0..<2).map {
            strongAyah(nas.startGlobalAyah + $0, practised: now)
        })
        snapshots.append(contentsOf: (2..<5).map {
            growingAyah(nas.startGlobalAyah + $0, practised: now)
        })

        let insights = ProgressInsights.make(
            snapshots: snapshots,
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        let closest = try #require(insights.closestInProgress)
        #expect(closest.surah.number == 1)
        #expect(closest.strongCount == 3)
        #expect(closest.knownCount == 3)
        #expect(insights.juz30HasProgress)
        #expect(insights.juz30CompletedCount == 0)
        #expect(insights.surahsWithKnownAyahs == 2)
    }

    @Test func juz30CountUsesSurahs78To114() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(ProgressInsights.juz30SurahRange == 78...114)
        #expect(ProgressInsights.juz30SurahCount == 37)

        let nas = try #require(catalog.surah(number: 114))
        let naba = try #require(catalog.surah(number: 78))
        #expect(nas.ayahCount == 6)
        #expect(naba.number == 78)

        let snapshots = (nas.startGlobalAyah...nas.endGlobalAyah).map {
            strongAyah($0, practised: now)
        }
        let insights = ProgressInsights.make(
            snapshots: snapshots,
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(insights.completedSurahs.map(\.number) == [114])
        #expect(insights.juz30CompletedCount == 1)
        #expect(insights.juz30HasProgress)
    }

    @Test func streakCountsConsecutiveDaysAndBreaksAfterAGap() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: today))
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: today))

        let consecutive = ProgressInsights.make(
            snapshots: [
                practised(1, on: today),
                practised(2, on: yesterday),
                practised(3, on: twoDaysAgo)
            ],
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(consecutive.practicedToday)
        #expect(consecutive.currentStreak == 3)
        #expect(consecutive.lastSevenDays.count == 7)
        #expect(Array(consecutive.lastSevenDays.suffix(3)) == [true, true, true])

        let yesterdayOnly = ProgressInsights.make(
            snapshots: [practised(1, on: yesterday)],
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(yesterdayOnly.practicedToday == false)
        #expect(yesterdayOnly.currentStreak == 1)

        let broken = ProgressInsights.make(
            snapshots: [practised(1, on: twoDaysAgo)],
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(broken.currentStreak == 0)
        #expect(broken.practicedToday == false)

        let withGap = ProgressInsights.make(
            snapshots: [
                practised(1, on: today),
                practised(2, on: yesterday),
                practised(3, on: threeDaysAgo)
            ],
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(withGap.currentStreak == 2)
    }

    @Test func weakAyahsKeepTheNewestNeedsWorkAyahs() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let snapshots = (1...12).map { index -> VerseProgressSnapshot in
            var item = VerseProgressSnapshot.fresh(globalAyah: index)
            item.recallState = .learning
            item.lastPractisedAt = now.addingTimeInterval(TimeInterval(index))
            return item
        }
        let insights = ProgressInsights.make(
            snapshots: snapshots,
            surahs: catalog.surahs,
            now: now,
            calendar: calendar
        )
        #expect(insights.weakAyahs.count == 10)
        #expect(insights.weakAyahs.first?.globalAyah == 12)
        #expect(insights.weakAyahs.last?.globalAyah == 3)
        #expect(insights.needsWorkCount == 12)
    }

    @Test func dueCountOnlyIncludesDueAyahsInsideTheRange() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 7)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))

        var dueInside = VerseProgressSnapshot.fresh(globalAyah: 2)
        dueInside.recallState = .review
        dueInside.nextReviewAt = yesterday

        var notYet = VerseProgressSnapshot.fresh(globalAyah: 3)
        notYet.recallState = .review
        notYet.nextReviewAt = tomorrow

        var dueOutside = VerseProgressSnapshot.fresh(globalAyah: 20)
        dueOutside.recallState = .review
        dueOutside.nextReviewAt = yesterday

        let count = ProgressInsights.dueAyahCount(
            in: [range],
            snapshots: [dueInside, notYet, dueOutside],
            now: now
        )
        #expect(count == 1)
    }

    private func strongAyah(_ ayah: Int, practised: Date, except skipStrong: Bool = false) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.lastPractisedAt = practised
        if skipStrong {
            item.recallState = .new
            return item
        }
        item.recallState = .review
        item.lastRating = .solid
        return item
    }

    private func growingAyah(_ ayah: Int, practised: Date) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.recallState = .strengthening
        item.lastRating = .comfortable
        item.lastPractisedAt = practised
        return item
    }

    private func practised(_ ayah: Int, on day: Date) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.lastPractisedAt = day
        return item
    }
}
