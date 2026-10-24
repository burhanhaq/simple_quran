import Foundation
import Testing
@testable import Simple_Quran

struct LearningTargetTests {
    @Test func juzPracticeCrossesSurahBoundariesAndStopsAtJuzEnd() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        for juz in catalog.juzs {
            let target = LearningTarget(range: .clamped(start: juz.startGlobalAyah, end: juz.endGlobalAyah), juzNumber: juz.number)
            var start = target.range.startGlobalAyah
            var covered: [Int] = []
            while let passage = target.passage(from: start, catalog: catalog) {
                #expect(passage.startGlobalAyah == start)
                #expect(passage.endGlobalAyah <= target.range.endGlobalAyah)
                covered += passage.globalAyahs
                start = passage.endGlobalAyah + 1
            }
            #expect(covered == target.range.globalAyahs)
        }
    }

    @Test func customFocusClipsSuggestionsAndPagesToItsBoundaries() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let target = LearningTarget(range: try catalog.range(surah: 2, startAyah: 4, endAyah: 6))
        for size in PieceSize.allCases {
            let passage = try #require(target.passage(catalog: catalog, size: size))
            #expect(passage.startGlobalAyah == target.range.startGlobalAyah)
            #expect(passage.endGlobalAyah <= target.range.endGlobalAyah)
            #expect(target.passage(from: target.range.endGlobalAyah + 1, catalog: catalog, size: size) == nil)
        }
    }

    @Test @MainActor func onePlanIsActiveAndOthersKeepTheirPlaces() throws {
        let suite = "PlanTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let first = LearningTarget(range: .clamped(start: 8, end: 293))
        let second = LearningTarget(range: .clamped(start: 1, end: 148), juzNumber: 1)
        settings.setActivePlan(first)
        settings.setActivePlan(second)
        settings.setActivePlan(LearningTarget(range: first.range))
        #expect(settings.learningTargets.count == 2)
        #expect(settings.activePlan?.id == first.id)

        let firstPlace = VerseRange.clamped(start: 25, end: 27)
        let secondPlace = VerseRange.clamped(start: 30, end: 35)
        settings.remember(firstPlace, targetID: first.id)
        settings.remember(secondPlace, targetID: second.id)
        settings.remember(.clamped(start: 4000, end: 4002), targetID: nil)
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.learningTargets[0].resumeRange == firstPlace)
        #expect(reopened.learningTargets[1].resumeRange == secondPlace)
        #expect(reopened.activePlan?.id == first.id)

        reopened.removePlan(id: first.id)
        #expect(AppSettings(defaults: defaults).activePlan?.id == second.id)
    }

    @Test @MainActor func queueingLinesUpATargetWithoutSwitchingToIt() throws {
        let suite = "PlanTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let current = LearningTarget(range: .clamped(start: 1, end: 7))
        let next = LearningTarget(range: .clamped(start: 6231, end: 6236))
        settings.setActivePlan(current)
        settings.queueNext(next)
        settings.queueNext(LearningTarget(range: next.range))
        settings.queueNext(LearningTarget(range: current.range))

        #expect(settings.learningTargets.map(\.id) == [current.id, next.id])
        #expect(settings.activePlan?.id == current.id)
        #expect(settings.isQueued(next.range))
        #expect(!settings.isQueued(current.range))
    }

    @Test @MainActor func todaysLogIsSavedAndStartsOverTheNextDay() throws {
        let suite = "PlanTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        settings.recordRevised(now: yesterday)
        settings.recordLearned(.clamped(start: 1, end: 4))

        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.dailyLog.learned == .clamped(start: 1, end: 4))
        #expect(!reopened.dailyLog.revised)
    }

    @Test func nextPassageSkipsMemorizedPassagesAndWraps() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = try #require(catalog.surah(number: 67))
        var plan = LearningTarget(range: mulk.range)
        let first = try #require(plan.passage(catalog: catalog))
        let second = try #require(plan.passage(from: first.endGlobalAyah + 1, catalog: catalog))

        #expect(plan.nextPassage(catalog: catalog) { _ in false } == first)
        #expect(plan.nextPassage(catalog: catalog) { $0 == first } == second)
        plan.resumeRange = second
        #expect(plan.nextPassage(catalog: catalog) { $0 != first } == first)
        #expect(plan.nextPassage(catalog: catalog) { _ in true } == nil)
    }

    @Test func reviewPassagesGroupNeighboursAndPutRefreshFirst() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func due(_ ayah: Int, daysAgo: Int, refresh: Bool = false) -> VerseProgressSnapshot {
            var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
            item.recallState = .review
            item.isWeak = refresh
            item.nextReviewAt = now.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            return item
        }
        var notDue = due(20, daysAgo: -3)
        notDue.nextReviewAt = now.addingTimeInterval(86_400)
        // 7 is the last ayah of Al-Fatiha and 8 starts Al-Baqarah, so they never share a passage.
        let snapshots = [due(2, daysAgo: 5), due(3, daysAgo: 4), due(7, daysAgo: 9), due(8, daysAgo: 1, refresh: true), notDue]
        let passages = ReviewPlanner.duePassages(snapshots: snapshots, catalog: catalog, now: now)
        #expect(passages == [.clamped(start: 8, end: 8), .clamped(start: 7, end: 7), .clamped(start: 2, end: 3)])
    }

    @Test func reviewingARangeOnlyIncludesItsMemorizedAyahs() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        func snapshot(_ ayah: Int, _ state: RecallState) -> VerseProgressSnapshot {
            var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
            item.recallState = state
            return item
        }
        let snapshots = [snapshot(1, .review), snapshot(2, .review), snapshot(3, .learning), snapshot(4, .review),
                         snapshot(5, .review), snapshot(6, .review), snapshot(7, .review), snapshot(8, .review)]
        let passages = ReviewPlanner.memorizedPassages(in: .clamped(start: 1, end: 7), snapshots: snapshots, catalog: catalog)
        #expect(passages == [.clamped(start: 1, end: 2), .clamped(start: 4, end: 7)])
    }

    @Test func existingCustomPassageResumesExactlyAndInvalidResumeIsIgnored() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var target = LearningTarget(range: .clamped(start: 8, end: 30), resumeRange: .clamped(start: 10, end: 20))
        #expect(target.passage(catalog: catalog) == target.resumeRange)
        target.range = .clamped(start: 8, end: 12)
        let passage = try #require(target.passage(catalog: catalog))
        #expect(passage.endGlobalAyah <= 12)
    }
}
