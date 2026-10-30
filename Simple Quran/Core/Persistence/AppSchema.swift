import Foundation
import SwiftData

/// The models as they shipped in 1.0. Never change them: add AppSchemaV2 with a migration stage instead.
///
/// They follow CloudKit's rules so iCloud sync can be turned on later without a migration:
/// no unique attributes, a default for every stored property, and optional relationships.
/// Without unique attributes, every insert looks for an existing record first.
enum AppSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PracticeSet.self,
            PracticePassage.self,
            VerseProgress.self,
            PracticeSession.self,
            AudioDownloadRecord.self,
            RecitationRecordingRecord.self
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@Model
final class PracticeSet {
    var id = UUID()
    var title = ""
    var createdAt = Date.now
    var updatedAt = Date.now
    var lastPractisedAt: Date?
    var lastGlobalAyah: Int?
    var ayahRepeatRaw = String(RepeatCount.one.rawValue)
    var setRepeatRaw = String(RepeatCount.one.rawValue)
    var pauseSeconds = 0
    var hideArabic = false
    var advanceManually = false

    @Relationship(deleteRule: .cascade, inverse: \PracticePassage.set)
    var passages: [PracticePassage]? = []

    @Relationship(deleteRule: .cascade, inverse: \PracticeSession.set)
    var sessions: [PracticeSession]? = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        settings: PracticeSettings = .default
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.ayahRepeatRaw = Self.encode(settings.ayahRepeatCount)
        self.setRepeatRaw = Self.encode(settings.setRepeatCount)
        self.pauseSeconds = settings.clampedPauseSeconds
        self.hideArabic = settings.hideArabic
        self.advanceManually = settings.advanceManually
        self.passages = []
        self.sessions = []
    }

    var settings: PracticeSettings {
        get {
            PracticeSettings(
                ayahRepeatCount: Self.decode(ayahRepeatRaw) ?? .one,
                setRepeatCount: Self.decode(setRepeatRaw) ?? .one,
                pauseSeconds: pauseSeconds,
                hideArabic: hideArabic,
                advanceManually: advanceManually
            )
        }
        set {
            ayahRepeatRaw = Self.encode(newValue.ayahRepeatCount)
            setRepeatRaw = Self.encode(newValue.setRepeatCount)
            pauseSeconds = newValue.clampedPauseSeconds
            hideArabic = newValue.hideArabic
            advanceManually = newValue.advanceManually
            updatedAt = .now
        }
    }

    var orderedPassages: [PracticePassage] {
        (passages ?? []).sorted { $0.order < $1.order }
    }

    private static func encode(_ value: RepeatCount) -> String {
        String(value.rawValue)
    }

    private static func decode(_ raw: String) -> RepeatCount? {
        Int(raw).flatMap(RepeatCount.init(rawValue:))
    }
}

@Model
final class PracticePassage {
    var id = UUID()
    var order = 0
    var startGlobalAyah = 1
    var endGlobalAyah = 1
    var set: PracticeSet?

    init(id: UUID = UUID(), order: Int, range: VerseRange) {
        self.id = id
        self.order = order
        self.startGlobalAyah = range.startGlobalAyah
        self.endGlobalAyah = range.endGlobalAyah
    }

    var range: VerseRange {
        get {
            VerseRange.clamped(start: startGlobalAyah, end: endGlobalAyah)
        }
        set {
            startGlobalAyah = newValue.startGlobalAyah
            endGlobalAyah = newValue.endGlobalAyah
        }
    }
}

@Model
final class VerseProgress {
    /// One record per ayah; `PracticeStore` looks it up before inserting.
    var globalAyah = 1
    var recallStateRaw = RecallState.new.rawValue
    var lastRatingRaw: String?
    var streak = 0
    var isWeak = false
    var lastPractisedAt: Date?
    var nextReviewAt: Date?
    var exposureCount = 0
    var listeningSeconds = 0.0
    var recallAttempts = 0
    /// Audio played through this ayah, in the reader or while memorizing.
    var lastHeardAt: Date?
    /// The user recited it from memory and said how it went.
    var lastRecitedAt: Date?
    /// The user said they know it or revised it, without reciting in the app.
    var lastRevisedAt: Date?

    init(globalAyah: Int) {
        self.globalAyah = globalAyah
        self.recallStateRaw = RecallState.new.rawValue
        self.streak = 0
        self.isWeak = false
        self.exposureCount = 0
        self.listeningSeconds = 0
        self.recallAttempts = 0
    }

    var snapshot: VerseProgressSnapshot {
        VerseProgressSnapshot(
            globalAyah: globalAyah,
            recallState: RecallState(rawValue: recallStateRaw) ?? .new,
            lastRating: lastRatingRaw.flatMap(RecallRating.init(rawValue:)),
            streak: streak,
            isWeak: isWeak,
            lastPractisedAt: lastPractisedAt,
            nextReviewAt: nextReviewAt,
            exposureCount: exposureCount,
            listeningSeconds: listeningSeconds,
            recallAttempts: recallAttempts,
            lastHeardAt: lastHeardAt,
            lastRecitedAt: lastRecitedAt,
            lastRevisedAt: lastRevisedAt
        )
    }

    func apply(_ snapshot: VerseProgressSnapshot) {
        recallStateRaw = snapshot.recallState.rawValue
        lastRatingRaw = snapshot.lastRating?.rawValue
        streak = snapshot.streak
        isWeak = snapshot.isWeak
        lastPractisedAt = snapshot.lastPractisedAt
        nextReviewAt = snapshot.nextReviewAt
        exposureCount = snapshot.exposureCount
        listeningSeconds = snapshot.listeningSeconds
        recallAttempts = snapshot.recallAttempts
        lastHeardAt = snapshot.lastHeardAt
        lastRecitedAt = snapshot.lastRecitedAt
        lastRevisedAt = snapshot.lastRevisedAt
    }
}

@Model
final class PracticeSession {
    var id = UUID()
    var startedAt = Date.now
    var endedAt: Date?
    var coveredAyahCount = 0
    var repetitionCount = 0
    var completed = false
    var finalRatingRaw: String?
    var lastGlobalAyah: Int?
    var set: PracticeSet?

    init(id: UUID = UUID(), set: PracticeSet, startedAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
        self.coveredAyahCount = 0
        self.repetitionCount = 0
        self.completed = false
        self.set = set
    }
}

@Model
final class AudioDownloadRecord {
    var reciterID = ""
    var quality = 0
    var globalAyah = 1
    var relativePath = ""
    var byteCount: Int64 = 0
    var downloadedAt: Date?
    var statusRaw = DownloadStatus.pending.rawValue
    var lastError: String?

    init(reciterID: String, quality: Int, globalAyah: Int, relativePath: String) {
        self.reciterID = reciterID
        self.quality = quality
        self.globalAyah = globalAyah
        self.relativePath = relativePath
        self.byteCount = 0
        self.statusRaw = DownloadStatus.pending.rawValue
    }

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case ready
    case failed
}

@Model
final class RecitationRecordingRecord {
    var id = UUID()
    /// The `PracticeSet` the recording belongs to.
    var collectionID: UUID?
    var createdAt = Date.now
    var isPinned = false
    var isLatest = true
    var relativePath = ""

    init(
        id: UUID = UUID(),
        collectionID: UUID? = nil,
        relativePath: String,
        isLatest: Bool = true
    ) {
        self.id = id
        self.collectionID = collectionID
        self.createdAt = .now
        self.isPinned = false
        self.isLatest = isLatest
        self.relativePath = relativePath
    }
}
