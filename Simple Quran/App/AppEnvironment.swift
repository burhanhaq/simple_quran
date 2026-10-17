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
        static let showsStatusChangeNote = "settings.showsStatusChangeNote"
        static let startTab = "settings.startTab"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let legacyLearningStart = "learning.start"
        static let legacyLearningEnd = "learning.end"
    }

    var learningTargets: [LearningTarget] {
        didSet {
            if let data = try? JSONEncoder().encode(learningTargets) {
                defaults.set(data, forKey: "learning.targets")
            }
        }
    }
    var activeTargetID: UUID? {
        didSet { defaults.set(activeTargetID?.uuidString, forKey: "learning.activeTarget") }
    }

    /// The one plan that drives "New" each day; other targets wait as "Up next".
    var activePlan: LearningTarget? {
        learningTargets.first { $0.id == activeTargetID } ?? learningTargets.first
    }

    func setActivePlan(_ target: LearningTarget) {
        if let existing = learningTargets.first(where: { $0.range == target.range }) {
            activeTargetID = existing.id
        } else {
            learningTargets.append(target)
            activeTargetID = target.id
        }
    }

    func removePlan(id: UUID) {
        learningTargets.removeAll { $0.id == id }
        if activeTargetID == id { activeTargetID = learningTargets.first?.id }
    }

    /// Saves where the user is in a plan. Never changes which plan is active.
    func remember(_ range: VerseRange, targetID: UUID?) {
        guard let index = learningTargets.firstIndex(where: { $0.id == targetID }),
              learningTargets[index].range.contains(range.startGlobalAyah),
              learningTargets[index].range.contains(range.endGlobalAyah) else { return }
        learningTargets[index].resumeRange = range
    }

    /// Earlier versions kept a single learning place outside any plan; turn it into the
    /// surah plan it belonged to so the user keeps their place.
    func adoptLegacyLearningPlace(catalog: some QuranCatalog) {
        let start = defaults.integer(forKey: Key.legacyLearningStart)
        let end = defaults.integer(forKey: Key.legacyLearningEnd)
        defaults.removeObject(forKey: Key.legacyLearningStart)
        defaults.removeObject(forKey: Key.legacyLearningEnd)
        guard learningTargets.isEmpty, start > 0, end >= start,
              let verse = catalog.verse(globalAyah: start),
              let surah = catalog.surah(number: verse.surahNumber) else { return }
        var plan = LearningTarget(range: surah.range)
        if surah.range.contains(end) { plan.resumeRange = .clamped(start: start, end: end) }
        setActivePlan(plan)
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

    /// The tab the app opens on: memorizers start on Memorize, readers on Quran.
    var startTab: AppTab {
        didSet { defaults.set(startTab.rawValue, forKey: Key.startTab) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Shown once to people whose earlier progress was recounted under explicit memorization.
    var showsStatusChangeNote: Bool {
        didSet { defaults.set(showsStatusChangeNote, forKey: Key.showsStatusChangeNote) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        learningTargets = defaults.data(forKey: "learning.targets")
            .flatMap { try? JSONDecoder().decode([LearningTarget].self, from: $0) } ?? []
        activeTargetID = defaults.string(forKey: "learning.activeTarget").flatMap(UUID.init(uuidString:))
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
        self.showsStatusChangeNote = defaults.bool(forKey: Key.showsStatusChangeNote)
        self.startTab = defaults.string(forKey: Key.startTab).flatMap(AppTab.init(rawValue:)) ?? .memorize
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
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
    var selectedTab: AppTab
    var route: AppRoute?
    /// The session behind the current practice playback, so the mini player can return to it.
    var lastSession: SessionRoute?
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
        selectedTab = settings.startTab
        settings.adoptLegacyLearningPlace(catalog: quran)
        // People updating from an earlier version get the one-time note instead of onboarding.
        if !settings.hasCompletedOnboarding,
           settings.showsStatusChangeNote || !settings.learningTargets.isEmpty || settings.readingAyah > 0 {
            settings.hasCompletedOnboarding = true
        }
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
        route = .reader(ReaderRoute(destination: destination))
    }

    func openSession(_ range: VerseRange, kind: SessionKind = .learn, planID: UUID? = nil) {
        route = .session(SessionRoute(range: range, kind: kind, planID: planID))
    }

    func openReviews(_ passages: [VerseRange]) {
        guard let first = passages.first else { return }
        route = .session(SessionRoute(range: first, kind: .review, reviewQueue: Array(passages.dropFirst())))
    }

    /// A session for a passage saved by an earlier version of the app.
    func savedPracticeRoute(_ set: PracticeSet) -> SessionRoute? {
        let ranges = set.orderedPassages.map(\.range)
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return SessionRoute(range: .clamped(start: first.startGlobalAyah, end: last.endGlobalAyah), savedPractice: set,
                            resumePlayback: playback.activeSet?.id == set.id)
    }

    func reopenPlayer() {
        guard let ayah = playback.snapshot.currentGlobalAyah,
              let verse = quran.verse(globalAyah: ayah) else { return }
        if let active = playback.activeSet, let session = lastSession {
            route = .session(SessionRoute(range: session.range, kind: session.kind, planID: session.planID,
                                          reviewQueue: session.reviewQueue, savedPractice: active, resumePlayback: true))
        } else {
            route = .reader(ReaderRoute(destination: .surah(number: verse.surahNumber, scrollToAyah: ayah), resumePlayback: true))
        }
    }

    func practice(for range: VerseRange) throws -> PracticeSet {
        if let existing = try store.activeSets().first(where: { $0.orderedPassages.map(\.range) == [range] }) {
            return existing
        }
        let title = PassageLabel.passage(range, catalog: quran)
        let created = try store.createSet(title: title, passages: [range], settings: .memorize)
        settings.generatedPracticeIDs.append(created.id.uuidString)
        return created
    }


}

enum AppTab: String, Hashable, CaseIterable {
    case memorize
    case progress
    case quran

    var title: String {
        switch self {
        case .memorize: String(localized: "Memorize")
        case .progress: String(localized: "Progress")
        case .quran: String(localized: "Quran")
        }
    }

    var systemImage: String {
        switch self {
        case .memorize: "leaf"
        case .progress: "square.grid.3x3.fill"
        case .quran: "book"
        }
    }
}
