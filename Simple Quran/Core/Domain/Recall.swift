import Foundation

nonisolated enum RecallRating: String, Codable, CaseIterable, Sendable {
    case again
    case needsWork
    case comfortable
    case solid

    var title: String {
        switch self {
        case .again: String(localized: "Again")
        case .needsWork: String(localized: "Needs work")
        case .comfortable: String(localized: "Comfortable")
        case .solid: String(localized: "Solid")
        }
    }
}

nonisolated enum RecallState: String, Codable, CaseIterable, Sendable {
    case new
    case learning
    case strengthening
    case review
}

nonisolated struct VerseProgressSnapshot: Equatable, Sendable {
    var globalAyah: Int
    var recallState: RecallState
    var lastRating: RecallRating?
    var streak: Int
    var isWeak: Bool
    var lastPractisedAt: Date?
    var nextReviewAt: Date?
    var exposureCount: Int
    var listeningSeconds: Double
    var recallAttempts: Int
    var lastHeardAt: Date? = nil
    var lastRecitedAt: Date? = nil
    var lastRevisedAt: Date? = nil

    static func fresh(globalAyah: Int) -> VerseProgressSnapshot {
        VerseProgressSnapshot(
            globalAyah: globalAyah,
            recallState: .new,
            lastRating: nil,
            streak: 0,
            isWeak: false,
            lastPractisedAt: nil,
            nextReviewAt: nil,
            exposureCount: 0,
            listeningSeconds: 0,
            recallAttempts: 0
        )
    }

    var isDue: Bool { isDue(at: Date()) }

    func isDue(at now: Date) -> Bool {
        guard let nextReviewAt else { return recallState != .new && isWeak }
        return nextReviewAt <= now
    }
}

nonisolated struct ReviewDecision: Equatable, Sendable {
    var state: RecallState
    var rating: RecallRating
    var streak: Int
    var isWeak: Bool
    var nextReviewAt: Date
    var practisedAt: Date
}

nonisolated struct ReviewScheduler: Sendable {
    func apply(
        rating: RecallRating,
        to current: VerseProgressSnapshot,
        now: Date = .now
    ) -> ReviewDecision {
        let calendar = Calendar.current
        let weak: Bool
        let streak: Int
        let days: Int
        let state: RecallState

        // Memorized is sticky: only an explicit `.solid` gets an ayah there, and a weaker
        // answer afterwards flags it for revision instead of taking it away.
        let memorized = current.recallState == .review
        switch rating {
        case .again:
            weak = true
            streak = 0
            days = 0
            state = memorized ? .review : .learning
        case .needsWork:
            weak = true
            streak = 0
            days = 1
            state = memorized ? .review : .learning
        case .comfortable:
            weak = false
            streak = current.streak + 1
            days = Self.comfortableInterval(streak: streak)
            state = memorized ? .review : .strengthening
        case .solid:
            weak = false
            streak = current.streak + 1
            days = Self.solidInterval(streak: streak)
            state = .review
        }

        let next = calendar.date(byAdding: .day, value: days, to: now) ?? now
        return ReviewDecision(
            state: state,
            rating: rating,
            streak: streak,
            isWeak: weak,
            nextReviewAt: next,
            practisedAt: now
        )
    }

    private static func comfortableInterval(streak: Int) -> Int {
        switch streak {
        case ...1: 3
        case 2: 7
        default: 14
        }
    }

    private static func solidInterval(streak: Int) -> Int {
        switch streak {
        case ...1: 7
        case 2: 14
        case 3: 30
        default: 60
        }
    }
}
