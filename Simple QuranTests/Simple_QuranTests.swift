import Foundation
import SwiftData
import Testing
@testable import Simple_Quran

struct QuranIntegrityTests {
    @Test func bundledCorpusPassesIntegrityChecks() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        #expect(catalog.integrity.isValid)
        #expect(catalog.integrity.surahCount == 114)
        #expect(catalog.integrity.ayahCount == 6236)
        #expect(catalog.integrity.pageCount == 604)
        #expect(catalog.integrity.juzCount == 30)
        #expect(catalog.integrity.sajdahCount == 15)
        #expect(catalog.integrity.contiguousIDs)
        #expect(catalog.integrity.matchingSurahCounts)
        #expect(catalog.verse(globalAyah: 1)?.reference == "1:1")
        #expect(catalog.verse(globalAyah: 6236)?.reference == "114:6")
        #expect(catalog.surah(number: 9)?.ayahCount == 129)
        #expect(catalog.verse(globalAyah: 1)?.showsBasmalaBefore == false)
        #expect(catalog.verse(globalAyah: 8)?.showsBasmalaBefore == true)
        #expect(catalog.verse(globalAyah: 8)?.text == "الٓمٓ")
        #expect(catalog.verse(globalAyah: 1236)?.showsBasmalaBefore == false)
        #expect(catalog.verse(globalAyah: 6099)?.showsBasmalaBefore == true)
        #expect(catalog.verses.filter(\.showsBasmalaBefore).count == 112)
        let kahf = try catalog.range(surah: 18, startAyah: 1, endAyah: 10)
        #expect(kahf.count == 10)
        #expect(catalog.verses(in: kahf).first?.text.isEmpty == false)
    }
}

struct PracticePlaybackCursorTests {
    @Test func practiceStartsWithContinuousPlayback() {
        #expect(PracticeSettings.default.pauseSeconds == 0)
        #expect(PracticeSettings.default.ayahRepeatCount == .one)
        #expect(PracticeSettings.default.setRepeatCount == .one)
        #expect(PracticeSettings.listening.ayahRepeatCount == .one)
        #expect(PracticeSettings.listening.setRepeatCount == .one)
        #expect(PracticeSettings.listening.hideArabic == false)
        #expect(PracticeSettings.listening.pauseSeconds == 0)
    }

    @Test func playbackCursorDoesNotMultiplySetRepeats() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 1)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .two
        settings.setRepeatCount = .two
        settings.pauseSeconds = 0
        var cursor = PracticePlaybackCursor(passages: [range], settings: settings)
        var played: [Int] = []
        while let item = cursor.current {
            if case .ayah(let ayah, _, _) = item { played.append(ayah) }
            cursor.advanceAfterCompletion()
        }
        #expect(played == [1, 1, 1, 1])
    }

    @Test func indefiniteAyahRepeatsUntilTheUserSkips() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 2)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .indefinitely
        settings.setRepeatCount = .one
        settings.pauseSeconds = 0
        var cursor = PracticePlaybackCursor(passages: [range], settings: settings)

        for _ in 0..<3 {
            guard case .ayah(let ayah, _, let total) = cursor.current else {
                Issue.record("Expected an ayah")
                return
            }
            #expect(ayah == 1)
            #expect(total == 0)
            cursor.advanceAfterCompletion()
        }
        cursor.skipForward()
        guard case .ayah(let ayah, _, _) = cursor.current else {
            Issue.record("Expected the next ayah")
            return
        }
        #expect(ayah == 2)
    }

    @Test func pauseHasOneExplicitCompletionStep() throws {
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 2)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .one
        settings.setRepeatCount = .one
        settings.pauseSeconds = 2
        var cursor = PracticePlaybackCursor(passages: [range], settings: settings)

        #expect(cursor.current == .ayah(globalAyah: 1, repetition: 1, totalRepetitions: 1))
        cursor.advanceAfterCompletion()
        #expect(cursor.current == .silence(seconds: 2))
        cursor.advanceAfterCompletion()
        #expect(cursor.current == .ayah(globalAyah: 2, repetition: 1, totalRepetitions: 1))
    }

    @Test func movingDirectlyToAnAyahResetsItsRepetition() throws {
        let range = try VerseRange(startGlobalAyah: 10, endGlobalAyah: 12)
        var settings = PracticeSettings.default
        settings.ayahRepeatCount = .three
        var cursor = PracticePlaybackCursor(passages: [range], settings: settings)

        cursor.advanceAfterCompletion()
        #expect(cursor.current == .ayah(globalAyah: 10, repetition: 2, totalRepetitions: 3))
        let moved = cursor.move(to: 12)
        #expect(moved)
        #expect(cursor.current == .ayah(globalAyah: 12, repetition: 1, totalRepetitions: 3))
        let rejected = cursor.move(to: 99)
        #expect(rejected == false)
        #expect(cursor.current == .ayah(globalAyah: 12, repetition: 1, totalRepetitions: 3))
    }
}

struct PlaybackCoordinatorTests {
    @Test @MainActor func openingPracticePreparesTheLastAyahWithoutStartingPlayback() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 2)
        let set = try store.createSet(title: "Paused practice", passages: [range], settings: .default)
        set.lastGlobalAyah = 2
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let audioSource = AlQuranCloudAudioSource()
        let fileStore = AudioFileStore(
            reciter: audioSource.reciter,
            baseDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        let playback = PlaybackCoordinator(source: audioSource, fileStore: fileStore)

        playback.start(set: set, catalog: catalog, resume: true, allowStreaming: true)

        #expect(playback.snapshot.currentGlobalAyah == 2)
        #expect(playback.snapshot.isPlaying == false)
        #expect(playback.snapshot.isLoading == false)
        #expect(playback.coveredAyahs.isEmpty)
        #expect(playback.repetitionCount == 0)
        playback.stop()
    }

    @Test @MainActor func startListeningPreparesWithoutAPracticeSet() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let audioSource = AlQuranCloudAudioSource()
        let fileStore = AudioFileStore(
            reciter: audioSource.reciter,
            baseDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        let playback = PlaybackCoordinator(source: audioSource, fileStore: fileStore)
        let range = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 7)

        playback.startListening(
            title: "Al-Faatiha",
            passages: [range],
            fromAyah: 1,
            catalog: catalog,
            allowStreaming: true
        )

        #expect(playback.activeSet == nil)
        #expect(playback.session == nil)
        #expect(playback.snapshot.setID == nil)
        #expect(playback.snapshot.setTitle == "Al-Faatiha")
        #expect(playback.snapshot.currentGlobalAyah == 1)
        #expect(playback.snapshot.isPlaying == false)
        #expect(playback.snapshot.isLoading == false)
        #expect(playback.snapshot.ayahRepeat == .one)
        #expect(playback.isPrepared(for: [range]))
        #expect(playback.containsAyah(7))
        #expect(playback.containsAyah(8) == false)
        playback.stop()
    }

    @Test @MainActor func skipWhilePausedAdvancesWithoutASessionOrPlayback() throws {
        let (playback, set, catalog) = try makeCoordinatorFixture(start: 1, end: 3)
        playback.start(set: set, catalog: catalog, resume: true, allowStreaming: true)

        #expect(playback.session == nil)
        #expect(playback.snapshot.currentGlobalAyah == 1)
        #expect(playback.hasPreparedQueue == false)

        playback.skipForward()

        #expect(playback.session == nil)
        #expect(playback.snapshot.currentGlobalAyah == 2)
        #expect(playback.snapshot.isPlaying == false)
        #expect(playback.snapshot.isLoading == false)
        #expect(playback.hasPreparedQueue)
        playback.stop()
    }

    @Test @MainActor func skipAfterPauseKeepsTheCurrentAyahAndQueue() throws {
        let (playback, set, catalog) = try makeCoordinatorFixture(start: 1, end: 3, lastAyah: 2)
        playback.start(set: set, catalog: catalog, resume: true, allowStreaming: true)

        playback.resume()
        playback.pause()
        #expect(playback.snapshot.currentGlobalAyah == 2)
        #expect(playback.snapshot.isPlaying == false)

        playback.skipBack()
        #expect(playback.snapshot.currentGlobalAyah == 1)
        #expect(playback.snapshot.isPlaying == false)
        #expect(playback.hasPreparedQueue)

        playback.skipForward()
        #expect(playback.snapshot.currentGlobalAyah == 2)
        #expect(playback.snapshot.isPlaying == false)
        #expect(playback.hasPreparedQueue)
        playback.stop()
    }

    @Test @MainActor func resumeNotifiesWillStartAudio() throws {
        let (playback, set, catalog) = try makeCoordinatorFixture(start: 1, end: 2)
        var count = 0
        playback.onWillStartAudio = { count += 1 }
        playback.start(set: set, catalog: catalog, resume: true, allowStreaming: true)
        playback.resume()
        #expect(count == 1)
        playback.stop()
    }
}

@MainActor
private func makeCoordinatorFixture(
    start: Int,
    end: Int,
    lastAyah: Int? = nil
) throws -> (PlaybackCoordinator, PracticeSet, BundledQuranCatalog) {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let store = PracticeStore(context: container.mainContext)
    let range = try VerseRange(startGlobalAyah: start, endGlobalAyah: end)
    let set = try store.createSet(title: "Transport practice", passages: [range], settings: .default)
    set.lastGlobalAyah = lastAyah
    let catalog = try BundledQuranCatalog.loadFromBundle()
    let audioSource = AlQuranCloudAudioSource()
    let fileStore = AudioFileStore(
        reciter: audioSource.reciter,
        baseDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    )
    return (PlaybackCoordinator(source: audioSource, fileStore: fileStore), set, catalog)
}

struct AudioInterruptionPolicyTests {
    @Test @MainActor func suspendedInterruptionsDoNotPause() {
        #expect(AudioInterruptionPolicy.actionForBegan(wasSuspended: true) == .ignore)
        #expect(AudioInterruptionPolicy.actionForBegan(wasSuspended: false) == .pausePreservingIntent)
    }

    @Test @MainActor func playbackIntentSurvivesInterruptionsWithoutShouldResume() {
        #expect(AudioInterruptionPolicy.actionForEnded(shouldResume: false, hasPlaybackIntent: true) == .resume)
        #expect(AudioInterruptionPolicy.actionForEnded(shouldResume: true, hasPlaybackIntent: true) == .resume)
        #expect(AudioInterruptionPolicy.actionForEnded(shouldResume: true, hasPlaybackIntent: false) == .ignore)
        #expect(AudioInterruptionPolicy.actionForEnded(shouldResume: false, hasPlaybackIntent: false) == .ignore)
    }
}

struct PracticePlaybackLifecycleTests {
    @Test @MainActor func reappearingTheSameCollectionDoesNotRestartPlayback() {
        let id = UUID()
        #expect(
            PracticePlaybackLifecycle.shouldPrepareNewSession(
                activeSetID: id,
                currentGlobalAyah: 12,
                openingSetID: id
            ) == false
        )
    }

    @Test @MainActor func aNewOrStoppedSessionPreparesPlaybackAgain() {
        let id = UUID()
        #expect(
            PracticePlaybackLifecycle.shouldPrepareNewSession(
                activeSetID: id,
                currentGlobalAyah: nil,
                openingSetID: id
            )
        )
        #expect(
            PracticePlaybackLifecycle.shouldPrepareNewSession(
                activeSetID: UUID(),
                currentGlobalAyah: 1,
                openingSetID: id
            )
        )
        #expect(
            PracticePlaybackLifecycle.shouldPrepareNewSession(
                activeSetID: nil,
                currentGlobalAyah: nil,
                openingSetID: id
            )
        )
    }
}

struct ReviewSchedulerTests {
    @Test func listeningIsNotMasteryAndRatingsScheduleReviews() {
        let scheduler = ReviewScheduler()
        let fresh = VerseProgressSnapshot.fresh(globalAyah: 255)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let again = scheduler.apply(rating: .again, to: fresh, now: now)
        #expect(again.state == .learning)
        #expect(again.isWeak)
        #expect(again.streak == 0)

        var comfortable = fresh
        comfortable.streak = 0
        let firstComfortable = scheduler.apply(rating: .comfortable, to: comfortable, now: now)
        #expect(firstComfortable.state == .strengthening)
        #expect(firstComfortable.isWeak == false)

        var solid = fresh
        solid.streak = 3
        let review = scheduler.apply(rating: .solid, to: solid, now: now)
        #expect(review.state == .review)
        #expect(review.nextReviewAt > now)
    }
}

struct SearchAndAudioSourceTests {
    @Test func searchFindsKahfRangeAndJuzAmma() throws {
        let catalog = try BundledQuranCatalog.loadFromBundle()
        let kahfRange = try catalog.range(surah: 18, startAyah: 1, endAyah: 10)
        let kahf = catalog.search("18:1-10")
        #expect(kahf.hits.contains { if case .range(let range) = $0.kind { return range.count == 10 }; return false })
        #expect(kahf.hits.contains { $0.title == PassageLabel.passage(kahfRange, catalog: catalog) })
        let amma = catalog.search("juz amma")
        #expect(amma.hits.contains { if case .juz(30) = $0.kind { return true }; return false })
    }

    @Test func sudaisURLsAreVerseAddressable() throws {
        let source = AlQuranCloudAudioSource()
        let url = try source.remoteURL(for: 1)
        #expect(source.reciter.id == "ar.abdurrahmaansudais")
        #expect(source.reciter.qualityKbps == 64)
        #expect(url.absoluteString.hasSuffix("/64/ar.abdurrahmaansudais/1.mp3"))
        #expect(throws: AppError.invalidRange) {
            _ = try source.remoteURL(for: 0)
        }
    }
}

struct AudioFileStoreTests {
    @Test func rejectsUndersizedDownloadsAndInstallsValidSizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioFileStore(baseDirectory: root)

        let invalid = root.appending(path: "invalid.mp3")
        try Data(repeating: 0, count: 100).write(to: invalid)
        #expect(throws: AppError.invalidAudio) {
            _ = try store.install(temporaryURL: invalid, globalAyah: 1)
        }
        #expect(store.isReady(1) == false)

        let validSized = root.appending(path: "valid.mp3")
        try Data(repeating: 0, count: 2_000).write(to: validSized)
        _ = try store.install(temporaryURL: validSized, globalAyah: 1)
        #expect(store.isReady(1))
        #expect(store.byteCount(globalAyah: 1) == 2_000)
    }
}

struct UserFacingErrorTests {
    @Test func mapsInternalFailuresToFriendlyCopy() {
        let message = UserFacingMessage.from(.downloadFailed)
        #expect(!message.message.contains("http"))
        #expect(!message.message.contains("URLSession"))
        #expect(message.title.isEmpty == false)
    }
}

struct PracticeStoreTests {
    @Test @MainActor func createsSetsAndKeepsGlobalRecall() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)
        let fatiha = try VerseRange(startGlobalAyah: 1, endGlobalAyah: 7)
        let set = try store.createSet(title: "First ten Kahf", passages: [fatiha], settings: .default)
        #expect(set.orderedPassages.count == 1)
        try store.applyRating(.needsWork, ayahs: [1], now: .now)
        let progress = try store.progress(for: 1)
        #expect(progress.recallState == .learning)
        #expect(progress.isWeak)
        #expect(progress.exposureCount == 0)
    }

    @Test @MainActor func reviewBookmarkCanBeToggled() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = PracticeStore(context: container.mainContext)

        #expect(try store.isMarkedWeak(globalAyah: 255) == false)
        try store.markWeak(globalAyah: 255, weak: true)
        #expect(try store.isMarkedWeak(globalAyah: 255))
        #expect(try store.progress(for: 255).nextReviewAt != nil)

        try store.markWeak(globalAyah: 255, weak: false)
        #expect(try store.isMarkedWeak(globalAyah: 255) == false)
        #expect(try store.progress(for: 255).nextReviewAt == nil)
    }
}
