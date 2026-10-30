import Foundation
import Testing
@testable import Simple_Quran

struct ReciterCatalogTests {
    @Test func bundledCatalogOffersTheVerifiedLaunchReciters() throws {
        let catalog = try ReciterCatalog.bundled()
        #expect(catalog.defaultReciterID == ReciterID.husary)
        #expect(catalog.host == AlQuranCloudAudioSource.defaultHost)
        let folders = Dictionary(uniqueKeysWithValues: catalog.reciters.map { ($0.id, $0.qualityKbps) })
        #expect(folders == [
            "ar.husary": 64,
            "ar.alafasy": 64,
            "ar.abdurrahmaansudais": 64,
            "ar.mahermuaiqly": 128,
            "ar.saoodshuraym": 64,
            "ar.shaatree": 64
        ])
        #expect(catalog.reciters.allSatisfy { ($0.averageAyahBytes ?? 0) > 0 && !$0.arabicName.isEmpty })
        #expect(catalog.reciter(id: ReciterID.sudais) == .sudais)
    }

    @Test func validationRejectsCatalogsTheAppCannotUse() {
        let good = ReciterCatalog.fallback
        #expect(throws: Never.self) { try good.validated() }

        var newer = good
        newer.schemaVersion = ReciterCatalog.supportedSchemaVersion + 1
        #expect(throws: ReciterCatalog.ValidationError.unsupportedSchema(newer.schemaVersion)) { try newer.validated() }

        var insecure = good
        insecure.host = URL(string: "http://cdn.example.org")!
        #expect(throws: ReciterCatalog.ValidationError.insecureHost("http://cdn.example.org")) { try insecure.validated() }

        var insecureReciter = good
        insecureReciter.reciters[0].host = URL(string: "http://cdn.example.org")!
        #expect(throws: ReciterCatalog.ValidationError.insecureHost("http://cdn.example.org")) { try insecureReciter.validated() }

        var empty = good
        empty.reciters = []
        #expect(throws: ReciterCatalog.ValidationError.empty) { try empty.validated() }

        var duplicated = good
        duplicated.reciters.append(.sudais)
        #expect(throws: ReciterCatalog.ValidationError.duplicateID(ReciterID.sudais)) { try duplicated.validated() }

        var badQuality = good
        badQuality.reciters[0].qualityKbps = 0
        #expect(throws: ReciterCatalog.ValidationError.invalidQuality(ReciterID.sudais)) { try badQuality.validated() }

        var unknownDefault = good
        unknownDefault.defaultReciterID = "ar.nobody"
        #expect(throws: ReciterCatalog.ValidationError.unknownDefault("ar.nobody")) { try unknownDefault.validated() }
    }
}

struct ReciterSettingTests {
    @Test @MainActor func newUsersStartOnTheCatalogDefaultAndKeepIt() throws {
        let catalog = try ReciterCatalog.bundled()

        let fresh = try isolatedDefaults()
        defer { fresh.defaults.removePersistentDomain(forName: fresh.name) }
        let newcomer = AppSettings(defaults: fresh.defaults)
        newcomer.resolveFirstReciter(catalog: catalog)
        #expect(newcomer.reciter(in: catalog).id == ReciterID.husary)
        // Once settled, it's kept even if a later catalog names a different default.
        newcomer.readingAyah = 10
        newcomer.resolveFirstReciter(catalog: catalog)
        #expect(AppSettings(defaults: fresh.defaults).reciterID == ReciterID.husary)
    }

    @Test @MainActor func aReciterTheCatalogDropsFallsBackToTheDefault() throws {
        let isolated = try isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.name) }
        let settings = AppSettings(defaults: isolated.defaults)
        settings.reciterID = "ar.withdrawn"
        let catalog = try ReciterCatalog.bundled()
        #expect(settings.reciter(in: catalog).id == catalog.defaultReciterID)
        // The choice is kept, so the reciter returns if the catalog offers them again.
        #expect(settings.reciterID == "ar.withdrawn")
    }

    private func isolatedDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "reciter-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (name, defaults)
    }
}

struct ReciterStorageTests {
    @Test func installAcceptsOnlyFilesThatStartLikeMP3() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioFileStore(reciter: .sudais, baseDirectory: root)
        let padding = Data(repeating: 0x20, count: 2_000)

        let errorPage = root.appending(path: "page.mp3")
        try (Data("<html><head><title> Error".utf8) + padding).write(to: errorPage)
        #expect(throws: AppError.invalidAudio) { _ = try store.install(temporaryURL: errorPage, globalAyah: 1) }

        let noise = root.appending(path: "noise.mp3")
        try (Data([0xB8, 0xB6, 0x08, 0x7F]) + padding).write(to: noise)
        #expect(throws: AppError.invalidAudio) { _ = try store.install(temporaryURL: noise, globalAyah: 2) }

        for (ayah, head) in [(3, Data("ID3".utf8)), (4, Data([0xFF, 0xFB, 0x90])), (5, Data([0xFF, 0xE7, 0x5B]))] {
            let file = root.appending(path: "\(ayah).tmp")
            try (head + padding).write(to: file)
            _ = try store.install(temporaryURL: file, globalAyah: ayah)
            #expect(store.isReady(ayah))
        }
    }

    @Test func sizesAndRemovalCoverEachReciterAndAll() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sudais = AudioFileStore(reciter: .sudais, baseDirectory: root)
        let husary = sudais.with(reciter: Reciter(id: ReciterID.husary, englishName: "Husary", arabicName: "الحصري", qualityKbps: 64))
        try install(2_000, into: sudais, ayah: 1, root: root)
        try install(3_000, into: husary, ayah: 1, root: root)
        try install(3_000, into: husary, ayah: 2, root: root)

        #expect(sudais.byteCount(reciterID: ReciterID.sudais) == 2_000)
        #expect(sudais.byteCount(reciterID: ReciterID.husary) == 6_000)
        #expect(sudais.totalByteCountAllReciters() == 8_000)
        #expect(sudais.storedReciterIDs() == [ReciterID.sudais, ReciterID.husary])

        try sudais.remove(reciterID: ReciterID.husary)
        #expect(sudais.storedReciterIDs() == [ReciterID.sudais])
        #expect(sudais.isReady(1))

        try husary.removeAllReciters()
        #expect(sudais.totalByteCountAllReciters() == 0)
        #expect(!sudais.isReady(1))
    }

    private func install(_ bytes: Int, into store: AudioFileStore, ayah: Int, root: URL) throws {
        let file = root.appending(path: UUID().uuidString)
        try (Data("ID3".utf8) + Data(repeating: 0, count: bytes - 3)).write(to: file)
        _ = try store.install(temporaryURL: file, globalAyah: ayah)
    }
}

@Suite(.serialized)
struct ReciterCatalogStoreTests {
    @Test @MainActor func withoutARemoteURLTheBundledCatalogIsUsedAndNothingIsFetched() async throws {
        let env = try StoreEnvironment()
        defer { env.tearDown() }
        // A stale cache is ignored while no remote catalog is configured.
        try catalogData(onlyReciter: "ar.alafasy").write(to: env.cacheURL)
        StubCatalogProtocol.reset()
        let store = ReciterCatalogStore(remoteURL: nil, session: env.session, defaults: env.defaults, cacheURL: env.cacheURL)
        await store.refreshIfNeeded()
        #expect(store.catalog == (try ReciterCatalog.bundled()))
        #expect(StubCatalogProtocol.requestCount == 0)
    }

    @Test @MainActor func aFetchedCatalogReplacesTheBundledOneAndIsCached() async throws {
        let env = try StoreEnvironment()
        defer { env.tearDown() }
        StubCatalogProtocol.reset(status: 200, body: try catalogData(onlyReciter: "ar.alafasy"), etag: "\"v2\"")
        let store = ReciterCatalogStore(remoteURL: env.remoteURL, session: env.session, defaults: env.defaults, cacheURL: env.cacheURL)
        var announced: ReciterCatalog?
        store.onCatalogChanged = { announced = $0 }
        let now = Date.now

        await store.refreshIfNeeded(now: now)
        #expect(store.catalog.reciters.map(\.id) == ["ar.alafasy"])
        #expect(announced == store.catalog)

        // Checked at most once a day.
        await store.refreshIfNeeded(now: now.addingTimeInterval(60))
        #expect(StubCatalogProtocol.requestCount == 1)

        // The next launch starts from the cache and asks only for changes.
        StubCatalogProtocol.reset(status: 304, body: Data(), etag: nil)
        let relaunched = ReciterCatalogStore(remoteURL: env.remoteURL, session: env.session, defaults: env.defaults, cacheURL: env.cacheURL)
        #expect(relaunched.catalog.reciters.map(\.id) == ["ar.alafasy"])
        await relaunched.refreshIfNeeded(now: now.addingTimeInterval(RemoteCatalog.refreshInterval + 1))
        #expect(StubCatalogProtocol.lastIfNoneMatch == "\"v2\"")
        #expect(relaunched.catalog.reciters.map(\.id) == ["ar.alafasy"])
    }

    @Test @MainActor func anInvalidOrCorruptCatalogIsIgnored() async throws {
        let env = try StoreEnvironment()
        defer { env.tearDown() }
        try Data("not json".utf8).write(to: env.cacheURL)
        var insecure = try ReciterCatalog.bundled()
        insecure.host = URL(string: "http://cdn.example.org")!
        StubCatalogProtocol.reset(status: 200, body: try JSONEncoder().encode(insecure), etag: nil)
        let store = ReciterCatalogStore(remoteURL: env.remoteURL, session: env.session, defaults: env.defaults, cacheURL: env.cacheURL)
        #expect(store.catalog == (try ReciterCatalog.bundled()))
        await store.refreshIfNeeded()
        #expect(store.catalog == (try ReciterCatalog.bundled()))
    }

    private func catalogData(onlyReciter id: String) throws -> Data {
        var catalog = try ReciterCatalog.bundled()
        catalog.reciters = catalog.reciters.filter { $0.id == id }
        catalog.defaultReciterID = id
        return try JSONEncoder().encode(catalog)
    }
}

private struct StoreEnvironment {
    let name = "reciter-catalog-\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let remoteURL = URL(string: "https://catalog.example.org/reciters.json")!
    let session: URLSession
    var cacheURL: URL { directory.appending(path: "reciters.json") }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubCatalogProtocol.self]
        session = URLSession(configuration: configuration)
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class StubCatalogProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var etag: String?
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastIfNoneMatch: String?

    static func reset(status: Int = 200, body: Data = Data(), etag: String? = nil) {
        self.status = status
        self.body = body
        self.etag = etag
        requestCount = 0
        lastIfNoneMatch = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        var headers = ["Content-Type": "application/json"]
        if let etag = Self.etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
