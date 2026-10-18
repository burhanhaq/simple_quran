import Foundation

/// How much of a Madani mushaf page one memorize piece covers.
nonisolated enum PieceSize: String, CaseIterable, Identifiable, Sendable {
    case quarterPage
    case halfPage
    case fullPage

    static let `default` = PieceSize.halfPage

    var id: String { rawValue }

    var partsPerPage: Int {
        switch self {
        case .quarterPage: 4
        case .halfPage: 2
        case .fullPage: 1
        }
    }

    var title: String {
        switch self {
        case .quarterPage: String(localized: "Quarter page")
        case .halfPage: String(localized: "Half page")
        case .fullPage: String(localized: "Full page")
        }
    }
}

/// Memorize pieces for the whole Quran, laid out on the 604-page Madani mushaf so a piece
/// matches what the user sees on the page. Pieces split a page at the ayah boundary nearest
/// each quarter or half of its text, never split an ayah, never cross a surah, and keep a
/// short surah whole. Built once with the catalog; lookups are constant time.
nonisolated struct QuranPieces: Sendable {
    /// A surah up to this many pieces long stays one piece.
    static let wholeSurahAllowance = 1.25
    /// A piece lighter than this share of a piece on its own page joins its neighbour in the same surah.
    /// Measuring against its own page keeps the short decorated opening pages whole.
    static let sliverShare = 0.35

    /// For each size, the first and last global ayah of the piece holding each ayah (index = globalAyah - 1).
    private let starts: [PieceSize: [Int]]
    private let ends: [PieceSize: [Int]]

    init(verses: [QuranVerse]) {
        let weights = verses.map(Self.weight)
        var starts: [PieceSize: [Int]] = [:]
        var ends: [PieceSize: [Int]] = [:]
        for size in PieceSize.allCases {
            var startOf = Array(repeating: 0, count: verses.count)
            var endOf = Array(repeating: 0, count: verses.count)
            for cell in Self.cells(verses: verses, weights: weights, size: size) {
                for index in cell {
                    startOf[index] = verses[cell.lowerBound].globalAyah
                    endOf[index] = verses[cell.upperBound].globalAyah
                }
            }
            starts[size] = startOf
            ends[size] = endOf
        }
        self.starts = starts
        self.ends = ends
    }

    func piece(containing globalAyah: Int, size: PieceSize) -> VerseRange? {
        guard let startOf = starts[size], let endOf = ends[size], startOf.indices.contains(globalAyah - 1) else { return nil }
        return .clamped(start: startOf[globalAyah - 1], end: endOf[globalAyah - 1])
    }

    /// Letters only, so diacritics and spacing don't make an ayah look longer than it reads.
    private static func weight(_ verse: QuranVerse) -> Double {
        let letters = verse.text.unicodeScalars.reduce(0) { count, scalar in
            scalar.properties.generalCategory == .nonspacingMark || scalar.properties.isWhitespace ? count : count + 1
        }
        return Double(max(letters, 1))
    }

    /// Index ranges into `verses`, one per piece, in order.
    private static func cells(verses: [QuranVerse], weights: [Double], size: PieceSize) -> [ClosedRange<Int>] {
        guard !verses.isEmpty else { return [] }
        let pageCount = Set(verses.map(\.page)).count
        let typicalPiece = weights.reduce(0, +) / Double(max(pageCount, 1)) / Double(size.partsPerPage)

        // Cut after these indices: at every page and surah end, and nearest each fraction of a page.
        var cuts = Set<Int>()
        var pageStart = 0
        for index in verses.indices {
            let isLast = index == verses.count - 1
            if !isLast && verses[index + 1].surahNumber != verses[index].surahNumber { cuts.insert(index) }
            guard isLast || verses[index + 1].page != verses[index].page else { continue }
            cuts.insert(index)
            let page = pageStart...index
            let total = page.reduce(0) { $0 + weights[$1] }
            for part in 1..<size.partsPerPage {
                let target = total * Double(part) / Double(size.partsPerPage)
                var running = 0.0
                var best: (index: Int, distance: Double)?
                for candidate in page.dropLast() {
                    running += weights[candidate]
                    let distance = abs(running - target)
                    if best == nil || distance < best!.distance { best = (candidate, distance) }
                }
                if let best { cuts.insert(best.index) }
            }
            pageStart = index + 1
        }

        var pageWeights: [Int: Double] = [:]
        for index in verses.indices { pageWeights[verses[index].page, default: 0] += weights[index] }
        let pieceOnPage = verses.map { (pageWeights[$0.page] ?? 1) / Double(size.partsPerPage) }

        var result: [ClosedRange<Int>] = []
        var surahStart = 0
        for index in verses.indices where index == verses.count - 1 || verses[index + 1].surahNumber != verses[index].surahNumber {
            result += surahCells(surahStart...index, cuts: cuts, weights: weights, typicalPiece: typicalPiece, pieceOnPage: pieceOnPage)
            surahStart = index + 1
        }
        return result
    }

    private static func surahCells(_ surah: ClosedRange<Int>, cuts: Set<Int>, weights: [Double], typicalPiece: Double,
                                   pieceOnPage: [Double]) -> [ClosedRange<Int>] {
        let surahWeight = surah.reduce(0) { $0 + weights[$1] }
        if surahWeight <= typicalPiece * wholeSurahAllowance { return [surah] }

        var cells: [ClosedRange<Int>] = []
        var start = surah.lowerBound
        for index in surah where cuts.contains(index) || index == surah.upperBound {
            cells.append(start...index)
            start = index + 1
        }

        func weight(_ cell: ClosedRange<Int>) -> Double { cell.reduce(0) { $0 + weights[$1] } }
        func share(_ cell: ClosedRange<Int>) -> Double { weight(cell) / pieceOnPage[cell.lowerBound] }
        while cells.count > 1, let lightest = cells.indices.min(by: { share(cells[$0]) < share(cells[$1]) }),
              share(cells[lightest]) < sliverShare {
            let neighbour: Int
            if lightest == 0 { neighbour = 1 }
            else if lightest == cells.count - 1 { neighbour = lightest - 1 }
            else { neighbour = weight(cells[lightest - 1]) <= weight(cells[lightest + 1]) ? lightest - 1 : lightest + 1 }
            let low = min(lightest, neighbour)
            cells[low] = cells[low].lowerBound...cells[low + 1].upperBound
            cells.remove(at: low + 1)
        }
        return cells
    }
}
