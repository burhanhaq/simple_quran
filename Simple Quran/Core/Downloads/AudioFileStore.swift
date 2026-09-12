import Foundation

struct AudioFileStore: Sendable {
    let reciter: Reciter
    private let fileManager: FileManager

    init(reciter: Reciter = .sudais, fileManager: FileManager = .default) {
        self.reciter = reciter
        self.fileManager = fileManager
    }

    func directory() throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appending(path: "Audio", directoryHint: .isDirectory)
            .appending(path: reciter.id, directoryHint: .isDirectory)
            .appending(path: "\(reciter.qualityKbps)", directoryHint: .isDirectory)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = folder
            try mutable.setResourceValues(values)
        }
        return folder
    }

    func fileURL(globalAyah: Int) throws -> URL {
        try directory().appending(path: "\(globalAyah).mp3")
    }

    func urlIfReady(reciter: Reciter, globalAyah: Int) -> URL? {
        guard reciter.id == self.reciter.id,
              let url = try? fileURL(globalAyah: globalAyah),
              fileManager.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    func isReady(_ globalAyah: Int) -> Bool {
        urlIfReady(reciter: reciter, globalAyah: globalAyah) != nil
    }

    func install(temporaryURL: URL, globalAyah: Int) throws -> URL {
        let destination = try fileURL(globalAyah: globalAyah)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = destination
        try mutable.setResourceValues(values)
        return destination
    }

    func remove(globalAyah: Int) throws {
        let url = try fileURL(globalAyah: globalAyah)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func removeAll() throws {
        let dir = try directory()
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        _ = try directory()
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

    func readyAyahs() -> Set<Int> {
        guard let dir = try? directory(),
              let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        return Set(files.compactMap { url in
            Int(url.deletingPathExtension().lastPathComponent)
        })
    }
}
