import Foundation
import SwiftUI
import Testing
@testable import Simple_Quran

struct SurahSwipeTests {
    private let width: CGFloat = 400
    private let both = Set(ReaderNeighbor.allCases)

    @Test func surahNeighboursStopAtTheEndsAndOpenAtTheStart() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(QuranDestination.surah(number: 67).neighbor(.next, in: catalog) == .surah(number: 68))
        #expect(QuranDestination.surah(number: 67).neighbor(.previous, in: catalog) == .surah(number: 66))
        #expect(QuranDestination.surah(number: 2, scrollToAyah: 300).neighbor(.next, in: catalog) == .surah(number: 3))
        #expect(QuranDestination.surah(number: 1).neighbor(.previous, in: catalog) == nil)
        #expect(QuranDestination.surah(number: 114).neighbor(.next, in: catalog) == nil)
    }

    @Test func juzAndPageNeighboursStayTheSameKind() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(QuranDestination.juz(5).neighbor(.next, in: catalog) == .juz(6))
        #expect(QuranDestination.juz(1).neighbor(.previous, in: catalog) == nil)
        #expect(QuranDestination.juz(30).neighbor(.next, in: catalog) == nil)
        #expect(QuranDestination.page(22).neighbor(.previous, in: catalog) == .page(21))
        #expect(QuranDestination.page(1).neighbor(.previous, in: catalog) == nil)
        #expect(QuranDestination.page(604).neighbor(.next, in: catalog) == nil)
    }

    @Test func draggingRightGoesToTheNextSurah() {
        #expect(SurahSwipe.side(for: 30) == .next)
        #expect(SurahSwipe.side(for: -30) == .previous)
        #expect(SurahSwipe.leavingOffset(toward: .next, width: width) == width)
        #expect(SurahSwipe.arrivalOffset(from: .next, width: width) < 0)
        #expect(SurahSwipe.arrivalOffset(from: .previous, width: width) > 0)
    }

    @Test func onlyMostlySidewaysDragsAreSwipes() {
        #expect(SurahSwipe.isHorizontal(dx: 20, dy: 5))
        #expect(SurahSwipe.isHorizontal(dx: -20, dy: 10))
        #expect(!SurahSwipe.isHorizontal(dx: 10, dy: 10))
        #expect(!SurahSwipe.isHorizontal(dx: 2, dy: -20))
    }

    @Test func lettingGoPastTheThresholdMovesOnAndShortOfItSpringsBack() {
        let past = width * SurahSwipe.commitFraction + 1
        #expect(SurahSwipe.outcome(translationX: past, projectedEndX: past, width: width, available: both) == .next)
        #expect(SurahSwipe.outcome(translationX: -past, projectedEndX: -past, width: width, available: both) == .previous)
        #expect(SurahSwipe.outcome(translationX: 40, projectedEndX: 45, width: width, available: both) == nil)
        // Flung back toward the start after passing the threshold.
        #expect(SurahSwipe.outcome(translationX: past, projectedEndX: 20, width: width, available: both) == nil)
        #expect(SurahSwipe.outcome(translationX: past, projectedEndX: -60, width: width, available: both) == nil)
    }

    @Test func aQuickFlickMovesOnBeforeTheThreshold() {
        let projected = SurahSwipe.projectedEnd(translationX: 40, velocityX: 1_200)
        #expect(SurahSwipe.outcome(translationX: 40, projectedEndX: projected, width: width, available: both) == .next)
    }

    @Test func withNothingThatWayTheTextOnlyStretches() {
        #expect(SurahSwipe.offset(for: 100, hasNeighbor: true) == 100)
        #expect(SurahSwipe.offset(for: 100, hasNeighbor: false) == 100 * SurahSwipe.rubberBand)
        #expect(SurahSwipe.outcome(translationX: 300, projectedEndX: 300, width: width, available: [.previous]) == nil)
    }

    @Test func progressReachesOneAtTheThreshold() {
        #expect(SurahSwipe.progress(for: 0, width: width) == 0)
        #expect(SurahSwipe.progress(for: -width * SurahSwipe.commitFraction / 2, width: width) == 0.5)
        #expect(SurahSwipe.progress(for: width, width: width) == 1)
        #expect(SurahSwipe.progress(for: 50, width: 0) == 0)
    }

    @Test @MainActor func theNextSurahKeepsTheSheetAtPeekOrTheMiddle() {
        #expect(SurahSheetStart.keeping(SurahSheetDetent.peek) == .peek)
        #expect(SurahSheetStart.keeping(SurahSheetDetent.half) == .half)
        #expect(SurahSheetStart.keeping(SurahSheetDetent.fitted(320)) == .half)
        #expect(SurahSheetStart.keeping(SurahSheetDetent.full) == .half)
    }
}
