import Foundation

/// The three steps of memorizing a passage. Suggested in order, but the user can move freely.
enum SessionStep: String, CaseIterable, Identifiable {
    case listen
    case reciteAlong
    case fromMemory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen: String(localized: "Listen")
        case .reciteAlong: String(localized: "Recite along")
        case .fromMemory: String(localized: "From memory")
        }
    }

    var hint: String {
        switch self {
        case .listen: String(localized: "Listen a few times and follow the words.")
        case .reciteAlong: String(localized: "Recite with the reciter. Pause whenever you need.")
        case .fromMemory: String(localized: "Recite without looking. Tap an ayah to peek.")
        }
    }

    var next: SessionStep? {
        switch self {
        case .listen: .reciteAlong
        case .reciteAlong: .fromMemory
        case .fromMemory: nil
        }
    }
}

/// The user's own answer about a passage or an ayah. Nothing changes unless they give one.
enum CheckAnswer: String, Identifiable {
    case memorized
    case almost
    case stillLearning
    case stillSolid
    case shaky
    case forgot

    var id: String { rawValue }

    static func choices(for kind: SessionKind) -> [CheckAnswer] {
        switch kind {
        case .learn: [.memorized, .almost, .stillLearning]
        case .review: [.stillSolid, .shaky, .forgot]
        }
    }

    var rating: RecallRating {
        switch self {
        case .memorized, .stillSolid: .solid
        case .almost, .shaky: .comfortable
        case .stillLearning: .needsWork
        case .forgot: .again
        }
    }

    var title: String {
        switch self {
        case .memorized: String(localized: "Memorized")
        case .almost: String(localized: "Almost")
        case .stillLearning: String(localized: "Still learning")
        case .stillSolid: String(localized: "Still solid")
        case .shaky: String(localized: "Shaky")
        case .forgot: String(localized: "Forgot")
        }
    }

    var systemImage: String {
        switch self {
        case .memorized, .stillSolid: "checkmark.circle"
        case .almost, .shaky: "leaf"
        case .stillLearning, .forgot: "arrow.counterclockwise"
        }
    }
}

enum PracticePlaybackLifecycle {
    static func shouldPrepareNewSession(activeSetID: UUID?, currentGlobalAyah: Int?, openingSetID: UUID) -> Bool {
        activeSetID != openingSetID || currentGlobalAyah == nil
    }
}

/// Memorizing one piece in place on the surah screen. Nothing about an ayah's status changes
/// until the user answers, and leaving without an answer keeps every status as it was.
struct MemorizeFocus {
    var range: VerseRange
    var kind: SessionKind
    var planID: UUID?
    /// What "Next passage" walks through; nil means the piece's surah.
    var scope: VerseRange?
    /// Review passages still waiting after this one.
    var queue: [VerseRange]
    var reviewsDone = 0
    var step: SessionStep
    var practice: PracticeSet?
    var peeked: Set<Int> = []
    var answer: CheckAnswer?
    var adjusted: [Int: CheckAnswer] = [:]
    var engaged = false
    /// Listening time already saved for this piece, so moving on never records it twice.
    var committedSeconds: Double = 0

    init(route: SessionRoute) {
        range = route.range
        kind = route.kind
        planID = route.planID
        scope = route.scope
        queue = route.reviewQueue
        step = route.kind == .review ? .fromMemory : .listen
        practice = route.savedPractice
    }

    var route: SessionRoute {
        SessionRoute(range: range, kind: kind, planID: planID, scope: scope, reviewQueue: queue)
    }

    var hiddenAyahs: Set<Int> {
        step == .fromMemory ? Set(range.globalAyahs).subtracting(peeked) : []
    }

    /// Starts the piece over at its first step, keeping where it sits in a plan or review queue.
    mutating func move(to newRange: VerseRange) {
        range = newRange
        step = kind == .review ? .fromMemory : .listen
        peeked = []
        answer = nil
        adjusted = [:]
        engaged = false
        practice = nil
        committedSeconds = 0
    }
}
