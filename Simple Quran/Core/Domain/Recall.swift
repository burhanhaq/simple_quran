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

    var title: String {
        switch self {
        case .new: String(localized: "New")
        case .learning: String(localized: "Learning")
        case .strengthening: String(localized: "Strengthening")
        case .review: String(localized: "Review")
        }
    }
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

    var isDue: Bool {
        guard let nextReviewAt else { return recallState != .new && isWeak }
        return nextReviewAt <= Date()
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

        switch rating {
        case .again:
            weak = true
            streak = 0
            days = 0
            state = .learning
        case .needsWork:
            weak = true
            streak = 0
            days = 1
            state = .learning
        case .comfortable:
            weak = false
            streak = current.streak + 1
            days = Self.comfortableInterval(streak: streak)
            state = streak >= 3 ? .review : .strengthening
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
