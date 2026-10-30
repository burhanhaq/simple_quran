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
}
