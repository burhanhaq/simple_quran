import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct SurahScreenTests {
    private func snapshot(_ ayah: Int, _ state: RecallState) -> VerseProgressSnapshot {
        var item = VerseProgressSnapshot.fresh(globalAyah: ayah)
        item.recallState = state
        return item
    }

    @Test @MainActor func mainActionStartsContinuesThenRevises() {
        let pieces: [VerseRange] = [.clamped(start: 1, end: 3), .clamped(start: 4, end: 7)]
        #expect(SurahAction.make(pieces: pieces, chosen: nil, index: ProgressIndex([])) == .start(pieces[0]))

        let learning = ProgressIndex([snapshot(2, .learning)])
        #expect(SurahAction.make(pieces: pieces, chosen: nil, index: learning) == .continue(pieces[0]))

        let firstDone = ProgressIndex((1...3).map { snapshot($0, .review) })
        #expect(SurahAction.make(pieces: pieces, chosen: nil, index: firstDone) == .continue(pieces[1]))

        let allDone = ProgressIndex((1...7).map { snapshot($0, .review) })
        #expect(SurahAction.make(pieces: pieces, chosen: nil, index: allDone) == .revise(pieces))

        // A piece picked on the strip takes over.
        #expect(SurahAction.make(pieces: pieces, chosen: pieces[0], index: firstDone) == .revise([pieces[0]]))
        #expect(SurahAction.make(pieces: pieces, chosen: pieces[1], index: firstDone) == .continue(pieces[1]))
        #expect(SurahAction.make(pieces: [], chosen: nil, index: allDone) == nil)
    }

    @Test @MainActor func focusHidesOnlyUnpeekedAyahsFromMemoryAndResetsOnMove() {
        var focus = MemorizeFocus(route: SessionRoute(range: .clamped(start: 8, end: 12)))
        #expect(focus.step == .listen)
        #expect(focus.hiddenAyahs.isEmpty)
        focus.step = .fromMemory
        focus.peeked = [9]
        focus.answer = .almost
        #expect(focus.hiddenAyahs == [8, 10, 11, 12])

        focus.move(to: .clamped(start: 13, end: 16))
        #expect(focus.step == .listen)
        #expect(focus.peeked.isEmpty)
        #expect(focus.answer == nil)
        #expect(focus.range == .clamped(start: 13, end: 16))

        let review = MemorizeFocus(route: SessionRoute(range: .clamped(start: 1, end: 7), kind: .review,
                                                       reviewQueue: [.clamped(start: 8, end: 9)]))
        #expect(review.step == .fromMemory)
        #expect(review.route.reviewQueue == [.clamped(start: 8, end: 9)])
    }

    @Test @MainActor func undoingAClaimRestoresEarlierProgress() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        try store.beginLearning(ayahs: [2])
        let before = try store.allProgress()
        let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.globalAyah, $0) })

        try store.markMemorized(ayahs: [1, 2, 3], now: .now)
        #expect(try store.allProgress().filter { $0.status == .memorized }.count == 3)

        try store.restoreProgress(previous, ayahs: [1, 2, 3])
        let after = try store.allProgress()
        #expect(after.count == 1)
        #expect(after.first?.globalAyah == 2)
        #expect(after.first?.status == .learning)
    }

    @Test @MainActor func juzPiecesAreGroupedBySurahAndCoverTheJuz() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let amma = try catalog.versesForJuz(30)
        let groups = SurahPieceCache().groups(for: amma, size: .halfPage, catalog: catalog)
        #expect(groups.first?.surah.number == 78)
        #expect(groups.last?.surah.number == 114)
        #expect(groups.count == 37)
        #expect(groups.flatMap(\.pieces).flatMap(\.globalAyahs) == amma.globalAyahs)
        for group in groups {
            #expect(group.pieces.allSatisfy { group.surah.range.contains($0.startGlobalAyah) && group.surah.range.contains($0.endGlobalAyah) })
        }
    }
}
