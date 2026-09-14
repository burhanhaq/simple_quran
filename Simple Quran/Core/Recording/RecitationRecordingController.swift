import AVFoundation
import Foundation
import OSLog
import SwiftData

enum RecordingPhase: Equatable {
    case idle
    case countdown(Int)
    case recording
    case finishing
    case comparing
}

@MainActor
@Observable
final class RecitationRecordingController: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "recording")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var context: ModelContext?
    private var countdownToken: UUID?
    private var pendingRecording: (id: UUID, collectionID: UUID, url: URL)?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    var phase: RecordingPhase = .idle
    var userMessage: UserFacingMessage?
    private var latestURL: URL?
    var isPlayingComparison = false

    /// Whether the selected practice collection has a playable recording.
    var hasRecording: Bool { latestURL != nil }
    private var currentCollectionID: UUID?

    func attach(context: ModelContext) {
        self.context = context
    }

    func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appending(path: "Recordings", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = folder
            try mutable.setResourceValues(values)
        }
        return folder
    }

    func fileURL(id: UUID) throws -> URL {
        try directory().appending(path: "\(id.uuidString).m4a")
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording(collectionID: UUID) async {
        userMessage = nil
        currentCollectionID = collectionID
        let token = UUID()
        countdownToken = token
        let granted = await requestPermission()
        guard countdownToken == token else { return }
        guard granted else {
            countdownToken = nil
            userMessage = UserFacingMessage.from(.microphoneDenied)
            return
        }
        for value in [3, 2, 1] {
            guard countdownToken == token else { return }
            phase = .countdown(value)
            try? await Task.sleep(for: .seconds(1))
        }
        guard countdownToken == token else { return }
        do {
            try AudioSessionController.shared.configure(.recording)
            let id = UUID()
            let url = try fileURL(id: id)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            pendingRecording = (id, collectionID, url)
            guard recorder.record() else { throw AppError.recordingFailed }
            self.recorder = recorder
            countdownToken = nil
            phase = .recording
        } catch {
            if let url = pendingRecording?.url { try? FileManager.default.removeItem(at: url) }
            countdownToken = nil
            pendingRecording = nil
            recorder = nil
            phase = .idle
            userMessage = UserFacingMessage.from(.recordingFailed)
            logger.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopRecording() {
        switch phase {
        case .countdown:
            countdownToken = nil
            phase = .idle
        case .recording:
            phase = .finishing
            recorder?.stop()
        default:
            break
        }
    }

    func playRecording() async throws {
        guard let latestURL else { throw AppError.recordingFailed }
        cancelComparisonPlayback()
        do {
            try AudioSessionController.shared.configure(.playback)
            let player = try AVAudioPlayer(contentsOf: latestURL)
            player.delegate = self
            self.player = player
            isPlayingComparison = true
            try await withCheckedThrowingContinuation { continuation in
                playbackContinuation = continuation
                if !player.play() {
                    playbackContinuation = nil
                    isPlayingComparison = false
                    continuation.resume(throwing: AppError.recordingFailed)
                }
            }
        } catch {
            userMessage = UserFacingMessage.from(.recordingFailed)
            throw error
        }
    }

    func selectCollection(_ collectionID: UUID) {
        currentCollectionID = collectionID
        guard phase != .recording, phase != .finishing, !isCountingDown else { return }
        latestURL = latestURL(for: collectionID)
        phase = latestURL == nil ? .idle : .comparing
    }

    func cancelComparisonPlayback() {
        player?.stop()
        player = nil
        isPlayingComparison = false
        let continuation = playbackContinuation
        playbackContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    func deleteLatest() {
        guard let currentCollectionID,
              let record = latestRecord(for: currentCollectionID)
        else { return }
        if let url = try? fileURL(id: record.id) {
            try? FileManager.default.removeItem(at: url)
        }
        context?.delete(record)
        try? context?.save()
        latestURL = nil
        phase = .idle
    }

    func deleteAll() {
        let records = (try? context?.fetch(FetchDescriptor<RecitationRecordingRecord>())) ?? []
        for record in records {
            if let url = try? fileURL(id: record.id) {
                try? FileManager.default.removeItem(at: url)
            }
            context?.delete(record)
        }
        try? context?.save()
        latestURL = nil
        phase = .idle
    }

    func deleteRecordings(for collectionID: UUID) {
        let records = ((try? context?.fetch(FetchDescriptor<RecitationRecordingRecord>())) ?? [])
            .filter { $0.collectionID == collectionID }
        for record in records {
            if let url = try? fileURL(id: record.id) {
                try? FileManager.default.removeItem(at: url)
            }
            context?.delete(record)
        }
        try? context?.save()

        guard currentCollectionID == collectionID else { return }
        cancelComparisonPlayback()
        latestURL = nil
        phase = .idle
    }

    func pinLatest() {
        guard let currentCollectionID,
              let record = latestRecord(for: currentCollectionID)
        else { return }
        record.isPinned = true
        try? context?.save()
    }

    func latestURL(for collectionID: UUID) -> URL? {
        guard let record = latestRecord(for: collectionID),
              let url = try? fileURL(id: record.id),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.recorder = nil
            self.countdownToken = nil
            guard flag, let pending = self.pendingRecording else {
                if let url = self.pendingRecording?.url { try? FileManager.default.removeItem(at: url) }
                self.pendingRecording = nil
                self.userMessage = UserFacingMessage.from(.recordingFailed)
                self.phase = .idle
                return
            }
            do {
                try self.persist(id: pending.id, collectionID: pending.collectionID, relativePath: pending.url.lastPathComponent)
                self.latestURL = self.currentCollectionID == pending.collectionID
                    ? pending.url
                    : self.currentCollectionID.flatMap(self.latestURL(for:))
                self.pendingRecording = nil
                self.phase = self.latestURL == nil ? .idle : .comparing
                try AudioSessionController.shared.configure(.playback)
            } catch {
                try? FileManager.default.removeItem(at: pending.url)
                self.pendingRecording = nil
                self.phase = .idle
                self.userMessage = UserFacingMessage.from(.persistenceFailure)
                self.logger.error("Recording metadata could not be saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingComparison = false
            self.player = nil
            let continuation = self.playbackContinuation
            self.playbackContinuation = nil
            if flag {
                continuation?.resume()
            } else {
                continuation?.resume(throwing: AppError.recordingFailed)
            }
        }
    }

    private func persist(id: UUID, collectionID: UUID, relativePath: String) throws {
        guard let context else { throw AppError.persistenceFailure }
        let records = try context.fetch(FetchDescriptor<RecitationRecordingRecord>())
            .filter { $0.collectionID == collectionID && $0.isLatest }
        var obsoleteFiles: [URL] = []
        for record in records {
            if record.isPinned {
                record.isLatest = false
            } else {
                if let url = try? fileURL(id: record.id) { obsoleteFiles.append(url) }
                context.delete(record)
            }
        }
        let created = RecitationRecordingRecord(
            id: id,
            collectionID: collectionID,
            relativePath: relativePath,
            isLatest: true
        )
        context.insert(created)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw AppError.persistenceFailure
        }
        for url in obsoleteFiles { try? FileManager.default.removeItem(at: url) }
    }

    private var isCountingDown: Bool {
        if case .countdown = phase { return true }
        return false
    }

    private func latestRecord(for collectionID: UUID) -> RecitationRecordingRecord? {
        let records = (try? context?.fetch(FetchDescriptor<RecitationRecordingRecord>())) ?? []
        return records
            .filter { $0.collectionID == collectionID && $0.isLatest }
            .max { $0.createdAt < $1.createdAt }
    }
}
