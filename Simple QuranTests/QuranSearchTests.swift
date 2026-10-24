import Foundation
import Testing
@testable import Simple_Quran

struct SearchKeyTests {
    @Test(arguments: [
        ("ta-ha", "Taa-Haa"),
        ("taha", "Taa-Haa"),
        ("Ta Ha", "Taa-Haa"),
        ("yaseen", "Ya-Sin"),
        ("noor", "Nur"),
        ("baqarah", "Al-Baqara"),
        ("tawbah", "Taubah"),
        ("quraysh", "Quraish"),
        ("layl", "Al-Lail"),
        ("kadr", "Al-Qadr"),
        ("duha", "Ad-Dhuhaa"),
        ("muzammil", "Al-Muzzammil"),
        ("shuara", "Ash-Shu'araa"),
        ("الفاتحة", "سُورَةُ ٱلْفَاتِحَةِ"),
        ("الاخلاص", "سُورَةُ الإِخۡلَاصِ")
    ])
    func spellingsShareAKey(typed: String, name: String) {
        #expect(!Set(SearchKey.keys(typed)).isDisjoint(with: SearchKey.keys(name)))
    }

    @Test func articlesAndFillerWordsAreOptional() {
        #expect(SearchKey.keys("Ash-Shams").contains("shams"))
        #expect(SearchKey.keys("As-Shams").contains("shams"))
        #expect(SearchKey.keys("Surah Al-Kahf").contains("kahf"))
        #expect(SearchKey.keys("سورة الكهف").contains("كهف"))
    }

    @Test func arabicDigitsBecomeWesternDigits() {
        #expect(SearchKey.westernDigits("٢:٢٥٥") == "2:255")
        #expect(SearchKey.westernDigits("۱۸") == "18")
    }

    @Test func editDistanceAllowsSwapsAndStopsEarly() {
        #expect(EditDistance.between(Array("bakra"), Array("bakara"), atMost: 1))
        #expect(EditDistance.between(Array("kafh"), Array("kahf"), atMost: 1))
        #expect(!EditDistance.between(Array("mulk"), Array("kahf"), atMost: 1))
    }
}

struct QuranSearchTests {
    let catalog: BundledQuranCatalog

    init() throws {
        catalog = try BundledQuranCatalog.loadFromBundle()
    }

    @Test(arguments: [
        ("ta-ha", 20), ("taha", 20), ("Ta Ha", 20), ("surah taha", 20),
        ("fatiha", 1), ("Al-Fatihah", 1), ("umm al kitab", 1),
        ("baqara", 2), ("the cow", 2),
        ("al imran", 3), ("imran", 3),
        ("yaseen", 36), ("yasin", 36), ("ya-sin", 36),
        ("rahman", 55), ("rehman", 55), ("arrahman", 55), ("alrahman", 55),
        ("waqiah", 56), ("mulk", 67), ("tabarak", 67),
        ("ashshams", 91), ("alshams", 91), ("shams", 91),
        ("kausar", 108), ("kawthar", 108), ("kauthar", 108),
        ("ikhlas", 112), ("ikhlaas", 112),
        ("nas", 114), ("an-nas", 114),
        ("quraysh", 106), ("anbiya", 21), ("mu'minun", 23), ("dhariyat", 51), ("zariyat", 51),
        ("inshirah", 94), ("zilzal", 99), ("lahab", 111), ("tatfif", 83),
        ("baqra", 2), ("kahaf", 18), ("fatihaa", 1),
        ("الفاتحة", 1), ("فاتحة", 1), ("الاخلاص", 112), ("سورة الكهف", 18), ("يس", 36), ("طه", 20),
        ("20", 20), ("١٨", 18)
    ])
    func surahNamesFindTheRightSurahFirst(query: String, surah: Int) {
        #expect(catalog.surahs(matching: query).first?.number == surah, "\(query)")
        #expect(catalog.search(query).hits.contains { $0.kind == .surah(surah) }, "\(query)")
    }

    @Test func exactNamesRankAboveLongerOnes() {
        #expect(catalog.surahs(matching: "nas").prefix(1).map(\.number) == [114])
        #expect(catalog.surahs(matching: "nasr").first?.number == 110)
        #expect(catalog.surahs(matching: "kahf").first?.number == 18)
    }

    @Test func namesRankAboveTranslations() throws {
        let numbers = catalog.surahs(matching: "ta").map(\.number)
        let taha = try #require(numbers.firstIndex(of: 20))
        let table = try #require(numbers.firstIndex(of: 5))
        #expect(taha < table)
    }

    @Test func arabicTyposStayTight() {
        #expect(catalog.surahs(matching: "الفاتحة").map(\.number) == [1])
    }

    @Test func shortQueriesMatchNameStartsOnly() {
        let numbers = catalog.surahs(matching: "y").map(\.number)
        #expect(Set(numbers) == [10, 12, 36])
    }

    @Test func unrelatedTextFindsNothing() {
        #expect(catalog.surahs(matching: "xyzzy").isEmpty)
        #expect(catalog.search("xyzzy").hits.isEmpty)
    }

    @Test(arguments: [
        ("2:255", 2, 255, 255), ("2 255", 2, 255, 255), ("2.255", 2, 255, 255),
        ("baqara 255", 2, 255, 255), ("ta-ha:5", 20, 5, 5), ("taha 5", 20, 5, 5),
        ("yasin 1-12", 36, 1, 12), ("kahf10", 18, 10, 10), ("الكهف ١٠", 18, 10, 10), ("18:1-10", 18, 1, 10)
    ])
    func referencesOpenThePassage(query: String, surah: Int, start: Int, end: Int) throws {
        let range = try catalog.range(surah: surah, startAyah: start, endAyah: end)
        let first = catalog.search(query).hits.first
        #expect(first?.kind == (start == end ? .verse(range.startGlobalAyah) : .range(range)), "\(query)")
        #expect(first?.title == PassageLabel.passage(range, catalog: catalog))
    }

    @Test func outOfRangeAyahStillOffersTheSurah() {
        let hits = catalog.search("taha 500").hits
        #expect(hits.map(\.kind) == [.surah(20)])
    }

    @Test func bareNumberOffersSurahJuzAndPage() {
        #expect(catalog.search("20").hits.map(\.kind) == [.surah(20), .juz(20), .page(20)])
        #expect(catalog.search("300").hits.map(\.kind) == [.page(300)])
    }

    @Test func namedPassagesOpenTheirVerses() throws {
        let kursi = try catalog.range(surah: 2, startAyah: 255, endAyah: 255)
        for query in ["kursi", "ayatul kursi", "ayat al-kursi", "آية الكرسي"] {
            #expect(catalog.search(query).hits.first?.kind == .verse(kursi.startGlobalAyah), "\(query)")
        }
        #expect(!catalog.search("baqara").hits.contains { $0.kind == .verse(kursi.startGlobalAyah) })
    }

    @Test(arguments: [
        ("juz 5", 5), ("juz5", 5), ("para 5", 5), ("sipara 29", 29), ("juz amma", 30), ("para amma", 30),
        ("جزء ٣٠", 30), ("sayaqul", 2), ("tilkal rusul", 3), ("qad aflaha", 18), ("alif lam mim", 1)
    ])
    func juzByNumberOrTraditionalName(query: String, juz: Int) {
        #expect(catalog.search(query).hits.contains { $0.kind == .juz(juz) }, "\(query)")
        #expect(catalog.juzs(matching: query).first?.number == juz, "\(query)")
    }

    @Test func juzListFindsTheJuzHoldingAVerse() {
        #expect(catalog.juzs(matching: "18:75").map(\.number) == [16])
        #expect(catalog.juzs(matching: "juz").count == 30)
        #expect(catalog.juzs(matching: "7").map(\.number) == [7])
    }

    @Test func pageKeyword() {
        #expect(catalog.search("page 12").hits.map(\.kind) == [.page(12)])
        #expect(catalog.search("pg 604").hits.map(\.kind) == [.page(604)])
    }
}
