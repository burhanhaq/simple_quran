import Foundation

/// Finds a playable file for an ayah: the saved download, a streamed copy kept in Caches,
/// or the background download once it lands. The player only ever plays files on disk.
@MainActor
final class AyahAudioResolver {
    enum Availability: Equatable {
        case ready(URL)
        /// `fetch(_:)` will make it ready.
        case needsFetch
        case unavailable(AppError)
    }

    /// Downloads a URL to a temporary file and returns where it landed.
    typealias Fetch = (URL) async throws -> URL

    /// Streamed ayahs kept so a repeating passage doesn't fetch them again; the oldest go first.
    static let streamCacheLimit = 60
    nonisolated static let streamCacheFolder = "Streamed"

    private(set) var source: AudioSource
    private var fileStore: AudioFileStore
    private var streamCache: AudioFileStore
    private let streamCacheDirectory: URL
    private let fetchFile: Fetch
    var allowStreaming = true
    /// Asks for missing ayahs to be saved, nearest first; returns false when automatic downloads are off.
    var downloadMissingAudio: (([Int]) -> Bool)?
    /// Whether missing ayahs are being saved, so playback can wait for them instead of failing.
    private var downloadsMissingAudio = false
    private var failedDownloads = Set<Int>()
    private var waiters: [Int: [UUID: CheckedContinuation<Void, Error>]] = [:]

    init(
        source: AudioSource,
        fileStore: AudioFileStore,
        streamCacheDirectory: URL = AyahAudioResolver.defaultStreamCacheDirectory,
        fetch: @escaping Fetch = AyahAudioResolver.download
    ) {
        self.source = source
        self.fileStore = fileStore
        self.streamCacheDirectory = streamCacheDirectory
        streamCache = AudioFileStore(reciter: source.reciter, baseDirectory: streamCacheDirectory)
        fetchFile = fetch
        try? streamCache.removeAllReciters()
    }

    nonisolated static var defaultStreamCacheDirectory: URL {
        URL.cachesDirectory.appending(path: streamCacheFolder, directoryHint: .isDirectory)
    }

    func use(source: AudioSource, fileStore: AudioFileStore) {
        self.source = source
        self.fileStore = fileStore
        try? streamCache.removeAllReciters()
        streamCache = AudioFileStore(reciter: source.reciter, baseDirectory: streamCacheDirectory)
        downloadsMissingAudio = false
        failedDownloads = []
        resumeAllWaiters(throwing: CancellationError())
    }

    func availability(of ayah: Int) -> Availability {
        if let url = fileStore.urlIfReady(reciter: source.reciter, globalAyah: ayah)
            ?? streamCache.urlIfReady(reciter: source.reciter, globalAyah: ayah) {
            return .ready(url)
        }
        if allowStreaming || (downloadsMissingAudio && !failedDownloads.contains(ayah)) {
            return .needsFetch
        }
        return .unavailable(downloadsMissingAudio ? .downloadFailed : .offlineAudioMissing)
    }

    /// Makes the ayah ready: streams it into the cache, or waits for its background download.
    func fetch(_ ayah: Int) async throws {
        guard allowStreaming else {
            try await waitForDownload(ayah)
            return
        }
        // Captured first, so a reciter switch mid-fetch can't file this audio under the new reciter.
        let cache = streamCache
        let temporary = try await fetchFile(source.remoteURL(for: ayah))
        _ = try cache.install(temporaryURL: temporary, globalAyah: ayah)
        cache.removeOldest(keeping: Self.streamCacheLimit)
    }

    /// Removes a file that wouldn't decode. True when the ayah can still be fetched again.
    func discardUnreadable(_ ayah: Int) -> Bool {
        if fileStore.isReady(ayah) {
            try? fileStore.remove(globalAyah: ayah)
            return allowStreaming
        }
        try? streamCache.remove(globalAyah: ayah)
        return false
    }

    /// Keeps the next few ayahs downloading, nearest first. Ayahs that already failed wait for `retryFailedDownloads`.
    func requestDownloads(order: [Int], current: Int?) {
        guard let downloadMissingAudio else { return }
        let missing = AudioPrefetch.ayahsToFetch(order: order, current: current) {
            fileStore.isReady($0) || failedDownloads.contains($0)
        }
        guard !missing.isEmpty else { return }
        downloadsMissingAudio = downloadMissingAudio(missing)
    }

    func retryFailedDownloads() {
        failedDownloads = []
    }

    func audioBecameAvailable(_ ayah: Int) {
        resumeWaiters(for: ayah, throwing: nil)
    }

    func audioDownloadFailed(_ ayah: Int) {
        failedDownloads.insert(ayah)
        resumeWaiters(for: ayah, throwing: AppError.downloadFailed)
    }

    private func waitForDownload(_ ayah: Int) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[ayah, default: [:]][id] = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.resumeWaiter(id, for: ayah, throwing: CancellationError()) }
        }
    }

    private func resumeWaiter(_ id: UUID, for ayah: Int, throwing error: Error) {
        guard let continuation = waiters[ayah]?.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    private func resumeWaiters(for ayah: Int, throwing error: Error?) {
        guard let pending = waiters.removeValue(forKey: ayah) else { return }
        for continuation in pending.values {
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
        }
    }

    private func resumeAllWaiters(throwing error: Error) {
        for ayah in Array(waiters.keys) { resumeWaiters(for: ayah, throwing: error) }
    }

    /// Fetches into a temporary file the caller then owns.
    nonisolated static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(AudioRequestHeader.acceptValue, forHTTPHeaderField: AudioRequestHeader.acceptField)
        let (file, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: file)
            throw AppError.httpStatus(http.statusCode)
        }
        return file
    }
}
