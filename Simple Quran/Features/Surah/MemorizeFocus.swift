import Foundation

/// The steps of working on a piece: listen with the text in view, recite it from memory with the
/// text hidden, then check it with the text back. Memorizing opens on Listen, revising on Recite.
enum CoachStep: String {
    case listen
    case recite
    case check

    static func first(for kind: SessionKind) -> CoachStep {
        kind == .review ? .recite : .listen
    }

    /// What the step asks of the user.
    var prompt: String {
        switch self {
        case .listen: String(localized: "Listen and repeat after the reciter.")
        case .recite: String(localized: "Recite from memory. Tap an ayah if you need to see it.")
        case .check: String(localized: "How did it go?")
        }
    }

    /// Where the step's main button leads; Check leads on to the next passage instead.
    var next: CoachStep? {
        switch self {
        case .listen: .recite
        case .recite: .check
        case .check: nil
        }
    }

    var previous: CoachStep? {
        switch self {
        case .listen: nil
        case .recite: .listen
        case .check: .recite
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

    /// What an ayah the user marked as slipped gets when they answer for the piece.
    static func slipped(for kind: SessionKind) -> CheckAnswer {
        switch kind {
        case .learn: .stillLearning
        case .review: .forgot
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
    private(set) var step: CoachStep
    var practice: PracticeSet?
    /// Ayahs the user tapped open while reciting.
    var revealed: Set<Int> = []
    /// Ayahs the user marked as slipped. They get a weaker answer than the rest of the piece.
    var slipped: Set<Int> = []
    var answer: CheckAnswer?
    var engaged = false
    /// Listening time already saved for this piece, so moving on never records it twice.
    var committedSeconds: Double = 0

    init(route: SessionRoute) {
        range = route.range
        kind = route.kind
        planID = route.planID
        scope = route.scope
        queue = route.reviewQueue
        step = .first(for: route.kind)
        practice = route.savedPractice
    }

    var route: SessionRoute {
        SessionRoute(range: range, kind: kind, planID: planID, scope: scope, reviewQueue: queue)
    }

    var hiddenAyahs: Set<Int> {
        step == .recite ? Set(range.globalAyahs).subtracting(revealed) : []
    }

    /// Reciting again hides the whole piece, ayahs opened last time included. Marks stay,
    /// since they're the record of the attempt.
    mutating func go(to newStep: CoachStep) {
        if newStep == .recite { revealed = [] }
        step = newStep
    }

    /// Reciting, a hidden ayah opens and counts as slipped, since the user needed to see it.
    /// A visible ayah toggles its mark, so a peek that wasn't a slip can be taken back.
    mutating func tap(_ ayah: Int) {
        guard range.contains(ayah) else { return }
        engaged = true
        if hiddenAyahs.contains(ayah) {
            revealed.insert(ayah)
            slipped.insert(ayah)
        } else if slipped.contains(ayah) {
            slipped.remove(ayah)
        } else {
            slipped.insert(ayah)
        }
    }

    /// The answer each ayah gets: slipped ayahs the weaker one, the rest the piece's answer.
    /// With no answer nothing changes, and a review only speaks for ayahs memorized going in.
    func ratings(isMemorized: (Int) -> Bool) -> [CheckAnswer: [Int]] {
        guard let answer else { return [:] }
        var result: [CheckAnswer: [Int]] = [:]
        for ayah in range.globalAyahs {
            if kind == .review && !isMemorized(ayah) { continue }
            result[slipped.contains(ayah) ? CheckAnswer.slipped(for: kind) : answer, default: []].append(ayah)
        }
        return result
    }

    /// Starts the piece over on its first step, keeping where it sits in a plan or review queue.
    mutating func move(to newRange: VerseRange) {
        range = newRange
        step = .first(for: kind)
        revealed = []
        slipped = []
        answer = nil
        engaged = false
        practice = nil
        committedSeconds = 0
    }
}
