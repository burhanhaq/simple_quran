import Foundation

/// What the user has told us about an ayah. Listening or reading never changes it;
/// only starting a memorize session (learning) or an explicit claim (memorized) does.
nonisolated enum MemorizationStatus: String, CaseIterable, Sendable {
    case notStarted
    case learning
    case memorized

    var title: String {
        switch self {
        case .notStarted: String(localized: "Not started")
        case .learning: String(localized: "Learning")
        case .memorized: String(localized: "Memorized")
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "circle"
        case .learning: "leaf"
        case .memorized: "checkmark.circle.fill"
        }
    }
}

extension VerseProgressSnapshot {
    nonisolated var status: MemorizationStatus {
        switch recallState {
        case .new: .notStarted
        case .learning, .strengthening: .learning
        case .review: .memorized
        }
    }

    /// A memorized ayah the user said they've forgotten or flagged; it stays memorized but comes back sooner.
    nonisolated var needsRefresh: Bool { status == .memorized && isWeak }
}

/// Looks up memorization status by ayah so views don't re-filter progress arrays per row.
nonisolated struct ProgressIndex: Sendable {
    private let snapshots: [Int: VerseProgressSnapshot]

    init(_ snapshots: some Sequence<VerseProgressSnapshot>) {
        self.snapshots = Dictionary(snapshots.map { ($0.globalAyah, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    func snapshot(for globalAyah: Int) -> VerseProgressSnapshot? { snapshots[globalAyah] }

    func status(of globalAyah: Int) -> MemorizationStatus { snapshots[globalAyah]?.status ?? .notStarted }

    func needsRefresh(_ globalAyah: Int) -> Bool { snapshots[globalAyah]?.needsRefresh ?? false }

    func count(_ status: MemorizationStatus, in range: VerseRange) -> Int {
        if status == .notStarted { return range.count - count(.learning, in: range) - count(.memorized, in: range) }
        return snapshots.values.reduce(0) { $0 + (range.contains($1.globalAyah) && $1.status == status ? 1 : 0) }
    }

    func needsRefreshCount(in range: VerseRange) -> Int {
        snapshots.values.reduce(0) { $0 + (range.contains($1.globalAyah) && $1.needsRefresh ? 1 : 0) }
    }

    func isDue(_ range: VerseRange, at now: Date = .now) -> Bool {
        range.globalAyahs.contains { snapshots[$0]?.isDue(at: now) ?? false }
    }

    /// Memorized only when every ayah is; learning once any ayah has been started.
    func status(of range: VerseRange) -> MemorizationStatus {
        let memorized = count(.memorized, in: range)
        if memorized == range.count { return .memorized }
        return memorized + count(.learning, in: range) > 0 ? .learning : .notStarted
    }
}
