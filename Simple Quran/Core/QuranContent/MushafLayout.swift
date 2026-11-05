import CoreGraphics
import Foundation

/// A run of one ayah's words on a mushaf line.
nonisolated struct MushafLineSegment: Equatable, Hashable, Sendable {
    var globalAyah: Int
    /// Indexes into the ayah's bundled words, split on regular spaces.
    var words: Range<Int>
    /// The ayah's number is drawn at the end of this run.
    var endsAyah: Bool
}

/// One of a page's 15 lines.
nonisolated struct MushafLine: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
        case surahHeader(Int)
        case basmala
        case text(centered: Bool)
    }

    var kind: Kind
    var segments: [MushafLineSegment] = []
    /// The line's width at `MushafLayout.measuringSize`, before any justification.
    var naturalWidth: CGFloat?

    /// Stretched edge to edge, like most lines in the printed mushaf.
    var isJustified: Bool { kind == .text(centered: false) }
}

nonisolated struct MushafPage: Equatable, Hashable, Sendable, Identifiable {
    var number: Int
    var lines: [MushafLine]
    var id: Int { number }

    /// The widest justified line, at `MushafLayout.measuringSize`.
    var widestJustifiedWidth: CGFloat {
        lines.filter(\.isJustified).compactMap(\.naturalWidth).max() ?? 0
    }

    var ayahs: Set<Int> { Set(lines.flatMap { $0.segments.map(\.globalAyah) }) }
}

/// Where each line of the 15-line Madani mushaf breaks, pointing at words of the bundled text.
/// Built by Scripts/BuildMushafLayout.swift from QUL's KFGQPC 1405H layout.
nonisolated struct MushafLayout: Sendable {
    static let pageCount = 604
    static let linesPerPage = 15
    /// The size line widths were measured at.
    static let measuringSize: CGFloat = 100

    let edition: String
    let pages: [MushafPage]
    /// Natural widths of every justified line, smallest first.
    let justifiedWidths: [CGFloat]
    private let firstPageByAyah: [Int]
    private let lastPageByAyah: [Int]

    init(data: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw AppError.corruptQuranData("Unable to decode the bundled mushaf layout.")
        }
        guard file.pages.count == Self.pageCount else {
            throw AppError.corruptQuranData("The mushaf layout has \(file.pages.count) pages.")
        }

        var firstPage = Array(repeating: 0, count: QuranCatalogMetrics.ayahCount + 1)
        var lastPage = firstPage
        var pages: [MushafPage] = []
        pages.reserveCapacity(Self.pageCount)
        for (index, filePage) in file.pages.enumerated() {
            let number = index + 1
            let lines = try filePage.lines.map { try $0.line() }
            for segment in lines.flatMap(\.segments) {
                guard segment.globalAyah >= 1, segment.globalAyah <= QuranCatalogMetrics.ayahCount else {
                    throw AppError.corruptQuranData("The mushaf layout names ayah \(segment.globalAyah).")
                }
                if firstPage[segment.globalAyah] == 0 { firstPage[segment.globalAyah] = number }
                lastPage[segment.globalAyah] = number
            }
            pages.append(MushafPage(number: number, lines: lines))
        }

        edition = file.edition
        self.pages = pages
        justifiedWidths = pages.flatMap { $0.lines.filter(\.isJustified).compactMap(\.naturalWidth) }.sorted()
        firstPageByAyah = firstPage
        lastPageByAyah = lastPage
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> MushafLayout {
        let candidates = [
            bundle.url(forResource: BundledLayoutFile.name, withExtension: BundledLayoutFile.fileExtension, subdirectory: "Resources/Quran"),
            bundle.url(forResource: BundledLayoutFile.name, withExtension: BundledLayoutFile.fileExtension, subdirectory: "Quran"),
            bundle.url(forResource: BundledLayoutFile.name, withExtension: BundledLayoutFile.fileExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first else { throw AppError.missingQuranData }
        return try MushafLayout(data: Data(contentsOf: url))
    }

    func page(_ number: Int) -> MushafPage? {
        guard number >= 1, number <= pages.count else { return nil }
        return pages[number - 1]
    }

    /// The page an ayah starts on.
    func page(containing globalAyah: Int) -> Int {
        let clamped = min(max(globalAyah, 1), QuranCatalogMetrics.ayahCount)
        return max(firstPageByAyah[clamped], 1)
    }

    /// Every page holding part of the range, including an ayah that runs onto the next page.
    func pages(touching range: VerseRange) -> ClosedRange<Int> {
        let first = max(firstPageByAyah[range.startGlobalAyah], 1)
        return first...max(lastPageByAyah[range.endGlobalAyah], first)
    }

    /// The justified-line width that this share of lines fits within.
    func justifiedWidth(atPercentile percentile: Double) -> CGFloat {
        guard !justifiedWidths.isEmpty else { return 0 }
        let index = Int((Double(justifiedWidths.count - 1) * min(max(percentile, 0), 1)).rounded())
        return justifiedWidths[index]
    }
}

// MARK: - File

private nonisolated enum BundledLayoutFile {
    static let name = "mushaf-1405"
    static let fileExtension = "json"
}

private nonisolated struct File: Decodable, Sendable {
    var edition: String
    var pages: [FilePage]
}

private nonisolated struct FilePage: Decodable, Sendable {
    var lines: [FileLine]
}

private nonisolated enum FileLineKind: String, Decodable, Sendable {
    case surah
    case basmala
    case text
}

private nonisolated struct FileLine: Decodable, Sendable {
    var k: FileLineKind
    var c: Bool?
    var s: Int?
    var w: Double?
    /// [global ayah, first word, end word (exclusive), 1 when the ayah's number ends here]
    var seg: [[Int]]?

    func line() throws -> MushafLine {
        switch k {
        case .surah:
            guard let s else { throw AppError.corruptQuranData("A mushaf surah header has no surah.") }
            return MushafLine(kind: .surahHeader(s))
        case .basmala:
            return MushafLine(kind: .basmala)
        case .text:
            let segments = try (seg ?? []).map { values in
                guard values.count == 4, values[1] <= values[2] else {
                    throw AppError.corruptQuranData("A mushaf line segment is malformed.")
                }
                return MushafLineSegment(globalAyah: values[0], words: values[1]..<values[2], endsAyah: values[3] == 1)
            }
            return MushafLine(kind: .text(centered: c ?? false), segments: segments, naturalWidth: w.map { CGFloat($0) })
        }
    }
}
