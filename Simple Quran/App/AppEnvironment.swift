import Foundation
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case night
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: String(localized: "Light")
        case .night: String(localized: "Dark")
        case .system: String(localized: "System")
        }
    }
}

enum QuranReadingLayout: String, CaseIterable, Identifiable {
    case ayahByAyah
    case mushaf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ayahByAyah: String(localized: "Ayah by Ayah")
        case .mushaf: String(localized: "Continuous text")
        }
    }

    var systemImage: String {
        switch self {
        case .ayahByAyah: "list.bullet"
        case .mushaf: "text.alignright"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private enum Key {
        static let wifiOnly = "settings.wifiOnly"
        static let streamWhenMissing = "settings.streamWhenMissing"
        static let lastTab = "settings.lastTab"
        static let quranReadingLayout = "settings.quranReadingLayout"
        static let hasSeenQuranHint = "settings.hasSeenQuranHint"
        static let appearance = "settings.appearance"
    }

    var learningStart: Int {
        didSet { defaults.set(learningStart, forKey: "learning.start") }
    }
    var learningEnd: Int {
        didSet { defaults.set(learningEnd, forKey: "learning.end") }
    }
    var readingAyah: Int {
        didSet { defaults.set(readingAyah, forKey: "reading.ayah") }
    }
    var practiceByPage: Bool {
        didSet { defaults.set(practiceByPage, forKey: "learning.byPage") }
    }
    var generatedPracticeIDs: [String] {
        didSet { defaults.set(generatedPracticeIDs, forKey: "learning.generatedIDs") }
    }

    func remember(_ range: VerseRange) {
        learningStart = range.startGlobalAyah
        learningEnd = range.endGlobalAyah
    }

    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Key.wifiOnly) }
    }

    var streamWhenMissing: Bool {
        didSet { defaults.set(streamWhenMissing, forKey: Key.streamWhenMissing) }
    }

    var quranReadingLayout: QuranReadingLayout {
        didSet { defaults.set(quranReadingLayout.rawValue, forKey: Key.quranReadingLayout) }
    }

    var hasSeenQuranHint: Bool {
        didSet { defaults.set(hasSeenQuranHint, forKey: Key.hasSeenQuranHint) }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        learningStart = defaults.integer(forKey: "learning.start")
        learningEnd = defaults.integer(forKey: "learning.end")
        readingAyah = defaults.integer(forKey: "reading.ayah")
        practiceByPage = defaults.bool(forKey: "learning.byPage")
        generatedPracticeIDs = defaults.stringArray(forKey: "learning.generatedIDs") ?? []
        self.wifiOnly = defaults.object(forKey: Key.wifiOnly) as? Bool ?? false
        self.streamWhenMissing = defaults.object(forKey: Key.streamWhenMissing) as? Bool ?? true
        self.quranReadingLayout = defaults.string(forKey: Key.quranReadingLayout)
            .flatMap(QuranReadingLayout.init(rawValue:)) ?? .ayahByAyah
        self.hasSeenQuranHint = defaults.bool(forKey: Key.hasSeenQuranHint)
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
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
    var readerRoute: ReaderRoute?
    var activePracticeIsReview = false
    var catalogLoadError: UserFacingMessage?
    var persistenceLoadError: UserFacingMessage?

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
        playback.onWillStartAudio = { [weak recorder] in
            recorder?.cancelComparisonPlayback()
        }
        playback.onPositionChanged = { [weak playback, weak store, weak settings] ayah in
            if let active = playback?.activeSet {
                active.lastGlobalAyah = ayah
                do { try store?.save() }
                catch { playback?.userMessage = .from(.persistenceFailure) }
            } else { settings?.readingAyah = ayah }
        }
        downloads.updateCellular(!settings.wifiOnly)
    }

    func openReader(_ destination: QuranDestination) {
        readerRoute = ReaderRoute(destination: destination)
    }

    func openPractice(_ range: VerseRange, isReview: Bool = false) {
        guard let verse = quran.verse(globalAyah: range.startGlobalAyah) else { return }
        readerRoute = ReaderRoute(destination: .surah(number: verse.surahNumber, scrollToAyah: range.startGlobalAyah), practiceRange: range, isReview: isReview)
    }

    func reopenPlayer() {
        guard let ayah = playback.snapshot.currentGlobalAyah,
              let verse = quran.verse(globalAyah: ayah) else { return }
        readerRoute = ReaderRoute(destination: .surah(number: verse.surahNumber, scrollToAyah: ayah),
                                  savedPractice: playback.activeSet, resumePlayback: true, isReview: activePracticeIsReview)
    }

    func practice(for range: VerseRange) throws -> PracticeSet {
        if let existing = try store.activeSets().first(where: { $0.orderedPassages.map(\.range) == [range] }) {
            return existing
        }
        let title = PassageLabel.passage(range, catalog: quran)
        let created = try store.createSet(title: title, passages: [range], settings: .default)
        settings.generatedPracticeIDs.append(created.id.uuidString)
        return created
    }


}

enum AppTab: Hashable {
    case home
    case quran
}
