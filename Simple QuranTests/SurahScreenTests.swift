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
        #expect(SurahAction.make(pieces: pieces, index: ProgressIndex([])) == .start(pieces[0]))

        let learning = ProgressIndex([snapshot(2, .learning)])
        #expect(SurahAction.make(pieces: pieces, index: learning) == .continue(pieces[0]))

        let firstDone = ProgressIndex((1...3).map { snapshot($0, .review) })
        #expect(SurahAction.make(pieces: pieces, index: firstDone) == .continue(pieces[1]))

        let allDone = ProgressIndex((1...7).map { snapshot($0, .review) })
        #expect(SurahAction.make(pieces: pieces, index: allDone) == .revise(pieces))

        #expect(SurahAction.make(pieces: [], index: allDone) == nil)
    }

    @Test @MainActor func recitingHidesTheTextAndTappingRevealsAndMarks() {
        var focus = MemorizeFocus(route: SessionRoute(range: .clamped(start: 8, end: 12)))
        #expect(focus.step == .listen)
        #expect(focus.hiddenAyahs.isEmpty)
        focus.go(to: .recite)
        #expect(focus.hiddenAyahs == [8, 9, 10, 11, 12])

        // A hidden ayah opens and is marked; tapping it again only takes the mark back.
        focus.tap(9)
        #expect(focus.hiddenAyahs == [8, 10, 11, 12])
        #expect(focus.slipped == [9])
        focus.tap(9)
        #expect(focus.slipped.isEmpty)
        #expect(focus.hiddenAyahs == [8, 10, 11, 12])
        focus.tap(20)
        #expect(focus.slipped.isEmpty)

        // Checking shows the whole piece and keeps the marks; a tap there marks a slip.
        focus.tap(10)
        focus.go(to: .check)
        #expect(focus.hiddenAyahs.isEmpty)
        focus.tap(11)
        #expect(focus.slipped == [10, 11])

        // Reciting again hides every ayah, tapped ones too, and keeps the marks.
        focus.go(to: .recite)
        #expect(focus.hiddenAyahs == [8, 9, 10, 11, 12])
        #expect(focus.slipped == [10, 11])

        focus.go(to: .listen)
        #expect(focus.hiddenAyahs.isEmpty)
        #expect(focus.slipped == [10, 11])

        focus.answer = .almost
        focus.move(to: .clamped(start: 13, end: 16))
        #expect(focus.step == .listen)
        #expect(focus.slipped.isEmpty && focus.revealed.isEmpty)
        #expect(focus.answer == nil)
        #expect(focus.range == .clamped(start: 13, end: 16))

        let review = MemorizeFocus(route: SessionRoute(range: .clamped(start: 1, end: 7), kind: .review,
                                                       reviewQueue: [.clamped(start: 8, end: 9)]))
        #expect(review.step == .recite)
        #expect(review.route.reviewQueue == [.clamped(start: 8, end: 9)])
    }

    @Test @MainActor func stepsRunListenReciteCheck() {
        #expect(CoachStep.listen.next == .recite && CoachStep.recite.next == .check && CoachStep.check.next == nil)
        #expect(CoachStep.listen.previous == nil && CoachStep.recite.previous == .listen && CoachStep.check.previous == .recite)
    }

    @Test @MainActor func onlyCheckingNeedsTheWholeCoach() {
        #expect(CoachStep.listen.allowsSlimCoach && CoachStep.recite.allowsSlimCoach)
        #expect(!CoachStep.check.allowsSlimCoach)
    }

    @Test @MainActor func openingEveryAyahShowsTheWholePieceUntilRecitingAgain() {
        var focus = MemorizeFocus(route: SessionRoute(range: .clamped(start: 1, end: 3), kind: .review))
        for ayah in 1...3 { focus.tap(ayah) }
        #expect(focus.hiddenAyahs.isEmpty)
        focus.go(to: .check)
        focus.go(to: .recite)
        #expect(focus.hiddenAyahs == [1, 2, 3])
        #expect(focus.slipped == [1, 2, 3])
    }

    @Test @MainActor func scrollingDuringPlaybackPausesFollowingUntilResumed() {
        var follow = AutoFollow()
        follow.userScrolled(isPlaying: false)
        #expect(!follow.isPaused)

        follow.userScrolled(isPlaying: true)
        #expect(follow.isPaused)
        #expect(follow.showsReturnButton(isPlaying: true))
        #expect(!follow.showsReturnButton(isPlaying: false))

        follow.resume()
        #expect(!follow.isPaused)
        #expect(!follow.showsReturnButton(isPlaying: true))
    }

    @Test @MainActor func slippedAyahsGetTheWeakerAnswerOnlyWithAnAnswer() {
        var learn = MemorizeFocus(route: SessionRoute(range: .clamped(start: 1, end: 4)))
        learn.slipped = [2]
        #expect(learn.ratings(isMemorized: { _ in false }).isEmpty)
        learn.answer = .memorized
        #expect(learn.ratings(isMemorized: { _ in false }) == [.memorized: [1, 3, 4], .stillLearning: [2]])

        // A review speaks only for ayahs memorized going in; a slip there is "Forgot".
        var review = MemorizeFocus(route: SessionRoute(range: .clamped(start: 1, end: 4), kind: .review))
        review.slipped = [3]
        review.answer = .stillSolid
        #expect(review.ratings(isMemorized: { $0 != 4 }) == [.stillSolid: [1, 2], .forgot: [3]])
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

    @Test @MainActor func pagesHoldTheirPiecesAndNameTheOpening() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let baqarah = try #require(catalog.surah(number: 2))
        let groups = SurahPieceCache().groups(for: baqarah.range, size: .halfPage, catalog: catalog)
        let pages = try #require(groups.first?.pages)
        let surahPages = Set(catalog.verses(in: baqarah.range).map(\.page))
        #expect(pages.count == surahPages.count)
        #expect(pages.first?.pageInSurah == 1)
        #expect(pages.last?.pageInSurah == surahPages.count)
        #expect(pages.allSatisfy { (1...2).contains($0.pieces.count) })
        #expect(pages.flatMap(\.pieces) == groups.first?.pieces)
        #expect(pages.allSatisfy { !$0.openingWords.isEmpty })
        // The opening ayah is one word, so the row reads on into the next.
        #expect(pages[0].openingWords.split(separator: " ").count == SurahPageRow.openingWordCount)
        #expect(pages[0].openingWords.hasSuffix("…"))

        // A short surah is one piece on one page, so the screen shows no parts.
        let fatiha = try #require(catalog.surah(number: 1))
        let fatihaGroups = SurahPieceCache().groups(for: fatiha.range, size: .halfPage, catalog: catalog)
        #expect(fatihaGroups.flatMap(\.pieces).count == 1)
    }
}
