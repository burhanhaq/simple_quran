import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private enum Key {
        static let wifiOnly = "settings.wifiOnly"
        static let streamWhenMissing = "settings.streamWhenMissing"
        static let lastTab = "settings.lastTab"
    }

    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Key.wifiOnly) }
    }

    var streamWhenMissing: Bool {
        didSet { defaults.set(streamWhenMissing, forKey: Key.streamWhenMissing) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.wifiOnly = defaults.object(forKey: Key.wifiOnly) as? Bool ?? false
        self.streamWhenMissing = defaults.object(forKey: Key.streamWhenMissing) as? Bool ?? true
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let quran: BundledQuranCatalog
    let store: PracticeStore
    let audioSource: AudioSource
    let downloads: AudioDownloadManager
    let playback: PlaybackCoordinator
    let recorder: RecitationRecordingController
    let settings: AppSettings
    var selectedTab: AppTab = .home
    var catalogLoadError: UserFacingMessage?

    init(
        quran: BundledQuranCatalog,
        store: PracticeStore,
        audioSource: AudioSource,
        downloads: AudioDownloadManager,
        playback: PlaybackCoordinator,
        recorder: RecitationRecordingController,
        settings: AppSettings
    ) {
        self.quran = quran
        self.store = store
        self.audioSource = audioSource
        self.downloads = downloads
        self.playback = playback
        self.recorder = recorder
        self.settings = settings
        playback.configure(catalog: quran, allowStreaming: settings.streamWhenMissing)
        downloads.updateCellular(!settings.wifiOnly)
    }
}

enum AppTab: Hashable {
    case home
    case quran
    case sets
    case progress
}
