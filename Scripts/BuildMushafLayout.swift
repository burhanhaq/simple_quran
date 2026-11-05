#!/usr/bin/env swift
// Builds Simple Quran/Resources/Quran/mushaf-1405.json, the 15-line Madani page layout the
// "Mushaf pages" reader draws, from QUL's KFGQPC 1405H layout and word-by-word Hafs text.
//
// Usage:
//   swift Scripts/BuildMushafLayout.swift <qul-layout.db> <qul-words.json> <quran-hafs.json> <font.ttf> <output.json>
//
// <qul-layout.db> is QUL's "KFGQPC V1 layout (1405H print)" sqlite, <qul-words.json> its
// "KFGQPC Hafs script - Word by word" json, and <quran-hafs.json> the app's bundled text.
// Only line breaks come from QUL; each line points at words of the bundled text, so the app
// keeps drawing the text it already ships. Lines also carry their natural width at 100pt in
// the given font, so the app can size pages without measuring every line.
// The script stops with an error instead of writing anything when a check fails.
import CoreText
import Foundation
import SQLite3

private enum Source {
    static let name = "KFGQPC 1405H 15-line Madani layout"
    static let edition = "1405H"
    static let attribution = "Page and line layout of the King Fahd Glorious Quran Printing Complex 1405H Madani print, distributed by QUL (qul.tarteel.ai)."
}

private enum Expected {
    static let pageCount = 604
    static let linesPerPage = 15
    static let ayahCount = 6236
    static let surahCount = 114
    static let surahsWithoutBasmala: Set<Int> = [1, 9]
}

/// Widths are measured at this size and scaled by the app.
private let measuringSize: CGFloat = 100
private let noBreakSpace = "\u{00A0}"
private let arabicIndicDigits = Array("٠١٢٣٤٥٦٧٨٩")

// MARK: - Bundled text (mirrors BundledQuranCatalog's File types)

struct BundledText: Decodable {
    var surahs: [BundleSurah]
}

struct BundleSurah: Decodable {
    var number: Int
    var ayahs: [BundleAyah]
}

struct BundleAyah: Decodable {
    var g: Int
    var n: Int
    var t: String
    var p: Int
}

// MARK: - QUL schema

struct QULWord: Decodable {
    var id: Int
    var surah: String
    var ayah: String
    var text: String
}

private enum QULLineType: String {
    case surahName = "surah_name"
    case basmala = "basmallah"
    case ayah
}

struct QULLine {
    var page: Int
    var line: Int
    var type: String
    var centered: Bool
    var firstWord: Int?
    var lastWord: Int?
    var surah: Int?
}

// MARK: - Output schema (mirrors MushafLayout's File types)

enum LineKind: String, Encodable {
    case surah
    case basmala
    case text
}

struct OutputLayout: Encodable {
    var source: String
    var attribution: String
    var edition: String
    var pages: [OutputPage]
}

struct OutputPage: Encodable {
    var lines: [OutputLine]
}

struct OutputLine: Encodable {
    var k: LineKind
    /// Centered instead of justified; only written when true.
    var c: Bool?
    /// The surah a header names.
    var s: Int?
    /// Natural width at 100pt.
    var w: Double?
    /// [global ayah, first bundled word, end bundled word (exclusive), 1 when the ayah's number ends here]
    var seg: [[Int]]?
}

// MARK: - Helpers

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private func isAyahNumber(_ text: String) -> Bool {
    !text.isEmpty && text.allSatisfy { arabicIndicDigits.contains($0) }
}

private func arabicIndic(_ number: Int) -> String {
    String(String(number).compactMap { $0.wholeNumberValue.map { arabicIndicDigits[$0] } })
}

/// Text without any spacing, for matching QUL's words against the bundled ones.
private func squeezed(_ text: String) -> String {
    String(text.unicodeScalars.filter { !$0.properties.isWhitespace }.map(Character.init))
}

/// The bundled ayah's words: split on regular spaces only, so a no-break space keeps
/// "۞ إِنَّ" one word, matching how the app splits them.
private func bundledWords(_ text: String) -> [String] {
    text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
}

private func readLines(from path: String) -> [QULLine] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { fail("could not open \(path)") }
    defer { sqlite3_close(db) }
    let query = "SELECT page_number, line_number, line_type, is_centered, first_word_id, last_word_id, surah_number FROM pages ORDER BY page_number, line_number"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { fail("\(path) has no pages table in QUL's layout schema") }
    defer { sqlite3_finalize(statement) }

    /// Empty strings and NULLs both mean "no value" in QUL's exports.
    func optionalInt(_ column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, column) else { return nil }
        return Int(String(cString: text).trimmingCharacters(in: .whitespaces))
    }

    var lines: [QULLine] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        lines.append(QULLine(
            page: Int(sqlite3_column_int(statement, 0)),
            line: Int(sqlite3_column_int(statement, 1)),
            type: String(cString: sqlite3_column_text(statement, 2)),
            centered: sqlite3_column_int(statement, 3) != 0,
            firstWord: optionalInt(4),
            lastWord: optionalInt(5),
            surah: optionalInt(6)
        ))
    }
    return lines
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 6 else {
    fail("usage: swift Scripts/BuildMushafLayout.swift <qul-layout.db> <qul-words.json> <quran-hafs.json> <font.ttf> <output.json>")
}
let layoutPath = arguments[1]
let wordsURL = URL(fileURLWithPath: arguments[2])
let bundleURL = URL(fileURLWithPath: arguments[3])
let fontURL = URL(fileURLWithPath: arguments[4])
let outputURL = URL(fileURLWithPath: arguments[5])

let qulWords: [Int: QULWord]
do {
    let decoded = try JSONDecoder().decode([String: QULWord].self, from: Data(contentsOf: wordsURL))
    qulWords = Dictionary(uniqueKeysWithValues: decoded.values.map { ($0.id, $0) })
} catch {
    fail("could not read the QUL words file as {\"s:a:w\": {id, surah, ayah, text, …}}: \(error)")
}
let bundle: BundledText
do {
    bundle = try JSONDecoder().decode(BundledText.self, from: Data(contentsOf: bundleURL))
} catch {
    fail("could not read the bundled text: \(error)")
}
guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first else {
    fail("could not load the font at \(fontURL.path)")
}
let font = CTFontCreateWithFontDescriptor(descriptor, measuringSize, nil)
let qulLines = readLines(from: layoutPath)

guard bundle.surahs.count == Expected.surahCount else { fail("bundled text has \(bundle.surahs.count) surahs") }

var issues: [String] = []

// Bundled ayahs by (surah, ayah), with their words.
struct Ayah {
    var global: Int
    var surah: Int
    var number: Int
    var page: Int
    var words: [String]
}
var ayahs: [String: Ayah] = [:]
for surah in bundle.surahs {
    for ayah in surah.ayahs {
        ayahs["\(surah.number):\(ayah.n)"] = Ayah(global: ayah.g, surah: surah.number, number: ayah.n, page: ayah.p, words: bundledWords(ayah.t))
    }
}
guard ayahs.count == Expected.ayahCount else { fail("bundled text has \(ayahs.count) ayahs") }
let ayahsByGlobal = Dictionary(uniqueKeysWithValues: ayahs.values.map { ($0.global, $0) })

// Map each QUL word to the bundled words it overlaps. Spacing differs in both directions: QUL
// splits some bundled words (لَّوۡ مَا for لَّوۡمَا) and joins others (إِلۡ يَاسِينَ is one QUL word),
// so words are matched by their position in the ayah's text with all spacing removed.
struct WordPlace {
    var ayahKey: String
    /// The bundled words this QUL word is part of; empty for the ayah's number.
    var words: Range<Int>
    var isNumber: Bool
    var startsWord: Bool
    var endsWord: Bool
}
var places: [Int: WordPlace] = [:]
let qulByAyah = Dictionary(grouping: qulWords.values) { "\($0.surah):\($0.ayah)" }
for (key, ayah) in ayahs {
    guard let words = qulByAyah[key]?.sorted(by: { $0.id < $1.id }), let last = words.last else {
        issues.append("\(key) has no QUL words")
        continue
    }
    guard isAyahNumber(last.text), last.text == arabicIndic(ayah.number) else {
        issues.append("\(key) doesn't end with its number in the QUL words")
        continue
    }
    places[last.id] = WordPlace(ayahKey: key, words: ayah.words.count..<ayah.words.count, isNumber: true, startsWord: true, endsWord: true)

    // Where each bundled word starts and ends in the spacing-free text.
    let bundledScalars = ayah.words.map { Array(squeezed($0).unicodeScalars) }
    var bounds: [Int] = [0]
    for scalars in bundledScalars { bounds.append(bounds[bounds.count - 1] + scalars.count) }
    let qulScalars = words.dropLast().map { Array(squeezed($0.text).unicodeScalars) }
    guard qulScalars.joined().elementsEqual(bundledScalars.joined()) else {
        issues.append("\(key): QUL words don't spell the bundled text")
        continue
    }
    var offset = 0
    for (word, scalars) in zip(words.dropLast(), qulScalars) {
        let end = offset + scalars.count
        let first = bounds.lastIndex { $0 <= offset }!
        let last = bounds.firstIndex { $0 >= end }!
        places[word.id] = WordPlace(
            ayahKey: key,
            words: first..<last,
            isNumber: false,
            startsWord: bounds.contains(offset),
            endsWord: bounds.contains(end)
        )
        offset = end
    }
}

// Build pages. Lines must cover every QUL word once, in order.
var pages: [Int: [OutputLine]] = [:]
var nextWord = 1
var firstPageOfAyah: [String: Int] = [:]
var headers: [Int] = []
var basmalaSurahs: [Int] = []
var lastHeader: Int?
var characters = Set<Unicode.Scalar>()

func measure(_ text: String) -> Double {
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    return (CTLineGetTypographicBounds(line, nil, nil, nil) * 100).rounded() / 100
}

for line in qulLines {
    let place = "page \(line.page) line \(line.line)"
    switch QULLineType(rawValue: line.type) {
    case .surahName:
        guard let surah = line.surah else { issues.append("\(place): surah header without a surah"); continue }
        headers.append(surah)
        lastHeader = surah
        pages[line.page, default: []].append(OutputLine(k: .surah, s: surah))
    case .basmala:
        if let surah = lastHeader { basmalaSurahs.append(surah) } else { issues.append("\(place): basmala before any surah header") }
        pages[line.page, default: []].append(OutputLine(k: .basmala))
    case .ayah:
        guard let first = line.firstWord, let last = line.lastWord, first <= last else {
            issues.append("\(place): ayah line without a word range")
            continue
        }
        if first != nextWord { issues.append("\(place) starts at word \(first), expected \(nextWord)") }
        nextWord = last + 1

        var segments: [[Int]] = []
        var text = ""
        for id in first...last {
            guard let wordPlace = places[id], let ayah = ayahs[wordPlace.ayahKey] else {
                issues.append("\(place): word \(id) has no bundled place")
                continue
            }
            if firstPageOfAyah[wordPlace.ayahKey] == nil { firstPageOfAyah[wordPlace.ayahKey] = line.page }
            if segments.last?[0] != ayah.global {
                if !wordPlace.startsWord {
                    issues.append("\(place) starts inside bundled word \(wordPlace.words.lowerBound + 1) of \(wordPlace.ayahKey)")
                }
                segments.append([ayah.global, wordPlace.words.lowerBound, wordPlace.words.lowerBound, 0])
            }
            if wordPlace.isNumber {
                segments[segments.count - 1][3] = 1
            } else {
                segments[segments.count - 1][2] = wordPlace.words.upperBound
                if id == last, !wordPlace.endsWord {
                    issues.append("\(place) ends inside bundled word \(wordPlace.words.upperBound) of \(wordPlace.ayahKey)")
                }
            }
        }
        // The same text the app draws: words joined by spaces, the number after a no-break space
        // (none when the number starts the line).
        for segment in segments {
            guard let ayah = ayahsByGlobal[segment[0]] else { continue }
            let body = ayah.words[segment[1]..<segment[2]].joined(separator: " ")
            if !body.isEmpty { text += (text.isEmpty ? "" : " ") + body }
            if segment[3] == 1 { text += (text.isEmpty ? "" : noBreakSpace) + arabicIndic(ayah.number) }
        }
        characters.formUnion(text.unicodeScalars)
        pages[line.page, default: []].append(OutputLine(k: .text, c: line.centered ? true : nil, w: measure(text), seg: segments))
    case nil:
        issues.append("\(place): unknown line type \(line.type)")
    }
}
if nextWord - 1 != qulWords.count { issues.append("lines cover \(nextWord - 1) of \(qulWords.count) words") }

// Page breaks must agree with the bundled page numbers the app navigates by.
let pageMismatches = ayahs.filter { firstPageOfAyah[$0.key] != $0.value.page }.map(\.key).sorted()
if !pageMismatches.isEmpty {
    issues.append("\(pageMismatches.count) ayahs start on a different page than the bundled text says, e.g. \(pageMismatches.prefix(5))")
}
if pages.count != Expected.pageCount { issues.append("layout has \(pages.count) pages") }
for (page, lines) in pages where lines.count > Expected.linesPerPage { issues.append("page \(page) has \(lines.count) lines") }
if headers != Array(1...Expected.surahCount) { issues.append("surah headers aren't 1…\(Expected.surahCount) in order") }
let expectedBasmalas = (1...Expected.surahCount).filter { !Expected.surahsWithoutBasmala.contains($0) }
if basmalaSurahs != expectedBasmalas { issues.append("basmala lines don't match the surahs that open with one") }

// Every character must exist in the font, or iOS silently draws it in another font.
for scalar in characters where !scalar.properties.isWhitespace {
    var units = Array(String(scalar).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    if !CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) {
        issues.append(String(format: "the font has no glyph for U+%04X", scalar.value))
    }
}

guard issues.isEmpty else { fail(issues.prefix(40).joined(separator: "\n")) }

let output = OutputLayout(
    source: Source.name,
    attribution: Source.attribution,
    edition: Source.edition,
    pages: (1...Expected.pageCount).map { OutputPage(lines: pages[$0] ?? []) }
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
do {
    try encoder.encode(output).write(to: outputURL, options: .atomic)
} catch {
    fail("could not write \(outputURL.path): \(error)")
}
let lineCount = pages.values.reduce(0) { $0 + $1.count }
print("wrote \(outputURL.lastPathComponent): \(pages.count) pages, \(lineCount) lines, \(qulWords.count) QUL words onto \(ayahs.count) ayahs")
