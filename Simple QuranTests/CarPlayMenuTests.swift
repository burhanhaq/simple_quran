import Foundation
import Testing
@testable import Simple_Quran

struct CarPlayMenuTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar.current

    private func memorized(_ range: VerseRange, touched: Date? = nil) -> [VerseProgressSnapshot] {
        range.globalAyahs.map { ayah in
            var snapshot = VerseProgressSnapshot.fresh(globalAyah: ayah)
            snapshot.recallState = .review
            snapshot.lastRevisedAt = touched ?? now
            return snapshot
        }
    }

    private func menu(_ targets: [LearningTarget] = [], active: LearningTarget? = nil, snapshots: [VerseProgressSnapshot] = [],
                      log: DailyLog? = nil, ayahRepeat: RepeatCount = .one, order: ProgressOrder = .fromAnNas,
                      catalog: BundledQuranCatalog) -> [CarPlaySection] {
        let today = TodayPlan(targets: targets, active: active, snapshots: snapshots, catalog: catalog, size: .default, cycle: .twoWeeks,
                              log: log ?? .empty(on: now, calendar: calendar), now: now, calendar: calendar)
        return CarPlayMenu.memorize(today: today, activePlanID: active?.id, snapshots: snapshots, catalog: catalog,
                                    order: order, ayahRepeat: ayahRepeat)
    }

    // MARK: - Memorize tab

    @Test func withNothingChosenTheCarPointsToThePhone() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let sections = menu(catalog: catalog)
        #expect(sections.count == 1)
        let row = try #require(sections.first?.rows.first)
        #expect(row.symbol == .phone)
        #expect(row.tap == nil)
    }

    @Test func todaysNewAyahsPlayWithTheMemorizeRepeats() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        let first = try #require(mulk.passage(catalog: catalog))

        let row = try #require(menu([mulk], active: mulk, ayahRepeat: .three, catalog: catalog).first?.rows.first)
        #expect(row.tap == .play(.memorize(passage: first, targetID: mulk.id)))
        #expect(row.detail?.contains(RepeatCount.three.label) == true)

        let once = try #require(menu([mulk], active: mulk, catalog: catalog).first?.rows.first)
        #expect(once.detail == LearningPassage.ayahLabel(first, catalog: catalog))
    }

    @Test func afterLearningTodayTheRowReplaysWhatWasLearned() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = LearningTarget(range: try #require(catalog.surah(number: 67)).range)
        let first = try #require(mulk.passage(catalog: catalog))
        let log = DailyLog(day: now, learned: first)

        let row = try #require(menu([mulk], active: mulk, snapshots: memorized(first), log: log, catalog: catalog).first?.rows.first)
        #expect(row.symbol == .done)
        #expect(row.tap == .play(.memorize(passage: first, targetID: mulk.id)))
    }

    @Test func dueRevisionPlaysEveryDuePassage() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        var forgotten = memorized(.clamped(start: 1, end: 1))
        forgotten[0].nextReviewAt = now
        let today = try #require(menu(snapshots: forgotten, catalog: catalog).first)

        #expect(today.rows.count == 2)
        #expect(today.rows[1].symbol == .revise)
        #expect(today.rows[1].tap == .play(.revise([.clamped(start: 1, end: 1)])))
    }

    @Test func memorizedSurahsFollowTheJourneyOrder() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let ikhlas = try #require(catalog.surah(number: 112))
        let falaq = try #require(catalog.surah(number: 113))
        let falaqStart = VerseRange.clamped(start: falaq.startGlobalAyah, end: falaq.startGlobalAyah + 2)
        let snapshots = memorized(ikhlas.range) + memorized(falaqStart)

        let fromAnNas = try #require(menu(snapshots: snapshots, catalog: catalog).last)
        #expect(fromAnNas.rows.map(\.title) == [falaq.englishName, ikhlas.englishName])
        // A whole surah shows its Arabic name; part of one names its ayahs.
        #expect(fromAnNas.rows[0].detail == LearningPassage.ayahLabel(falaqStart, catalog: catalog))
        #expect(fromAnNas.rows[1].detail == ikhlas.arabicName)
        #expect(fromAnNas.rows[1].tap == .play(.memorized(surah: 112, passages: [ikhlas.range])))

        let fromAlFatiha = try #require(menu(snapshots: snapshots, order: .fromAlFatiha, catalog: catalog).last)
        #expect(fromAlFatiha.rows.map(\.title) == [ikhlas.englishName, falaq.englishName])
    }

    @Test func aLongMemorizedStretchIsLabeledOnce() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let mulk = try #require(catalog.surah(number: 67))
        let firstTwelve = VerseRange.clamped(start: mulk.startGlobalAyah, end: mulk.startGlobalAyah + 11)

        let row = try #require(menu(snapshots: memorized(firstTwelve), catalog: catalog).last?.rows.first)
        #expect(row.detail == LearningPassage.ayahLabel(firstTwelve, catalog: catalog))
    }

    // MARK: - Quran tab

    @Test func theLatestRecentSurahContinuesWhereListeningStopped() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let kahf = try #require(catalog.surah(number: 18))
        let reading = kahf.startGlobalAyah + 33

        let sections = CarPlayMenu.quran(recentSurahs: [18, 36], readingAyah: reading, catalog: catalog)
        #expect(sections.map(\.rows.count) == [2, 30])
        let recent = sections[0].rows
        #expect(recent[0].symbol == .resume)
        #expect(recent[0].tap == .play(.surah(18, fromAyah: reading)))
        #expect(recent[1].tap == .play(.surah(36, fromAyah: nil)))
        #expect(sections[1].rows.first?.tap == .browseJuz(1))
    }

    @Test func withNothingPlayedYetOnlyJuzShow() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let sections = CarPlayMenu.quran(recentSurahs: [], readingAyah: 0, catalog: catalog)
        #expect(sections.count == 1)
        #expect(sections[0].rows.count == 30)
    }

    @Test func aJuzPlaysWholeOrFromAnySurahInIt() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let juz2 = try #require(catalog.juzs.first { $0.number == 2 })
        let sections = CarPlayMenu.juz(2, catalog: catalog)

        #expect(sections[0].rows.first?.tap == .play(.juz(2)))
        // Al-Baqarah began in juz 1, so from here it starts where juz 2 does.
        let baqarah = try #require(sections[1].rows.first)
        #expect(baqarah.tap == .play(.surah(2, fromAyah: juz2.startGlobalAyah)))
        #expect(CarPlayMenu.juz(30, catalog: catalog)[1].rows.count == 37)
    }

    // MARK: - Playing

    @Test func onlyTheRowPlayingNowIsMarked() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let yasin = try #require(catalog.surah(number: 36))
        let sections = CarPlayMenu.quran(recentSurahs: [36, 18], readingAyah: 0, catalog: catalog)

        let marked = CarPlayMenu.markingPlaying(sections, playing: [yasin.range], catalog: catalog)
        #expect(marked[0].rows.map(\.isPlaying) == [true, false])
        let stopped = CarPlayMenu.markingPlaying(sections, playing: nil, catalog: catalog)
        #expect(stopped[0].rows.map(\.isPlaying) == [false, false])
    }

    @Test func actionsPlayTheirPassagesUnderThePhonesNames() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let juz30 = try #require(catalog.juzs.first { $0.number == 30 })
        #expect(CarPlayAction.juz(30).passages(in: catalog) == [juz30.range])
        #expect(CarPlayAction.juz(30).title(in: catalog) == QuranDestination.juz(30).title(in: catalog))
        #expect(CarPlayAction.surah(18, fromAyah: 100).startAyah == 100)
        #expect(CarPlayAction.juz(30).startAyah == nil)
    }
}

@MainActor
struct RecentSurahTests {
    @Test func recentSurahsKeepTheLatestFiveWithoutRepeats() throws {
        let suite = "RecentSurahTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        for surah in [1, 2, 3, 2, 4, 5, 6, 7] { settings.noteListened(surah: surah) }
        #expect(settings.recentSurahs == [7, 6, 5, 4, 2])
        #expect(AppSettings(defaults: defaults).recentSurahs == [7, 6, 5, 4, 2])
    }
}
