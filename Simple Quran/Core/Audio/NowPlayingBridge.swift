import Foundation
import MediaPlayer

@MainActor
final class NowPlayingBridge {
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private(set) var isPublished = false

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
        isPlaying: Bool,
        elapsedTime: Double?,
        duration: Double?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: verse.reference,
            MPMediaItemPropertyAlbumTitle: setTitle,
            MPMediaItemPropertyArtist: reciter.englishName,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let elapsedTime, elapsedTime.isFinite, elapsedTime >= 0 {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        }
        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
        isPublished = true
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
