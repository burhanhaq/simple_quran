import Foundation

/// The one full-screen destination over the tabs. Switching between cases swaps the cover.
enum AppRoute: Identifiable {
    case reader(ReaderRoute)
    case session(SessionRoute)

    var id: UUID {
        switch self {
        case .reader(let route): route.id
        case .session(let route): route.id
        }
    }
}

struct ReaderRoute: Identifiable {
    let id = UUID()
    let destination: QuranDestination
    var resumePlayback = false
}

enum SessionKind {
    /// Learning new ayahs, from the plan or anything else.
    case learn
    /// Recalling ayahs already memorized.
    case review
}

struct SessionRoute: Identifiable {
    let id = UUID()
    var range: VerseRange
    var kind: SessionKind = .learn
    var planID: UUID? = nil
    /// What the user chose to memorize; "Next passage" stays inside it. Nil means the passage's surah.
    var scope: VerseRange? = nil
    /// Review passages still waiting after this one.
    var reviewQueue: [VerseRange] = []
    var savedPractice: PracticeSet? = nil
    var resumePlayback = false
}
