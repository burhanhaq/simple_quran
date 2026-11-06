import AVFoundation

/// Decodes one segment into chunks in a single fixed format, so every reciter's files
/// (22.05 or 44.1 kHz, mono or stereo) can play back to back on one player node.
///
/// `AVAudioFile` honours the MP3s' gapless header, so the chunks hold exactly the
/// recorded samples: no encoder priming at the start and no padding at the end.
@MainActor
final class PCMSegmentReader {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    /// Half a second, so a long ayah is never held in memory whole.
    nonisolated static let chunkFrames: AVAudioFrameCount = 22_050
    /// Most of a file's start that can be trimmed as dead air, when its joins are smoothed.
    ///
    /// Some CDN files were re-encoded from older MP3s without removing that encoder's delay,
    /// so they open with 13 or 40 ms of digital silence and residue (Shuraim's on every ayah).
    /// Between two ayahs that's a dropout. The cap keeps a reciter's real pauses, which last
    /// half a second or more, all but intact.
    static let deadAirLimit: TimeInterval = 0.05
    /// Quieter than this, per millisecond, counts as dead air. The re-encoding residue sits between
    /// -75 and -61 dB; a reciter's first sound is well above it.
    static let deadAirFloorDecibels: Float = -60
    /// Resampled lengths are estimates, off by a frame or two.
    private static let lengthSlack: AVAudioFrameCount = 64

    private enum Decoder {
        case file(AVAudioFile, AVAudioConverter, startFrame: AVAudioFramePosition)
        case silence
    }

    private let decoder: Decoder
    /// Length in the fixed format, after trimming. Exact for silence; for a file, the rounded resampled length.
    let totalFrames: AVAudioFramePosition
    /// Frames handed out so far, in the fixed format.
    private(set) var position: AVAudioFramePosition = 0
    private(set) var isExhausted: Bool
    private var inputEnded = false

    init(source: AudioSegment.Source) throws {
        switch source {
        case .silence(let seconds):
            decoder = .silence
            totalFrames = AVAudioFramePosition(max(0, seconds)) * AVAudioFramePosition(Self.format.sampleRate)
        case .file(let url, let smoothsJoins):
            guard let file = try? AVAudioFile(forReading: url),
                  let converter = AVAudioConverter(from: file.processingFormat, to: Self.format),
                  let startFrame = smoothsJoins ? try? Self.deadAirFrames(at: file) : 0
            else { throw AppError.invalidAudio }
            if file.processingFormat.channelCount == 1 {
                // Mono recordings play from both speakers.
                converter.channelMap = [0, 0]
            }
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            file.framePosition = startFrame
            decoder = .file(file, converter, startFrame: startFrame)
            totalFrames = Self.outputFrame(file.length - startFrame, inputRate: file.processingFormat.sampleRate)
        }
        isExhausted = totalFrames == 0
        if case .file(_, let smoothsJoins) = source { self.smoothsJoins = smoothsJoins } else { smoothsJoins = false }
    }

    /// A file whose joins with neighbouring files are crossfaded.
    let smoothsJoins: Bool

    /// Frames still to come. An estimate for a resampled file.
    var remainingFrames: AVAudioFramePosition { max(0, totalFrames - position) }

    /// The next chunk of at most `maxFrames`, or nil once the segment has been read to its end.
    func nextChunk(maxFrames: AVAudioFrameCount = PCMSegmentReader.chunkFrames) throws -> AVAudioPCMBuffer? {
        guard !isExhausted else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: max(1, maxFrames)) else {
            throw AppError.audioUnavailable
        }
        switch decoder {
        case .silence:
            fillSilence(buffer)
        case .file(let file, let converter, _):
            try convert(from: file, with: converter, into: buffer)
        }
        position += AVAudioFramePosition(buffer.frameLength)
        if position >= totalFrames, case .silence = decoder { isExhausted = true }
        guard buffer.frameLength > 0 else {
            isExhausted = true
            return nil
        }
        return buffer
    }

    /// Everything left, as one buffer. For a short tail.
    func readToEnd() throws -> AVAudioPCMBuffer? {
        var parts: [AVAudioPCMBuffer] = []
        while let part = try nextChunk(maxFrames: AVAudioFrameCount(remainingFrames) + Self.lengthSlack) {
            parts.append(part)
        }
        return Self.joined(parts)
    }

    /// Continues from `frame` (in the fixed format, after trimming), as after the engine had to restart mid-ayah.
    func seek(toFrame frame: AVAudioFramePosition) {
        position = min(max(0, frame), totalFrames)
        isExhausted = position >= totalFrames
        inputEnded = false
        guard case .file(let file, let converter, let startFrame) = decoder else { return }
        file.framePosition = startFrame + Self.inputFrame(position, inputRate: file.processingFormat.sampleRate)
        converter.reset()
    }

    /// How many of the file's opening frames are dead air, in whole milliseconds, up to `deadAirLimit`.
    private static func deadAirFrames(at file: AVAudioFile) throws -> AVAudioFramePosition {
        let rate = file.processingFormat.sampleRate
        let window = max(1, Int(rate / 1_000))
        let limit = AVAudioFrameCount(min(AVAudioFramePosition(rate * deadAirLimit), file.length))
        guard limit > 0,
              let head = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: limit),
              let channels = head.floatChannelData
        else { return 0 }
        file.framePosition = 0
        try file.read(into: head, frameCount: limit)
        let floor = pow(10, deadAirFloorDecibels / 20)
        let channelCount = Int(file.processingFormat.channelCount)
        var frame = 0
        while frame + window <= Int(head.frameLength) {
            var sumOfSquares: Float = 0
            for channel in 0..<channelCount {
                for index in frame..<(frame + window) {
                    sumOfSquares += channels[channel][index] * channels[channel][index]
                }
            }
            guard (sumOfSquares / Float(window * channelCount)).squareRoot() < floor else { break }
            frame += window
        }
        return AVAudioFramePosition(frame)
    }

    private static func joined(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard parts.count > 1 else { return parts.first }
        let total = parts.reduce(0) { $0 + $1.frameLength }
        guard let whole = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let destination = whole.floatChannelData
        else { return parts.first }
        for part in parts {
            guard let source = part.floatChannelData else { continue }
            for channel in 0..<Int(format.channelCount) {
                (destination[channel] + Int(whole.frameLength))
                    .update(from: source[channel], count: Int(part.frameLength))
            }
            whole.frameLength += part.frameLength
        }
        return whole
    }

    private func fillSilence(_ buffer: AVAudioPCMBuffer) {
        let frames = min(AVAudioFramePosition(buffer.frameCapacity), totalFrames - position)
        buffer.frameLength = AVAudioFrameCount(max(0, frames))
        guard let channels = buffer.floatChannelData else { return }
        for channel in 0..<Int(Self.format.channelCount) {
            channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
        }
    }

    private func convert(from file: AVAudioFile, with converter: AVAudioConverter, into buffer: AVAudioPCMBuffer) throws {
        var readFailed = false
        var conversionError: NSError?
        let status = converter.convert(to: buffer, error: &conversionError) { [self] requested, inputStatus in
            let remaining = file.length - file.framePosition
            guard !inputEnded, remaining > 0,
                  let input = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat,
                      frameCapacity: AVAudioFrameCount(min(AVAudioFramePosition(requested), remaining))
                  )
            else {
                inputEnded = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: input)
            } catch {
                readFailed = true
            }
            guard input.frameLength > 0 else {
                inputEnded = true
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        if readFailed || status == .error { throw AppError.invalidAudio }
        if status == .endOfStream { isExhausted = true }
    }

    private static func outputFrame(_ inputFrame: AVAudioFramePosition, inputRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((Double(inputFrame) * format.sampleRate / inputRate).rounded())
    }

    private static func inputFrame(_ outputFrame: AVAudioFramePosition, inputRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition((Double(outputFrame) * inputRate / format.sampleRate).rounded())
    }
}
