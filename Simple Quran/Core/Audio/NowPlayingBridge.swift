import AVFoundation
import Foundation
import MediaPlayer

@MainActor
final class NowPlayingBridge {
    private let session: MPNowPlayingSession
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []

    init(player: AVPlayer) {
        session = MPNowPlayingSession(players: [player])
        session.automaticallyPublishesNowPlayingInfo = true
        let center = session.remoteCommandCenter
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
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
        let center = session.remoteCommandCenter
        bind(center.playCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            play()
            return .success
        }
        bind(center.pauseCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            pause()
            return .success
        }
        bind(center.togglePlayPauseCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            toggle()
            return .success
        }
        bind(center.nextTrackCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            next()
            return .success
        }
        bind(center.previousTrackCommand) {
            guard hasItem() else { return .noActionableNowPlayingItem }
            previous()
            return .success
        }
    }

    func becomeActive() {
        session.becomeActiveIfPossible { _ in }
    }

    func clear() {
        session.nowPlayingInfoCenter.nowPlayingInfo = nil
    }

    func stamp(_ item: AVPlayerItem, setTitle: String, verse: QuranVerse, reciter: Reciter) {
        item.nowPlayingInfo = [
            MPMediaItemPropertyTitle: verse.reference,
            MPMediaItemPropertyAlbumTitle: setTitle,
            MPMediaItemPropertyArtist: reciter.englishName
        ]
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
