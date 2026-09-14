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
        pauseSeconds: 0,
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

/// A lazy practice sequence. Repetition is represented as cursor state instead
/// of duplicating a potentially unbounded queue in memory.
nonisolated struct PracticePlaybackCursor: Equatable, Sendable {
    private let ayahs: [Int]
    private let settings: PracticeSettings
    private(set) var ayahIndex: Int
    private(set) var ayahRepetition = 1
    private(set) var setRepetition = 1
    private(set) var isInPause = false
    private(set) var isComplete = false

    init(passages: [VerseRange], settings: PracticeSettings, resumeAt globalAyah: Int? = nil) {
        let resolvedAyahs = passages.flatMap(\.globalAyahs)
        let resolvedIndex: Int
        if let globalAyah {
            resolvedIndex = resolvedAyahs.firstIndex(of: globalAyah) ?? 0
        } else {
            resolvedIndex = 0
        }
        self.ayahs = resolvedAyahs
        self.settings = settings
        self.ayahIndex = resolvedIndex
        self.isComplete = resolvedAyahs.isEmpty
    }

    var current: QueueItem? {
        guard !isComplete, ayahs.indices.contains(ayahIndex) else { return nil }
        if isInPause {
            return .silence(seconds: settings.clampedPauseSeconds)
        }
        let total = settings.ayahRepeatCount.finiteCount ?? 0
        return .ayah(globalAyah: ayahs[ayahIndex], repetition: ayahRepetition, totalRepetitions: total)
    }

    mutating func advanceAfterCompletion() {
        guard !isComplete else { return }
        if !isInPause, settings.clampedPauseSeconds > 0 {
            isInPause = true
            return
        }
        isInPause = false

        if settings.ayahRepeatCount == .indefinitely {
            ayahRepetition += 1
            return
        }
        if ayahRepetition < (settings.ayahRepeatCount.finiteCount ?? 1) {
            ayahRepetition += 1
            return
        }
        moveToNextAyah()
    }

    mutating func skipForward() {
        guard !isComplete else { return }
        isInPause = false
        moveToNextAyah()
    }

    mutating func skipBack() {
        guard !ayahs.isEmpty else { return }
        isComplete = false
        isInPause = false
        ayahRepetition = 1
        if ayahIndex > 0 {
            ayahIndex -= 1
        }
    }

    @discardableResult
    mutating func move(to globalAyah: Int) -> Bool {
        guard let index = ayahs.firstIndex(of: globalAyah) else { return false }
        ayahIndex = index
        ayahRepetition = 1
        isInPause = false
        isComplete = false
        return true
    }

    private mutating func moveToNextAyah() {
        ayahRepetition = 1
        if ayahIndex + 1 < ayahs.count {
            ayahIndex += 1
            return
        }

        if settings.setRepeatCount == .indefinitely {
            setRepetition += 1
            ayahIndex = 0
            return
        }
        if setRepetition < (settings.setRepeatCount.finiteCount ?? 1) {
            setRepetition += 1
            ayahIndex = 0
            return
        }
        isComplete = true
    }
}
