import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AppSchemaV1.self)
        let configuration = ModelConfiguration(
            "SimpleQuran",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

@MainActor
protocol PracticeStoring: AnyObject {
    func activeSets() throws -> [PracticeSet]
    func set(id: UUID) throws -> PracticeSet?
    func createSet(title: String, passages: [VerseRange], settings: PracticeSettings) throws -> PracticeSet
    func updateSet(_ set: PracticeSet, title: String, passages: [VerseRange], settings: PracticeSettings) throws
    func archive(_ set: PracticeSet, archived: Bool) throws
    func delete(_ set: PracticeSet) throws
    func recordExposure(ayahs: [Int], seconds: Double) throws
    func markWeak(globalAyah: Int, weak: Bool) throws
    func applyRating(_ rating: RecallRating, ayahs: [Int], now: Date) throws
    func startSession(for set: PracticeSet) throws -> PracticeSession
    func finishSession(_ session: PracticeSession, coveredAyahs: Int, repetitions: Int, lastAyah: Int?, completed: Bool, rating: RecallRating?) throws
    func continueSet() throws -> PracticeSet?
    func dueSets(now: Date) throws -> [PracticeSet]
    func recentSets(limit: Int) throws -> [PracticeSet]
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

    func activeSets() throws -> [PracticeSet] {
        let descriptor = FetchDescriptor<PracticeSet>(
            predicate: #Predicate { $0.deletedAt == nil && $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func set(id: UUID) throws -> PracticeSet? {
        let descriptor = FetchDescriptor<PracticeSet>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    func createSet(title: String, passages: [VerseRange], settings: PracticeSettings) throws -> PracticeSet {
        let set = PracticeSet(title: sanitizedTitle(title), settings: settings)
        context.insert(set)
        replacePassages(on: set, with: passages)
        try context.save()
        return set
    }

    func updateSet(_ set: PracticeSet, title: String, passages: [VerseRange], settings: PracticeSettings) throws {
        set.title = sanitizedTitle(title)
        set.settings = settings
        set.updatedAt = .now
        replacePassages(on: set, with: passages)
        try context.save()
    }

    func archive(_ set: PracticeSet, archived: Bool) throws {
        set.archivedAt = archived ? .now : nil
        set.updatedAt = .now
        try context.save()
    }

    func delete(_ set: PracticeSet) throws {
        set.deletedAt = .now
        set.updatedAt = .now
        try context.save()
    }

    func recordExposure(ayahs: [Int], seconds: Double) throws {
        let share = seconds / Double(max(ayahs.count, 1))
        for ayah in ayahs {
            let progress = try progressModel(for: ayah)
            progress.exposureCount += 1
            progress.listeningSeconds += share
            progress.lastPractisedAt = .now
        }
        try context.save()
    }

    func markWeak(globalAyah: Int, weak: Bool) throws {
        let progress = try progressModel(for: globalAyah)
        progress.isWeak = weak
        if weak {
            progress.nextReviewAt = .now
            if progress.recallStateRaw == RecallState.new.rawValue {
                progress.recallStateRaw = RecallState.learning.rawValue
            }
        }
        try context.save()
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
            snapshot.recallAttempts += 1
            model.apply(snapshot)
        }
        try context.save()
    }

    func startSession(for set: PracticeSet) throws -> PracticeSession {
        let session = PracticeSession(set: set)
        context.insert(session)
        set.lastPractisedAt = .now
        set.updatedAt = .now
        try context.save()
        return session
    }

    func finishSession(
        _ session: PracticeSession,
        coveredAyahs: Int,
        repetitions: Int,
        lastAyah: Int?,
        completed: Bool,
        rating: RecallRating?
    ) throws {
        session.endedAt = .now
        session.coveredAyahCount = coveredAyahs
        session.repetitionCount = repetitions
        session.completed = completed
        session.finalRatingRaw = rating?.rawValue
        session.lastGlobalAyah = lastAyah
        if let set = session.set {
            set.lastGlobalAyah = lastAyah
            set.lastPractisedAt = .now
            set.updatedAt = .now
        }
        try context.save()
    }

    func continueSet() throws -> PracticeSet? {
        try activeSets()
            .filter { $0.lastPractisedAt != nil }
            .sorted { ($0.lastPractisedAt ?? .distantPast) > ($1.lastPractisedAt ?? .distantPast) }
            .first
    }

    func dueSets(now: Date) throws -> [PracticeSet] {
        let dueProgress = try context.fetch(FetchDescriptor<VerseProgress>()).filter { snapshot in
            let item = snapshot.snapshot
            if item.isWeak { return true }
            if let next = item.nextReviewAt { return next <= now }
            return false
        }
        let dueAyahs = Set(dueProgress.map(\.globalAyah))
        return try activeSets().filter { set in
            set.orderedPassages.contains { passage in
                (passage.startGlobalAyah...passage.endGlobalAyah).contains { dueAyahs.contains($0) }
            }
        }
    }

    func recentSets(limit: Int) throws -> [PracticeSet] {
        Array(try activeSets().prefix(limit))
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
        let created = VerseProgress(globalAyah: globalAyah)
        context.insert(created)
        return created
    }

    private func replacePassages(on set: PracticeSet, with ranges: [VerseRange]) {
        for passage in set.passages {
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
        return trimmed.isEmpty ? String(localized: "Untitled set") : trimmed
    }
}
