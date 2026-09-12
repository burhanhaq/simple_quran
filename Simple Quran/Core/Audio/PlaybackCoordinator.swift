import AVFoundation
import Foundation
import OSLog

struct PlaybackSnapshot: Equatable {
    var setID: UUID?
    var setTitle: String
    var currentGlobalAyah: Int?
    var isPlaying: Bool
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
    private let planner = PracticeQueuePlanner()
    private let nowPlaying = NowPlayingBridge()
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "playback")

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var queue: [QueueItem] = []
    private var index: Int = 0
    private var setRepeatsRemaining: Int?
    private var cycleLength = 0
    private var catalog: (any QuranCatalog)?
    private var allowStreaming = true

    var snapshot = PlaybackSnapshot(
        setID: nil,
        setTitle: "",
        currentGlobalAyah: nil,
        isPlaying: false,
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
        AudioSessionController.shared.onInterruption = { [weak self] began in
            if began { self?.pause() }
        }
        AudioSessionController.shared.onRouteChange = { [weak self] in
            guard let self, self.snapshot.isPlaying else { return }
            self.resume()
        }
    }

    func configure(catalog: any QuranCatalog, allowStreaming: Bool) {
        self.catalog = catalog
        self.allowStreaming = allowStreaming
    }

    func start(set: PracticeSet, catalog: any QuranCatalog, resume: Bool, allowStreaming: Bool) {
        self.catalog = catalog
        self.allowStreaming = allowStreaming
        activeSet = set
        let ranges = set.orderedPassages.map(\.range)
        versesInSet = ranges.flatMap { catalog.verses(in: $0) }
        queue = planner.expand(passages: ranges, settings: set.settings)
        cycleLength = planner.makeCycle(passages: ranges, settings: set.settings).count
        coveredAyahs = []
        repetitionCount = 0
        userMessage = nil
        setRepeatsRemaining = set.settings.setRepeatCount.finiteCount
        index = 0
        if resume, let last = set.lastGlobalAyah, let found = queue.firstIndex(where: {
            if case .ayah(let ayah, _, _) = $0 { return ayah == last }
            return false
        }) {
            index = found
        }
        snapshot.setID = set.id
        snapshot.setTitle = set.title
        snapshot.hideArabic = set.settings.hideArabic
        snapshot.ayahRepeat = set.settings.ayahRepeatCount
        snapshot.setRepeat = set.settings.setRepeatCount
        snapshot.pauseSeconds = set.settings.clampedPauseSeconds
        snapshot.advanceManually = set.settings.advanceManually
        playCurrent()
    }

    func pause() {
        player?.pause()
        snapshot.isPlaying = false
        refreshNowPlaying()
    }

    func resume() {
        guard player != nil else {
            playCurrent()
            return
        }
        player?.play()
        snapshot.isPlaying = true
        refreshNowPlaying()
    }

    func stop() {
        player?.pause()
        player = nil
        snapshot.isPlaying = false
        snapshot.currentGlobalAyah = nil
        nowPlaying.clear()
        try? AudioSessionController.shared.configure(.idle)
    }

    func skipForward() {
        advance(by: 1)
        playCurrent()
    }

    func skipBack() {
        advance(by: -1)
        playCurrent()
    }

    func toggleArabicHidden() {
        snapshot.hideArabic.toggle()
        activeSet?.settings.hideArabic = snapshot.hideArabic
    }

    func applySettingsAndRestart(_ settings: PracticeSettings) {
        guard let activeSet, let catalog else { return }
        activeSet.settings = settings
        snapshot.hideArabic = settings.hideArabic
        snapshot.advanceManually = settings.advanceManually
        start(set: activeSet, catalog: catalog, resume: true, allowStreaming: allowStreaming)
    }

    private func playCurrent() {
        guard index >= 0 else { index = 0; return }
        if index >= queue.count {
            if let remaining = setRepeatsRemaining {
                let leftover = remaining - 1
                setRepeatsRemaining = leftover
                if leftover <= 0 {
                    snapshot.isPlaying = false
                    return
                }
            }
            index = 0
        }

        switch queue[index] {
        case .silence(let seconds):
            playSilence(seconds: seconds)
        case .ayah(let ayah, let repetition, let total):
            snapshot.currentGlobalAyah = ayah
            snapshot.repetitionLabel = total == 1 ? "" : "\(repetition)/\(total)"
            coveredAyahs.insert(ayah)
            repetitionCount += 1
            playAyah(ayah)
        }
    }

    private func playAyah(_ globalAyah: Int) {
        do {
            try AudioSessionController.shared.configure(.playback)
            let item: AVPlayerItem
            if let local = fileStore.urlIfReady(reciter: source.reciter, globalAyah: globalAyah) {
                item = AVPlayerItem(url: local)
            } else if allowStreaming {
                item = AVPlayerItem(url: try source.remoteURL(for: globalAyah))
            } else {
                throw AppError.offlineAudioMissing
            }
            replaceCurrentItem(item, autoplay: !snapshot.advanceManually || snapshot.isPlaying || player == nil)
            refreshNowPlaying()
        } catch let error as AppError {
            userMessage = UserFacingMessage.from(error)
            snapshot.isPlaying = false
            logger.error("Playback failed: \(String(describing: error), privacy: .public)")
        } catch {
            userMessage = UserFacingMessage.from(.audioUnavailable)
            snapshot.isPlaying = false
            logger.error("Playback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func playSilence(seconds: Int) {
        guard seconds > 0, let url = silenceURL() else {
            advance(by: 1)
            playCurrent()
            return
        }
        do {
            try AudioSessionController.shared.configure(.playback)
        } catch {
            logger.error("Silence session failed")
        }
        let item = AVPlayerItem(url: url)
        replaceCurrentItem(item, autoplay: true)
        // Loop the 1s file by scheduling the next advance after `seconds`.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            await MainActor.run {
                guard let self, self.snapshot.isPlaying || !self.snapshot.advanceManually else { return }
                self.advance(by: 1)
                self.playCurrent()
            }
        }
    }

    private func replaceCurrentItem(_ item: AVPlayerItem, autoplay: Bool) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        let player = player ?? AVPlayer()
        self.player = player
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.snapshot.advanceManually {
                    self.snapshot.isPlaying = false
                    return
                }
                self.advance(by: 1)
                self.playCurrent()
            }
        }
        if autoplay {
            player.play()
            snapshot.isPlaying = true
        }
    }

    private func advance(by step: Int) {
        index += step
        if index < 0 { index = 0 }
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
