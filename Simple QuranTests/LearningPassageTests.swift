import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct LearningPassageTests {
    @Test @MainActor func pieceSizeAndPlaybackArePreferencesThatPersist() throws {
        let suite = "PieceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fresh = AppSettings(defaults: defaults)
        #expect(fresh.pieceSize == .halfPage)
        #expect(fresh.memorizePlayback.ayahRepeatCount == .one)

        fresh.pieceSize = .quarterPage
        fresh.memorizePlayback.ayahRepeatCount = .five
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.pieceSize == .quarterPage)
        #expect(reopened.memorizePlayback.ayahRepeatCount == .five)
    }

    @Test @MainActor func pagePreferenceFromEarlierVersionsBecomesFullPages() throws {
        let suite = "PieceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "learning.byPage")
        #expect(AppSettings(defaults: defaults).pieceSize == .fullPage)
    }

    @Test @MainActor func savedPlanPlacesSnapToTheirPieceOnce() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let suite = "PieceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let mulk = try #require(catalog.surah(number: 67))
        let settings = AppSettings(defaults: defaults)
        let oldPlace = VerseRange.clamped(start: mulk.startGlobalAyah, end: mulk.startGlobalAyah + 2)
        settings.setActivePlan(LearningTarget(range: mulk.range, resumeRange: oldPlace))
        settings.adoptPagePieces(catalog: catalog)
        let piece = try #require(catalog.piece(containing: mulk.startGlobalAyah, size: .halfPage))
        #expect(settings.activePlan?.resumeRange == piece)

        settings.remember(oldPlace, targetID: settings.activePlan?.id)
        settings.adoptPagePieces(catalog: catalog)
        #expect(settings.activePlan?.resumeRange == oldPlace)
    }

    @Test @MainActor func finishingWithoutAnAnswerRecordsActivityButNotMemorization() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        let first = VerseRange.clamped(start: 8, end: 10)
        let set = try store.createSet(title: "Small passage", passages: [first], settings: .default)
        #expect(try store.allProgress().isEmpty)
        try store.completePractice(set, ayahs: first.globalAyahs, rating: nil, lastAyah: 10, seconds: 0, repetitions: 0)
        #expect(try store.progress(for: 8).exposureCount == 1)
        #expect(try store.progress(for: 8).lastRating == nil)
        #expect(try store.progress(for: 8).recallAttempts == 0)
        #expect(try store.progress(for: 8).status == .notStarted)
        let overlap = VerseRange.clamped(start: 10, end: 12)
        let other = try store.createSet(title: "Another passage", passages: [overlap], settings: .default)
        try store.completePractice(other, ayahs: overlap.globalAyahs, rating: .solid, lastAyah: 12, seconds: 0, repetitions: 0)
        #expect(try store.progress(for: 10).exposureCount == 2)
        #expect(try store.progress(for: 10).lastRating == .solid)
        #expect(try store.progress(for: 10).status == .memorized)
        #expect(try store.progress(for: 9).lastRating == nil)
        #expect(try store.progress(for: 12).nextReviewAt != nil)
        let sessions = try container.mainContext.fetch(FetchDescriptor<PracticeSession>())
        #expect(sessions.count == 2)
        #expect(sessions.allSatisfy { $0.completed })
    }

    @Test @MainActor func legacyLearningPlaceBecomesASurahPlanOnce() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let suite = "LearningTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(25, forKey: "learning.start")
        defaults.set(27, forKey: "learning.end")
        let settings = AppSettings(defaults: defaults)
        settings.readingAyah = 100
        settings.adoptLegacyLearningPlace(catalog: catalog)
        let baqarah = try #require(catalog.surah(number: 2))
        #expect(settings.activePlan?.range == baqarah.range)
        #expect(settings.activePlan?.resumeRange == .clamped(start: 25, end: 27))

        settings.adoptLegacyLearningPlace(catalog: catalog)
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.learningTargets.count == 1)
        #expect(reopened.readingAyah == 100)
    }
}
