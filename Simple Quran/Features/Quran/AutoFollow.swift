import Foundation

/// Whether the text keeps the playing ayah in view. Scrolling by hand during playback pauses it,
/// so the reader can look back or ahead without being pulled away; it comes back after a pause
/// in scrolling, with the "Current ayah" button, or when the user picks an ayah or presses play.
struct AutoFollow: Equatable {
    /// How long the text rests after the user's scroll before it follows playback again.
    static let resumeAfterIdle: Duration = .seconds(5)

    private(set) var isPaused = false

    /// Only a scroll during playback pauses; without audio there's nothing to follow.
    mutating func userScrolled(isPlaying: Bool) {
        if isPlaying { isPaused = true }
    }

    mutating func resume() {
        isPaused = false
    }

    /// The way back to the playing ayah shows only while it's playing out of view.
    func showsReturnButton(isPlaying: Bool) -> Bool {
        isPaused && isPlaying
    }
}
