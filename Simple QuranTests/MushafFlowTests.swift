import UIKit
import Testing
@testable import Simple_Quran

@MainActor
struct MushafFlowTests {
    @Test func consecutivePagesStayInOrderAsSeparateBlocks() {
        let verses = [
            sampleVerse(globalAyah: 1, ayahInSurah: 1, page: 2, text: "الأولى"),
            sampleVerse(globalAyah: 2, ayahInSurah: 2, page: 2, text: "الثانية"),
            sampleVerse(globalAyah: 3, ayahInSurah: 3, page: 3, text: "الثالثة")
        ]

        let blocks = MushafPageBlocks.make(from: verses)

        #expect(blocks.map(\.id) == [1, 3])
        #expect(blocks.map { $0.verses.map(\.globalAyah) } == [[1, 2], [3]])
        #expect(blocks.map { $0.verses.map(\.page) } == [[2, 2], [3]])
    }

    @Test func returningToAnEarlierPageStartsANewBlock() {
        let verses = [
            sampleVerse(globalAyah: 10, ayahInSurah: 1, page: 1, text: "ألف"),
            sampleVerse(globalAyah: 11, ayahInSurah: 2, page: 1, text: "باء"),
            sampleVerse(globalAyah: 40, ayahInSurah: 1, page: 5, text: "جيم"),
            sampleVerse(globalAyah: 12, ayahInSurah: 3, page: 1, text: "دال")
        ]

        let blocks = MushafPageBlocks.make(from: verses)

        #expect(blocks.map(\.id) == [10, 40, 12])
        #expect(blocks.map { $0.verses.map(\.page) } == [[1, 1], [5], [1]])
        #expect(blocks.map { $0.verses.map(\.globalAyah) } == [[10, 11], [40], [12]])
    }

    @Test func ayahRangesStayDistinctAndMapBackToTheirAyah() throws {
        let verses = [
            sampleVerse(globalAyah: 8, ayahInSurah: 1, page: 2, text: "الٓمٓ"),
            sampleVerse(globalAyah: 9, ayahInSurah: 2, page: 2, text: "ذَٰلِكَ ٱلْكِتَٰبُ")
        ]

        let page = MushafTextBuilder.make(verses: verses, hiddenAyah: nil, contentSizeCategory: .large)
        let firstRange = try #require(page.ayahRanges[8])
        let secondRange = try #require(page.ayahRanges[9])

        #expect(NSIntersectionRange(firstRange, secondRange).length == 0)
        #expect(substring(page.text, range: firstRange).hasPrefix("الٓمٓ"))
        #expect(substring(page.text, range: secondRange).hasPrefix("ذَٰلِكَ ٱلْكِتَٰبُ"))
        #expect(page.ayahRanges.count == verses.count)
    }

    @Test func hiddenAyahKeepsLaterRangesOnTheFollowingAyah() throws {
        let verses = [
            sampleVerse(globalAyah: 8, ayahInSurah: 1, page: 2, text: "الٓمٓ"),
            sampleVerse(globalAyah: 9, ayahInSurah: 2, page: 2, text: "ذَٰلِكَ ٱلْكِتَٰبُ")
        ]

        let page = MushafTextBuilder.make(verses: verses, hiddenAyah: 8, contentSizeCategory: .large)
        let hiddenRange = try #require(page.ayahRanges[8])
        let followingRange = try #require(page.ayahRanges[9])
        let hiddenText = substring(page.text, range: hiddenRange)
        let followingText = substring(page.text, range: followingRange)

        #expect(hiddenText.hasPrefix(MushafTextBuilder.hiddenPlaceholder))
        #expect(hiddenText.contains("الٓمٓ") == false)
        #expect(followingText.hasPrefix("ذَٰلِكَ ٱلْكِتَٰبُ"))
        #expect(NSIntersectionRange(hiddenRange, followingRange).length == 0)
        #expect(hiddenRange.location + hiddenRange.length <= followingRange.location)
    }

    @Test func applyingAHighlightChangesBackgroundWithoutChangingTheString() throws {
        let verses = [
            sampleVerse(globalAyah: 8, ayahInSurah: 1, page: 2, text: "الٓمٓ"),
            sampleVerse(globalAyah: 9, ayahInSurah: 2, page: 2, text: "ذَٰلِكَ ٱلْكِتَٰبُ")
        ]
        let page = MushafTextBuilder.make(verses: verses, hiddenAyah: nil, contentSizeCategory: .large)
        let text = NSMutableAttributedString(attributedString: page.text)
        let original = text.string
        let first = try #require(page.ayahRanges[8])
        let second = try #require(page.ayahRanges[9])

        #expect(backgroundColor(text, range: first) == nil)
        MushafTextBuilder.applyHighlightChange(
            to: text,
            ayahRanges: page.ayahRanges,
            from: .empty,
            to: MushafHighlightState(highlightedAyah: 8)
        )

        #expect(text.string == original)
        #expect(text.length == original.utf16.count)
        #expect(backgroundColor(text, range: first) != nil)
        #expect(backgroundColor(text, range: second) == nil)

        MushafTextBuilder.applyHighlightChange(
            to: text,
            ayahRanges: page.ayahRanges,
            from: MushafHighlightState(highlightedAyah: 8),
            to: MushafHighlightState(highlightedAyah: 9, collectedAyahs: [8])
        )

        #expect(text.string == original)
        #expect(backgroundColor(text, range: first) != nil)
        #expect(backgroundColor(text, range: second) != nil)
    }

    private func substring(_ text: NSAttributedString, range: NSRange) -> String {
        text.attributedSubstring(from: range).string
    }

    private func backgroundColor(_ text: NSAttributedString, range: NSRange) -> UIColor? {
        text.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? UIColor
    }

    private func sampleVerse(
        globalAyah: Int,
        ayahInSurah: Int,
        page: Int,
        text: String
    ) -> QuranVerse {
        QuranVerse(
            globalAyah: globalAyah,
            surahNumber: 2,
            ayahInSurah: ayahInSurah,
            text: text,
            juz: 1,
            page: page,
            sajdah: .none
        )
    }
}
