import Foundation

/// The reciters the app offers and where their audio lives. Bundled as Resources/Audio/reciters.json;
/// the same file can be published remotely (see `ReciterCatalogStore`) to change reciters or hosts
/// without an app update. Check every change with Scripts/CheckReciterAudio.swift first.
nonisolated struct ReciterCatalog: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    var schemaVersion: Int
    var host: URL
    var defaultReciterID: String
    var reciters: [Reciter]

    enum ValidationError: Error, Equatable {
        case unsupportedSchema(Int)
        case insecureHost(String)
        case empty
        case duplicateID(String)
        case invalidQuality(String)
        case unknownDefault(String)
    }

    /// Used only if the bundled file is missing, so audio always has a reciter.
    static let fallback = ReciterCatalog(
        schemaVersion: supportedSchemaVersion,
        host: AlQuranCloudAudioSource.defaultHost,
        defaultReciterID: ReciterID.sudais,
        reciters: [.sudais]
    )

    var defaultReciter: Reciter {
        reciter(id: defaultReciterID) ?? reciters.first ?? .sudais
    }

    func reciter(id: String?) -> Reciter? {
        guard let id else { return nil }
        return reciters.first { $0.id == id }
    }

    func audioSource(for reciter: Reciter) -> AlQuranCloudAudioSource {
        AlQuranCloudAudioSource(reciter: reciter, host: host)
    }

    func validated() throws -> Self {
        guard schemaVersion <= Self.supportedSchemaVersion else { throw ValidationError.unsupportedSchema(schemaVersion) }
        guard !reciters.isEmpty else { throw ValidationError.empty }
        for url in [host] + reciters.compactMap(\.host) where url.scheme != "https" {
            throw ValidationError.insecureHost(url.absoluteString)
        }
        var seen = Set<String>()
        for reciter in reciters {
            guard seen.insert(reciter.id).inserted else { throw ValidationError.duplicateID(reciter.id) }
            guard reciter.qualityKbps > 0 else { throw ValidationError.invalidQuality(reciter.id) }
        }
        guard seen.contains(defaultReciterID) else { throw ValidationError.unknownDefault(defaultReciterID) }
        return self
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data).validated()
    }

    static func bundled(_ bundle: Bundle = .main) throws -> Self {
        let candidates = [
            bundle.url(forResource: File.name, withExtension: File.fileExtension, subdirectory: "Resources/Audio"),
            bundle.url(forResource: File.name, withExtension: File.fileExtension, subdirectory: "Audio"),
            bundle.url(forResource: File.name, withExtension: File.fileExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first else { throw AppError.audioUnavailable }
        return try decode(Data(contentsOf: url))
    }

    enum File {
        static let name = "reciters"
        static let fileExtension = "json"
    }
}
