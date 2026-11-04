import Foundation
import OSLog

/// The app's identifier, for anything named after it: logs, background sessions.
nonisolated enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.dumblemon.SimpleQuran"
    static let name = "Simple Quran"
    static let publisher = "Dumb Lemon"

    private enum InfoKey {
        static let version = "CFBundleShortVersionString"
        static let build = "CFBundleVersion"
    }

    static let version = Bundle.main.object(forInfoDictionaryKey: InfoKey.version) as? String ?? ""
    static let build = Bundle.main.object(forInfoDictionaryKey: InfoKey.build) as? String ?? ""
    /// "1.0 (1)", as Settings shows it.
    static var displayVersion: String { "\(version) (\(build))" }
}

/// Every log the app writes, under its one subsystem.
nonisolated enum Log {
    private enum Category: String {
        case translation
        case rendering
        case quranScript = "quran-script"
        case recording
        case audio
        case playback
        case reciters
        case downloads
    }

    static let translation = logger(.translation)
    static let quranScript = logger(.quranScript)
    static let recording = logger(.recording)
    static let audio = logger(.audio)
    static let playback = logger(.playback)
    static let reciters = logger(.reciters)
    static let downloads = logger(.downloads)
    /// Intervals for Instruments' os_signpost track, to see what opening a long surah costs.
    static let rendering = OSSignposter(subsystem: AppIdentity.bundleID, category: Category.rendering.rawValue)
    /// Intervals for how long a tap on Play takes to become sound.
    static let playbackSignposts = OSSignposter(subsystem: AppIdentity.bundleID, category: Category.playback.rawValue)

    private static func logger(_ category: Category) -> Logger {
        Logger(subsystem: AppIdentity.bundleID, category: category.rawValue)
    }
}
