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
    /// Saved as "mushaf" from when it was the only mushaf-style layout.
    case continuous = "mushaf"
    /// Whole 15-line Madani pages, one per screen.
    case page

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ayahByAyah: String(localized: "Ayah by Ayah")
        case .continuous: String(localized: "Continuous text")
        case .page: String(localized: "Mushaf pages")
        }
    }

    /// Only ayah by ayah has room for a translation under each ayah.
    var showsTranslation: Bool { self == .ayahByAyah }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private enum Key {
        static let wifiOnly = "settings.wifiOnly"
        static let streamWhenMissing = "settings.streamWhenMissing"
        static let downloadWhilePlaying = "settings.downloadWhilePlaying"
        static let reciterID = "settings.reciterID"
        static let quranReadingLayout = "settings.quranReadingLayout"
        static let showsTranslation = "settings.showsTranslation"
        static let hasSeenTranslationLayoutNote = "settings.hasSeenTranslationLayoutNote"
        static let hasSeenQuranHint = "settings.hasSeenQuranHint"
        static let appearance = "settings.appearance"
        static let startTab = "settings.startTab"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let learningTargets = "learning.targets"
        static let activeTargetID = "learning.activeTarget"
        static let oneOffPlaces = "learning.oneOffPlaces"
        static let pieceSize = "learning.pieceSize"
        static let memorizePlayback = "learning.playback"
        static let revisionCycle = "learning.revisionCycle"
        static let dailyLog = "learning.dailyLog"
        static let readingAyah = "reading.ayah"
        static let recentSurahs = "reading.recentSurahs"
    }

    var learningTargets: [LearningTarget] {
        didSet {
            if let data = try? JSONEncoder().encode(learningTargets) {
                defaults.set(data, forKey: Key.learningTargets)
            }
        }
    }
    var activeTargetID: UUID? {
        didSet { defaults.set(activeTargetID?.uuidString, forKey: Key.activeTargetID) }
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

    /// Lines a target up after what the user is memorizing now, without switching to it.
    func queueNext(_ target: LearningTarget) {
        guard !learningTargets.contains(where: { $0.range == target.range }) else { return }
        learningTargets.append(target)
    }

    /// Whether `range` is already lined up after what the user is memorizing now.
    func isQueued(_ range: VerseRange) -> Bool {
        learningTargets.contains { $0.range == range && $0.id != activePlan?.id }
    }

    /// What the user finished today, for the Memorize checklist.
    var dailyLog: DailyLog {
        didSet {
            if let data = try? JSONEncoder().encode(dailyLog) { defaults.set(data, forKey: Key.dailyLog) }
        }
    }

    func recordLearned(_ range: VerseRange, now: Date = .now) {
        var log = dailyLog.forToday(now: now)
        log.learned = range
        dailyLog = log
    }

    func recordRevised(now: Date = .now) {
        var log = dailyLog.forToday(now: now)
        log.revised = true
        dailyLog = log
    }

    /// Where the user left off in each surah they memorize outside a plan, by surah number,
    /// so a range they chose there is where they carry on.
    var oneOffPlaces: [Int: VerseRange] {
        didSet {
            if let data = try? JSONEncoder().encode(oneOffPlaces) { defaults.set(data, forKey: Key.oneOffPlaces) }
        }
    }

    /// Saves where the user is: in the plan they're working through, or without one, in the
    /// passage's surah. Never changes which plan is active.
    func remember(_ range: VerseRange, targetID: UUID?) {
        guard let targetID else {
            if let surah = QuranCatalogMetrics.surahNumber(containing: range.startGlobalAyah) { oneOffPlaces[surah] = range }
            return
        }
        guard let index = learningTargets.firstIndex(where: { $0.id == targetID }),
              learningTargets[index].range.contains(range.startGlobalAyah),
              learningTargets[index].range.contains(range.endGlobalAyah) else { return }
        learningTargets[index].resumeRange = range
    }

    /// What the user is memorizing, when it takes in all of `range`. Memorizing anything else is one-off.
    func activePlan(covering range: VerseRange) -> LearningTarget? {
        activePlan.flatMap { $0.range.contains(range) ? $0 : nil }
    }

    /// Where the user left off inside `range`: their place in what they're memorizing first,
    /// then their places in one-off surahs in reading order.
    func resumeRanges(within range: VerseRange) -> [VerseRange] {
        let planPlace = activePlan?.resumeRange.map { [$0] } ?? []
        let oneOff = oneOffPlaces.values.sorted { $0.startGlobalAyah < $1.startGlobalAyah }
        return (planPlace + oneOff).filter { range.contains($0) }
    }

    var readingAyah: Int {
        didSet { defaults.set(readingAyah, forKey: Key.readingAyah) }
    }
    /// Surahs the user last listened to, most recent first, for CarPlay's Recent list.
    private(set) var recentSurahs: [Int] {
        didSet { defaults.set(recentSurahs, forKey: Key.recentSurahs) }
    }
    static let recentSurahLimit = 5

    func noteListened(surah: Int) {
        guard recentSurahs.first != surah else { return }
        recentSurahs = Array(([surah] + recentSurahs.filter { $0 != surah }).prefix(Self.recentSurahLimit))
    }
    /// How much of a page each memorize piece covers, for every plan and passage.
    var pieceSize: PieceSize {
        didSet { defaults.set(pieceSize.rawValue, forKey: Key.pieceSize) }
    }
    /// How often the user means to revise what they've memorized; drives fresh, fading, and needs revision.
    var revisionCycle: RevisionCycle {
        didSet { defaults.set(revisionCycle.rawValue, forKey: Key.revisionCycle) }
    }
    /// How memorize passages play: one setting for all of them, so a new passage never resets it.
    var memorizePlayback: PracticeSettings {
        didSet {
            if let data = try? JSONEncoder().encode(memorizePlayback) { defaults.set(data, forKey: Key.memorizePlayback) }
        }
    }

    var wifiOnly: Bool {
        didSet { defaults.set(wifiOnly, forKey: Key.wifiOnly) }
    }

    var streamWhenMissing: Bool {
        didSet { defaults.set(streamWhenMissing, forKey: Key.streamWhenMissing) }
    }

    /// Saves recitation that isn't on the device yet whenever it is played.
    var downloadWhilePlaying: Bool {
        didSet { defaults.set(downloadWhilePlaying, forKey: Key.downloadWhilePlaying) }
    }

    /// The reciter the user listens to; nil only until the first launch resolves it.
    var reciterID: String? {
        didSet { defaults.set(reciterID, forKey: Key.reciterID) }
    }

    /// Settles on the catalog's default the first time, so a later catalog with a new default
    /// never switches the reciter someone is used to.
    func resolveFirstReciter(catalog: ReciterCatalog) {
        guard reciterID == nil else { return }
        reciterID = catalog.defaultReciterID
    }

    /// The chosen reciter, or the catalog's default when the catalog no longer offers them.
    func reciter(in catalog: ReciterCatalog) -> Reciter {
        catalog.reciter(id: reciterID) ?? catalog.defaultReciter
    }

    /// The layout the user chose. Translation shows ayah by ayah without changing it.
    var quranReadingLayout: QuranReadingLayout {
        didSet {
            defaults.set(quranReadingLayout.rawValue, forKey: Key.quranReadingLayout)
            // Only ayah by ayah can show translations, so choosing another layout turns them off.
            if !quranReadingLayout.showsTranslation { showsTranslation = false }
        }
    }

    /// What the reader shows: ayah by ayah while translation is on, otherwise the chosen layout.
    /// Choosing a layout here saves it.
    var displayedReadingLayout: QuranReadingLayout {
        get { showsTranslation ? .ayahByAyah : quranReadingLayout }
        set { quranReadingLayout = newValue }
    }

    /// Shows the translation under each ayah, reading or memorizing.
    var showsTranslation: Bool {
        didSet { defaults.set(showsTranslation, forKey: Key.showsTranslation) }
    }

    var hasSeenTranslationLayoutNote: Bool {
        didSet { defaults.set(hasSeenTranslationLayoutNote, forKey: Key.hasSeenTranslationLayoutNote) }
    }

    /// Translation just took another layout to ayah by ayah, which is explained once.
    var needsTranslationLayoutNote: Bool {
        showsTranslation && !quranReadingLayout.showsTranslation && !hasSeenTranslationLayoutNote
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        learningTargets = defaults.data(forKey: Key.learningTargets)
            .flatMap { try? JSONDecoder().decode([LearningTarget].self, from: $0) } ?? []
        activeTargetID = defaults.string(forKey: Key.activeTargetID).flatMap(UUID.init(uuidString:))
        oneOffPlaces = defaults.data(forKey: Key.oneOffPlaces)
            .flatMap { try? JSONDecoder().decode([Int: VerseRange].self, from: $0) } ?? [:]
        dailyLog = defaults.data(forKey: Key.dailyLog)
            .flatMap { try? JSONDecoder().decode(DailyLog.self, from: $0) } ?? .empty(on: .now)
        readingAyah = defaults.integer(forKey: Key.readingAyah)
        recentSurahs = defaults.array(forKey: Key.recentSurahs) as? [Int] ?? []
        pieceSize = defaults.string(forKey: Key.pieceSize).flatMap(PieceSize.init(rawValue:)) ?? .default
        revisionCycle = RevisionCycle(rawValue: defaults.integer(forKey: Key.revisionCycle)) ?? .default
        memorizePlayback = defaults.data(forKey: Key.memorizePlayback)
            .flatMap { try? JSONDecoder().decode(PracticeSettings.self, from: $0) } ?? .default
        self.wifiOnly = defaults.object(forKey: Key.wifiOnly) as? Bool ?? false
        self.streamWhenMissing = defaults.object(forKey: Key.streamWhenMissing) as? Bool ?? true
        self.downloadWhilePlaying = defaults.object(forKey: Key.downloadWhilePlaying) as? Bool ?? true
        self.reciterID = defaults.string(forKey: Key.reciterID)
        self.quranReadingLayout = defaults.string(forKey: Key.quranReadingLayout)
            .flatMap(QuranReadingLayout.init(rawValue:)) ?? .ayahByAyah
        self.showsTranslation = defaults.bool(forKey: Key.showsTranslation)
        self.hasSeenTranslationLayoutNote = defaults.bool(forKey: Key.hasSeenTranslationLayoutNote)
        self.hasSeenQuranHint = defaults.bool(forKey: Key.hasSeenQuranHint)
        self.appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        self.startTab = defaults.string(forKey: Key.startTab).flatMap(AppTab.init(rawValue:)) ?? .memorize
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let quran: BundledQuranCatalog
    let store: PracticeStore
    private(set) var audioSource: AlQuranCloudAudioSource
    let reciters: ReciterCatalogStore
    let downloads: AudioDownloadManager
    let playback: PlaybackCoordinator
    let recorder: RecitationRecordingController
    let settings: AppSettings
    let reviewPrompt: ReviewPrompt
    let translations = TranslationLibrary()
    /// The 15-line pages, loaded the first time "Mushaf pages" is shown. Nil if the layout is missing or corrupt.
    @ObservationIgnored private(set) lazy var mushafPages: MushafPageLibrary? = (try? MushafLayout.loadFromBundle())
        .map { MushafPageLibrary(layout: $0, catalog: self.quran) }
    var selectedTab: AppTab
    var route: AppRoute?
    /// The session behind the current practice playback, so the mini player can return to it.
    var lastSession: SessionRoute?
    var catalogLoadError: UserFacingMessage?
    var persistenceLoadError: UserFacingMessage?

    init(
        quran: BundledQuranCatalog,
        store: PracticeStore,
        audioSource: AlQuranCloudAudioSource,
        reciters: ReciterCatalogStore,
        downloads: AudioDownloadManager,
        playback: PlaybackCoordinator,
        recorder: RecitationRecordingController,
        settings: AppSettings,
        reviewPrompt: ReviewPrompt
    ) {
        self.quran = quran
        self.store = store
        self.audioSource = audioSource
        self.reciters = reciters
        self.downloads = downloads
        self.playback = playback
        self.recorder = recorder
        self.settings = settings
        self.reviewPrompt = reviewPrompt
        selectedTab = settings.startTab
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
            if let surah = quran.verse(globalAyah: ayah)?.surahNumber { settings?.noteListened(surah: surah) }
        }
        playback.onListened = { [weak reviewPrompt] in reviewPrompt?.recordListen() }
        playback.onAyahHeard = { [weak playback, weak store] ayah in
            do { try store?.recordHeard(globalAyah: ayah, at: .now) }
            catch { playback?.userMessage = .from(.persistenceFailure) }
        }
        playback.downloadMissingAudio = { [weak downloads, weak settings] ayahs in
            guard settings?.downloadWhilePlaying == true, let downloads else { return false }
            downloads.download(ayahs: ayahs, reportsFailures: false)
            return true
        }
        downloads.onAudioReady = { [weak playback] ayah in playback?.audioBecameAvailable(ayah) }
        downloads.onAudioFailed = { [weak playback] ayah in playback?.audioDownloadFailed(ayah) }
        downloads.updateCellular(!settings.wifiOnly)
        reciters.onCatalogChanged = { [weak self] catalog in
            self?.downloads.removeReciters(notIn: Set(catalog.reciters.map(\.id)))
            self?.applyReciter()
        }
    }

    func selectReciter(_ reciter: Reciter) {
        settings.reciterID = reciter.id
        applyReciter()
    }

    /// Points playback and downloads at the chosen reciter from the current catalog.
    private func applyReciter() {
        let catalog = reciters.catalog
        let source = catalog.audioSource(for: settings.reciter(in: catalog))
        guard source != audioSource else { return }
        let files = downloads.fileStore.with(reciter: source.reciter)
        audioSource = source
        downloads.use(source: source, fileStore: files)
        playback.use(source: source, fileStore: files)
    }

    /// Plays passages straight through, as the Quran tab, CarPlay and Siri listen. Asking again for what's
    /// already loaded carries on from where it paused, unless `restart` starts it over from `fromAyah`.
    func listen(title: String, passages: [VerseRange], fromAyah: Int? = nil, restart: Bool = false) {
        if restart || playback.activeSet != nil || !playback.isPrepared(for: passages) {
            playback.startListening(title: title, passages: passages, fromAyah: fromAyah,
                                    catalog: quran, allowStreaming: settings.streamWhenMissing)
        }
        lastSession = nil
        playback.resume()
    }

    /// Opens the surah screen. Readers start with the text in full view; Progress opens the overview.
    func openReader(_ destination: QuranDestination, sheet: SurahSheetStart = .peek) {
        route = .reader(ReaderRoute(destination: destination, sheet: sheet))
    }

    /// `scope` is what the user chose to memorize (a surah, juz, or range), so "Next passage"
    /// carries on through it. Without one, the passage's surah.
    func openSession(_ range: VerseRange, kind: SessionKind = .learn, planID: UUID? = nil, scope: VerseRange? = nil) {
        route = .session(SessionRoute(range: range, kind: kind, planID: planID, scope: scope))
    }

    func openReviews(_ passages: [VerseRange]) {
        guard let first = passages.first else { return }
        route = .session(SessionRoute(range: first, kind: .review, reviewQueue: Array(passages.dropFirst())))
    }

    func reopenPlayer() {
        guard let ayah = playback.snapshot.currentGlobalAyah,
              let verse = quran.verse(globalAyah: ayah) else { return }
        if let active = playback.activeSet, let session = lastSession {
            route = .session(SessionRoute(range: session.range, kind: session.kind, planID: session.planID, scope: session.scope,
                                          reviewQueue: session.reviewQueue, savedPractice: active, resumePlayback: true))
        } else {
            route = .reader(ReaderRoute(destination: .surah(number: verse.surahNumber, scrollToAyah: ayah), resumePlayback: true))
        }
    }

    func practice(for range: VerseRange) throws -> PracticeSet {
        if let existing = try store.allSets().first(where: { $0.orderedPassages.map(\.range) == [range] }) {
            // Every passage follows the one memorize setting, keeping only whether its Arabic is hidden.
            let playback = settings.memorizePlayback.keepingHideArabic(of: existing.settings)
            if existing.settings != playback {
                existing.settings = playback
                try store.save()
            }
            return existing
        }
        let title = PassageLabel.passage(range, catalog: quran)
        return try store.createSet(title: title, passages: [range], settings: settings.memorizePlayback)
    }

}

enum AppTab: String, Hashable, CaseIterable {
    case memorize
    case quran

    var title: String {
        switch self {
        case .memorize: String(localized: "Memorize")
        case .quran: String(localized: "Quran")
        }
    }

    var systemImage: String {
        switch self {
        case .memorize: "leaf"
        case .quran: "book"
        }
    }
}
