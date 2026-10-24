import Foundation
import Testing
@testable import Simple_Quran

struct TodayPlanTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar.current

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private func memorized(_ ayah: Int, touched: Date?) -> VerseProgressSnapshot {
        var snapshot = VerseProgressSnapshot.fresh(globalAyah: ayah)
        snapshot.recallState = .review
        snapshot.lastRevisedAt = touched
        return snapshot
    }

    private func memorized(_ range: VerseRange, touched: Date? = nil) -> [VerseProgressSnapshot] {
        range.globalAyahs.map { memorized($0, touched: touched ?? now) }
    }

    private func plan(_ targets: [LearningTarget], active: LearningTarget?, snapshots: [VerseProgressSnapshot] = [],
                      log: DailyLog? = nil, catalog: BundledQuranCatalog) -> TodayPlan {
        TodayPlan(targets: targets, active: active, snapshots: snapshots, catalog: catalog, size: .default, cycle: .twoWeeks,
                  log: log ?? .empty(on: now, calendar: calendar), now: now, calendar: calendar)
    }

    @Test func nothingChosenHasNoLearnRow() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let today = plan([], active: nil, catalog: catalog)
        #expect(today.learn == nil)
        #expect(today.revise == nil)
        #expect(!today.isAllDone)
    }

    @Test func learnRowIsTheNextPassageOfWhatTheUserIsMemorizing() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        let first = try #require(mulk.passage(catalog: catalog))
        #expect(plan([mulk], active: mulk, catalog: catalog).learn == .next(passage: first, targetID: mulk.id, started: false))

        let second = try #require(mulk.passage(from: first.endGlobalAyah + 1, catalog: catalog))
        let started = plan([mulk], active: mulk, snapshots: memorized(first), catalog: catalog)
        #expect(started.learn == .next(passage: second, targetID: mulk.id, started: true))
    }

    @Test func learningTodayTicksTheRowAndOffersTheNextPassage() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        let first = try #require(mulk.passage(catalog: catalog))
        let next = try #require(mulk.passage(from: first.endGlobalAyah + 1, catalog: catalog))
        let log = DailyLog(day: now, learned: first)

        let today = plan([mulk], active: mulk, snapshots: memorized(first), log: log, catalog: catalog)
        #expect(today.learn == .done(learned: first, next: next))
        #expect(today.revise == nil)
        #expect(today.isAllDone)
    }

    @Test func yesterdaysLogDoesNotCount() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        let first = try #require(mulk.passage(catalog: catalog))
        let yesterday = DailyLog(day: daysAgo(1), learned: first, revised: true)

        #expect(yesterday.forToday(now: now, calendar: calendar) == .empty(on: now, calendar: calendar))
        let today = plan([mulk], active: mulk, log: yesterday, catalog: catalog)
        #expect(today.learn == .next(passage: first, targetID: mulk.id, started: false))
        #expect(today.revise == nil)
    }

    @Test func finishingASurahMovesOnToWhatIsLinedUpNext() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatiha = LearningTarget(range: try #require(catalog.surah(number: 1)).range)
        let ikhlas = LearningTarget(range: try #require(catalog.surah(number: 112)).range)
        let nas = LearningTarget(range: try #require(catalog.surah(number: 114)).range)
        // Al-Ikhlas is also memorized, so it's skipped.
        let snapshots = memorized(fatiha.range) + memorized(ikhlas.range)

        let today = plan([fatiha, ikhlas, nas], active: fatiha, snapshots: snapshots, catalog: catalog)
        #expect(today.learn == .beginNext(nas, passage: try #require(nas.passage(catalog: catalog))))

        let nothingLeft = plan([fatiha, ikhlas], active: fatiha, snapshots: snapshots, catalog: catalog)
        #expect(nothingLeft.learn == .finished(fatiha))
    }

    @Test func upNextStartsAfterTheActiveTargetAndWraps() {
        let targets = (1...4).map { LearningTarget(range: .clamped(start: $0 * 10, end: $0 * 10 + 5)) }
        #expect(TodayPlan.upNext(targets, after: targets[2]).map(\.id) == [targets[3], targets[0], targets[1]].map(\.id))
        #expect(TodayPlan.upNext(targets, after: targets[0]).map(\.id) == targets.dropFirst().map(\.id))
    }

    @Test func reviseRowShowsTheMostUrgentThenTicksOnceRevised() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        var forgotten = memorized(1, touched: daysAgo(1))
        forgotten.nextReviewAt = now
        let snapshots = [forgotten, memorized(2, touched: daysAgo(1)), memorized(9, touched: daysAgo(20))]

        let due = plan([mulk], active: mulk, snapshots: snapshots, catalog: catalog)
        #expect(due.revise == .due(surahName: try #require(catalog.surah(number: 1)).englishName, ayahs: LearningPassage.ayahLabel(.clamped(start: 1, end: 1), catalog: catalog),
                                   passages: [.clamped(start: 1, end: 1)], freshness: .needsRevision, more: 1))

        let caughtUp = plan([mulk], active: mulk, snapshots: memorized(.clamped(start: 1, end: 7)),
                            log: DailyLog(day: now, revised: true), catalog: catalog)
        #expect(caughtUp.revise == .done)
        #expect(!caughtUp.isAllDone)
    }
}
