import Foundation
import Testing
@testable import Simple_Quran

struct QuranTranslationTests {
    @Test func bundledSaheehIsCompleteWithoutFootnoteMarkers() throws {
        let translation = try BundledTranslation.load(.saheehInternational)
        #expect(translation.version == "1.1.2")
        #expect(translation.texts.count == QuranCatalogMetrics.ayahCount)
        #expect(translation.texts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(!translation.texts.contains { $0.contains(#/\[\d/#) })
    }

    @Test func textIsLookedUpByGlobalAyah() throws {
        let translation = try BundledTranslation.load(.saheehInternational)
        #expect(translation.text(globalAyah: 1) == "In the name of Allāh, the Entirely Merciful, the Especially Merciful.")
        #expect(translation.text(globalAyah: 8)?.hasPrefix("Alif, Lām, Meem") == true)
        #expect(translation.text(globalAyah: 0) == nil)
        #expect(translation.text(globalAyah: QuranCatalogMetrics.ayahCount + 1) == nil)
    }

    @Test func onlyFootnoteMarkersAreRemoved() {
        #expect(TranslationText.removingFootnoteMarkers("Lord[4] of the worlds -") == "Lord of the worlds -")
        #expect(TranslationText.removingFootnoteMarkers("[It[437] is] a revelation") == "[It is] a revelation")
        let bracketed = "[All] praise is [due] to Allāh, no exchange [i.e., ransom]"
        #expect(TranslationText.removingFootnoteMarkers(bracketed) == bracketed)
    }

    @Test func translationThatDoesNotMatchItsEditionIsRejected() {
        let file = #"{"key":"english_other","version":"1","info":"","ayahs":[]}"#
        #expect(throws: AppError.self) {
            try BundledTranslation(edition: .saheehInternational, data: Data(file.utf8))
        }
    }
}
