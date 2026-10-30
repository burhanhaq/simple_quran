import Foundation
import SwiftData

enum PersistenceController {
    static let storeName = "SimpleQuran"

    /// `url` places the store somewhere specific, for migration tests.
    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = url.map { ModelConfiguration(storeName, schema: schema, url: $0) }
            ?? ModelConfiguration(storeName, schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

@MainActor
protocol PracticeStoring: AnyObject {
    func allSets() throws -> [PracticeSet]
    func createSet(title: String, passages: [VerseRange], settings: PracticeSettings) throws -> PracticeSet
    func recordHeard(globalAyah: Int, at now: Date) throws
    func markRevised(ayahs: [Int], now: Date) throws
    func markWeak(globalAyah: Int, weak: Bool) throws
    func isMarkedWeak(globalAyah: Int) throws -> Bool
    func applyRating(_ rating: RecallRating, ayahs: [Int], now: Date) throws
    func beginLearning(ayahs: [Int]) throws
    func markMemorized(ayahs: [Int], now: Date) throws
    func markNeedsRevision(ayahs: [Int], now: Date) throws
    func restoreProgress(_ previous: [Int: VerseProgressSnapshot], ayahs: [Int]) throws
    func progress(for globalAyah: Int) throws -> VerseProgressSnapshot
    func allProgress() throws -> [VerseProgressSnapshot]
    func save() throws
}

@MainActor
final class PracticeStore: PracticeStoring {
    private let context: ModelContext
    private let scheduler = ReviewScheduler()

    init(context: ModelContext) {
        self.context = context
    }

    func allSets() throws -> [PracticeSet] {
        let descriptor = FetchDescriptor<PracticeSet>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func createSet(title: String, passages: [VerseRange], settings: PracticeSettings) throws -> PracticeSet {
        let set = PracticeSet(title: sanitizedTitle(title), settings: settings)
        context.insert(set)
        replacePassages(on: set, with: passages)
        try context.save()
        return set
    }

    func markWeak(globalAyah: Int, weak: Bool) throws {
        let progress = try progressModel(for: globalAyah)
        progress.isWeak = weak
        if weak {
            progress.nextReviewAt = .now
            if progress.recallStateRaw == RecallState.new.rawValue {
                progress.recallStateRaw = RecallState.learning.rawValue
            }
        } else {
            progress.nextReviewAt = nil
        }
        try context.save()
    }

    func isMarkedWeak(globalAyah: Int) throws -> Bool {
        let descriptor = FetchDescriptor<VerseProgress>(
            predicate: #Predicate { $0.globalAyah == globalAyah }
        )
        return try context.fetch(descriptor).first?.isWeak ?? false
    }

    func applyRating(_ rating: RecallRating, ayahs: [Int], now: Date) throws {
        for ayah in ayahs {
            let model = try progressModel(for: ayah)
            let decision = scheduler.apply(rating: rating, to: model.snapshot, now: now)
            var snapshot = model.snapshot
            snapshot.recallState = decision.state
            snapshot.lastRating = decision.rating
            snapshot.streak = decision.streak
            snapshot.isWeak = decision.isWeak
            snapshot.nextReviewAt = decision.nextReviewAt
            snapshot.lastPractisedAt = decision.practisedAt
            snapshot.lastRecitedAt = now
            snapshot.recallAttempts += 1
            model.apply(snapshot)
        }
        try context.save()
    }

    /// Starting a memorize session is an explicit intent to learn; it never claims the ayahs are known.
    func beginLearning(ayahs: [Int]) throws {
        for ayah in Set(ayahs) {
            let model = try progressModel(for: ayah)
            if model.recallStateRaw == RecallState.new.rawValue { model.recallStateRaw = RecallState.learning.rawValue }
        }
        try save()
    }

    /// An explicit "I know these" claim. It schedules review but isn't practice, so activity stays untouched.
    func markMemorized(ayahs: [Int], now: Date = .now) throws {
        for ayah in Set(ayahs) {
            let model = try progressModel(for: ayah)
            let decision = scheduler.apply(rating: .solid, to: model.snapshot, now: now)
            model.recallStateRaw = decision.state.rawValue
            model.lastRatingRaw = decision.rating.rawValue
            model.streak = decision.streak
            model.isWeak = decision.isWeak
            model.nextReviewAt = decision.nextReviewAt
            // Saying you know it now starts its revision clock.
            model.lastRevisedAt = now
        }
        try save()
    }

    /// Audio played through an ayah. It keeps memorized ayahs fresh but never changes a status.
    func recordHeard(globalAyah: Int, at now: Date = .now) throws {
        try progressModel(for: globalAyah).lastHeardAt = now
        try save()
    }

    /// "Revised today": the user went over these memorized ayahs on their own, so they're fresh
    /// again and no longer flagged as forgotten. Other ayahs are left alone.
    func markRevised(ayahs: [Int], now: Date = .now) throws {
        for ayah in Set(ayahs) {
            let descriptor = FetchDescriptor<VerseProgress>(predicate: #Predicate { $0.globalAyah == ayah })
            guard let model = try context.fetch(descriptor).first, model.snapshot.status == .memorized else { continue }
            model.lastRevisedAt = now
            model.isWeak = false
        }
        try save()
    }

    /// Memorized ayahs keep their status and need revision now; others become learning.
    func markNeedsRevision(ayahs: [Int], now: Date = .now) throws {
        for ayah in Set(ayahs) {
            let model = try progressModel(for: ayah)
            model.isWeak = true
            model.nextReviewAt = now
            if model.recallStateRaw == RecallState.new.rawValue { model.recallStateRaw = RecallState.learning.rawValue }
        }
        try save()
    }

    /// Puts ayahs back the way they were before a claim. An ayah with no earlier progress loses its record.
    func restoreProgress(_ previous: [Int: VerseProgressSnapshot], ayahs: [Int]) throws {
        for ayah in Set(ayahs) {
            let descriptor = FetchDescriptor<VerseProgress>(predicate: #Predicate { $0.globalAyah == ayah })
            let existing = try context.fetch(descriptor).first
            if let snapshot = previous[ayah] {
                (existing ?? progressModel(inserting: ayah)).apply(snapshot)
            } else if let existing {
                context.delete(existing)
            }
        }
        try save()
    }

    /// Commit the user's explicit passage-level reflection as one transaction.
    /// Merely opening the reader or playing audio never marks a passage learned.
    func completePractice(_ set: PracticeSet, ayahs: [Int], rating: RecallRating?, lastAyah: Int?, seconds: Double, repetitions: Int) throws {
        let now = Date()
        do {
            for ayah in Set(ayahs) {
                let model = try progressModel(for: ayah)
                model.exposureCount += 1
                model.lastPractisedAt = now
                model.listeningSeconds += seconds / Double(max(ayahs.count, 1))
                if let rating {
                    let decision = scheduler.apply(rating: rating, to: model.snapshot, now: now)
                    var snapshot = model.snapshot
                    snapshot.recallState = decision.state
                    snapshot.lastRating = rating
                    snapshot.streak = decision.streak
                    snapshot.isWeak = decision.isWeak
                    snapshot.nextReviewAt = decision.nextReviewAt
                    snapshot.lastRecitedAt = now
                    snapshot.recallAttempts += 1
                    model.apply(snapshot)
                }
            }
            let session = PracticeSession(set: set)
            session.endedAt = now
            session.completed = true
            session.coveredAyahCount = Set(ayahs).count
            session.repetitionCount = repetitions
            session.finalRatingRaw = rating?.rawValue
            session.lastGlobalAyah = lastAyah
            context.insert(session)
            set.lastGlobalAyah = lastAyah
            set.lastPractisedAt = now
            set.updatedAt = now
            try context.save()
        } catch {
            context.rollback()
            throw AppError.persistenceFailure
        }
    }

    func progress(for globalAyah: Int) throws -> VerseProgressSnapshot {
        try progressModel(for: globalAyah).snapshot
    }

    func allProgress() throws -> [VerseProgressSnapshot] {
        try context.fetch(FetchDescriptor<VerseProgress>()).map(\.snapshot)
    }

    func save() throws {
        do {
            try context.save()
        } catch {
            throw AppError.persistenceFailure
        }
    }

    private func progressModel(for globalAyah: Int) throws -> VerseProgress {
        let descriptor = FetchDescriptor<VerseProgress>(predicate: #Predicate { $0.globalAyah == globalAyah })
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        return progressModel(inserting: globalAyah)
    }

    private func progressModel(inserting globalAyah: Int) -> VerseProgress {
        let created = VerseProgress(globalAyah: globalAyah)
        context.insert(created)
        return created
    }

    private func replacePassages(on set: PracticeSet, with ranges: [VerseRange]) {
        for passage in set.passages ?? [] {
            context.delete(passage)
        }
        set.passages = ranges.enumerated().map { index, range in
            let passage = PracticePassage(order: index, range: range)
            passage.set = set
            return passage
        }
    }

    private func sanitizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Saved passage") : trimmed
    }
}
