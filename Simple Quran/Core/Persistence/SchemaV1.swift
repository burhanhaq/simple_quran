import Foundation
import SwiftData

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
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var lastPractisedAt: Date?
    var lastGlobalAyah: Int?
    var lastQueueIndex: Int?
    var ayahRepeatRaw: String
    var setRepeatRaw: String
    var pauseSeconds: Int
    var hideArabic: Bool
    var advanceManually: Bool

    @Relationship(deleteRule: .cascade, inverse: \PracticePassage.set)
    var passages: [PracticePassage]

    @Relationship(deleteRule: .cascade, inverse: \PracticeSession.set)
    var sessions: [PracticeSession]

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
                ayahRepeatCount: Self.decode(ayahRepeatRaw) ?? .three,
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
        passages.sorted { $0.order < $1.order }
    }

    var isActive: Bool { deletedAt == nil && archivedAt == nil }

    private static func encode(_ value: RepeatCount) -> String {
        String(value.rawValue)
    }

    private static func decode(_ raw: String) -> RepeatCount? {
        Int(raw).flatMap(RepeatCount.init(rawValue:))
    }
}

@Model
final class PracticePassage {
    @Attribute(.unique) var id: UUID
    var order: Int
    var startGlobalAyah: Int
    var endGlobalAyah: Int
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
    @Attribute(.unique) var globalAyah: Int
    var recallStateRaw: String
    var lastRatingRaw: String?
    var streak: Int
    var isWeak: Bool
    var lastPractisedAt: Date?
    var nextReviewAt: Date?
    var exposureCount: Int
    var listeningSeconds: Double
    var recallAttempts: Int

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
            recallAttempts: recallAttempts
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
    }
}

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var coveredAyahCount: Int
    var repetitionCount: Int
    var completed: Bool
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
    var reciterID: String
    var quality: Int
    var globalAyah: Int
    var relativePath: String
    var byteCount: Int64
    var downloadedAt: Date?
    var statusRaw: String
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
    @Attribute(.unique) var id: UUID
    var globalAyah: Int
    var createdAt: Date
    var isPinned: Bool
    var isLatest: Bool
    var relativePath: String

    init(id: UUID = UUID(), globalAyah: Int, relativePath: String, isLatest: Bool = true) {
        self.id = id
        self.globalAyah = globalAyah
        self.createdAt = .now
        self.isPinned = false
        self.isLatest = isLatest
        self.relativePath = relativePath
    }
}
