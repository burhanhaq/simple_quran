import Foundation
import OSLog
import SwiftData

struct DownloadJob: Equatable, Identifiable {
    var id: Int { globalAyah }
    var globalAyah: Int
    var fraction: Double
    var status: DownloadStatus
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
    var allowCellular: Bool = true

    init(source: AudioSource, fileStore: AudioFileStore) {
        self.source = source
        self.fileStore = fileStore
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = allowCellular
        configuration.allowsExpensiveNetworkAccess = allowCellular
        configuration.allowsConstrainedNetworkAccess = false
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    func attach(context: ModelContext) {
        self.context = context
    }

    func updateCellular(_ allowed: Bool) {
        allowCellular = allowed
    }

    func estimate(for ayahs: [Int]) -> Int64 {
        let missing = ayahs.filter { !fileStore.isReady($0) }
        return Int64(missing.count) * source.estimatedBytesPerAyah
    }

    func downloadedCount(in ayahs: [Int]) -> Int {
        ayahs.filter { fileStore.isReady($0) }.count
    }

    func download(ayahs: [Int]) {
        userMessage = nil
        let unique = Array(Set(ayahs)).sorted()
        for ayah in unique where !fileStore.isReady(ayah) {
            jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 0, status: .downloading)
            upsertRecord(ayah: ayah, status: .downloading)
            do {
                let url = try source.remoteURL(for: ayah)
                var request = URLRequest(url: url)
                request.allowsConstrainedNetworkAccess = false
                request.allowsExpensiveNetworkAccess = allowCellular
                let task = session.downloadTask(with: request)
                taskAyahs[task.taskIdentifier] = ayah
                task.resume()
            } catch {
                jobs[ayah]?.status = .failed
                userMessage = UserFacingMessage.from(.downloadFailed)
                logger.error("Could not enqueue ayah \(ayah, privacy: .public)")
            }
        }
    }

    func cancelAll() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        jobs = jobs.mapValues {
            var copy = $0
            if copy.status == .downloading { copy.status = .pending }
            return copy
        }
    }

    func remove(ayahs: [Int]) {
        for ayah in ayahs {
            try? fileStore.remove(globalAyah: ayah)
            jobs[ayah] = nil
            if let record = record(for: ayah) {
                context?.delete(record)
            }
        }
        try? context?.save()
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
        let identifier = downloadTask.taskIdentifier
        let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.copyItem(at: location, to: temp)
        Task { @MainActor in
            guard let ayah = self.taskAyahs[identifier] else { return }
            do {
                let http = downloadTask.response as? HTTPURLResponse
                guard http?.statusCode == 200 || http == nil else {
                    throw AppError.downloadFailed
                }
                let installed = try self.fileStore.install(temporaryURL: temp, globalAyah: ayah)
                let bytes = self.fileStore.byteCount(globalAyah: ayah)
                guard bytes > 1000 else {
                    try self.fileStore.remove(globalAyah: ayah)
                    throw AppError.downloadFailed
                }
                self.jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 1, status: .ready)
                self.upsertRecord(ayah: ayah, status: .ready, bytes: bytes, path: installed.lastPathComponent)
                _ = installed
            } catch {
                self.jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 0, status: .failed)
                self.upsertRecord(ayah: ayah, status: .failed)
                self.userMessage = UserFacingMessage.from(.downloadFailed)
                self.logger.error("Install failed for ayah \(ayah, privacy: .public)")
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
        let identifier = downloadTask.taskIdentifier
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in
            guard let ayah = self.taskAyahs[identifier] else { return }
            self.jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: fraction, status: .downloading)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let identifier = task.taskIdentifier
        Task { @MainActor in
            defer { self.taskAyahs[identifier] = nil }
            if let error, (error as NSError).code != NSURLErrorCancelled {
                if let ayah = self.taskAyahs[identifier] {
                    self.jobs[ayah] = DownloadJob(globalAyah: ayah, fraction: 0, status: .failed)
                    self.upsertRecord(ayah: ayah, status: .failed)
                }
                self.userMessage = UserFacingMessage.from(.downloadFailed)
                self.logger.error("Task failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }

    private func record(for ayah: Int) -> AudioDownloadRecord? {
        let reciterID = source.reciter.id
        let quality = source.reciter.qualityKbps
        let descriptor = FetchDescriptor<AudioDownloadRecord>(
            predicate: #Predicate { $0.reciterID == reciterID && $0.quality == quality && $0.globalAyah == ayah }
        )
        return try? context?.fetch(descriptor).first
    }

    private func upsertRecord(ayah: Int, status: DownloadStatus, bytes: Int64 = 0, path: String? = nil) {
        let existing = record(for: ayah) ?? {
            let created = AudioDownloadRecord(
                reciterID: source.reciter.id,
                quality: source.reciter.qualityKbps,
                globalAyah: ayah,
                relativePath: path ?? "\(ayah).mp3"
            )
            context?.insert(created)
            return created
        }()
        existing.status = status
        existing.byteCount = bytes
        if status == .ready { existing.downloadedAt = .now }
        existing.lastError = status == .failed ? "download" : nil
        try? context?.save()
    }
}
