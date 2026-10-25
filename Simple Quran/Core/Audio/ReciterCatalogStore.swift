import Foundation
import Observation
import OSLog

/// Where the reciter catalog is published. While this is nil, only the bundled catalog is used.
nonisolated enum RemoteCatalog {
    static let url: URL? = nil
    static let refreshInterval: TimeInterval = 24 * 60 * 60
}

/// The reciter catalog in use: the last published one the app fetched, otherwise the bundled one.
/// A fetch sends a plain GET with no identifiers, so the app stays free of tracking.
@MainActor
@Observable
final class ReciterCatalogStore {
    private(set) var catalog: ReciterCatalog
    /// A newly fetched catalog differs from the one in use.
    var onCatalogChanged: ((ReciterCatalog) -> Void)?

    private let remoteURL: URL?
    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheURL: URL?
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "reciters")

    private enum Key {
        static let lastChecked = "reciters.lastChecked"
        static let etag = "reciters.etag"
    }

    init(
        remoteURL: URL? = RemoteCatalog.url,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = ReciterCatalogStore.defaultCacheURL(),
        bundle: Bundle = .main
    ) {
        self.remoteURL = remoteURL
        self.session = session
        self.defaults = defaults
        self.cacheURL = cacheURL
        let bundled = (try? ReciterCatalog.bundled(bundle)) ?? .fallback
        // A cache only counts while a remote catalog is configured; otherwise the bundled one is the truth.
        if remoteURL != nil, let cached = Self.loadCache(cacheURL) {
            catalog = cached
        } else {
            catalog = bundled
            // Without a cache, an unchanged (304) reply would leave the app on the bundled catalog.
            defaults.removeObject(forKey: Key.etag)
        }
    }

    /// Fetches the published catalog at most once a day. Any failure keeps the catalog in use.
    func refreshIfNeeded(now: Date = .now) async {
        guard let remoteURL else { return }
        if let last = defaults.object(forKey: Key.lastChecked) as? Date,
           now.timeIntervalSince(last) < RemoteCatalog.refreshInterval { return }
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData)
        if let etag = defaults.string(forKey: Key.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            defaults.set(now, forKey: Key.lastChecked)
            guard http.statusCode == 200 else { return }
            let fetched = try ReciterCatalog.decode(data)
            if let cacheURL { try data.write(to: cacheURL, options: .atomic) }
            defaults.set(http.value(forHTTPHeaderField: "ETag"), forKey: Key.etag)
            guard fetched != catalog else { return }
            catalog = fetched
            onCatalogChanged?(fetched)
        } catch {
            logger.error("Reciter catalog refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func defaultCacheURL(fileManager: FileManager = .default) -> URL? {
        try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "\(ReciterCatalog.File.name).\(ReciterCatalog.File.fileExtension)")
    }

    private static func loadCache(_ url: URL?) -> ReciterCatalog? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? ReciterCatalog.decode(data)
    }
}
