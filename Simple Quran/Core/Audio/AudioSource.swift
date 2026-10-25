import Foundation

/// Reciter IDs the app refers to by name; every other reciter comes from the catalog.
nonisolated enum ReciterID {
    static let sudais = "ar.abdurrahmaansudais"
    static let husary = "ar.husary"
}

nonisolated struct Reciter: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var englishName: String
    var arabicName: String
    /// The CDN folder the files live in. Usually the bitrate, but not always: Maher Al-Muaiqly's
    /// complete set sits in the 128 folder at 64 kbps. Scripts/CheckReciterAudio.swift verifies it.
    var qualityKbps: Int
    /// Measured by Scripts/CheckReciterAudio.swift, for download size estimates.
    var averageAyahBytes: Int64?
    /// Overrides the catalog host when this reciter's files live elsewhere.
    var host: URL?

    static let sudais = Reciter(
        id: ReciterID.sudais,
        englishName: "Abdul Rahman Al-Sudais",
        arabicName: "عبدالرحمن السديس",
        qualityKbps: 64,
        averageAyahBytes: 98_000
    )
}

nonisolated protocol AudioSource: Sendable {
    var reciter: Reciter { get }
    func remoteURL(for globalAyah: Int) throws -> URL
    var estimatedBytesPerAyah: Int64 { get }
}

/// Files laid out as `{host}/{qualityKbps}/{reciterID}/{globalAyah}.mp3`, as on cdn.islamic.network.
nonisolated struct AlQuranCloudAudioSource: AudioSource, Equatable {
    static let defaultHost = URL(string: "https://cdn.islamic.network/quran/audio")!
    /// A conservative display estimate for reciters the catalog hasn't measured.
    static let fallbackBytesPerAyah: Int64 = 96_000

    var reciter: Reciter = .sudais
    /// The catalog's host; a reciter with its own host overrides it.
    var host: URL = Self.defaultHost

    var estimatedBytesPerAyah: Int64 { reciter.averageAyahBytes ?? Self.fallbackBytesPerAyah }

    func remoteURL(for globalAyah: Int) throws -> URL {
        guard (1...QuranCatalogMetrics.ayahCount).contains(globalAyah) else {
            throw AppError.invalidRange
        }
        return (reciter.host ?? host)
            .appending(path: "\(reciter.qualityKbps)")
            .appending(path: reciter.id)
            .appending(path: "\(globalAyah).mp3")
    }
}
