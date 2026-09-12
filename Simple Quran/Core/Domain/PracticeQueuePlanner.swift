import Foundation

nonisolated enum RepeatCount: Int, Equatable, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case indefinitely = 0
    case one = 1
    case two = 2
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .indefinitely: String(localized: "∞")
        default: String(localized: "\(rawValue)x")
        }
    }

    var finiteCount: Int? {
        self == .indefinitely ? nil : rawValue
    }

    static let ayahPresets: [RepeatCount] = [.one, .three, .five, .ten, .indefinitely]
    static let setPresets: [RepeatCount] = [.one, .two, .three, .indefinitely]
}

nonisolated struct PracticeSettings: Equatable, Sendable, Codable {
    var ayahRepeatCount: RepeatCount
    var setRepeatCount: RepeatCount
    var pauseSeconds: Int
    var hideArabic: Bool
    var advanceManually: Bool

    static let `default` = PracticeSettings(
        ayahRepeatCount: .three,
        setRepeatCount: .one,
        pauseSeconds: 1,
        hideArabic: false,
        advanceManually: false
    )

    var clampedPauseSeconds: Int {
        min(5, max(0, pauseSeconds))
    }
}

nonisolated enum QueueItem: Equatable, Sendable {
    case ayah(globalAyah: Int, repetition: Int, totalRepetitions: Int)
    case silence(seconds: Int)
}

nonisolated struct PracticeQueuePlanner: Sendable {
    func makeCycle(passages: [VerseRange], settings: PracticeSettings) -> [QueueItem] {
        let ayahRepeats = settings.ayahRepeatCount.finiteCount ?? 1

        var items: [QueueItem] = []
        for range in passages {
            for ayah in range.globalAyahs {
                for repetition in 1...ayahRepeats {
                    items.append(.ayah(globalAyah: ayah, repetition: repetition, totalRepetitions: ayahRepeats))
                    if settings.clampedPauseSeconds > 0 {
                        items.append(.silence(seconds: settings.clampedPauseSeconds))
                    }
                }
            }
        }
        if case .silence = items.last {
            items.removeLast()
        }
        return items
    }

    func expand(passages: [VerseRange], settings: PracticeSettings, maxSetRepeats: Int = 50) -> [QueueItem] {
        let cycle = makeCycle(passages: passages, settings: settings)
        guard !cycle.isEmpty else { return [] }
        if let count = settings.setRepeatCount.finiteCount {
            let repeats = min(maxSetRepeats, max(1, count))
            return Array(repeating: cycle, count: repeats).flatMap { $0 }
        }
        return cycle
    }

    func uniqueAyahs(in passages: [VerseRange]) -> [Int] {
        var seen = Set<Int>()
        var ordered: [Int] = []
        for range in passages {
            for ayah in range.globalAyahs where seen.insert(ayah).inserted {
                ordered.append(ayah)
            }
        }
        return ordered
    }
}
