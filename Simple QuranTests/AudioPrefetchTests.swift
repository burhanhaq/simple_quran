import Testing
@testable import Simple_Quran

struct AudioPrefetchTests {
    private let nothingSaved: (Int) -> Bool = { _ in false }

    @Test func startsAtTheAyahPlaying() {
        #expect(AudioPrefetch.ayahsToFetch(order: [1, 2, 3, 4], current: 3, limit: 2, skip: nothingSaved) == [3, 4])
    }

    @Test func withNothingPlayingStartsAtTheBeginning() {
        #expect(AudioPrefetch.ayahsToFetch(order: [1, 2, 3], current: nil, limit: 2, skip: nothingSaved) == [1, 2])
    }

    @Test func wrapsAroundForPassagesThatRepeat() {
        #expect(AudioPrefetch.ayahsToFetch(order: [1, 2, 3, 4], current: 3, limit: 4, skip: nothingSaved) == [3, 4, 1, 2])
    }

    @Test func aLongPassageOnlyFetchesTheWindow() {
        let juz = Array(5673...6236)
        let window = AudioPrefetch.ayahsToFetch(order: juz, current: 5673, skip: nothingSaved)
        #expect(window == Array(5673..<(5673 + AudioPrefetch.lookahead)))
    }

    @Test func skipsSavedAyahsWithoutShrinkingTheWindow() {
        let saved: Set<Int> = [2, 3]
        #expect(AudioPrefetch.ayahsToFetch(order: [1, 2, 3, 4, 5], current: 1, limit: 3) { saved.contains($0) } == [1, 4, 5])
    }

    @Test func listsARepeatedAyahOnce() {
        #expect(AudioPrefetch.ayahsToFetch(order: [7, 7, 7, 8, 8], current: 7, limit: 5, skip: nothingSaved) == [7, 8])
    }

    @Test func anUnknownCurrentAyahStartsAtTheBeginning() {
        #expect(AudioPrefetch.ayahsToFetch(order: [1, 2, 3], current: 99, limit: 1, skip: nothingSaved) == [1])
    }
}
