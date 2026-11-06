import AVFoundation

/// Plays segments back to back on one player node, so consecutive ayahs join with no gap.
/// It knows nothing about ayahs: the coordinator decides what plays next.
///
/// Segments are decoded in chunks just ahead of the playhead. Where one smoothing file follows
/// another, the first file's last `crossfade` is blended into the start of the next, so the room's
/// echo carries across the join instead of cutting off. Other files play exactly back to back.
/// A segment starts when the one before it has played its last chunk.
@MainActor
final class GaplessAudioPlayer {
    /// How much audio stays scheduled past the playhead.
    nonisolated static let lookahead: TimeInterval = 4
    /// How long consecutive files overlap. Long enough to bridge the faded cut at the end of
    /// each CDN file, short enough not to blur words.
    nonisolated static let crossfade: TimeInterval = 0.03
    /// A file's tail waits for the next file to blend into, until only this much audio is left
    /// ahead of it; then it plays on its own, as at the end of a passage.
    nonisolated static let tailHoldLimit: TimeInterval = 1.5

    var onSegmentStarted: ((Int) -> Void)?
    var onSegmentFinished: ((Int) -> Void)?
    /// A segment couldn't be decoded. Everything queued has been dropped.
    var onFailure: ((Int, Error) -> Void)?

    private struct Entry {
        let id: Int
        let reader: PCMSegmentReader
        var pendingChunks = 0
        var playedFrames: AVAudioFramePosition = 0
        /// The previous file's tail, blended into this segment's first chunk.
        var fadeIn: AVAudioPCMBuffer?

        var isDone: Bool { reader.isExhausted && pendingChunks == 0 }
    }

    /// What to do next with the earliest segment that still has audio to read.
    private enum NextRead {
        /// Read up to this many frames and schedule them.
        case chunk(AVAudioFrameCount)
        /// Hand the file's tail to the file after it, to blend into its start.
        case handOffTail
        /// Keep the tail back until the next segment is queued.
        case holdTail
    }

    private let engine: AVAudioEngine
    private let node = AVAudioPlayerNode()
    private let lookaheadFrames: AVAudioFramePosition
    private let crossfadeFrames: AVAudioFramePosition
    private let tailHoldLimitFrames: AVAudioFramePosition
    /// When a chunk counts as played: once heard on a device, or once rendered by an offline engine,
    /// which has no output for "played back" to wait for.
    private let chunkPlayedWhen: AVAudioPlayerNodeCompletionCallbackType
    /// Queued segments, the one playing first.
    private var entries: [Entry] = []
    private var unplayedFrames: AVAudioFramePosition = 0
    /// Bumped whenever scheduled chunks are thrown away, so their late completions are ignored.
    private var generation = 0
    private var engineHasRun = false
    private var configurationObserver: NSObjectProtocol?
    private(set) var isPlaying = false

    init(engine: AVAudioEngine = AVAudioEngine(), lookahead: TimeInterval = GaplessAudioPlayer.lookahead) {
        self.engine = engine
        let sampleRate = PCMSegmentReader.format.sampleRate
        lookaheadFrames = AVAudioFramePosition(lookahead * sampleRate)
        crossfadeFrames = AVAudioFramePosition(Self.crossfade * sampleRate)
        tailHoldLimitFrames = AVAudioFramePosition(Self.tailHoldLimit * sampleRate)
        chunkPlayedWhen = engine.isInManualRenderingMode ? .dataRendered : .dataPlayedBack
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: PCMSegmentReader.format)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.engineConfigurationChanged() }
        }
    }

    isolated deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
    }

    var hasQueuedAudio: Bool { !entries.isEmpty }
    var currentSegmentID: Int? { entries.first?.id }
    var elapsedInCurrentSegment: TimeInterval { Self.seconds(entries.first?.playedFrames ?? 0) }
    var durationOfCurrentSegment: TimeInterval? { entries.first.map { Self.seconds($0.reader.totalFrames) } }

    /// Adds a segment after everything queued. If nothing was queued, it starts right away.
    func enqueue(_ segment: AudioSegment) throws {
        let reader = try PCMSegmentReader(source: segment.source)
        entries.append(Entry(id: segment.id, reader: reader))
        if entries.count == 1 { onSegmentStarted?(segment.id) }
        scheduleAhead()
        finishCompletedSegments()
    }

    func play() throws {
        if !engine.isRunning {
            // The system stops the engine for interruptions and route changes, dropping what it had scheduled.
            if engineHasRun { reschedule() }
            try engine.start()
            engineHasRun = true
        }
        node.play()
        isPlaying = true
    }

    func pause() {
        node.pause()
        isPlaying = false
    }

    /// Drops everything queued.
    func reset() {
        discardScheduledChunks()
        entries.removeAll()
        isPlaying = false
    }

    private func discardScheduledChunks() {
        generation += 1
        // Stopping calls every pending completion handler; the new generation makes them no-ops.
        node.stop()
        unplayedFrames = 0
    }

    /// Schedules the queue again from where each segment had played to.
    private func reschedule() {
        discardScheduledChunks()
        for index in entries.indices {
            entries[index].reader.seek(toFrame: entries[index].playedFrames)
            entries[index].pendingChunks = 0
            entries[index].fadeIn = nil
        }
        scheduleAhead()
    }

    private func scheduleAhead() {
        while unplayedFrames < lookaheadFrames,
              let index = entries.firstIndex(where: { !$0.reader.isExhausted }) {
            do {
                switch nextRead(for: index) {
                case .holdTail:
                    return
                case .handOffTail:
                    entries[index + 1].fadeIn = try entries[index].reader.readToEnd()
                case .chunk(let frames):
                    guard let chunk = try entries[index].reader.nextChunk(maxFrames: frames) else { continue }
                    if let tail = entries[index].fadeIn {
                        Self.blend(tail, into: chunk)
                        entries[index].fadeIn = nil
                    }
                    schedule(chunk, for: index)
                }
            } catch {
                let id = entries[index].id
                reset()
                onFailure?(id, error)
                return
            }
        }
    }

    /// A smoothing file is read up to its last `crossfade`; that tail goes to the next smoothing file if there is one.
    private func nextRead(for index: Int) -> NextRead {
        let reader = entries[index].reader
        guard reader.smoothsJoins else { return .chunk(PCMSegmentReader.chunkFrames) }
        let body = reader.remainingFrames - crossfadeFrames
        if body > 0 {
            return .chunk(AVAudioFrameCount(min(AVAudioFramePosition(PCMSegmentReader.chunkFrames), body)))
        }
        guard entries.indices.contains(index + 1) else {
            return unplayedFrames > tailHoldLimitFrames ? .holdTail : .chunk(PCMSegmentReader.chunkFrames)
        }
        // A pause after an ayah starts cleanly; its echo is part of the pause.
        return entries[index + 1].reader.smoothsJoins ? .handOffTail : .chunk(PCMSegmentReader.chunkFrames)
    }

    private func schedule(_ chunk: AVAudioPCMBuffer, for index: Int) {
        let frames = AVAudioFramePosition(chunk.frameLength)
        entries[index].pendingChunks += 1
        unplayedFrames += frames
        node.scheduleBuffer(
            chunk,
            completionCallbackType: chunkPlayedWhen,
            completionHandler: Self.completion(for: self, generation: generation, frames: frames)
        )
    }

    /// Equal-power crossfade: `tail` fades out over the start of `head`, which fades in.
    private static func blend(_ tail: AVAudioPCMBuffer, into head: AVAudioPCMBuffer) {
        guard let fading = tail.floatChannelData, let rising = head.floatChannelData, tail.frameLength > 0 else { return }
        let length = Float(tail.frameLength)
        for frame in 0..<Int(min(tail.frameLength, head.frameLength)) {
            let progress = (Float(frame) + 0.5) / length * .pi / 2
            let fadeOut = cos(progress)
            let fadeIn = sin(progress)
            for channel in 0..<Int(PCMSegmentReader.format.channelCount) {
                rising[channel][frame] = fading[channel][frame] * fadeOut + rising[channel][frame] * fadeIn
            }
        }
    }

    /// Built outside the main actor: the node calls it on its own render thread.
    private nonisolated static func completion(
        for player: GaplessAudioPlayer,
        generation: Int,
        frames: AVAudioFramePosition
    ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak player] _ in
            Task { @MainActor in player?.chunkPlayed(generation: generation, frames: frames) }
        }
    }

    private func chunkPlayed(generation: Int, frames: AVAudioFramePosition) {
        // Chunks finish in the order they were scheduled, so this one is the oldest still pending.
        guard generation == self.generation,
              let index = entries.firstIndex(where: { $0.pendingChunks > 0 })
        else { return }
        entries[index].pendingChunks -= 1
        entries[index].playedFrames += frames
        unplayedFrames -= frames
        scheduleAhead()
        finishCompletedSegments()
    }

    private func finishCompletedSegments() {
        let generation = self.generation
        while let head = entries.first, head.isDone {
            entries.removeFirst()
            onSegmentFinished?(head.id)
            // The listener may have reset or replaced the queue in response.
            guard generation == self.generation, let next = entries.first else { return }
            onSegmentStarted?(next.id)
        }
    }

    private func engineConfigurationChanged() {
        guard isPlaying else { return }
        do {
            try play()
        } catch {
            let id = currentSegmentID ?? 0
            reset()
            onFailure?(id, error)
        }
    }

    private static func seconds(_ frames: AVAudioFramePosition) -> TimeInterval {
        TimeInterval(frames) / PCMSegmentReader.format.sampleRate
    }
}
