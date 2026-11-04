import Foundation

/// Which ayahs to download while playing: a short window from the one playing onward,
/// so the next file is fetched first and a long passage doesn't queue hundreds of downloads at once.
nonisolated enum AudioPrefetch {
    /// About 2 MB of audio, well ahead of even the shortest ayahs.
    static let lookahead = 20

    /// Up to `limit` distinct ayahs from `current` onward, wrapping to the start for passages that repeat.
    /// `skip` leaves out ayahs that are already saved or can't be fetched.
    static func ayahsToFetch(order: [Int], current: Int?, limit: Int = lookahead, skip: (Int) -> Bool) -> [Int] {
        let start = current.flatMap { order.firstIndex(of: $0) } ?? 0
        var seen = Set<Int>()
        var result: [Int] = []
        for ayah in order[start...] + order[..<start] where result.count < limit {
            guard seen.insert(ayah).inserted, !skip(ayah) else { continue }
            result.append(ayah)
        }
        return result
    }
}
