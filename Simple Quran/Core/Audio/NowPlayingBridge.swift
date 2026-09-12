import Foundation
import MediaPlayer
import UIKit

@MainActor
final class NowPlayingBridge {
    func becomeActive() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
    }

    func update(setTitle: String, verse: QuranVerse, reciter: Reciter, isPlaying: Bool) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(verse.surahNumber):\(verse.ayahInSurah)",
            MPMediaItemPropertyAlbumTitle: setTitle,
            MPMediaItemPropertyArtist: reciter.englishName,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func handle(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)

        center.playCommand.addTarget { _ in
            play()
            return .success
        }
        center.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            toggle()
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            next()
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            previous()
            return .success
        }
    }
}
