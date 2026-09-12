import AVFoundation
import Foundation
import OSLog
import SwiftData

enum RecordingPhase: Equatable {
    case idle
    case countdown(Int)
    case recording
    case comparing
}

@MainActor
@Observable
final class RecitationRecordingController: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "recording")
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var context: ModelContext?
    var phase: RecordingPhase = .idle
    var currentAyah: Int?
    var userMessage: UserFacingMessage?
    var latestURL: URL?
    var isPlayingComparison = false

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

    func startRecording(globalAyah: Int) async {
        userMessage = nil
        currentAyah = globalAyah
        let granted = await requestPermission()
        guard granted else {
            userMessage = UserFacingMessage.from(.microphoneDenied)
            return
        }
        for value in [3, 2, 1] {
            phase = .countdown(value)
            try? await Task.sleep(for: .seconds(1))
        }
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
            guard recorder.record() else { throw AppError.recordingFailed }
            self.recorder = recorder
            phase = .recording
            latestURL = url
            persist(id: id, globalAyah: globalAyah, relativePath: url.lastPathComponent)
        } catch {
            phase = .idle
            userMessage = UserFacingMessage.from(.recordingFailed)
            logger.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
        phase = latestURL == nil ? .idle : .comparing
        try? AudioSessionController.shared.configure(.playback)
    }

    func playLatest() {
        guard let latestURL else { return }
        do {
            try AudioSessionController.shared.configure(.playback)
            let player = try AVAudioPlayer(contentsOf: latestURL)
            player.delegate = self
            player.play()
            self.player = player
            isPlayingComparison = true
        } catch {
            userMessage = UserFacingMessage.from(.recordingFailed)
        }
    }

    func deleteLatest() {
        guard let currentAyah else { return }
        let descriptor = FetchDescriptor<RecitationRecordingRecord>(
            predicate: #Predicate { $0.globalAyah == currentAyah && $0.isLatest == true }
        )
        if let record = try? context?.fetch(descriptor).first {
            if let url = try? fileURL(id: record.id) {
                try? FileManager.default.removeItem(at: url)
            }
            context?.delete(record)
            try? context?.save()
        }
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

    func pinLatest() {
        guard let currentAyah else { return }
        let descriptor = FetchDescriptor<RecitationRecordingRecord>(
            predicate: #Predicate { $0.globalAyah == currentAyah && $0.isLatest == true }
        )
        if let record = try? context?.fetch(descriptor).first {
            record.isPinned = true
            try? context?.save()
        }
    }

    func latestURL(for globalAyah: Int) -> URL? {
        let descriptor = FetchDescriptor<RecitationRecordingRecord>(
            predicate: #Predicate { $0.globalAyah == globalAyah && $0.isLatest == true }
        )
        guard let record = try? context?.fetch(descriptor).first,
              let url = try? fileURL(id: record.id),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                self.userMessage = UserFacingMessage.from(.recordingFailed)
                self.phase = .idle
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlayingComparison = false
        }
    }

    private func persist(id: UUID, globalAyah: Int, relativePath: String) {
        let previous = FetchDescriptor<RecitationRecordingRecord>(
            predicate: #Predicate { $0.globalAyah == globalAyah && $0.isLatest == true }
        )
        if let records = try? context?.fetch(previous) {
            for record in records {
                if record.isPinned {
                    record.isLatest = false
                } else if let url = try? fileURL(id: record.id) {
                    try? FileManager.default.removeItem(at: url)
                    context?.delete(record)
                }
            }
        }
        let created = RecitationRecordingRecord(id: id, globalAyah: globalAyah, relativePath: relativePath, isLatest: true)
        context?.insert(created)
        try? context?.save()
    }
}
