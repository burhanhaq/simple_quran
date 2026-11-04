import CarPlay
import Observation
import SwiftData
import UIKit

/// Builds the car's screens from `CarPlayMenu` and plays what the driver picks.
/// Everything goes through the same playback as the phone, so either one can pick up where the other left off.
final class CarPlayController: NSObject {
    /// A tapped row waiting for its audio to start, with its spinner still showing.
    private struct PendingStart {
        var completion: () -> Void
        var timeout: Task<Void, Never>
    }

    /// How long a row's spinner shows before Now Playing opens anyway, reading "Loading…".
    private static let startSpinnerLimit: Duration = .seconds(3)
    /// Saves that only touch download bookkeeping don't change anything the car shows.
    private static let downloadRecordEntity = String(describing: AudioDownloadRecord.self)

    private let environment: AppEnvironment
    private let interface: CPInterfaceController
    private let memorizeTemplate: CPListTemplate
    private let quranTemplate: CPListTemplate
    private var juzTemplate: (number: Int, template: CPListTemplate)?
    private lazy var nowPlaying = CarPlayNowPlaying(environment: environment, interface: interface)
    /// What each list last showed, so unchanged lists aren't redrawn while audio plays.
    private var shownSections: [ObjectIdentifier: [CarPlaySection]] = [:]
    /// Progress only changes when the store saves, so it isn't fetched on every refresh.
    private var progress: [VerseProgressSnapshot] = []
    private var shownMessage: UserFacingMessage?
    private var saveObserver: NSObjectProtocol?
    private var isReloadScheduled = false
    private var pendingStart: PendingStart?
    private var isConnected = false

    private var playback: PlaybackCoordinator { environment.playback }
    private var quran: BundledQuranCatalog { environment.quran }
    /// The passages playing right now, for the rows' playing indicator.
    private var playingPassages: [VerseRange]? {
        playback.snapshot.isPlaying || playback.snapshot.isLoading ? playback.passageRanges : nil
    }

    init(environment: AppEnvironment, interface: CPInterfaceController) {
        self.environment = environment
        self.interface = interface
        memorizeTemplate = Self.tab(.memorize)
        quranTemplate = Self.tab(.quran)
        super.init()
    }

    func connect() {
        isConnected = true
        interface.delegate = self
        nowPlaying.connect()
        reloadProgress()
        refresh()
        interface.setRootTemplate(CPTabBarTemplate(templates: [memorizeTemplate, quranTemplate]), animated: false, completion: nil)
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] notification in
            let saved = Self.savedEntityNames(notification)
            MainActor.assumeIsolated {
                guard Self.affectsMenus(saved) else { return }
                self?.scheduleReload()
            }
        }
        observeState()
    }

    func disconnect() {
        isConnected = false
        finishPendingStart(showingNowPlaying: false)
        nowPlaying.disconnect()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
    }

    private static func tab(_ tab: AppTab) -> CPListTemplate {
        let template = CPListTemplate(title: tab.title, sections: [])
        template.tabTitle = tab.title
        template.tabImage = UIImage(systemName: tab.systemImage)
        return template
    }

    // MARK: - Updating

    /// Re-runs `refresh` whenever anything the lists or Now Playing show changes.
    private func observeState() {
        guard isConnected else { return }
        withObservationTracking {
            let settings = environment.settings
            _ = (settings.learningTargets, settings.activeTargetID, settings.dailyLog, settings.pieceSize, settings.revisionCycle)
            _ = (settings.memorizePlayback, settings.recentSurahs, settings.readingAyah, settings.reciterID)
            _ = (playback.snapshot, playback.userMessage, playback.activeSet, environment.reciters.catalog)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeState()
            }
        }
    }

    private func reloadProgress() {
        progress = (try? environment.store.allProgress()) ?? []
    }

    /// The model types a save inserted, updated or deleted.
    nonisolated private static func savedEntityNames(_ notification: Notification) -> [String] {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        return keys.flatMap { key in
            (notification.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []).map(\.entityName)
        }
    }

    /// Whether a save touched anything besides download bookkeeping. A save without details counts.
    private static func affectsMenus(_ savedEntityNames: [String]) -> Bool {
        savedEntityNames.isEmpty || savedEntityNames.contains { $0 != downloadRecordEntity }
    }

    /// Playback saves several times per ayah; those saves become one reload.
    private func scheduleReload() {
        guard !isReloadScheduled else { return }
        isReloadScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isReloadScheduled = false
            reloadProgress()
            refresh()
        }
    }

    private func refresh() {
        guard isConnected else { return }
        let playing = playingPassages
        show(memorizeSections(), in: memorizeTemplate, playing: playing)
        show(CarPlayMenu.quran(recentSurahs: environment.settings.recentSurahs, readingAyah: environment.settings.readingAyah,
                               catalog: quran),
             in: quranTemplate, playing: playing)
        if let juz = juzTemplate {
            show(CarPlayMenu.juz(juz.number, catalog: quran), in: juz.template, playing: playing)
        }
        nowPlaying.refresh()
        checkPendingStart()
        presentMessageIfNeeded()
    }

    private func memorizeSections() -> [CarPlaySection] {
        guard environment.persistenceLoadError == nil, environment.catalogLoadError == nil else {
            return [CarPlaySection(header: nil, rows: [CarPlayRow(title: String(localized: "Open Simple Quran on your iPhone"), symbol: .phone)])]
        }
        let settings = environment.settings
        let today = TodayPlan(targets: settings.learningTargets, active: settings.activePlan, snapshots: progress, catalog: quran,
                              size: settings.pieceSize, cycle: settings.revisionCycle, log: settings.dailyLog)
        let order = UserDefaults.standard.string(forKey: ProgressOrder.storageKey).flatMap(ProgressOrder.init(rawValue:)) ?? .fromAnNas
        return CarPlayMenu.memorize(today: today, activePlanID: settings.activePlan?.id, snapshots: progress, catalog: quran,
                                    order: order, ayahRepeat: settings.memorizePlayback.ayahRepeatCount)
    }

    private func show(_ sections: [CarPlaySection], in template: CPListTemplate, playing: [VerseRange]?) {
        let sections = Self.fitting(CarPlayMenu.markingPlaying(sections, playing: playing, catalog: quran))
        let key = ObjectIdentifier(template)
        guard shownSections[key] != sections else { return }
        shownSections[key] = sections
        template.updateSections(sections.map { section in
            CPListSection(items: section.rows.map(listItem), header: section.header, sectionIndexTitle: nil)
        })
    }

    /// Cars cap how many rows and sections a list may hold; anything past the cap is left off.
    private static func fitting(_ sections: [CarPlaySection]) -> [CarPlaySection] {
        var budget = CPListTemplate.maximumItemCount
        return sections.prefix(CPListTemplate.maximumSectionCount).compactMap { section in
            guard budget > 0 else { return nil }
            var section = section
            section.rows = Array(section.rows.prefix(budget))
            budget -= section.rows.count
            return section
        }
    }

    private func listItem(_ row: CarPlayRow) -> CPListItem {
        let item = CPListItem(text: row.title, detailText: row.detail, image: UIImage(systemName: row.symbol.rawValue))
        item.isPlaying = row.isPlaying
        switch row.tap {
        case .play(let action):
            // The row's spinner shows until `completion` runs, once the audio starts.
            item.handler = { [weak self] _, completion in
                guard let self else { return completion() }
                play(action, completion: completion)
            }
        case .browseJuz(let number):
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.openJuz(number)
                completion()
            }
        case nil:
            break
        }
        return item
    }

    // MARK: - Actions

    private func openJuz(_ number: Int) {
        let template = CPListTemplate(title: QuranDestination.juz(number).title(in: quran), sections: [])
        juzTemplate = (number, template)
        show(CarPlayMenu.juz(number, catalog: quran), in: template, playing: playingPassages)
        interface.pushTemplate(template, animated: true, completion: nil)
    }

    private func play(_ action: CarPlayAction, completion: @escaping () -> Void) {
        finishPendingStart(showingNowPlaying: false)
        let streaming = environment.settings.streamWhenMissing
        switch action {
        case .memorize(let passage, let targetID):
            do {
                let practice = try environment.practice(for: passage)
                if PracticePlaybackLifecycle.shouldPrepareNewSession(activeSetID: playback.activeSet?.id,
                                                                      currentGlobalAyah: playback.snapshot.currentGlobalAyah,
                                                                      openingSetID: practice.id) {
                    playback.start(set: practice, catalog: quran, resume: false, allowStreaming: streaming)
                }
                // The phone's mini player then reopens this passage in the memorize coach.
                environment.lastSession = SessionRoute(range: passage, kind: .learn, planID: targetID)
            } catch {
                playback.userMessage = .from(.persistenceFailure)
                completion()
                return
            }
        case .revise, .memorized, .surah, .juz:
            let passages = action.passages(in: quran)
            // Tapping what's already loaded carries on from where it paused.
            if playback.activeSet != nil || !playback.isPrepared(for: passages) {
                playback.startListening(title: action.title(in: quran), passages: passages, fromAyah: action.startAyah,
                                        catalog: quran, allowStreaming: streaming)
            }
            environment.lastSession = nil
        }
        playback.resume()
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.startSpinnerLimit)
            guard !Task.isCancelled else { return }
            self?.finishPendingStart(showingNowPlaying: true)
        }
        pendingStart = PendingStart(completion: completion, timeout: timeout)
        checkPendingStart()
    }

    /// Ends the row's spinner once audio plays or stops loading. A failure leaves the list in place for its alert.
    private func checkPendingStart() {
        guard pendingStart != nil else { return }
        if playback.userMessage != nil {
            finishPendingStart(showingNowPlaying: false)
        } else if playback.snapshot.isPlaying || !playback.snapshot.isLoading {
            finishPendingStart(showingNowPlaying: true)
        }
    }

    private func finishPendingStart(showingNowPlaying: Bool) {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        pending.timeout.cancel()
        pending.completion()
        if showingNowPlaying { nowPlaying.show() }
    }

    /// Playback problems (audio not downloaded with streaming off, no connection) show as an alert,
    /// once per message, rather than failing silently.
    private func presentMessageIfNeeded() {
        let message = playback.userMessage
        defer { shownMessage = message }
        guard let message, message != shownMessage, interface.presentedTemplate == nil else { return }
        let alert = CPAlertTemplate(titleVariants: ["\(message.title). \(message.message)", message.title], actions: [
            CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                self?.interface.dismissTemplate(animated: true, completion: nil)
            }
        ])
        interface.presentTemplate(alert, animated: true, completion: nil)
    }
}

extension CarPlayController: CPInterfaceControllerDelegate {
    /// A new day or a change made on the phone shows as soon as a list comes back into view.
    func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
        guard aTemplate === memorizeTemplate || aTemplate === quranTemplate else { return }
        reloadProgress()
        refresh()
    }

    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        guard let juz = juzTemplate, aTemplate === juz.template,
              !interface.templates.contains(where: { $0 === juz.template }) else { return }
        shownSections[ObjectIdentifier(juz.template)] = nil
        juzTemplate = nil
    }
}
