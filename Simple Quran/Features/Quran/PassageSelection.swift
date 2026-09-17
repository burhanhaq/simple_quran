import Foundation

nonisolated struct PassageSelection: Equatable, Sendable {
    private(set) var startGlobalAyah: Int?

    var isSelecting: Bool { startGlobalAyah != nil }

    mutating func tap(_ globalAyah: Int) -> VerseRange? {
        if let start = startGlobalAyah {
            startGlobalAyah = nil
            let lower = min(start, globalAyah)
            let upper = max(start, globalAyah)
            return try? VerseRange(startGlobalAyah: lower, endGlobalAyah: upper)
        }
        startGlobalAyah = globalAyah
        return nil
    }

    mutating func reset() {
        startGlobalAyah = nil
    }

    func contains(_ globalAyah: Int) -> Bool {
        startGlobalAyah == globalAyah
    }

    func highlights(_ globalAyah: Int, collected: [VerseRange]) -> Bool {
        contains(globalAyah) || collected.contains { $0.contains(globalAyah) }
    }
}
