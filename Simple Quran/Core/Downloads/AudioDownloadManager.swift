import Foundation
import OSLog
import SwiftData

struct DownloadJob: Equatable, Identifiable {
    var id: Int { globalAyah }
    var globalAyah: Int
    var fraction: Double
    var status: DownloadStatus
}

private nonisolated struct DownloadTaskMetadata: Equatable, Sendable {
    let reciterID: String
    let quality: Int
    let globalAyah: Int

    var taskDescription: String {
        "audio|\(reciterID)|\(quality)|\(globalAyah)"
    }

    init(reciter: Reciter, globalAyah: Int) {
        self.reciterID = reciter.id
        self.quality = reciter.qualityKbps
        self.globalAyah = globalAyah
    }

    init?(taskDescription: String?) {
        guard let taskDescription else { return nil }
        let parts = taskDescription.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "audio",
              let quality = Int(parts[2]),
              let globalAyah = Int(parts[3])
        else { return nil }
        self.reciterID = String(parts[1])
        self.quality = quality
        self.globalAyah = globalAyah
    }
}

@MainActor
@Observable
final class AudioDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let sessionIdentifier = "com.simpleAzaan.Simple-Quran1.audio"

    let source: AudioSource
    let fileStore: AudioFileStore
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "downloads")
    private var session: URLSession!
    private var taskAyahs: [Int: Int] = [:]
    private var context: ModelContext?
    var backgroundCompletionHandler: (() -> Void)?
    var jobs: [Int: DownloadJob] = [:]
    var userMessage: UserFacingMessage?
    private(set) var allowCellular: Bool

    init(source: AudioSource, fileStore: AudioFileStore, allowCellular: Bool = true) {
        self.source = source
        self.fileStore = fileStore
        self.allowCellular = allowCellular
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = allowCellular
        configuration.allowsExpensiveNetworkAccess = allowCellular
        configuration.allowsConstrainedNetworkAccess = true
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        restoreBackgroundTasks()
    }

    func attach(context: ModelContext) {
        self.context = context
        reconcileRecordsWithFiles()
    }

    func updateCellular(_ allowed: Bool) {
        allowCellular = allowed
    }

    func estimate(for ayahs: [Int]) -> Int64 {
        let missing = Set(ayahs).filter { !fileStore.isReady($0) }
        return Int64(missing.count) * source.estimatedBytesPerAyah
    }

    func downloadedCount(in ayahs: [Int]) -> Int {
        Set(ayahs).filter { fileStore.isReady($0) }.count
    }

    func download(ayahs: [Int]) {
        userMessage = nil
        let unique = Set(ayahs).sorted()
        for ayah in unique where !fileStore.isReady(ayah) && jobs[ayah]?.status != .downloading {
            do {
                let metadata = DownloadTaskMetadata(reciter: source.reciter, globalAyah: ayah)
                var request = URLRequest(url: try source.remoteURL(for: ayah))
                request.allowsCellularAccess = allowCellular
                request.allowsConstrainedNetworkAccess = true
                request.allowsExpensiveNetworkAccess = allowCellular
                request.setValue("audio/mpeg,audio/*;q=0.9", forHTTPHeaderField: "Accept")
                let task = session.downloadTask(with: request)
                task.taskDescription = metadata.taskDescription
                taskAyahs[task.taskIdentifier] = ayah
                jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 0, status: .downloading)
                upsertRecord(ayah: ayah, status: .downloading)
                task.resume()
            } catch {
                markFailed(ayah: ayah, error: error)
            }
        }
    }

    func cancelAll() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        for ayah in jobs.keys where jobs[ayah]?.status == .downloading {
            jobs[ayah]?.status = .pending
            upsertRecord(ayah: ayah, status: .pending)
        }
    }

    func remove(ayahs: [Int]) {
        for ayah in Set(ayahs) {
            do {
                try fileStore.remove(globalAyah: ayah)
                jobs[ayah] = nil
                for record in records(for: ayah) { context?.delete(record) }
            } catch {
                userMessage = UserFacingMessage.from(.downloadFailed)
                logger.error("Could not remove ayah \(ayah, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        saveContext()
    }

    func removeAll() {
        do {
            try fileStore.removeAll()
            let reciterID = source.reciter.id
            let quality = source.reciter.qualityKbps
            let descriptor = FetchDescriptor<AudioDownloadRecord>(
                predicate: #Predicate { $0.reciterID == reciterID && $0.quality == quality }
            )
            for record in (try? context?.fetch(descriptor)) ?? [] { context?.delete(record) }
            jobs.removeAll()
            saveContext()
        } catch {
            userMessage = UserFacingMessage.from(.downloadFailed)
            logger.error("Could not remove downloads: \(error.localizedDescription, privacy: .public)")
        }
    }

    var overallFraction: Double {
        guard !jobs.isEmpty else { return 1 }
        return jobs.values.map(\.fraction).reduce(0, +) / Double(jobs.count)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let metadata = DownloadTaskMetadata(taskDescription: downloadTask.taskDescription) else { return }
        let http = downloadTask.response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? -1
        guard (200...299).contains(statusCode) else {
            Task { @MainActor in self.markFailed(ayah: metadata.globalAyah, error: AppError.httpStatus(statusCode)) }
            return
        }
        let mime = http?.mimeType?.lowercased()
        guard mime?.hasPrefix("audio/") == true || mime == "application/octet-stream" else {
            Task { @MainActor in self.markFailed(ayah: metadata.globalAyah, error: AppError.invalidAudio) }
            return
        }

        let temp = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("mp3")
        do {
            try FileManager.default.copyItem(at: location, to: temp)
        } catch {
            Task { @MainActor in self.markFailed(ayah: metadata.globalAyah, error: error) }
            return
        }

        Task { @MainActor in
            guard metadata.reciterID == self.source.reciter.id,
                  metadata.quality == self.source.reciter.qualityKbps
            else {
                try? FileManager.default.removeItem(at: temp)
                return
            }
            do {
                let installed = try self.fileStore.install(temporaryURL: temp, globalAyah: metadata.globalAyah)
                let bytes = self.fileStore.byteCount(globalAyah: metadata.globalAyah)
                self.jobs[metadata.globalAyah] = DownloadJob(
                    globalAyah: metadata.globalAyah,
                    fraction: 1,
                    status: .ready
                )
                self.upsertRecord(
                    ayah: metadata.globalAyah,
                    status: .ready,
                    bytes: bytes,
                    path: installed.lastPathComponent
                )
            } catch {
                try? FileManager.default.removeItem(at: temp)
                self.markFailed(ayah: metadata.globalAyah, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let metadata = DownloadTaskMetadata(taskDescription: downloadTask.taskDescription) else { return }
        let fraction = totalBytesExpectedToWrite > 0
            ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            : 0
        Task { @MainActor in
            self.jobs[metadata.globalAyah] = DownloadJob(
                globalAyah: metadata.globalAyah,
                fraction: fraction,
                status: .downloading
            )
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let identifier = task.taskIdentifier
        let metadata = DownloadTaskMetadata(taskDescription: task.taskDescription)
        Task { @MainActor in
            defer { self.taskAyahs[identifier] = nil }
            guard let metadata, let error else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            self.markFailed(ayah: metadata.globalAyah, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    private func restoreBackgroundTasks() {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let metadata = DownloadTaskMetadata(taskDescription: task.taskDescription),
                          metadata.reciterID == self.source.reciter.id,
                          metadata.quality == self.source.reciter.qualityKbps
                    else {
                        task.cancel()
                        continue
                    }
                    self.taskAyahs[task.taskIdentifier] = metadata.globalAyah
                    self.jobs[metadata.globalAyah] = DownloadJob(
                        globalAyah: metadata.globalAyah,
                        fraction: task.progress.fractionCompleted,
                        status: .downloading
                    )
                }
            }
        }
    }

    private func reconcileRecordsWithFiles() {
        let reciterID = source.reciter.id
        let quality = source.reciter.qualityKbps
        let descriptor = FetchDescriptor<AudioDownloadRecord>(
            predicate: #Predicate { $0.reciterID == reciterID && $0.quality == quality }
        )
        guard let records = try? context?.fetch(descriptor) else { return }
        let ready = fileStore.readyAyahs()
        for record in records {
            if ready.contains(record.globalAyah) {
                record.status = .ready
                record.byteCount = fileStore.byteCount(globalAyah: record.globalAyah)
                jobs[record.globalAyah] = DownloadJob(globalAyah: record.globalAyah, fraction: 1, status: .ready)
            } else if record.status == .ready || record.status == .downloading {
                record.status = .pending
                record.byteCount = 0
            }
        }
        saveContext()
    }

    private func records(for ayah: Int) -> [AudioDownloadRecord] {
        let reciterID = source.reciter.id
        let quality = source.reciter.qualityKbps
        let descriptor = FetchDescriptor<AudioDownloadRecord>(
            predicate: #Predicate {
                $0.reciterID == reciterID && $0.quality == quality && $0.globalAyah == ayah
            }
        )
        return (try? context?.fetch(descriptor)) ?? []
    }

    private func upsertRecord(
        ayah: Int,
        status: DownloadStatus,
        bytes: Int64 = 0,
        path: String? = nil,
        lastError: String? = nil
    ) {
        let matches = records(for: ayah)
        let existing = matches.first ?? {
            let created = AudioDownloadRecord(
                reciterID: source.reciter.id,
                quality: source.reciter.qualityKbps,
                globalAyah: ayah,
                relativePath: path ?? "\(ayah).mp3"
            )
            context?.insert(created)
            return created
        }()
        for duplicate in matches.dropFirst() { context?.delete(duplicate) }
        existing.status = status
        existing.byteCount = bytes
        if let path { existing.relativePath = path }
        if status == .ready { existing.downloadedAt = .now }
        existing.lastError = lastError
        saveContext()
    }

    private func markFailed(ayah: Int, error: Error) {
        let appError = (error as? AppError) ?? .downloadFailed
        jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 0, status: .failed)
        upsertRecord(ayah: ayah, status: .failed, lastError: String(describing: appError))
        userMessage = UserFacingMessage.from(appError)
        logger.error("Download failed for ayah \(ayah, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    private func saveContext() {
        do {
            try context?.save()
        } catch {
            userMessage = UserFacingMessage.from(.persistenceFailure)
            logger.error("Download state could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }
}
