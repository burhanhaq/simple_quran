import Foundation
import Observation

/// Asks for an App Store rating once, after someone has clearly used the app:
/// five listening sessions or five revisions, whichever comes first.
@MainActor
@Observable
final class ReviewPrompt {
    static let threshold = 5

    private let defaults: UserDefaults
    /// Off for UI tests, so the system's rating sheet never covers what they tap.
    private let isEnabled: Bool
    private enum Key {
        static let listens = "review.listens"
        static let revisions = "review.revisions"
        static let hasRequested = "review.hasRequested"
    }

    private(set) var listens: Int {
        didSet { defaults.set(listens, forKey: Key.listens) }
    }
    private(set) var revisions: Int {
        didSet { defaults.set(revisions, forKey: Key.revisions) }
    }
    private(set) var hasRequested: Bool {
        didSet { defaults.set(hasRequested, forKey: Key.hasRequested) }
    }

    init(defaults: UserDefaults = .standard, isEnabled: Bool = true) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        listens = defaults.integer(forKey: Key.listens)
        revisions = defaults.integer(forKey: Key.revisions)
        hasRequested = defaults.bool(forKey: Key.hasRequested)
    }

    var isDue: Bool {
        isEnabled && !hasRequested && (listens >= Self.threshold || revisions >= Self.threshold)
    }

    func recordListen() {
        guard !hasRequested else { return }
        listens += 1
    }

    func recordRevision() {
        guard !hasRequested else { return }
        revisions += 1
    }

    func markRequested() {
        hasRequested = true
    }
}
