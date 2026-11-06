import Foundation

/// One stretch of audio for `GaplessAudioPlayer`: an ayah's file or a pause.
nonisolated struct AudioSegment: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// `smoothsJoins`: trim the file's dead start and crossfade it with neighbouring files that also smooth.
        case file(URL, smoothsJoins: Bool = false)
        case silence(seconds: Int)
    }

    /// Assigned by whoever enqueues it, so player events can be matched back to what was asked for.
    let id: Int
    let source: Source
}
