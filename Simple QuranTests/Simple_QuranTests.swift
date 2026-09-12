import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct QuranIntegrityTests {
    @Test func bundledCorpusPassesIntegrityChecks() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(catalog.integrity.isValid)
        #expect(catalog.integrity.surahCount == 114)
        #expect(catalog.integrity.ayahCount == 6236)
        #expect(catalog.integrity.pageCount == 604)
        #expect(catalog.integrity.juzCount == 30)
        #expect(catalog.integrity.sajdahCount == 15)
        #expect(catalog.integrity.contiguousIDs)
        #expect(catalog.integrity.matchingSurahCounts)
        #expect(catalog.verse(globalAyah: 1)?.reference == "1:1")
        #expect(catalog.verse(globalAyah: 6236)?.reference == "114:6")
        #expect(catalog.surah(number: 9)?.ayahCount == 129)
        let kahf = try catalog.range(surah: 18, startAyah: 1, endAyah: 10)
        #expect(kahf.count == 10)
        #expect(catalog.verses(in: kahf).first?.text.isEmpty == false)
    }
}

struct PracticeQueuePlannerTests {
    @Test func repeatsAyahsAndInsertsSilence() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 2)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .three
        settings.setRepeatCount = .one
        settings.pauseSeconds = 1
        let items = PracticeQueuePlanner().expand(passages: [range], settings: settings)
        let ayahs = items.compactMap { item -> Int? in
            if case .ayah(let ayah, _, _) = item { return ayah }
            return nil
        }
        #expect(ayahs == [1, 1, 1, 2, 2, 2])
        #expect(items.contains { if case .silence(1) = $0 { return true }; return false })
    }

    @Test func repeatsTheWholeSet() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 1)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .one
        settings.setRepeatCount = .two
        settings.pauseSeconds = 0
        let items = PracticeQueuePlanner().expand(passages: [range], settings: settings)
        #expect(items.count == 2)
    }
}

struct ReviewSchedulerTests {
    @Test func listeningIsNotMasteryAndRatingsScheduleReviews() {
        let scheduler = ReviewScheduler()
        let fresh = VerseProgressSnapshot.fresh(globalAyah: 255)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let again = scheduler.apply(rating: .again, to: fresh, now: now)
        #expect(again.state == .learning)
        #expect(again.isWeak)
        #expect(again.streak == 0)

        var comfortable = fresh
        comfortable.streak = 0
        let firstComfortable = scheduler.apply(rating: .comfortable, to: comfortable, now: now)
        #expect(firstComfortable.state == .strengthening)
        #expect(firstComfortable.isWeak == false)

        var solid = fresh
        solid.streak = 3
        let review = scheduler.apply(rating: .solid, to: solid, now: now)
        #expect(review.state == .review)
        #expect(review.nextReviewAt > now)
    }
}

struct SearchAndAudioSourceTests {
    @Test func searchFindsKahfRangeAndJuzAmma() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let kahf = catalog.search("18:1-10")
        #expect(kahf.hits.contains { if case .range(let range) = $0.kind { return range.count == 10 }; return false })
        let amma = catalog.search("juz amma")
        #expect(amma.hits.contains { if case .juz(30) = $0.kind { return true }; return false })
    }

    @Test func sudaisURLsAreVerseAddressable() throws {
        let source = AlQuranCloudAudioSource()
        let url = try source.remoteURL(for: 1)
        #expect(url.absoluteString.hasSuffix("/192/ar.sudais/1.mp3"))
        #expect(throws: AppError.invalidRange) {
            _ = try source.remoteURL(for: 0)
        }
    }
}

struct UserFacingErrorTests {
    @Test func mapsInternalFailuresToFriendlyCopy() {
        let message = UserFacingMessage.from(.downloadFailed)
        #expect(!message.message.contains("http"))
        #expect(!message.message.contains("URLSession"))
        #expect(message.title.isEmpty == false)
    }
}

struct PracticeStoreTests {
    @Test @MainActor func createsSetsAndKeepsGlobalRecall() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        let fatiha = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 7)
        let set = try store.createSet(title: "First ten Kahf", passages: [fatiha], settings: .default)
        #expect(set.orderedPassages.count == 1)
        try store.applyRating(.needsWork, ayahs: [1], now: .now)
        let progress = try store.progress(for: 1)
        #expect(progress.recallState == .learning)
        #expect(progress.isWeak)
        #expect(progress.exposureCount == 0)
    }
}
