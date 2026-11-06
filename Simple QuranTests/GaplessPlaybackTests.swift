import AVFoundation
import Foundation
import Testing
@testable import Simple_Quran

/// Real CDN files: Shuraim 18 and 19 are consecutive ayahs (44.1 kHz stereo) cut with no silence
/// between them; Maher 300 is 22.05 kHz mono.
private enum Fixture: String {
    case shuraim18 = "shuraim-18"
    case shuraim19 = "shuraim-19"
    case maherMono = "maher-mono-300"

    /// Valid frames per `afinfo`, after the gapless header's priming and padding are removed.
    var trimmedFrames: AVAudioFramePosition {
        switch self {
        case .shuraim18: 334_912
        case .shuraim19: 244_544
        case .maherMono: 1_025_856
        }
    }

    var url: URL {
        let bundle = Bundle(for: FixtureBundleToken.self)
        return bundle.url(forResource: rawValue, withExtension: "mp3")
            ?? bundle.url(forResource: rawValue, withExtension: "mp3", subdirectory: "Fixtures")!
    }

    /// A copy the test may move or delete.
    func temporaryCopy() throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
}

private final class FixtureBundleToken {}

@MainActor
private func decodeAll(_ source: AudioSegment.Source) throws -> [[Float]] {
    let reader = try PCMSegmentReader(source: source)
    var channels: [[Float]] = [[], []]
    while let chunk = try reader.nextChunk() {
        append(chunk, to: &channels)
    }
    return channels
}

private func append(_ buffer: AVAudioPCMBuffer, to channels: inout [[Float]]) {
    guard let data = buffer.floatChannelData else { return }
    let frames = Int(buffer.frameLength)
    for channel in channels.indices {
        channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: frames))
    }
}

private func maxDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
    zip(lhs, rhs).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// A 44.1 kHz mono file: `silence` of digital zero, then a 440 Hz tone.
@MainActor
private func writeToneFile(silence: TimeInterval, tone: TimeInterval) throws -> URL {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).caf")
    let silentFrames = Int(silence * 44_100)
    let frames = silentFrames + Int(tone * 44_100)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for frame in 0..<frames {
        buffer.floatChannelData![0][frame] = frame < silentFrames ? 0 : 0.5 * sin(2 * .pi * 440 * Float(frame) / 44_100)
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

/// The longest run of 1 ms windows quieter than -45 dB within 120 ms either side of `frame`.
private func longestDipMilliseconds(in samples: [Float], around frame: Int) -> Int {
    let window = 44
    var run = 0
    var longest = 0
    for start in stride(from: max(0, frame - 120 * window), to: min(samples.count - window, frame + 120 * window), by: window) {
        let rms = (samples[start..<(start + window)].reduce(0) { $0 + $1 * $1 } / Float(window)).squareRoot()
        if 20 * log10(max(rms, 1e-9)) < -45 {
            run += 1
            longest = max(longest, run)
        } else {
            run = 0
        }
    }
    return longest
}

struct PCMSegmentReaderTests {
    @Test @MainActor func fileStartsAtItsFirstAudibleMillisecond() throws {
        let channels = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))
        let trimmed = Fixture.shuraim19.trimmedFrames - AVAudioFramePosition(channels[0].count)
        // Shuraim 19 opens with ~46 ms of re-encoding residue.
        #expect(trimmed > 1_764 && trimmed <= 2_205)
        #expect(channels[1].count == channels[0].count)
        #expect(longestDipMilliseconds(in: Array(channels[0].prefix(44 * 120)), around: 0) < 10)
    }

    @Test @MainActor func deadAirTrimStopsAtFiftyMilliseconds() throws {
        let url = try writeToneFile(silence: 0.3, tone: 0.2)
        let reader = try PCMSegmentReader(source: .file(url, smoothsJoins: true))
        // A real pause is kept: only 50 whole milliseconds (50 × 44 frames) of it are trimmed.
        #expect(reader.totalFrames == 22_050 - 2_200)
    }

    @Test @MainActor func fileThatStartsWithSoundIsNotTrimmed() throws {
        let url = try writeToneFile(silence: 0, tone: 0.2)
        let reader = try PCMSegmentReader(source: .file(url, smoothsJoins: true))
        #expect(reader.totalFrames == 8_820)
    }

    @Test @MainActor func fileAsRecordedKeepsEverySample() throws {
        let channels = try decodeAll(.file(Fixture.shuraim19.url))
        #expect(AVAudioFramePosition(channels[0].count) == Fixture.shuraim19.trimmedFrames)
        let pause = try PCMSegmentReader(source: .file(writeToneFile(silence: 0.3, tone: 0.2)))
        #expect(pause.totalFrames == 22_050)
    }

    @Test @MainActor func monoAtHalfRateBecomesStereoAtTheFixedRate() throws {
        let reader = try PCMSegmentReader(source: .file(Fixture.maherMono.url, smoothsJoins: true))
        #expect(reader.totalFrames <= Fixture.maherMono.trimmedFrames * 2)
        #expect(reader.totalFrames > Fixture.maherMono.trimmedFrames * 2 - 4_410)
        let channels = try decodeAll(.file(Fixture.maherMono.url, smoothsJoins: true))
        #expect(abs(AVAudioFramePosition(channels[0].count) - reader.totalFrames) <= 2)
        #expect(channels[0] == channels[1])
        #expect(channels[0].contains { $0 != 0 })
    }

    @Test @MainActor func readToEndReturnsEveryRemainingFrame() throws {
        let whole = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))
        let reader = try PCMSegmentReader(source: .file(Fixture.shuraim19.url, smoothsJoins: true))
        _ = try reader.nextChunk(maxFrames: AVAudioFrameCount(reader.totalFrames - 1_323))
        let tail = try #require(try reader.readToEnd())
        #expect(tail.frameLength == 1_323)
        #expect(reader.isExhausted)
        let samples = Array(UnsafeBufferPointer(start: tail.floatChannelData![0], count: Int(tail.frameLength)))
        #expect(maxDifference(samples, Array(whole[0].suffix(1_323))) < 1e-6)
    }

    @Test @MainActor func silenceIsExactlyItsLengthOfZeros() throws {
        let channels = try decodeAll(.silence(seconds: 2))
        #expect(channels[0].count == 88_200)
        #expect(channels.allSatisfy { $0.allSatisfy { $0 == 0 } })
        #expect(try decodeAll(.silence(seconds: 0))[0].isEmpty)
    }

    @Test @MainActor func seekingContinuesWithTheSameSamples() throws {
        let whole = try decodeAll(.file(Fixture.shuraim18.url, smoothsJoins: true))
        let reader = try PCMSegmentReader(source: .file(Fixture.shuraim18.url, smoothsJoins: true))
        _ = try reader.nextChunk()
        let resumeAt: AVAudioFramePosition = 100_000
        reader.seek(toFrame: resumeAt)
        var rest: [[Float]] = [[], []]
        while let chunk = try reader.nextChunk() { append(chunk, to: &rest) }
        let expected = Array(whole[0][Int(resumeAt)...])
        #expect(rest[0].count == expected.count)
        #expect(maxDifference(rest[0], expected) < 1e-6)
    }

    @Test @MainActor func unreadableFileIsRejected() throws {
        let junk = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data("not audio".utf8).write(to: junk)
        #expect(throws: AppError.invalidAudio) { try PCMSegmentReader(source: .file(junk)) }
    }
}

struct GaplessAudioPlayerTests {
    /// An engine that renders as fast as the test pulls frames, instead of to the speaker.
    @MainActor private func makeOfflinePlayer(lookahead: TimeInterval) throws -> (GaplessAudioPlayer, AVAudioEngine) {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: PCMSegmentReader.format, maximumFrameCount: 4_096)
        return (GaplessAudioPlayer(engine: engine, lookahead: lookahead), engine)
    }

    @MainActor private func render(_ engine: AVAudioEngine, frames total: Int) throws -> [[Float]] {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4_096)!
        var channels: [[Float]] = [[], []]
        while channels[0].count < total {
            let frames = AVAudioFrameCount(min(4_096, total - channels[0].count))
            #expect(try engine.renderOffline(frames, to: buffer) == .success)
            append(buffer, to: &channels)
        }
        return channels
    }

    /// Renders in small steps, letting the player's main-actor callbacks run in between, as on a device.
    @MainActor private func renderWithCallbacks(_ engine: AVAudioEngine, frames total: Int) async throws -> [[Float]] {
        var channels: [[Float]] = [[], []]
        while channels[0].count < total {
            let step = try render(engine, frames: min(4_096, total - channels[0].count))
            for channel in 0..<2 { channels[channel] += step[channel] }
            try await Task.sleep(for: .milliseconds(2))
        }
        return channels
    }

    private static let crossfadeFrames = Int(GaplessAudioPlayer.crossfade * 44_100)

    /// `tail` fading out over the start of `head`, as the player blends them.
    private func blended(_ tail: [Float], _ head: [Float]) -> [Float] {
        let length = Float(tail.count)
        return head.indices.map { frame in
            guard frame < tail.count else { return head[frame] }
            let progress = (Float(frame) + 0.5) / length * .pi / 2
            return tail[frame] * cos(progress) + head[frame] * sin(progress)
        }
    }

    @Test @MainActor func consecutiveAyahsCrossfadeWithoutADip() throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        try player.enqueue(AudioSegment(id: 1, source: .file(Fixture.shuraim18.url, smoothsJoins: true)))
        try player.enqueue(AudioSegment(id: 2, source: .file(Fixture.shuraim19.url, smoothsJoins: true)))
        try player.play()

        let fade = Self.crossfadeFrames
        let first = try decodeAll(.file(Fixture.shuraim18.url, smoothsJoins: true))
        let second = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))
        // The second ayah's own tail waits for a next ayah that never comes, so it isn't rendered here.
        let expected = (0..<2).map { channel in
            Array(first[channel].dropLast(fade))
                + blended(Array(first[channel].suffix(fade)), Array(second[channel].dropLast(fade)))
        }
        let rendered = try render(engine, frames: expected[0].count)

        // Exactly the two recordings overlapped by the crossfade: nothing inserted, nothing lost.
        for channel in 0..<2 {
            #expect(maxDifference(rendered[channel], expected[channel]) < 1e-5)
        }
        let join = first[0].count - fade / 2
        #expect(longestDipMilliseconds(in: rendered[0], around: join) <= 10)
    }

    @Test @MainActor func ayahsAsRecordedJoinExactlyBackToBack() throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        try player.enqueue(AudioSegment(id: 1, source: .file(Fixture.shuraim18.url)))
        try player.enqueue(AudioSegment(id: 2, source: .file(Fixture.shuraim19.url)))
        try player.play()

        // No trim, no overlap, nothing held back: every recorded sample, one file straight after the other.
        let first = try decodeAll(.file(Fixture.shuraim18.url))
        let second = try decodeAll(.file(Fixture.shuraim19.url))
        let expected = (0..<2).map { first[$0] + second[$0] }
        let rendered = try render(engine, frames: expected[0].count)
        for channel in 0..<2 {
            #expect(maxDifference(rendered[channel], expected[channel]) < 1e-5)
        }
    }

    @Test @MainActor func lastAyahsTailStillPlaysWhenNothingFollows() async throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        try player.enqueue(AudioSegment(id: 1, source: .file(Fixture.shuraim19.url, smoothsJoins: true)))
        try player.play()

        let expected = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))
        let rendered = try await renderWithCallbacks(engine, frames: expected[0].count)
        #expect(maxDifference(rendered[0], expected[0]) < 1e-5)
    }

    @Test @MainActor func pauseBetweenAyahsIsExactlyItsLength() throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        try player.enqueue(AudioSegment(id: 1, source: .file(Fixture.shuraim19.url, smoothsJoins: true)))
        try player.enqueue(AudioSegment(id: 2, source: .silence(seconds: 1)))
        try player.enqueue(AudioSegment(id: 3, source: .file(Fixture.shuraim19.url, smoothsJoins: true)))
        try player.play()

        // No crossfade into or out of a pause; the last ayah's tail waits for a next ayah.
        let ayah = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))
        let expected = ayah[0] + [Float](repeating: 0, count: 44_100) + ayah[0].dropLast(Self.crossfadeFrames)
        let rendered = try render(engine, frames: expected.count)
        #expect(maxDifference(rendered[0], expected) < 1e-5)
    }

    @Test @MainActor func segmentsReportStartAndFinishInOrder() async throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        var events: [String] = []
        player.onSegmentStarted = { events.append("start \($0)") }
        player.onSegmentFinished = { events.append("finish \($0)") }
        try player.enqueue(AudioSegment(id: 1, source: .silence(seconds: 1)))
        try player.enqueue(AudioSegment(id: 2, source: .silence(seconds: 1)))
        try player.play()
        #expect(events == ["start 1"])

        _ = try render(engine, frames: 2 * 44_100)
        await waitUntil { events.count == 4 }
        #expect(events == ["start 1", "finish 1", "start 2", "finish 2"])
        #expect(!player.hasQueuedAudio)
    }

    @Test @MainActor func resetDropsTheQueueWithoutReportingIt() async throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        var finished: [Int] = []
        player.onSegmentFinished = { finished.append($0) }
        try player.enqueue(AudioSegment(id: 1, source: .silence(seconds: 1)))
        try player.play()
        _ = try render(engine, frames: 44_100)
        player.reset()
        await waitUntil(timeout: .milliseconds(200)) { !finished.isEmpty }
        #expect(finished.isEmpty)
        #expect(!player.hasQueuedAudio)
    }

    @Test @MainActor func emptyQueueRendersSilenceAndPicksUpWhatIsAddedLater() throws {
        let (player, engine) = try makeOfflinePlayer(lookahead: 60)
        try player.play()
        let idle = try render(engine, frames: 4_096)
        #expect(idle[0].allSatisfy { $0 == 0 })

        try player.enqueue(AudioSegment(id: 1, source: .file(Fixture.shuraim19.url, smoothsJoins: true)))
        let expected = try decodeAll(.file(Fixture.shuraim19.url, smoothsJoins: true))[0].dropLast(Self.crossfadeFrames)
        let rendered = try render(engine, frames: expected.count)
        #expect(maxDifference(rendered[0], Array(expected)) < 1e-5)
    }
}

struct AyahAudioResolverTests {
    private static let ayah = 19

    @MainActor private func makeResolver(fetch: @escaping AyahAudioResolver.Fetch = { _ in throw AppError.downloadFailed })
        -> (AyahAudioResolver, AudioFileStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let source = AlQuranCloudAudioSource()
        let store = AudioFileStore(reciter: source.reciter, baseDirectory: root.appending(path: "Saved"))
        let resolver = AyahAudioResolver(
            source: source,
            fileStore: store,
            streamCacheDirectory: root.appending(path: "Streamed"),
            fetch: fetch
        )
        return (resolver, store)
    }

    @Test @MainActor func savedFileIsReady() throws {
        let (resolver, store) = makeResolver()
        let saved = try store.install(temporaryURL: Fixture.shuraim19.temporaryCopy(), globalAyah: Self.ayah)
        #expect(resolver.availability(of: Self.ayah) == .ready(saved))
    }

    @Test @MainActor func streamingFetchesIntoTheCacheOnce() async throws {
        var fetches = 0
        let (resolver, store) = makeResolver { _ in
            fetches += 1
            return try Fixture.shuraim19.temporaryCopy()
        }
        resolver.allowStreaming = true
        #expect(resolver.availability(of: Self.ayah) == .needsFetch)
        try await resolver.fetch(Self.ayah)
        guard case .ready(let url) = resolver.availability(of: Self.ayah) else {
            Issue.record("Streamed ayah should be ready")
            return
        }
        #expect(fetches == 1)
        #expect(!store.isReady(Self.ayah))
        #expect(url.path.contains(AyahAudioResolver.streamCacheFolder))
    }

    @Test @MainActor func offlineWithoutDownloadsIsUnavailable() {
        let (resolver, _) = makeResolver()
        resolver.allowStreaming = false
        #expect(resolver.availability(of: Self.ayah) == .unavailable(.offlineAudioMissing))
    }

    @Test @MainActor func waitsForTheBackgroundDownload() async throws {
        let (resolver, store) = makeResolver()
        resolver.allowStreaming = false
        resolver.downloadMissingAudio = { _ in true }
        resolver.requestDownloads(order: [Self.ayah], current: Self.ayah)
        #expect(resolver.availability(of: Self.ayah) == .needsFetch)

        let wait = Task { try await resolver.fetch(Self.ayah) }
        try await Task.sleep(for: .milliseconds(20))
        let saved = try store.install(temporaryURL: Fixture.shuraim19.temporaryCopy(), globalAyah: Self.ayah)
        resolver.audioBecameAvailable(Self.ayah)
        try await wait.value
        #expect(resolver.availability(of: Self.ayah) == .ready(saved))
    }

    @Test @MainActor func failedDownloadEndsTheWaitAndIsReported() async throws {
        let (resolver, _) = makeResolver()
        resolver.allowStreaming = false
        resolver.downloadMissingAudio = { _ in true }
        resolver.requestDownloads(order: [Self.ayah], current: Self.ayah)

        let wait = Task { try await resolver.fetch(Self.ayah) }
        try await Task.sleep(for: .milliseconds(20))
        resolver.audioDownloadFailed(Self.ayah)
        await #expect(throws: AppError.downloadFailed) { try await wait.value }
        #expect(resolver.availability(of: Self.ayah) == .unavailable(.downloadFailed))

        resolver.retryFailedDownloads()
        #expect(resolver.availability(of: Self.ayah) == .needsFetch)
    }

    @Test @MainActor func unreadableSavedFileIsDiscardedSoItCanStream() throws {
        let (resolver, store) = makeResolver()
        resolver.allowStreaming = true
        _ = try store.install(temporaryURL: Fixture.shuraim19.temporaryCopy(), globalAyah: Self.ayah)
        #expect(resolver.discardUnreadable(Self.ayah))
        #expect(!store.isReady(Self.ayah))
        #expect(resolver.availability(of: Self.ayah) == .needsFetch)
    }
}

struct AudioFileStoreTrimTests {
    @Test @MainActor func removeOldestKeepsTheNewest() throws {
        let store = AudioFileStore(baseDirectory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        for ayah in 1...4 {
            _ = try store.install(temporaryURL: Fixture.shuraim19.temporaryCopy(), globalAyah: ayah)
            try FileManager.default.setAttributes(
                [.creationDate: Date(timeIntervalSince1970: TimeInterval(ayah * 1_000))],
                ofItemAtPath: store.fileURL(globalAyah: ayah).path
            )
        }
        store.removeOldest(keeping: 2)
        #expect(store.readyAyahs() == [3, 4])
    }
}
