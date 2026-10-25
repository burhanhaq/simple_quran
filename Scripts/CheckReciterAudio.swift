#!/usr/bin/env swift
// Checks that every ayah of every reciter in a reciter catalog (Simple Quran/Resources/Audio/reciters.json,
// or the published copy) is really on the CDN, before the catalog ships or is published.
//
// Usage:
//   swift Scripts/CheckReciterAudio.swift <reciters.json>                      every reciter in the catalog
//   swift Scripts/CheckReciterAudio.swift <reciters.json> --reciter ar.husary  one of them
//   swift Scripts/CheckReciterAudio.swift <reciters.json> --catalog-entry '{"id":"ar.abdulsamad",
//       "englishName":"Abdul Basit","arabicName":"عبد الباسط","qualityKbps":64}'  a candidate not in the catalog yet
//   swift Scripts/CheckReciterAudio.swift <reciters.json> --probe-bitrates     which CDN folders each reciter has
//
// Each ayah is fetched with `Range: bytes=0-3`, which returns its size and first bytes in one small request.
// An ayah fails when it doesn't answer 200/206, is smaller than the app's minimum, or doesn't start like an MP3
// (an ID3 tag or an MPEG frame sync). The CDN has answered 200 with error pages and random bytes before, so
// status alone proves nothing. A content type other than audio/mpeg is only a warning: valid files are
// sometimes labelled application/octet-stream. Exits non-zero when any ayah fails.
import Foundation

private enum Expected {
    static let ayahCount = 6236
    /// AudioFileStore.minimumPlayableBytes
    static let minimumBytes: Int64 = 1_000
    static let contentType = "audio/mpeg"
    static let probeFolders = [32, 40, 48, 64, 128, 192]
    /// How far the catalog's averageAyahBytes may drift from the measured average before it's flagged.
    static let averageTolerance = 0.1
    /// On a cold cache the CDN can report its 1 MiB slice as a ranged file's total size.
    static let cdnSliceBytes: Int64 = 1 << 20
}

private enum Network {
    static let concurrency = 16
    static let attempts = 3
    static let timeout: TimeInterval = 30
}

// MARK: - Catalog schema (mirrors ReciterCatalog and Reciter)

struct Catalog: Codable {
    var schemaVersion: Int
    var host: URL
    var defaultReciterID: String
    var reciters: [CatalogReciter]
}

struct CatalogReciter: Codable {
    var id: String
    var englishName: String
    var arabicName: String
    var qualityKbps: Int
    var averageAyahBytes: Int64?
    var host: URL?
}

// MARK: - Helpers

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

private enum Failure: String {
    case status, small = "small", notMP3 = "not-mp3", network
}

private struct AyahResult {
    var ayah: Int
    var bytes: Int64 = 0
    var contentType: String?
    var failure: (kind: Failure, detail: String)?
}

private let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpMaximumConnectionsPerHost = Network.concurrency
    configuration.timeoutIntervalForRequest = Network.timeout
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
}()

private func url(host: URL, folder: Int, reciterID: String, ayah: Int) -> URL {
    host.appending(path: "\(folder)").appending(path: reciterID).appending(path: "\(ayah).mp3")
}

private func startsLikeMP3(_ data: Data) -> Bool {
    let bytes = [UInt8](data.prefix(3))
    guard bytes.count == 3 else { return false }
    return bytes == Array("ID3".utf8) || (bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0)
}

/// "bytes 0-3/52552" → 52552
private func totalSize(contentRange: String?) -> Int64? {
    contentRange?.split(separator: "/").last.flatMap { Int64($0) }
}

private func headSize(_ url: URL) async -> Int64? {
    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    guard let (_, response) = try? await session.data(for: request),
          let length = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length")
    else { return nil }
    return Int64(length)
}

private func check(_ url: URL, ayah: Int) async -> AyahResult {
    var request = URLRequest(url: url)
    request.setValue("bytes=0-3", forHTTPHeaderField: "Range")
    var lastError = ""
    for attempt in 1...Network.attempts {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode >= 500, attempt < Network.attempts { continue }
            var result = AyahResult(ayah: ayah, contentType: http.mimeType)
            guard http.statusCode == 200 || http.statusCode == 206 else {
                result.failure = (.status, "\(http.statusCode)")
                return result
            }
            result.bytes = http.statusCode == 206
                ? totalSize(contentRange: http.value(forHTTPHeaderField: "Content-Range")) ?? 0
                : Int64(data.count)
            if result.bytes == Expected.cdnSliceBytes, let confirmed = await headSize(url) {
                result.bytes = confirmed
            }
            if result.bytes < Expected.minimumBytes {
                result.failure = (.small, "\(result.bytes) B")
            } else if !startsLikeMP3(data) {
                result.failure = (.notMP3, data.prefix(4).map { String(format: "%02x", $0) }.joined())
            }
            return result
        } catch {
            lastError = error.localizedDescription
        }
    }
    return AyahResult(ayah: ayah, failure: (.network, lastError))
}

private func checkAll(host: URL, folder: Int, reciterID: String, ayahs: ClosedRange<Int>) async -> [AyahResult] {
    await withTaskGroup(of: AyahResult.self) { group in
        var pending = ayahs.makeIterator()
        var results: [AyahResult] = []
        for _ in 0..<Network.concurrency {
            guard let ayah = pending.next() else { break }
            group.addTask { await check(url(host: host, folder: folder, reciterID: reciterID, ayah: ayah), ayah: ayah) }
        }
        for await result in group {
            results.append(result)
            if let ayah = pending.next() {
                group.addTask { await check(url(host: host, folder: folder, reciterID: reciterID, ayah: ayah), ayah: ayah) }
            }
        }
        return results.sorted { $0.ayah < $1.ayah }
    }
}

private func megabytes(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_000_000) }

/// Prints the report for one reciter and returns whether every ayah passed.
private func report(_ reciter: CatalogReciter, results: [AyahResult]) -> Bool {
    let passed = results.filter { $0.failure == nil }
    let failed = results.filter { $0.failure != nil }
    let total = passed.reduce(0) { $0 + $1.bytes }
    let average = passed.isEmpty ? 0 : total / Int64(passed.count)
    print("\(reciter.id) @\(reciter.qualityKbps): \(passed.count)/\(results.count) ok, \(megabytes(total)), average \(average) B/ayah")
    if let smallest = passed.min(by: { $0.bytes < $1.bytes }), let largest = passed.max(by: { $0.bytes < $1.bytes }) {
        print("  smallest ayah \(smallest.ayah) (\(smallest.bytes) B), largest ayah \(largest.ayah) (\(largest.bytes) B)")
    }
    if let listed = reciter.averageAyahBytes, listed > 0, !passed.isEmpty,
       abs(Double(average - listed)) / Double(listed) > Expected.averageTolerance {
        print("  warning: catalog averageAyahBytes is \(listed); measured \(average)")
    } else if reciter.averageAyahBytes == nil, !passed.isEmpty {
        print("  note: set averageAyahBytes to \(average)")
    }
    let relabelled = Dictionary(grouping: passed.filter { $0.contentType != Expected.contentType }) { $0.contentType ?? "none" }
    for (type, ayahs) in relabelled.sorted(by: { $0.key < $1.key }) {
        print("  warning: \(ayahs.count) served as \(type): \(ayahs.prefix(20).map { "\($0.ayah)" }.joined(separator: " "))")
    }
    for (kind, ayahs) in Dictionary(grouping: failed, by: { $0.failure!.kind.rawValue }).sorted(by: { $0.key < $1.key }) {
        let list = ayahs.map { "\($0.ayah)(\($0.failure!.detail))" }.joined(separator: " ")
        print("  FAILED \(kind) ×\(ayahs.count): \(list)")
    }
    return failed.isEmpty
}

// MARK: - Main

var arguments = Array(CommandLine.arguments.dropFirst())
guard let catalogPath = arguments.first, !catalogPath.hasPrefix("--") else {
    fail("usage: swift Scripts/CheckReciterAudio.swift <reciters.json> [--reciter <id> | --catalog-entry '<json>'] [--probe-bitrates]")
}
arguments.removeFirst()

private func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let catalog: Catalog
do {
    catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: catalogPath)))
} catch {
    fail("could not read \(catalogPath): \(error)")
}

var reciters = catalog.reciters
if let id = option("--reciter") {
    reciters = reciters.filter { $0.id == id }
    guard !reciters.isEmpty else { fail("\(id) isn't in \(catalogPath)") }
}
if let entry = option("--catalog-entry") {
    do {
        reciters = [try JSONDecoder().decode(CatalogReciter.self, from: Data(entry.utf8))]
    } catch {
        fail("--catalog-entry isn't a reciter: \(error)")
    }
}

if arguments.contains("--probe-bitrates") {
    for reciter in reciters {
        var folders: [Int] = []
        for folder in Expected.probeFolders {
            let host = reciter.host ?? catalog.host
            if await check(url(host: host, folder: folder, reciterID: reciter.id, ayah: 1), ayah: 1).failure == nil {
                folders.append(folder)
            }
        }
        print("\(reciter.id): folders with ayah 1 = \(folders.map(String.init).joined(separator: ", "))")
    }
    exit(0)
}

var allPassed = true
for reciter in reciters {
    let results = await checkAll(
        host: reciter.host ?? catalog.host,
        folder: reciter.qualityKbps,
        reciterID: reciter.id,
        ayahs: 1...Expected.ayahCount
    )
    allPassed = report(reciter, results: results) && allPassed
}
if !allPassed { fail("some ayahs are missing or aren't audio; don't ship this catalog as is") }
print("all \(reciters.count) reciters complete")
