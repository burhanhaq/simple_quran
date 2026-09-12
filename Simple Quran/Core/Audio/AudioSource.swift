import Foundation

nonisolated struct Reciter: Equatable, Hashable, Sendable, Identifiable {
    var id: String
    var englishName: String
    var arabicName: String
    var qualityKbps: Int

    static let sudais = Reciter(
        id: "ar.sudais",
        englishName: "Abdul Rahman Al-Sudais",
        arabicName: "عبدالرحمن السديس",
        qualityKbps: 192
    )
}

nonisolated protocol AudioSource: Sendable {
    var reciter: Reciter { get }
    func remoteURL(for globalAyah: Int) throws -> URL
    var estimatedBytesPerAyah: Int64 { get }
}

nonisolated struct AlQuranCloudAudioSource: AudioSource {
    var reciter: Reciter = .sudais
    var host: URL = URL(string: "https://cdn.islamic.network/quran/audio")!

    var estimatedBytesPerAyah: Int64 { 28_000 }

    func remoteURL(for globalAyah: Int) throws -> URL {
        guard (1...QuranCatalogMetrics.ayahCount).contains(globalAyah) else {
            throw AppError.invalidRange
        }
        return host
            .appending(path: "\(reciter.qualityKbps)")
            .appending(path: reciter.id)
            .appending(path: "\(globalAyah).mp3")
    }
}
