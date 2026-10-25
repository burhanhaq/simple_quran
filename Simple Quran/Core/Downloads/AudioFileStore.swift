import Foundation

nonisolated struct AudioFileStore {
    static let minimumPlayableBytes: Int64 = 1_000
    let reciter: Reciter
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(
        reciter: Reciter = .sudais,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.reciter = reciter
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    /// The same storage, for another reciter.
    func with(reciter: Reciter) -> AudioFileStore {
        AudioFileStore(reciter: reciter, fileManager: fileManager, baseDirectory: baseDirectory)
    }

    /// Holds one folder per reciter.
    func audioRoot() throws -> URL {
        let base = try baseDirectory ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "Audio", directoryHint: .isDirectory)
    }

    /// This reciter's folder, created on first use.
    func directory() throws -> URL {
        let folder = try folderURL()
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = folder
            try mutable.setResourceValues(values)
        }
        return folder
    }

    /// Where an ayah lives. Looking doesn't create the folder; installing does.
    func fileURL(globalAyah: Int) throws -> URL {
        try folderURL().appending(path: "\(globalAyah).mp3")
    }

    private func folderURL() throws -> URL {
        try audioRoot()
            .appending(path: reciter.id, directoryHint: .isDirectory)
            .appending(path: "\(reciter.qualityKbps)", directoryHint: .isDirectory)
    }

    func urlIfReady(reciter: Reciter, globalAyah: Int) -> URL? {
        guard reciter.id == self.reciter.id,
              let url = try? fileURL(globalAyah: globalAyah),
              fileManager.fileExists(atPath: url.path),
              byteCount(globalAyah: globalAyah) >= Self.minimumPlayableBytes
        else { return nil }
        return url
    }

    func isReady(_ globalAyah: Int) -> Bool {
        urlIfReady(reciter: reciter, globalAyah: globalAyah) != nil
    }

    func install(temporaryURL: URL, globalAyah: Int) throws -> URL {
        let destination = try directory().appending(path: "\(globalAyah).mp3")
        let staging = destination
            .deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString).mp3")
        do {
            try fileManager.moveItem(at: temporaryURL, to: staging)
            guard let size = try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  Int64(size) >= Self.minimumPlayableBytes,
                  Self.startsLikeMP3(staging)
            else { throw AppError.invalidAudio }
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: staging.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = staging
            try mutable.setResourceValues(values)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func remove(globalAyah: Int) throws {
        let url = try fileURL(globalAyah: globalAyah)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func byteCount(globalAyah: Int) -> Int64 {
        guard let url = try? fileURL(globalAyah: globalAyah),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }

    func totalByteCount() -> Int64 {
        guard let dir = try? directory(),
              let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    /// Everything saved for `reciterID`, at any quality.
    func byteCount(reciterID: String) -> Int64 {
        guard let folder = try? audioRoot().appending(path: reciterID, directoryHint: .isDirectory) else { return 0 }
        return byteCount(under: folder)
    }

    /// Everything saved, for every reciter.
    func totalByteCountAllReciters() -> Int64 {
        guard let root = try? audioRoot() else { return 0 }
        return byteCount(under: root)
    }

    /// Reciters with a folder on the device.
    func storedReciterIDs() -> Set<String> {
        guard let root = try? audioRoot(),
              let folders = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return Set(folders.map(\.lastPathComponent))
    }

    func remove(reciterID: String) throws {
        let folder = try audioRoot().appending(path: reciterID, directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }

    /// Removes every reciter's audio.
    func removeAllReciters() throws {
        let root = try audioRoot()
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        _ = try directory()
    }

    /// Servers sometimes answer 200 with something that isn't audio, such as an error page,
    /// so a file must begin with an ID3 tag or an MPEG frame sync (11 set bits).
    static func startsLikeMP3(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 3), head.count == 3 else { return false }
        let bytes = [UInt8](head)
        return bytes == Array("ID3".utf8) || (bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0)
    }

    private func byteCount(under folder: URL) -> Int64 {
        guard let files = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.compactMap { $0 as? URL }.reduce(0) { partial, url in
            partial + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func readyAyahs() -> Set<Int> {
        guard let dir = try? directory(),
              let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return Set(files.compactMap { url in
            Int(url.deletingPathExtension().lastPathComponent)
        })
    }
}
