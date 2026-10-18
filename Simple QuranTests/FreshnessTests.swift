import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct FreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private func memorized(_ ayah: Int, touched: Date?, weak: Bool = false) -> VerseProgressSnapshot {
        var snapshot = VerseProgressSnapshot.fresh(globalAyah: ayah)
        snapshot.recallState = .review
        snapshot.lastRevisedAt = touched
        snapshot.isWeak = weak
        return snapshot
    }

    @Test func freshnessFollowsTheRevisionCycle() {
        let cycle = RevisionCycle.twoWeeks
        #expect(Freshness.make(lastTouchedAt: daysAgo(0), isWeak: false, cycle: cycle, now: now) == .fresh)
        #expect(Freshness.make(lastTouchedAt: daysAgo(14), isWeak: false, cycle: cycle, now: now) == .fresh)
        #expect(Freshness.make(lastTouchedAt: daysAgo(15), isWeak: false, cycle: cycle, now: now) == .fading)
        #expect(Freshness.make(lastTouchedAt: daysAgo(42), isWeak: false, cycle: cycle, now: now) == .fading)
        #expect(Freshness.make(lastTouchedAt: daysAgo(43), isWeak: false, cycle: cycle, now: now) == .needsRevision)
        #expect(Freshness.make(lastTouchedAt: nil, isWeak: false, cycle: cycle, now: now) == .needsRevision)
        // Saying you forgot it needs revision however recent.
        #expect(Freshness.make(lastTouchedAt: daysAgo(0), isWeak: true, cycle: cycle, now: now) == .needsRevision)
        #expect(Freshness.make(lastTouchedAt: daysAgo(10), isWeak: false, cycle: .oneWeek, now: now) == .fading)
    }

    @Test func anyKindOfRevisionCountsAndOnlyMemorizedAyahsHaveFreshness() {
        var heard = memorized(1, touched: daysAgo(60))
        heard.lastHeardAt = daysAgo(2)
        #expect(heard.freshness(cycle: .twoWeeks, now: now) == .fresh)
        var recited = memorized(2, touched: nil)
        recited.lastRecitedAt = daysAgo(20)
        #expect(recited.freshness(cycle: .twoWeeks, now: now) == .fading)
        var practised = memorized(3, touched: nil)
        practised.lastPractisedAt = daysAgo(1)
        #expect(practised.freshness(cycle: .twoWeeks, now: now) == .fresh)

        var learning = VerseProgressSnapshot.fresh(globalAyah: 4)
        learning.recallState = .learning
        #expect(learning.freshness(cycle: .twoWeeks, now: now) == nil)
    }

    @Test func aRangeIsAsFreshAsItsWeakestMemorizedAyah() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let fatiha = try #require(catalog.surah(number: 1))
        let index = ProgressIndex([memorized(1, touched: daysAgo(1)), memorized(2, touched: daysAgo(20)), memorized(9, touched: daysAgo(90))])
        #expect(index.freshness(of: .clamped(start: 1, end: 1), cycle: .twoWeeks, now: now) == .fresh)
        #expect(index.freshness(of: fatiha.range, cycle: .twoWeeks, now: now) == .fading)
        #expect(index.freshness(of: .clamped(start: 3, end: 7), cycle: .twoWeeks, now: now) == nil)

        let toRevise = index.surahsToRevise(catalog.surahs, cycle: .twoWeeks, now: now)
        #expect(toRevise.map(\.surah.number) == [2, 1])
        #expect(toRevise.map(\.freshness) == [.needsRevision, .fading])
    }

    @Test @MainActor func storeRecordsHearingRecitingAndRevisingWithoutChangingStatus() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)

        try store.recordHeard(globalAyah: 10, at: now)
        #expect(try store.progress(for: 10).lastHeardAt == now)
        #expect(try store.progress(for: 10).status == .notStarted)

        try store.markMemorized(ayahs: [11, 12], now: now)
        #expect(try store.progress(for: 11).lastRevisedAt == now)

        try store.applyRating(.again, ayahs: [11], now: now)
        #expect(try store.progress(for: 11).lastRecitedAt == now)
        #expect(try store.progress(for: 11).isWeak)

        let later = now.addingTimeInterval(86_400)
        try store.markRevised(ayahs: [10, 11], now: later)
        #expect(try store.progress(for: 11).lastRevisedAt == later)
        #expect(try store.progress(for: 11).isWeak == false)
        #expect(try store.progress(for: 11).status == .memorized)
        // Not memorized, so "Revised today" leaves it alone.
        #expect(try store.progress(for: 10).lastRevisedAt == nil)
    }

    @Test func dueSurahsAreListedOnceAmongWhatToRevise() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var forgotten = memorized(1, touched: daysAgo(1), weak: true)
        forgotten.nextReviewAt = now
        let snapshots = [forgotten, memorized(2, touched: daysAgo(1)), memorized(9, touched: daysAgo(20))]

        let list = RevisionList(snapshots: snapshots, catalog: catalog, cycle: .twoWeeks, now: now)
        #expect(list.pieces == [.clamped(start: 1, end: 1)])
        // Al-Fatiha already has a due piece, so only Al-Baqarah is left as a surah.
        #expect(list.surahs.map(\.surah.number) == [2])
        #expect(list.count == 2)
        #expect(ProgressIndex(snapshots).needsRevisionCount(in: .clamped(start: 1, end: 7), cycle: .twoWeeks, now: now) == 1)
    }

    @Test @MainActor func memorizedAyahsWithoutDatesStartTheirClockOnce() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        try store.markMemorized(ayahs: [20], now: now)
        try store.restoreProgress([20: memorized(20, touched: nil)], ayahs: [20])
        #expect(try store.progress(for: 20).lastTouchedAt == nil)

        try store.startRevisionClocks(now: now)
        #expect(try store.progress(for: 20).lastRevisedAt == now)
    }

    @Test @MainActor func version1StoresMigrateAndKeepTheirProgress() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "SimpleQuran.store")

        do {
            let schema = Schema(versionedSchema: AppSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(PersistenceController.storeName, schema: schema, url: url))
            let progress = AppSchemaV1.VerseProgress(globalAyah: 5, recallStateRaw: RecallState.review.rawValue)
            progress.lastPractisedAt = now
            container.mainContext.insert(progress)
            container.mainContext.insert(AppSchemaV1.PracticeSet(title: "Al-Fatiha"))
            try container.mainContext.save()
        }

        let migrated = try PersistenceController.makeContainer(url: url)
        let rows = try migrated.mainContext.fetch(FetchDescriptor<VerseProgress>())
        #expect(rows.count == 1)
        #expect(rows.first?.snapshot.status == .memorized)
        #expect(rows.first?.lastPractisedAt == now)
        #expect(rows.first?.lastHeardAt == nil)
        #expect(try migrated.mainContext.fetch(FetchDescriptor<PracticeSet>()).first?.title == "Al-Fatiha")
    }
}
