import Foundation
import Observation
import OSLog

/// A translation the app bundles, built by Scripts/BuildTranslation.swift from QuranEnc.com.
nonisolated enum TranslationEdition: String, CaseIterable, Identifiable, Sendable {
    case saheehInternational = "english_saheeh"

    static let `default`: TranslationEdition = .saheehInternational

    var id: String { rawValue }
    var fileName: String { rawValue }

    var title: String {
        switch self {
        case .saheehInternational: "Saheeh International"
        }
    }

    /// The publisher QuranEnc credits for this edition.
    var publisher: String {
        switch self {
        case .saheehInternational: "Noor International Center"
        }
    }

    var sourceURL: URL {
        URL(string: "https://quranenc.com/en/browse/\(rawValue)")!
    }
}

/// Translation text as the app shows it. The bundle keeps QuranEnc's text verbatim.
nonisolated enum TranslationText {
    /// Footnotes aren't shown, so their "[12]" markers are hidden too. Bracketed words such as
    /// "[All]" stay, and so do brackets around a marker: "[It[437] is]" becomes "[It is]".
    static func removingFootnoteMarkers(_ text: String) -> String {
        text.replacing(#/\[\d+\]/#, with: "")
    }
}

nonisolated struct BundledTranslation: Sendable {
    let edition: TranslationEdition
    let version: String
    /// Indexed by global ayah - 1, footnote markers removed.
    let texts: [String]

    init(edition: TranslationEdition, data: Data) throws {
        let decoded: TranslationFile
        do {
            decoded = try JSONDecoder().decode(TranslationFile.self, from: data)
        } catch {
            throw AppError.corruptQuranData("Unable to decode the bundled \(edition.title) translation.")
        }
        guard decoded.key == edition.rawValue, decoded.ayahs.count == QuranCatalogMetrics.ayahCount else {
            throw AppError.corruptQuranData("The bundled \(edition.title) translation is incomplete.")
        }
        self.edition = edition
        version = decoded.version
        texts = decoded.ayahs.map { TranslationText.removingFootnoteMarkers($0.t) }
    }

    static func load(_ edition: TranslationEdition, bundle: Bundle = .main) throws -> BundledTranslation {
        let candidates = [
            bundle.url(forResource: edition.fileName, withExtension: TranslationFileFormat.fileExtension,
                       subdirectory: TranslationFileFormat.subdirectory),
            bundle.url(forResource: edition.fileName, withExtension: TranslationFileFormat.fileExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first else { throw AppError.missingQuranData }
        return try BundledTranslation(edition: edition, data: Data(contentsOf: url))
    }

    func text(globalAyah: Int) -> String? {
        texts.indices.contains(globalAyah - 1) ? texts[globalAyah - 1] : nil
    }
}

/// Loads the translation the first time it's shown, off the main thread.
@MainActor
@Observable
final class TranslationLibrary {
    private(set) var current: BundledTranslation?
    @ObservationIgnored private var loading: Task<BundledTranslation?, Never>?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadIfNeeded(_ edition: TranslationEdition = .default) async {
        guard current?.edition != edition else { return }
        let bundle = bundle
        // Views that appear together share one load.
        let task = loading ?? Task.detached(priority: .userInitiated) {
            do {
                return try BundledTranslation.load(edition, bundle: bundle)
            } catch {
                QuranLog.translation.error("Couldn't load the \(edition.rawValue, privacy: .public) translation: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        loading = task
        let loaded = await task.value
        loading = nil
        if let loaded { current = loaded }
    }
}

nonisolated private enum TranslationFileFormat {
    static let subdirectory = "Translations"
    static let fileExtension = "json"
}

/// Written by Scripts/BuildTranslation.swift; footnotes (`f`) are bundled but not shown.
nonisolated private struct TranslationFile: Decodable, Sendable {
    var key: String
    var version: String
    var ayahs: [TranslationFileAyah]
}

nonisolated private struct TranslationFileAyah: Decodable, Sendable {
    var t: String
}
