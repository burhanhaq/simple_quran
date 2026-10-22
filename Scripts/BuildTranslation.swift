#!/usr/bin/env swift
// Builds a bundled translation (e.g. Simple Quran/Resources/Translations/english_saheeh.json) from a
// QuranEnc.com CSV download (https://quranenc.com/en/home/d/csv/<key>).
//
// Usage:
//   swift Scripts/BuildTranslation.swift <quranenc.csv> <output.json>
//
// QuranEnc's terms forbid changing the text and ask that its header info be kept, so translations and
// footnotes are bundled verbatim; the app hides footnote markers when it displays them.
// The script stops with an error instead of writing anything when a check fails.
import Foundation

private enum Expected {
    static let ayahCount = 6236
    static let surahCount = 114
    static let columns = ["id", "sura", "aya", "translation", "footnotes"]
    static let headerPrefix = "Translation Info:"
}

private enum HeaderLine {
    static let translationID = "# Translation ID: "
    static let lastUpdate = "# Last update: "
}

// MARK: - Bundled schema (mirrors BundledTranslation's File types)

struct BundledTranslationFile: Codable {
    var key: String
    var version: String
    var info: String
    var ayahs: [BundledTranslationAyah]
}

struct BundledTranslationAyah: Codable {
    var t: String
    var f: String?
}

// MARK: - Helpers

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// RFC 4180 rows: quoted fields may hold commas, newlines and doubled quotes.
private func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var characters = text.makeIterator()
    var pending: Character? = nil
    while let character = pending ?? characters.next() {
        pending = nil
        if inQuotes {
            if character == "\"" {
                if let next = characters.next() {
                    if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                } else { inQuotes = false }
            } else { field.append(character) }
            continue
        }
        switch character {
        case "\"": inQuotes = true
        case ",": row.append(field); field = ""
        // Swift treats "\r\n" as one Character.
        case "\n", "\r\n", "\r":
            row.append(field); field = ""
            rows.append(row); row = []
        default: field.append(character)
        }
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
}

private func headerValue(_ prefix: String, in info: String) -> String? {
    info.split(whereSeparator: \.isNewline).first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
}

/// "2025-06-24 16:37:27 (v1.1.2-csv.1)" → "1.1.2"
private func version(fromLastUpdate line: String) -> String? {
    guard let start = line.range(of: "(v"), let end = line[start.upperBound...].firstIndex(where: { $0 == "-" || $0 == ")" })
    else { return nil }
    return String(line[start.upperBound..<end])
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fail("usage: swift Scripts/BuildTranslation.swift <quranenc.csv> <output.json>")
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

let csv: String
do {
    csv = try String(contentsOf: inputURL, encoding: .utf8)
} catch {
    fail("could not read \(inputURL.path) as UTF-8: \(error)")
}
let rows = parseCSV(csv.hasPrefix("\u{FEFF}") ? String(csv.dropFirst()) : csv)

guard let headerRow = rows.first, let info = headerRow.first, info.hasPrefix(Expected.headerPrefix) else {
    fail("the file doesn't start with QuranEnc's \"\(Expected.headerPrefix)\" block")
}
guard let key = headerValue(HeaderLine.translationID, in: info) else { fail("the header has no translation ID") }
guard let lastUpdate = headerValue(HeaderLine.lastUpdate, in: info), let version = version(fromLastUpdate: lastUpdate) else {
    fail("the header has no version in its last update line")
}
guard rows.count > 1, rows[1] == Expected.columns else {
    fail("expected the columns \(Expected.columns), found \(rows.count > 1 ? rows[1] : [])")
}

let body = rows.dropFirst(2).filter { $0 != [""] }
guard body.count == Expected.ayahCount else { fail("the file has \(body.count) ayahs, expected \(Expected.ayahCount)") }

var issues: [String] = []
var ayahs: [BundledTranslationAyah] = []
var previous = (sura: 0, aya: 0)
var footnoted = 0

for (index, row) in body.enumerated() {
    guard row.count == Expected.columns.count, let id = Int(row[0]), let sura = Int(row[1]), let aya = Int(row[2]) else {
        issues.append("row \(index + 1) is malformed: \(row.prefix(3))")
        continue
    }
    let key = "\(sura):\(aya)"
    if id != index + 1 { issues.append("\(key) has id \(id), expected \(index + 1)") }
    let follows = (sura == previous.sura && aya == previous.aya + 1) || (sura == previous.sura + 1 && aya == 1)
    if !follows { issues.append("\(key) doesn't follow \(previous.sura):\(previous.aya)") }
    previous = (sura, aya)
    let text = row[3]
    let footnotes = row[4]
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("\(key) is empty") }
    if !footnotes.isEmpty { footnoted += 1 }
    ayahs.append(BundledTranslationAyah(t: text, f: footnotes.isEmpty ? nil : footnotes))
}
if previous.sura != Expected.surahCount { issues.append("the last ayah is in surah \(previous.sura)") }
guard issues.isEmpty else { fail(issues.joined(separator: "\n")) }

let output = BundledTranslationFile(key: key, version: version, info: info, ayahs: ayahs)
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]
do {
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(output).write(to: outputURL, options: .atomic)
} catch {
    fail("could not write \(outputURL.path): \(error)")
}
print("wrote \(outputURL.lastPathComponent): \(key) v\(version), \(ayahs.count) ayahs, \(footnoted) with footnotes")
