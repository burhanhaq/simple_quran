import AVFoundation
import Foundation
import OSLog
import UIKit

struct PlaybackSnapshot: Equatable {
    var setID: UUID?
    var setTitle: String
    var currentGlobalAyah: Int?
    var isPlaying: Bool
    var isLoading: Bool
    var hideArabic: Bool
    var ayahRepeat: RepeatCount
    var setRepeat: RepeatCount
    var pauseSeconds: Int
    var advanceManually: Bool
    var repetitionLabel: String
}

/// Decides what plays: walks the practice cursor, keeps a few segments queued on the
/// gapless player, and publishes the state the UI, Now Playing and CarPlay show.
@MainActor
@Observable
final class PlaybackCoordinator {
    /// Segments kept queued ahead. Cheap (files open lazily), and leaves time to fetch the next ayah.
    static let queueDepth = 4

    private let resolver: AyahAudioResolver
    private let nowPlaying: NowPlayingBridge
    private let logger = Log.playback

    private var player = GaplessAudioPlayer()
    /// The step playing now.
    private var cursor: PracticePlaybackCursor?
    /// The next step to queue; runs ahead of `cursor` by what's queued.
    private var queueCursor: PracticePlaybackCursor?
    /// What each queued segment plays. Each segment completes exactly one step.
    private var queuedSteps: [Int: QueueItem] = [:]
    private var lastSegmentID = 0
    /// Fetching the next ayah to queue. Queuing waits for it, so segments stay in order.
    private var fetchTask: Task<Void, Never>?
    private var preparedPassages: [VerseRange] = []
    private var preparedSettings: PracticeSettings = .listening
    private var catalog: (any QuranCatalog)?
    private var shouldAutoplay = false {
        didSet { updateIdleTimer() }
    }
    private var resumeAfterInterruption = false
    private var becomeActiveObserver: NSObjectProtocol?
    private var countedCurrentItem = false
    private var playbackBeganAt: Date?
    private(set) var listeningSeconds: Double = 0
    /// How long one playback has to run before it counts as a listening session.
    static let listenSeconds: TimeInterval = 60
    private var countedListen = false
    private static let startAudioSignpost: StaticString = "Start audio"
    /// Open from asking for audio until it plays, fails, or is paused.
    private var startAudioInterval: OSSignpostIntervalState?

    var snapshot = PlaybackSnapshot(
        setID: nil,
        setTitle: "",
        currentGlobalAyah: nil,
        isPlaying: false,
        isLoading: false,
        hideArabic: false,
        ayahRepeat: .one,
        setRepeat: .one,
        pauseSeconds: 0,
        advanceManually: false,
        repetitionLabel: ""
    )
    var userMessage: UserFacingMessage?
    var coveredAyahs = Set<Int>()
    var repetitionCount = 0
    var session: PracticeSession?
    var activeSet: PracticeSet?
    var versesInSet: [QuranVerse] = []
    var onWillStartAudio: (() -> Void)?
    var onPositionChanged: ((Int) -> Void)?
    /// An ayah's audio played to its end (not skipped), in the reader or while memorizing.
    var onAyahHeard: ((Int) -> Void)?
    /// A playback has run for `listenSeconds`. Fires once per playback, wherever it was started.
    var onListened: (() -> Void)?
    /// Asks for missing ayahs to be saved, nearest first; returns false when automatic downloads are off.
    var downloadMissingAudio: (([Int]) -> Bool)? {
        get { resolver.downloadMissingAudio }
        set { resolver.downloadMissingAudio = newValue }
    }
    var passageRanges: [VerseRange] { preparedPassages }
    var hasPreparedQueue: Bool { queueCursor != nil }

    init(source: AudioSource, fileStore: AudioFileStore) {
        resolver = AyahAudioResolver(source: source, fileStore: fileStore)
        nowPlaying = NowPlayingBridge()
        bindPlayerEvents()
        bindRemoteCommands()
        AudioSessionController.shared.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .interruptionBegan:
                self.resumeAfterInterruption = self.snapshot.isPlaying || self.shouldAutoplay
                self.pausePreservingAutoplayIntent()
            case .interruptionEnded(let shouldResume):
                let hasIntent = self.shouldAutoplay || self.resumeAfterInterruption
                if AudioInterruptionPolicy.actionForEnded(
                    shouldResume: shouldResume,
                    hasPlaybackIntent: hasIntent
                ) == .resume {
                    self.resume()
                }
                self.resumeAfterInterruption = false
            case .routeChanged(let reason):
                if reason == .oldDeviceUnavailable { self.pause() }
            case .mediaServicesReset:
                let resume = self.snapshot.isPlaying || self.shouldAutoplay
                self.replacePlayer()
                self.rebuildQueue(autoplay: resume)
            }
        }
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeIfNeededAfterBecomingActive()
            }
        }
    }

    func configure(catalog: any QuranCatalog, allowStreaming: Bool) {
        self.catalog = catalog
        resolver.allowStreaming = allowStreaming
    }

    /// Switches reciter. Whatever is prepared carries on from the same ayah in the new voice.
    func use(source: AudioSource, fileStore: AudioFileStore) {
        let wasPlaying = snapshot.isPlaying || shouldAutoplay
        resolver.use(source: source, fileStore: fileStore)
        guard !preparedPassages.isEmpty, cursor?.current != nil else { return }
        rebuildQueue(autoplay: wasPlaying)
    }

    func start(set: PracticeSet, catalog: any QuranCatalog, resume: Bool, allowStreaming: Bool) {
        preparePlayback(
            title: set.title,
            passages: set.orderedPassages.map(\.range),
            settings: set.settings,
            resumeAt: resume ? set.lastGlobalAyah : nil,
            catalog: catalog,
            allowStreaming: allowStreaming,
            set: set
        )
    }

    func startListening(
        title: String,
        passages: [VerseRange],
        fromAyah: Int? = nil,
        catalog: any QuranCatalog,
        allowStreaming: Bool
    ) {
        guard !passages.isEmpty else { return }
        preparePlayback(
            title: title,
            passages: passages,
            settings: .listening,
            resumeAt: fromAyah,
            catalog: catalog,
            allowStreaming: allowStreaming,
            set: nil
        )
    }

    func isPrepared(for passages: [VerseRange]) -> Bool {
        !preparedPassages.isEmpty && preparedPassages == passages
    }

    func containsAyah(_ globalAyah: Int) -> Bool {
        versesInSet.contains { $0.globalAyah == globalAyah }
    }

    func pause() {
        endStartAudioInterval()
        shouldAutoplay = false
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        refreshNowPlayingIfPublished()
    }

    func resume() {
        guard !preparedPassages.isEmpty else { return }
        // A finished queue remains visible so Play can replay the passage.
        if cursor?.current == nil {
            cursor = PracticePlaybackCursor(passages: preparedPassages, settings: preparedSettings)
        }
        guard cursor?.current != nil else { return }
        userMessage = nil
        // Pressing Play retries ayahs whose download failed.
        resolver.retryFailedDownloads()
        onWillStartAudio?()
        shouldAutoplay = true
        guard player.hasQueuedAudio || fetchTask != nil else {
            // Rebuilding activates the session; do not activate it twice on first play.
            rebuildQueue(autoplay: true)
            return
        }
        do {
            try AudioSessionController.shared.configure(.playback)
        } catch {
            failPlayback(error)
            return
        }
        if player.hasQueuedAudio {
            startPlayer()
        } else {
            // Starts as soon as the ayah being fetched is queued.
            snapshot.isLoading = true
        }
    }

    func stop() {
        shouldAutoplay = false
        accumulateListeningTime()
        resetQueue()
        cursor = nil
        preparedPassages = []
        activeSet = nil
        versesInSet = []
        snapshot.isPlaying = false
        snapshot.isLoading = false
        snapshot.currentGlobalAyah = nil
        session = nil
        nowPlaying.clear()
        try? AudioSessionController.shared.configure(.idle)
    }

    func skipForward() {
        let resume = snapshot.isPlaying || shouldAutoplay
        if resume { onWillStartAudio?() }
        cursor?.skipForward()
        rebuildQueue(autoplay: resume)
    }

    func skipBack() {
        let resume = snapshot.isPlaying || shouldAutoplay
        if resume { onWillStartAudio?() }
        cursor?.skipBack()
        rebuildQueue(autoplay: resume)
    }

    func move(to globalAyah: Int) {
        let resume = snapshot.isPlaying || shouldAutoplay
        guard cursor?.move(to: globalAyah) == true else { return }
        if resume { onWillStartAudio?() }
        rebuildQueue(autoplay: resume)
    }

    /// A background download finished; playback waiting for it carries on.
    func audioBecameAvailable(_ globalAyah: Int) {
        resolver.audioBecameAvailable(globalAyah)
    }

    func audioDownloadFailed(_ globalAyah: Int) {
        resolver.audioDownloadFailed(globalAyah)
    }

    func toggleArabicHidden() {
        snapshot.hideArabic.toggle()
        activeSet?.settings.hideArabic = snapshot.hideArabic
    }

    func applySettingsAndRestart(_ settings: PracticeSettings) {
        guard let activeSet, let catalog else { return }
        let resumePlayback = snapshot.isPlaying || shouldAutoplay
        let currentAyah = snapshot.currentGlobalAyah
        accumulateListeningTime()
        resetQueue()
        activeSet.settings = settings
        preparedSettings = settings
        snapshot.hideArabic = settings.hideArabic
        snapshot.advanceManually = settings.advanceManually
        snapshot.ayahRepeat = settings.ayahRepeatCount
        snapshot.setRepeat = settings.setRepeatCount
        snapshot.pauseSeconds = settings.clampedPauseSeconds
        let ranges = activeSet.orderedPassages.map(\.range)
        cursor = PracticePlaybackCursor(passages: ranges, settings: settings, resumeAt: currentAyah)
        self.catalog = catalog
        rebuildQueue(autoplay: resumePlayback)
    }

    private func bindPlayerEvents() {
        player.onSegmentStarted = { [weak self] id in self?.segmentStarted(id) }
        player.onSegmentFinished = { [weak self] id in self?.segmentFinished(id) }
        player.onFailure = { [weak self] id, error in self?.segmentFailed(id, error: error) }
    }

    private func bindRemoteCommands() {
        nowPlaying.handle(
            hasItem: { [weak self] in self?.cursor?.current != nil },
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in
                guard let self else { return }
                self.snapshot.isPlaying ? self.pause() : self.resume()
            },
            next: { [weak self] in self?.skipForward() },
            previous: { [weak self] in self?.skipBack() }
        )
    }

    private func preparePlayback(
        title: String,
        passages: [VerseRange],
        settings: PracticeSettings,
        resumeAt: Int?,
        catalog: any QuranCatalog,
        allowStreaming: Bool,
        set: PracticeSet?
    ) {
        resetQueue()
        nowPlaying.clear()
        session = nil
        self.catalog = catalog
        resolver.allowStreaming = allowStreaming
        preparedPassages = passages
        preparedSettings = settings
        activeSet = set
        versesInSet = passages.flatMap { catalog.verses(in: $0) }
        cursor = PracticePlaybackCursor(
            passages: passages,
            settings: settings,
            resumeAt: resumeAt
        )
        coveredAyahs = []
        repetitionCount = 0
        listeningSeconds = 0
        playbackBeganAt = nil
        countedListen = false
        userMessage = nil
        shouldAutoplay = false
        resolver.retryFailedDownloads()
        snapshot.setID = set?.id
        snapshot.setTitle = title
        snapshot.hideArabic = settings.hideArabic
        snapshot.ayahRepeat = settings.ayahRepeatCount
        snapshot.setRepeat = settings.setRepeatCount
        snapshot.pauseSeconds = settings.clampedPauseSeconds
        snapshot.advanceManually = settings.advanceManually
        prepareCurrentStep()
    }

    private func prepareCurrentStep() {
        snapshot.isPlaying = false
        snapshot.isLoading = false
        guard let step = cursor?.current else {
            snapshot.currentGlobalAyah = nil
            snapshot.repetitionLabel = ""
            nowPlaying.clear()
            return
        }
        updateSnapshot(for: step)
    }

    /// Throws away what's queued and queues again from the cursor.
    private func rebuildQueue(autoplay: Bool) {
        accumulateListeningTime()
        resetQueue()
        shouldAutoplay = autoplay
        guard let step = cursor?.current else {
            finishPlayback()
            return
        }
        if autoplay {
            beginStartAudioInterval()
            do {
                try AudioSessionController.shared.configure(.playback)
            } catch {
                failPlayback(error)
                return
            }
        }
        updateSnapshot(for: step)
        requestMissingAudio()
        countedCurrentItem = false
        queueCursor = cursor
        snapshot.isPlaying = false
        snapshot.isLoading = autoplay
        if autoplay { publishNowPlaying() }
        fillQueue()
    }

    /// Queues steps from `queueCursor` until the queue is full or the next ayah has to be fetched first.
    private func fillQueue() {
        guard fetchTask == nil else { return }
        let depth = snapshot.advanceManually ? 1 : Self.queueDepth
        while queuedSteps.count < depth, let step = queueCursor?.current {
            let source: AudioSegment.Source
            switch step {
            case .silence(let seconds):
                source = .silence(seconds: seconds)
            case .ayah(let ayah, _, _):
                switch resolver.availability(of: ayah) {
                case .ready(let url):
                    source = .file(url, smoothsJoins: resolver.source.reciter.smoothsJoins)
                case .needsFetch:
                    fetch(ayah)
                    return
                case .unavailable(let error):
                    // With audio still queued, this is retried when the queue runs down.
                    if queuedSteps.isEmpty { failPlayback(error) }
                    return
                }
            }
            do {
                try enqueue(source, for: step)
            } catch {
                // A saved file that won't decode is removed, and the loop fetches it again.
                if case .ayah(let ayah, _, _) = step, resolver.discardUnreadable(ayah) { continue }
                if queuedSteps.isEmpty { failPlayback(error) }
                return
            }
            queueCursor?.advanceAfterCompletion()
            if shouldAutoplay, !player.isPlaying { startPlayer() }
        }
    }

    private func enqueue(_ source: AudioSegment.Source, for step: QueueItem) throws {
        lastSegmentID += 1
        let id = lastSegmentID
        // Recorded first: the player reports a segment's start while it's being enqueued.
        queuedSteps[id] = step
        do {
            try player.enqueue(AudioSegment(id: id, source: source))
        } catch {
            queuedSteps[id] = nil
            throw error
        }
    }

    private func fetch(_ ayah: Int) {
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await resolver.fetch(ayah)
                guard !Task.isCancelled else { return }
                fetchTask = nil
                fillQueue()
            } catch {
                guard !Task.isCancelled else { return }
                fetchTask = nil
                // With audio still queued, the fetch is retried when the queue runs down.
                if queuedSteps.isEmpty { failPlayback(error) }
            }
        }
    }

    /// Keeps the next few ayahs downloading, nearest first.
    private func requestMissingAudio() {
        resolver.requestDownloads(order: versesInSet.map(\.globalAyah), current: snapshot.currentGlobalAyah)
    }

    private func segmentStarted(_ id: Int) {
        guard queuedSteps[id] != nil, shouldAutoplay, player.isPlaying else { return }
        markCurrentAyahStarted()
        snapshot.isPlaying = true
        snapshot.isLoading = false
        refreshNowPlayingIfPublished()
    }

    private func segmentFinished(_ id: Int) {
        guard let step = queuedSteps.removeValue(forKey: id) else { return }
        accumulateListeningTime()
        if case .ayah(let ayah, _, _) = step { onAyahHeard?(ayah) }
        cursor?.advanceAfterCompletion()

        guard let next = cursor?.current else {
            finishPlayback()
            return
        }
        if snapshot.advanceManually {
            rebuildQueue(autoplay: false)
            return
        }
        updateSnapshot(for: next)
        // The download window moves along with playback, ahead of what fillQueue will need.
        requestMissingAudio()
        countedCurrentItem = false
        if shouldAutoplay { playbackBeganAt = .now }
        fillQueue()
        if shouldAutoplay, !player.hasQueuedAudio {
            // The next ayah is still being fetched.
            snapshot.isPlaying = false
            snapshot.isLoading = true
        }
        refreshNowPlayingIfPublished()
    }

    private func segmentFailed(_ id: Int, error: Error) {
        let step = queuedSteps[id]
        resetQueue()
        if case .ayah(let ayah, _, _) = step, resolver.discardUnreadable(ayah) {
            rebuildQueue(autoplay: shouldAutoplay)
            return
        }
        failPlayback(error)
    }

    private func updateSnapshot(for step: QueueItem) {
        guard case .ayah(let ayah, let repetition, let total) = step else { return }
        snapshot.currentGlobalAyah = ayah
        onPositionChanged?(ayah)
        snapshot.repetitionLabel = total == 0 ? "\(repetition)/∞" : (total == 1 ? "" : "\(repetition)/\(total)")
    }

    private func failPlayback(_ error: Error) {
        endStartAudioInterval()
        shouldAutoplay = false
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        refreshNowPlayingIfPublished()
        if let appError = error as? AppError {
            userMessage = UserFacingMessage.from(appError)
        } else {
            userMessage = UserFacingMessage.from(.audioUnavailable)
        }
        logger.error("Playback failed: \(error.localizedDescription, privacy: .public)")
    }

    private func finishPlayback() {
        shouldAutoplay = false
        accumulateListeningTime()
        resetQueue()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        nowPlaying.clear()
    }

    private func resetQueue() {
        fetchTask?.cancel()
        fetchTask = nil
        player.reset()
        queueCursor = nil
        queuedSteps.removeAll()
    }

    private func replacePlayer() {
        resetQueue()
        player = GaplessAudioPlayer()
        bindPlayerEvents()
    }

    private func beginStartAudioInterval() {
        endStartAudioInterval()
        startAudioInterval = Log.playbackSignposts.beginInterval(Self.startAudioSignpost)
    }

    private func endStartAudioInterval() {
        guard let startAudioInterval else { return }
        Log.playbackSignposts.endInterval(Self.startAudioSignpost, startAudioInterval)
        self.startAudioInterval = nil
    }

    private func startPlayer() {
        endStartAudioInterval()
        do {
            try player.play()
        } catch {
            failPlayback(error)
            return
        }
        markCurrentAyahStarted()
        if playbackBeganAt == nil { playbackBeganAt = .now }
        snapshot.isPlaying = true
        snapshot.isLoading = false
        updateIdleTimer()
        publishNowPlaying()
    }

    private func pausePreservingAutoplayIntent() {
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        refreshNowPlayingIfPublished()
    }

    private func resumeIfNeededAfterBecomingActive() {
        guard shouldAutoplay, !snapshot.isPlaying else { return }
        resume()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = shouldAutoplay
    }

    private func markCurrentAyahStarted() {
        guard !countedCurrentItem,
              let step = cursor?.current,
              case .ayah(let ayah, _, _) = step
        else { return }
        coveredAyahs.insert(ayah)
        repetitionCount += 1
        countedCurrentItem = true
    }

    private func accumulateListeningTime() {
        guard let playbackBeganAt else { return }
        listeningSeconds += max(0, Date.now.timeIntervalSince(playbackBeganAt))
        self.playbackBeganAt = nil
        if !countedListen, listeningSeconds >= Self.listenSeconds {
            countedListen = true
            onListened?()
        }
    }

    private func publishNowPlaying() {
        guard let ayah = snapshot.currentGlobalAyah,
              let verse = catalog?.verse(globalAyah: ayah)
        else { return }
        nowPlaying.publish(
            setTitle: snapshot.setTitle,
            verse: verse,
            reciter: resolver.source.reciter,
            state: snapshot.isPlaying ? .playing : (snapshot.isLoading ? .loading : .paused),
            elapsedTime: player.elapsedInCurrentSegment,
            duration: player.durationOfCurrentSegment
        )
    }

    private func refreshNowPlayingIfPublished() {
        guard nowPlaying.isPublished else { return }
        publishNowPlaying()
    }
}
