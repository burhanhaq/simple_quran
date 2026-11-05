import CoreGraphics
import Foundation

/// A mushaf line's text, with where each ayah's words and number fall in it.
nonisolated struct MushafComposedLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A surah's name in its frame.
        case surahHeader
        case basmala
        case text(justified: Bool)
    }

    var kind: Kind
    var text: String
    /// Each ayah's words on this line, in UTF-16 offsets.
    var bodyRanges: [Int: NSRange] = [:]
    /// Each ayah number on this line, in UTF-16 offsets.
    var numberRanges: [Int: NSRange] = [:]
    /// Width at `MushafLayout.measuringSize`, before justification.
    var naturalWidth: CGFloat?

    /// The ayah at a character, counting its number as part of it.
    func ayah(at index: Int) -> Int? {
        let ranges = bodyRanges.merging(numberRanges) { body, number in NSUnionRange(body, number) }
        return ranges.first { NSLocationInRange(index, $0.value) }?.key
    }

    /// The ayah's words and number on this line, as one range.
    func range(of ayah: Int) -> NSRange? {
        switch (bodyRanges[ayah], numberRanges[ayah]) {
        case let (body?, number?): NSUnionRange(body, number)
        case let (body?, nil): body
        case let (nil, number?): number
        case (nil, nil): nil
        }
    }

    /// Offsets of the spaces between words, which an over-wide line narrows.
    var spaceOffsets: [Int] {
        var offsets: [Int] = []
        for (offset, unit) in text.utf16.enumerated() where unit == MushafPageComposer.space { offsets.append(offset) }
        return offsets
    }
}

/// Turns a layout page into the text of its lines, from the bundled ayahs.
nonisolated enum MushafPageComposer {
    static let space: UTF16.CodeUnit = 0x20

    static func compose(_ page: MushafPage, catalog: BundledQuranCatalog) -> [MushafComposedLine] {
        page.lines.map { compose($0, catalog: catalog) }
    }

    static func compose(_ line: MushafLine, catalog: BundledQuranCatalog) -> MushafComposedLine {
        switch line.kind {
        case .surahHeader(let number):
            return MushafComposedLine(kind: .surahHeader, text: catalog.surah(number: number)?.arabicName ?? "")
        case .basmala:
            return MushafComposedLine(kind: .basmala, text: catalog.basmala)
        case .text(let centered):
            var composed = MushafComposedLine(kind: .text(justified: !centered), text: "", naturalWidth: line.naturalWidth)
            var text = ""
            var length = 0
            func append(_ piece: String) -> NSRange {
                let range = NSRange(location: length, length: (piece as NSString).length)
                text += piece
                length += range.length
                return range
            }
            for segment in line.segments {
                guard let verse = catalog.verse(globalAyah: segment.globalAyah) else { continue }
                let words = verse.text.split(separator: " ", omittingEmptySubsequences: false)
                let clamped = segment.words.clamped(to: 0..<words.count)
                if !clamped.isEmpty {
                    if length > 0 { _ = append(" ") }
                    composed.bodyRanges[verse.globalAyah] = append(words[clamped].joined(separator: " "))
                }
                if segment.endsAyah {
                    // The number keeps to its ayah with a no-break space, unless it starts the line.
                    let number = QuranScript.ayahNumber(verse.ayahInSurah)
                    let piece = length > 0 ? number : String(number.drop { $0 == "\u{00A0}" })
                    composed.numberRanges[verse.globalAyah] = append(piece)
                }
            }
            composed.text = text
            return composed
        }
    }
}
