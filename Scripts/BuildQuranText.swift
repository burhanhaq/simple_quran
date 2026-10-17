#!/usr/bin/env swift
// Builds Simple Quran/Resources/Quran/quran-hafs.json from the King Fahd Complex (QPC Hafs) text
// distributed by QUL, keeping the app's existing surah metadata, page, juz and sajdah data.
//
// Usage:
//   swift Scripts/BuildQuranText.swift <qul-qpc-hafs.json> <metadata.json> <font.ttf> <output.json>
//
// <metadata.json> is any file in the app's bundled schema (the current bundled text works).
// The script stops with an error instead of writing anything when a check fails.
import CoreText
import Foundation

private enum Source {
    static let name = "KFGQPC Hafs"
    static let attribution = "Quran text and HAFS Uthmanic Script font by King Fahd Glorious Quran Printing Complex (qurancomplex.gov.sa), distributed by QUL (qul.tarteel.ai). Bundled verbatim except removing the ayah number that ends each ayah."
}

private enum Expected {
    static let ayahCount = 6236
    static let surahCount = 114
    static let surahsWithoutBasmala: Set<Int> = [1, 9]
}

// MARK: - Bundled schema (mirrors BundledQuranCatalog's File types)

struct BundledText: Codable {
    var source: String?
    var attribution: String?
    var surahs: [BundleSurah]
}

struct BundleSurah: Codable {
    var number: Int
    var arabicName: String
    var englishName: String
    var translation: String
    var revelation: String
    var ayahs: [BundleAyah]
}

struct BundleAyah: Codable {
    var g: Int
    var n: Int
    var t: String
    var j: Int
    var p: Int
    var s: Int?
}

// MARK: - QUL schema

struct QULVerse: Decodable {
    var verse_key: String
    var text: String
    var page_number: Int?
    var juz_number: Int?
}

// MARK: - Helpers


private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private let arabicIndicDigits = "٠١٢٣٤٥٦٧٨٩"

private func arabicIndicValue(_ text: Substring) -> Int? {
    var value = 0
    for character in text {
        guard let index = arabicIndicDigits.firstIndex(of: character) else { return nil }
        value = value * 10 + arabicIndicDigits.distance(from: arabicIndicDigits.startIndex, to: index)
    }
    return text.isEmpty ? nil : value
}

/// Removes a trailing " ١٢٣" (space or no-break space, then Arabic-Indic digits) and returns its value.
private func strippingAyahNumber(_ text: String) -> (body: String, number: Int?) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let separator = trimmed.lastIndex(where: { $0 == " " || $0 == "\u{00A0}" }),
          let number = arabicIndicValue(trimmed[trimmed.index(after: separator)...])
    else { return (trimmed, nil) }
    let body = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
    return (body, number)
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("usage: swift Scripts/BuildQuranText.swift <qul-qpc-hafs.json> <metadata.json> <font.ttf> <output.json>")
}
let qulURL = URL(fileURLWithPath: arguments[1])
let metadataURL = URL(fileURLWithPath: arguments[2])
let fontURL = URL(fileURLWithPath: arguments[3])
let outputURL = URL(fileURLWithPath: arguments[4])

let qul: [String: QULVerse]
do {
    qul = try JSONDecoder().decode([String: QULVerse].self, from: Data(contentsOf: qulURL))
} catch {
    fail("could not read the QUL file as {\"s:a\": {verse_key, text, …}}: \(error)")
}
let metadata: BundledText
do {
    metadata = try JSONDecoder().decode(BundledText.self, from: Data(contentsOf: metadataURL))
} catch {
    fail("could not read the metadata file: \(error)")
}
guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor])?.first else {
    fail("could not load the font at \(fontURL.path)")
}
let font = CTFontCreateWithFontDescriptor(descriptor, 28, nil)

guard qul.count == Expected.ayahCount else { fail("QUL file has \(qul.count) ayahs, expected \(Expected.ayahCount)") }
guard metadata.surahs.count == Expected.surahCount else { fail("metadata has \(metadata.surahs.count) surahs") }

var issues: [String] = []
var pageMismatches: [String] = []
var juzMismatches: [String] = []
var strippedNumbers = 0
var surahs: [BundleSurah] = []

for surah in metadata.surahs {
    var ayahs: [BundleAyah] = []
    for ayah in surah.ayahs {
        let key = "\(surah.number):\(ayah.n)"
        guard let verse = qul[key] else {
            issues.append("\(key) is missing from the QUL file")
            continue
        }
        let (body, number) = strippingAyahNumber(verse.text)
        if let number {
            strippedNumbers += 1
            if number != ayah.n { issues.append("\(key) ends with number \(number)") }
        }
        if body.isEmpty { issues.append("\(key) is empty") }
        if let page = verse.page_number, page != ayah.p { pageMismatches.append("\(key) QUL page \(page) vs \(ayah.p)") }
        if let juz = verse.juz_number, juz != ayah.j { juzMismatches.append("\(key) QUL juz \(juz) vs \(ayah.j)") }
        ayahs.append(BundleAyah(g: ayah.g, n: ayah.n, t: body, j: ayah.j, p: ayah.p, s: ayah.s))
    }
    surahs.append(BundleSurah(
        number: surah.number,
        arabicName: surah.arabicName,
        englishName: surah.englishName,
        translation: surah.translation,
        revelation: surah.revelation,
        ayahs: ayahs
    ))
}

// The basmala is shown above surahs, never inside their first ayah.
let basmala = surahs[0].ayahs[0].t
let basmalaOpening = basmala.split(separator: " ").prefix(2).joined(separator: " ")
for surah in surahs where !Expected.surahsWithoutBasmala.contains(surah.number) {
    if surah.ayahs.first?.t.hasPrefix(basmalaOpening) == true {
        issues.append("\(surah.number):1 starts with a basmala")
    }
}

// Every character must exist in the font, or iOS silently draws it in another font.
var characters = Set<Unicode.Scalar>()
for surah in surahs { for ayah in surah.ayahs { characters.formUnion(ayah.t.unicodeScalars) } }
for scalar in characters where !scalar.properties.isWhitespace {
    var units = Array(String(scalar).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    if !CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) {
        issues.append(String(format: "the font has no glyph for U+%04X", scalar.value))
    }
}

let total = surahs.reduce(0) { $0 + $1.ayahs.count }
if total != Expected.ayahCount { issues.append("built \(total) ayahs") }

if !pageMismatches.isEmpty { print("note: kept existing page numbers for \(pageMismatches.count) ayahs, e.g. \(pageMismatches.prefix(3))") }
if !juzMismatches.isEmpty { print("note: kept existing juz numbers for \(juzMismatches.count) ayahs, e.g. \(juzMismatches.prefix(3))") }
guard issues.isEmpty else { fail(issues.joined(separator: "\n")) }

let output = BundledText(source: Source.name, attribution: Source.attribution, surahs: surahs)
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]
do {
    try encoder.encode(output).write(to: outputURL, options: .atomic)
} catch {
    fail("could not write \(outputURL.path): \(error)")
}
print("wrote \(outputURL.lastPathComponent): \(surahs.count) surahs, \(total) ayahs, \(characters.count) distinct characters, \(strippedNumbers) ayah numbers removed")
