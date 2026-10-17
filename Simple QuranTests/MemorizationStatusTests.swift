import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct MemorizationStatusTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func statusComesOnlyFromRecallState() {
        var item = VerseProgressSnapshot.fresh(globalAyah: 1)
        item.exposureCount = 10
        item.listeningSeconds = 600
        #expect(item.status == .notStarted)
        item.recallState = .learning
        #expect(item.status == .learning)
        item.recallState = .strengthening
        #expect(item.status == .learning)
        item.recallState = .review
        #expect(item.status == .memorized)
        #expect(item.needsRefresh == false)
        item.isWeak = true
        #expect(item.needsRefresh)
    }

    @Test func comfortableNeverPromotesToMemorized() {
        let scheduler = ReviewScheduler()
        var item = VerseProgressSnapshot.fresh(globalAyah: 1)
        for _ in 0..<5 {
            let decision = scheduler.apply(rating: .comfortable, to: item, now: now)
            item.recallState = decision.state
            item.streak = decision.streak
        }
        #expect(item.status == .learning)
        #expect(scheduler.apply(rating: .solid, to: item, now: now).state == .review)
    }

    @Test func forgettingAMemorizedAyahKeepsItMemorizedButFlagged() {
        let scheduler = ReviewScheduler()
        var memorized = VerseProgressSnapshot.fresh(globalAyah: 1)
        memorized.recallState = .review
        for rating in [RecallRating.again, .needsWork] {
            let decision = scheduler.apply(rating: rating, to: memorized, now: now)
            #expect(decision.state == .review)
            #expect(decision.isWeak)
        }
        let shaky = scheduler.apply(rating: .comfortable, to: memorized, now: now)
        #expect(shaky.state == .review)
        #expect(shaky.isWeak == false)

        let learning = VerseProgressSnapshot.fresh(globalAyah: 2)
        #expect(scheduler.apply(rating: .again, to: learning, now: now).state == .learning)
    }

    @Test func rangeStatusNeedsEveryAyahForMemorized() throws {
        var memorized = VerseProgressSnapshot.fresh(globalAyah: 1)
        memorized.recallState = .review
        var second = memorized
        second.globalAyah = 2
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 3)

        #expect(ProgressIndex([memorized, second]).status(of: range) == .learning)
        #expect(ProgressIndex([memorized, second]).count(.notStarted, in: range) == 1)
        var third = memorized
        third.globalAyah = 3
        #expect(ProgressIndex([memorized, second, third]).status(of: range) == .memorized)
        #expect(ProgressIndex([]).status(of: range) == .notStarted)
    }

    @Test @MainActor func skippingTheCheckLeavesStatusUnchanged() throws {
        let (container, store) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let range = VerseRange.clamped(start: 1, end: 3)
        let set = try store.createSet(title: "Al-Fatiha", passages: [range], settings: .default)
        try store.markMemorized(ayahs: [1], now: now)
        try store.completePractice(set, ayahs: range.globalAyahs, rating: nil, lastAyah: 3, seconds: 30, repetitions: 3)
        #expect(try store.progress(for: 1).status == .memorized)
        #expect(try store.progress(for: 2).status == .notStarted)
        #expect(try store.progress(for: 2).exposureCount == 1)
    }

    @Test @MainActor func beginLearningOnlyMovesNewAyahs() throws {
        let (container, store) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        try store.markMemorized(ayahs: [1], now: now)
        try store.beginLearning(ayahs: [1, 2])
        #expect(try store.progress(for: 1).status == .memorized)
        #expect(try store.progress(for: 1).lastPractisedAt == nil)
        #expect(try store.progress(for: 2).status == .learning)
    }

    @Test @MainActor func markNeedsRefreshKeepsMemorizedAndMakesItDue() throws {
        let (container, store) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        try store.markMemorized(ayahs: [1], now: now)
        try store.markNeedsRefresh(ayahs: [1, 2], now: now)
        let first = try store.progress(for: 1)
        #expect(first.status == .memorized)
        #expect(first.needsRefresh)
        #expect(first.isDue(at: now))
        #expect(try store.progress(for: 2).status == .learning)
    }

    @Test @MainActor func migrationOnlyKeepsExplicitClaimsAndIsIdempotent() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext
        let store = PracticeStore(context: context)
        #expect(try store.migrateToExplicitMemorization() == false)

        func insert(_ ayah: Int, _ state: RecallState, rating: RecallRating? = nil, exposure: Int = 0) {
            let model = VerseProgress(globalAyah: ayah)
            model.recallStateRaw = state.rawValue
            model.lastRatingRaw = rating?.rawValue
            model.exposureCount = exposure
            context.insert(model)
        }
        insert(1, .review, rating: .solid, exposure: 2)
        insert(2, .review, rating: .comfortable, exposure: 3)
        insert(3, .new, exposure: 1)
        insert(4, .learning, rating: .needsWork, exposure: 1)
        try context.save()

        #expect(try store.migrateToExplicitMemorization())
        #expect(try store.migrateToExplicitMemorization())
        #expect(try store.progress(for: 1).status == .memorized)
        #expect(try store.progress(for: 2).status == .learning)
        #expect(try store.progress(for: 3).status == .learning)
        #expect(try store.progress(for: 4).status == .learning)
    }

    /// The container must outlive the store, so callers keep both.
    @MainActor private func makeStore() throws -> (ModelContainer, PracticeStore) {
        let container = try PersistenceController.makeContainer(inMemory: true)
        return (container, PracticeStore(context: container.mainContext))
    }
}
