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

@MainActor
@Observable
final class PlaybackCoordinator {
    private let source: AudioSource
    private let fileStore: AudioFileStore
    private var nowPlaying: NowPlayingBridge
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "playback")

    private var player: AVQueuePlayer
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var cursor: PracticePlaybackCursor?
    private var queueCursor: PracticePlaybackCursor?
    private var queuedItems: [ObjectIdentifier: QueuedItemInfo] = [:]
    private var catalog: (any QuranCatalog)?
    private var allowStreaming = true
    private var shouldAutoplay = false {
        didSet { updateIdleTimer() }
    }
    private var resumeAfterInterruption = false
    private var becomeActiveObserver: NSObjectProtocol?
    private var countedCurrentItem = false
    private var playbackBeganAt: Date?
    private(set) var listeningSeconds: Double = 0

    var snapshot = PlaybackSnapshot(
        setID: nil,
        setTitle: "",
        currentGlobalAyah: nil,
        isPlaying: false,
        isLoading: false,
        hideArabic: false,
        ayahRepeat: .three,
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
    var hasPreparedQueue: Bool { player.currentItem != nil }

    init(source: AudioSource, fileStore: AudioFileStore) {
        self.source = source
        self.fileStore = fileStore
        let player = Self.makePlayer()
        self.player = player
        self.nowPlaying = NowPlayingBridge(player: player)
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
        self.allowStreaming = allowStreaming
    }

    func start(set: PracticeSet, catalog: any QuranCatalog, resume: Bool, allowStreaming: Bool) {
        resetQueue()
        session = nil
        self.catalog = catalog
        self.allowStreaming = allowStreaming
        activeSet = set
        let ranges = set.orderedPassages.map(\.range)
        versesInSet = ranges.flatMap { catalog.verses(in: $0) }
        cursor = PracticePlaybackCursor(
            passages: ranges,
            settings: set.settings,
            resumeAt: resume ? set.lastGlobalAyah : nil
        )
        coveredAyahs = []
        repetitionCount = 0
        listeningSeconds = 0
        playbackBeganAt = nil
        userMessage = nil
        snapshot.setID = set.id
        snapshot.setTitle = set.title
        snapshot.hideArabic = set.settings.hideArabic
        snapshot.ayahRepeat = set.settings.ayahRepeatCount
        snapshot.setRepeat = set.settings.setRepeatCount
        snapshot.pauseSeconds = set.settings.clampedPauseSeconds
        snapshot.advanceManually = set.settings.advanceManually
        prepareCurrentStep()
    }

    func pause() {
        shouldAutoplay = false
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
    }

    func resume() {
        guard cursor?.current != nil else { return }
        onWillStartAudio?()
        shouldAutoplay = true
        do {
            try AudioSessionController.shared.configure(.playback)
        } catch {
            failPlayback(error)
            return
        }
        guard player.currentItem != nil else {
            rebuildQueue(autoplay: true)
            return
        }
        if player.currentItem?.status == .readyToPlay {
            startPlayer()
        } else {
            snapshot.isLoading = true
        }
    }

    func stop() {
        shouldAutoplay = false
        accumulateListeningTime()
        resetQueue()
        cursor = nil
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
        refreshAfterNavigation(autoplay: resume)
    }

    func skipBack() {
        let resume = snapshot.isPlaying || shouldAutoplay
        if resume { onWillStartAudio?() }
        cursor?.skipBack()
        refreshAfterNavigation(autoplay: resume)
    }

    func move(to globalAyah: Int) {
        let resume = snapshot.isPlaying || shouldAutoplay
        guard cursor?.move(to: globalAyah) == true else { return }
        if resume { onWillStartAudio?() }
        refreshAfterNavigation(autoplay: resume)
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
        snapshot.hideArabic = settings.hideArabic
        snapshot.advanceManually = settings.advanceManually
        snapshot.ayahRepeat = settings.ayahRepeatCount
        snapshot.setRepeat = settings.setRepeatCount
        snapshot.pauseSeconds = settings.clampedPauseSeconds
        let ranges = activeSet.orderedPassages.map(\.range)
        cursor = PracticePlaybackCursor(passages: ranges, settings: settings, resumeAt: currentAyah)
        self.catalog = catalog
        refreshAfterNavigation(autoplay: resumePlayback)
    }

    private struct QueuedItemInfo {
        var step: QueueItem
        var completesStep: Bool
        var isLocal: Bool
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

    private func refreshAfterNavigation(autoplay: Bool) {
        rebuildQueue(autoplay: autoplay)
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

    private func rebuildQueue(autoplay: Bool) {
        accumulateListeningTime()
        resetQueue()
        shouldAutoplay = autoplay
        guard let step = cursor?.current else {
            finishPlayback()
            return
        }

        do {
            if autoplay {
                try AudioSessionController.shared.configure(.playback)
            }
            updateSnapshot(for: step)
            countedCurrentItem = false
            queueCursor = cursor
            try fillQueue()
            observeQueue()

            guard let first = player.currentItem else {
                finishPlayback()
                return
            }
            observeReadiness(of: first, autoplay: autoplay)
        } catch {
            failPlayback(error)
        }
    }

    private func fillQueue() throws {
        let targetDepth = snapshot.advanceManually ? 1 : 8
        var lastAyah = snapshot.currentGlobalAyah
        while player.items().count < targetDepth, let step = queueCursor?.current {
            switch step {
            case .ayah(let ayah, _, _):
                let resolved: (url: URL, isLocal: Bool)
                if let local = fileStore.urlIfReady(reciter: source.reciter, globalAyah: ayah) {
                    resolved = (local, true)
                } else if allowStreaming {
                    resolved = (try source.remoteURL(for: ayah), false)
                } else {
                    if player.items().isEmpty {
                        throw AppError.offlineAudioMissing
                    }
                    return
                }
                let item = AVPlayerItem(url: resolved.url)
                item.preferredForwardBufferDuration = 10
                stampNowPlaying(on: item, globalAyah: ayah)
                queuedItems[ObjectIdentifier(item)] = QueuedItemInfo(
                    step: step,
                    completesStep: true,
                    isLocal: resolved.isLocal
                )
                player.insert(item, after: nil)
                lastAyah = ayah
            case .silence(let seconds):
                guard seconds > 0, let url = silenceURL() else {
                    queueCursor?.advanceAfterCompletion()
                    continue
                }
                for index in 0..<seconds {
                    let item = AVPlayerItem(url: url)
                    if let lastAyah {
                        stampNowPlaying(on: item, globalAyah: lastAyah)
                    }
                    queuedItems[ObjectIdentifier(item)] = QueuedItemInfo(
                        step: step,
                        completesStep: index == seconds - 1,
                        isLocal: true
                    )
                    player.insert(item, after: nil)
                }
            }
            queueCursor?.advanceAfterCompletion()
        }
    }

    private func stampNowPlaying(on item: AVPlayerItem, globalAyah: Int) {
        guard let verse = catalog?.verse(globalAyah: globalAyah) else { return }
        nowPlaying.stamp(item, setTitle: snapshot.setTitle, verse: verse, reciter: source.reciter)
    }

    private func observeReadiness(of item: AVPlayerItem, autoplay: Bool) {
        snapshot.isPlaying = false
        if autoplay {
            snapshot.isLoading = true
        }
        shouldAutoplay = autoplay
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item else { return }
                switch item.status {
                case .readyToPlay:
                    self.snapshot.isLoading = false
                    if self.shouldAutoplay { self.startPlayer() }
                case .failed:
                    self.handleItemFailure(item.error, failedItem: item)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeQueue() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in self?.itemDidFinish(item) }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor in
                guard self?.queuedItems[ObjectIdentifier(item)] != nil else { return }
                self?.handleItemFailure(error, failedItem: item)
            }
        }
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.shouldAutoplay else { return }
                self.snapshot.isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.snapshot.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func itemDidFinish(_ item: AVPlayerItem) {
        guard let info = queuedItems.removeValue(forKey: ObjectIdentifier(item)) else { return }
        accumulateListeningTime()
        if info.completesStep {
            cursor?.advanceAfterCompletion()
        }

        guard cursor?.current != nil else {
            finishPlayback()
            return
        }
        if snapshot.advanceManually, info.completesStep {
            rebuildQueue(autoplay: false)
            return
        }

        if let step = cursor?.current {
            updateSnapshot(for: step)
        }
        countedCurrentItem = false
        if shouldAutoplay {
            markCurrentAyahStarted()
            playbackBeganAt = .now
            snapshot.isPlaying = true
        }
        do {
            try fillQueue()
        } catch {
            failPlayback(error)
        }
    }

    private func updateSnapshot(for step: QueueItem) {
        guard case .ayah(let ayah, let repetition, let total) = step else { return }
        snapshot.currentGlobalAyah = ayah
        snapshot.repetitionLabel = total == 0 ? "\(repetition)/∞" : (total == 1 ? "" : "\(repetition)/\(total)")
    }

    private func handleItemFailure(_ error: Error?, failedItem: AVPlayerItem? = nil) {
        guard snapshot.isLoading || snapshot.isPlaying || shouldAutoplay else { return }
        let failedInfo = failedItem.flatMap { queuedItems[ObjectIdentifier($0)] }
        if let failedInfo,
           failedInfo.isLocal,
           case .ayah = failedInfo.step,
           let ayah = snapshot.currentGlobalAyah,
           allowStreaming {
            try? fileStore.remove(globalAyah: ayah)
            rebuildQueue(autoplay: shouldAutoplay)
            return
        }
        failPlayback(error ?? AppError.audioUnavailable)
    }

    private func failPlayback(_ error: Error) {
        shouldAutoplay = false
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
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
    }

    private func resetQueue() {
        removeItemObservers()
        player.pause()
        player.removeAllItems()
        queueCursor = nil
        queuedItems.removeAll()
    }

    private func replacePlayer() {
        resetQueue()
        let player = Self.makePlayer()
        self.player = player
        nowPlaying = NowPlayingBridge(player: player)
        bindRemoteCommands()
    }

    private func startPlayer() {
        markCurrentAyahStarted()
        if playbackBeganAt == nil { playbackBeganAt = .now }
        player.play()
        snapshot.isPlaying = true
        snapshot.isLoading = false
        updateIdleTimer()
        nowPlaying.becomeActive()
    }

    private func pausePreservingAutoplayIntent() {
        accumulateListeningTime()
        player.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
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
    }

    private func removeItemObservers() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }

    private func silenceURL() -> URL? {
        Bundle.main.url(forResource: "silence", withExtension: "m4a", subdirectory: "Resources/Audio")
            ?? Bundle.main.url(forResource: "silence", withExtension: "m4a", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: "silence", withExtension: "m4a")
    }

    private static func makePlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.preventsDisplaySleepDuringVideoPlayback = false
        return player
    }
}
