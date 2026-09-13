import AVFoundation
import Foundation
import OSLog

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
    private let nowPlaying = NowPlayingBridge()
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "playback")

    private var player: AVQueuePlayer?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var cursor: PracticePlaybackCursor?
    private var catalog: (any QuranCatalog)?
    private var allowStreaming = true
    private var shouldAutoplay = false
    private var resumeAfterInterruption = false
    private var currentAyahWasLocal = false
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
        pauseSeconds: 1,
        advanceManually: false,
        repetitionLabel: ""
    )
    var userMessage: UserFacingMessage?
    var coveredAyahs = Set<Int>()
    var repetitionCount = 0
    var session: PracticeSession?
    var activeSet: PracticeSet?
    var versesInSet: [QuranVerse] = []

    init(source: AudioSource, fileStore: AudioFileStore) {
        self.source = source
        self.fileStore = fileStore
        nowPlaying.becomeActive()
        nowPlaying.handle(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in
                guard let self else { return }
                self.snapshot.isPlaying ? self.pause() : self.resume()
            },
            next: { [weak self] in self?.skipForward() },
            previous: { [weak self] in self?.skipBack() }
        )
        AudioSessionController.shared.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .interruptionBegan:
                self.resumeAfterInterruption = self.snapshot.isPlaying || self.shouldAutoplay
                self.pause()
            case .interruptionEnded(let shouldResume):
                if shouldResume, self.resumeAfterInterruption { self.resume() }
                self.resumeAfterInterruption = false
            case .routeChanged(let reason):
                if reason == .oldDeviceUnavailable { self.pause() }
            case .mediaServicesReset:
                let resume = self.snapshot.isPlaying || self.shouldAutoplay
                self.playCurrent(autoplay: resume)
            }
        }
    }

    func configure(catalog: any QuranCatalog, allowStreaming: Bool) {
        self.catalog = catalog
        self.allowStreaming = allowStreaming
    }

    func start(set: PracticeSet, catalog: any QuranCatalog, resume: Bool, allowStreaming: Bool) {
        cleanupPlayer()
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
        playCurrent(autoplay: true)
    }

    func pause() {
        shouldAutoplay = false
        accumulateListeningTime()
        player?.pause()
        snapshot.isPlaying = false
        refreshNowPlaying()
    }

    func resume() {
        guard cursor?.current != nil else { return }
        shouldAutoplay = true
        do {
            try AudioSessionController.shared.configure(.playback)
        } catch {
            failPlayback(error)
            return
        }
        guard let player, player.currentItem != nil else {
            playCurrent(autoplay: true)
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
        cleanupPlayer()
        cursor = nil
        snapshot.isPlaying = false
        snapshot.isLoading = false
        snapshot.currentGlobalAyah = nil
        nowPlaying.clear()
        try? AudioSessionController.shared.configure(.idle)
    }

    func skipForward() {
        let resume = snapshot.isPlaying || shouldAutoplay
        cursor?.skipForward()
        playCurrent(autoplay: resume)
    }

    func skipBack() {
        let resume = snapshot.isPlaying || shouldAutoplay
        cursor?.skipBack()
        playCurrent(autoplay: resume)
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
        cleanupPlayer()
        activeSet.settings = settings
        snapshot.hideArabic = settings.hideArabic
        snapshot.advanceManually = settings.advanceManually
        snapshot.ayahRepeat = settings.ayahRepeatCount
        snapshot.setRepeat = settings.setRepeatCount
        snapshot.pauseSeconds = settings.clampedPauseSeconds
        let ranges = activeSet.orderedPassages.map(\.range)
        cursor = PracticePlaybackCursor(passages: ranges, settings: settings, resumeAt: currentAyah)
        self.catalog = catalog
        playCurrent(autoplay: resumePlayback)
    }

    private func playCurrent(autoplay: Bool) {
        shouldAutoplay = autoplay
        guard let step = cursor?.current else {
            finishPlayback()
            return
        }

        switch step {
        case .silence(let seconds):
            playSilence(seconds: seconds, autoplay: autoplay)
        case .ayah(let ayah, let repetition, let total):
            snapshot.currentGlobalAyah = ayah
            snapshot.repetitionLabel = total == 0 ? "\(repetition)/∞" : (total == 1 ? "" : "\(repetition)/\(total)")
            playAyah(ayah, autoplay: autoplay)
        }
    }

    private func playAyah(_ globalAyah: Int, autoplay: Bool, forceRemote: Bool = false) {
        do {
            try AudioSessionController.shared.configure(.playback)
            let item: AVPlayerItem
            if !forceRemote, let local = fileStore.urlIfReady(reciter: source.reciter, globalAyah: globalAyah) {
                currentAyahWasLocal = true
                item = AVPlayerItem(url: local)
            } else if allowStreaming {
                currentAyahWasLocal = false
                item = AVPlayerItem(url: try source.remoteURL(for: globalAyah))
            } else {
                throw AppError.offlineAudioMissing
            }
            countedCurrentItem = false
            replaceQueue(with: [item], completionItem: item, autoplay: autoplay)
            refreshNowPlaying()
        } catch {
            failPlayback(error)
        }
    }

    private func playSilence(seconds: Int, autoplay: Bool) {
        guard seconds > 0, let url = silenceURL() else {
            cursor?.advanceAfterCompletion()
            playCurrent(autoplay: autoplay)
            return
        }
        currentAyahWasLocal = false
        countedCurrentItem = true
        let items = (0..<seconds).map { _ in AVPlayerItem(url: url) }
        guard let last = items.last else { return }
        replaceQueue(with: items, completionItem: last, autoplay: autoplay)
    }

    private func replaceQueue(with items: [AVPlayerItem], completionItem: AVPlayerItem, autoplay: Bool) {
        removeItemObservers()
        let player = player ?? AVQueuePlayer()
        self.player = player
        player.removeAllItems()
        for item in items { player.insert(item, after: nil) }
        snapshot.isPlaying = false
        snapshot.isLoading = true
        shouldAutoplay = autoplay

        if let first = items.first {
            itemStatusObserver = first.observe(\.status, options: [.initial, .new]) { [weak self, weak first] _, _ in
                Task { @MainActor in
                    guard let self, let first else { return }
                    switch first.status {
                    case .readyToPlay:
                        self.snapshot.isLoading = false
                        if self.shouldAutoplay {
                            self.startPlayer()
                        }
                        self.refreshNowPlaying()
                    case .failed:
                        self.handleItemFailure(first.error)
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: completionItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.itemDidFinish() }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: completionItem,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in self?.handleItemFailure(error) }
        }
    }

    private func itemDidFinish() {
        accumulateListeningTime()
        snapshot.isPlaying = false
        cursor?.advanceAfterCompletion()
        playCurrent(autoplay: !snapshot.advanceManually)
    }

    private func handleItemFailure(_ error: Error?) {
        guard snapshot.isLoading || snapshot.isPlaying || shouldAutoplay else { return }
        if currentAyahWasLocal, let ayah = snapshot.currentGlobalAyah, allowStreaming {
            try? fileStore.remove(globalAyah: ayah)
            playAyah(ayah, autoplay: shouldAutoplay, forceRemote: true)
            return
        }
        failPlayback(error ?? AppError.audioUnavailable)
    }

    private func failPlayback(_ error: Error) {
        shouldAutoplay = false
        accumulateListeningTime()
        player?.pause()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        if let appError = error as? AppError {
            userMessage = UserFacingMessage.from(appError)
        } else {
            userMessage = UserFacingMessage.from(.audioUnavailable)
        }
        logger.error("Playback failed: \(error.localizedDescription, privacy: .public)")
        refreshNowPlaying()
    }

    private func finishPlayback() {
        shouldAutoplay = false
        accumulateListeningTime()
        cleanupPlayer()
        snapshot.isPlaying = false
        snapshot.isLoading = false
        refreshNowPlaying()
    }

    private func cleanupPlayer() {
        player?.pause()
        player?.removeAllItems()
        player = nil
        removeItemObservers()
    }

    private func startPlayer() {
        if !countedCurrentItem, let ayah = snapshot.currentGlobalAyah {
            coveredAyahs.insert(ayah)
            repetitionCount += 1
            countedCurrentItem = true
        }
        if playbackBeganAt == nil { playbackBeganAt = .now }
        player?.play()
        snapshot.isPlaying = true
        snapshot.isLoading = false
        refreshNowPlaying()
    }

    private func accumulateListeningTime() {
        guard let playbackBeganAt else { return }
        listeningSeconds += max(0, Date.now.timeIntervalSince(playbackBeganAt))
        self.playbackBeganAt = nil
    }

    private func removeItemObservers() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }

    private func refreshNowPlaying() {
        guard let ayah = snapshot.currentGlobalAyah, let verse = catalog?.verse(globalAyah: ayah) else { return }
        nowPlaying.update(
            setTitle: snapshot.setTitle,
            verse: verse,
            reciter: source.reciter,
            isPlaying: snapshot.isPlaying
        )
    }

    private func silenceURL() -> URL? {
        Bundle.main.url(forResource: "silence", withExtension: "m4a", subdirectory: "Resources/Audio")
            ?? Bundle.main.url(forResource: "silence", withExtension: "m4a", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: "silence", withExtension: "m4a")
    }
}
