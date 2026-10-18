import Foundation
import SwiftData

/// The models as they shipped in version 1, frozen so SwiftData can recognize existing stores
/// and migrate them. Never change these; add a new schema version instead.
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

        init(id: UUID = UUID(), title: String) {
            self.id = id
            self.title = title
            self.createdAt = .now
            self.updatedAt = .now
            self.ayahRepeatRaw = "1"
            self.setRepeatRaw = "1"
            self.pauseSeconds = 0
            self.hideArabic = false
            self.advanceManually = false
            self.passages = []
            self.sessions = []
        }
    }

    @Model
    final class PracticePassage {
        @Attribute(.unique) var id: UUID
        var order: Int
        var startGlobalAyah: Int
        var endGlobalAyah: Int
        var set: PracticeSet?

        init(id: UUID = UUID(), order: Int, startGlobalAyah: Int, endGlobalAyah: Int) {
            self.id = id
            self.order = order
            self.startGlobalAyah = startGlobalAyah
            self.endGlobalAyah = endGlobalAyah
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

        init(globalAyah: Int, recallStateRaw: String) {
            self.globalAyah = globalAyah
            self.recallStateRaw = recallStateRaw
            self.streak = 0
            self.isWeak = false
            self.exposureCount = 0
            self.listeningSeconds = 0
            self.recallAttempts = 0
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

        init(id: UUID = UUID()) {
            self.id = id
            self.startedAt = .now
            self.coveredAyahCount = 0
            self.repetitionCount = 0
            self.completed = false
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
            self.statusRaw = "pending"
        }
    }

    @Model
    final class RecitationRecordingRecord {
        @Attribute(.unique) var id: UUID
        var collectionID: UUID?
        var globalAyah: Int
        var createdAt: Date
        var isPinned: Bool
        var isLatest: Bool
        var relativePath: String

        init(id: UUID = UUID(), relativePath: String) {
            self.id = id
            self.globalAyah = 0
            self.createdAt = .now
            self.isPinned = false
            self.isLatest = true
            self.relativePath = relativePath
        }
    }
}
