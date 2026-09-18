import AVFoundation
import Foundation
import OSLog

enum AudioSessionMode {
    case playback
    case recording
    case idle
}

enum AudioSessionEvent {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(AVAudioSession.RouteChangeReason)
    case mediaServicesReset
}

enum AudioInterruptionAction: Equatable {
    case ignore
    case pausePreservingIntent
    case resume
}

enum AudioInterruptionPolicy {
    // AVAudioSession.InterruptionReason.appWasSuspended has raw value 1. The
    // case is deprecated because newer iOS versions no longer send it, but the
    // value is still delivered by older system behavior and must not be
    // treated as a user-visible playback interruption.
    private static let appWasSuspendedReason: UInt = 1

    static func actionForBegan(reasonRawValue: UInt?) -> AudioInterruptionAction {
        reasonRawValue == appWasSuspendedReason ? .ignore : .pausePreservingIntent
    }

    static func actionForEnded(shouldResume _: Bool, hasPlaybackIntent: Bool) -> AudioInterruptionAction {
        hasPlaybackIntent ? .resume : .ignore
    }
}

@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "audio")
    private var observers: [NSObjectProtocol] = []
    var onEvent: ((AudioSessionEvent) -> Void)?

    func configure(_ mode: AudioSessionMode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .playback:
            // The playback category already supports Bluetooth A2DP. Input-only
            // Bluetooth options are invalid here and cause OSStatus -50.
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
        case .recording:
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        case .idle:
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
        startObservingIfNeeded()
    }

    private func startObservingIfNeeded() {
        guard observers.isEmpty else { return }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let userInfo = notification.userInfo
                let rawType = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let rawReason = userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                Task { @MainActor in
                    guard let self,
                          let rawType,
                          let type = AVAudioSession.InterruptionType(rawValue: rawType)
                    else { return }
                    switch type {
                    case .began:
                        guard AudioInterruptionPolicy.actionForBegan(
                            reasonRawValue: rawReason
                        ) == .pausePreservingIntent else { return }
                        self.onEvent?(.interruptionBegan)
                    case .ended:
                        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.onEvent?(.interruptionEnded(shouldResume: shouldResume))
                    @unknown default:
                        break
                    }
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                Task { @MainActor in
                    let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) ?? .unknown
                    self?.onEvent?(.routeChanged(reason))
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.logger.error("Media services reset")
                    self?.onEvent?(.mediaServicesReset)
                }
            }
        )
    }

}
