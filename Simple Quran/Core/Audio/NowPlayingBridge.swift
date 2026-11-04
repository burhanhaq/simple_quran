import Foundation
import MediaPlayer
import UIKit

/// What the lock screen and CarPlay show playback doing.
nonisolated enum NowPlayingState: Equatable, Sendable {
    case playing
    case paused
    /// Waiting for audio to download or buffer before it can play.
    case loading
}

@MainActor
final class NowPlayingBridge {
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private(set) var isPublished = false
    /// Shown on the lock screen and in CarPlay.
    private let artwork = NowPlayingBridge.makeArtwork()

    init() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    func handle(
        hasItem: @escaping @MainActor () -> Bool,
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        toggle: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void,
        previous: @escaping @MainActor () -> Void
    ) {
        removeCommandTargets()
        bind(commandCenter.playCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            play()
            return .success
        }
        bind(commandCenter.pauseCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            pause()
            return .success
        }
        bind(commandCenter.togglePlayPauseCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            toggle()
            return .success
        }
        bind(commandCenter.nextTrackCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            next()
            return .success
        }
        bind(commandCenter.previousTrackCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            previous()
            return .success
        }
    }

    func clear() {
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
        isPublished = false
    }

    func publish(
        setTitle: String,
        verse: QuranVerse,
        reciter: Reciter,
        state: NowPlayingState,
        elapsedTime: Double?,
        duration: Double?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: verse.reference,
            MPMediaItemPropertyAlbumTitle: setTitle,
            // In place of the reciter while waiting, so a slow start doesn't look like nothing happened.
            MPMediaItemPropertyArtist: state == .loading ? String(localized: "Loading…") : reciter.englishName,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let elapsedTime, elapsedTime.isFinite, elapsedTime >= 0 {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        }
        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        infoCenter.nowPlayingInfo = info
        // Loading shows Pause, like the phone's mini player, so the driver can cancel a slow start.
        infoCenter.playbackState = state == .paused ? .paused : .playing
        isPublished = true
    }

    /// The artwork's image is requested off the main thread, so it's built outside the main actor.
    nonisolated private static func makeArtwork() -> MPMediaItemArtwork? {
        guard let image = UIImage(named: "NowPlayingArtwork") else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private func bind(
        _ command: MPRemoteCommand,
        perform: @escaping @MainActor () -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget { _ in
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    perform()
                }
            }
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    perform()
                }
            }
        }
        commandTargets.append((command, target))
    }

    private func removeCommandTargets() {
        for registration in commandTargets {
            registration.command.removeTarget(registration.target)
        }
        commandTargets.removeAll()
    }
}
