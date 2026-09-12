import AVFoundation
import Foundation
import OSLog

enum AudioSessionMode {
    case playback
    case recording
    case idle
}

@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()
    private let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "audio")
    private var observers: [NSObjectProtocol] = []
    var onInterruption: ((Bool) -> Void)?
    var onRouteChange: (() -> Void)?

    func configure(_ mode: AudioSessionMode) throws {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .playback:
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothHFP, .allowAirPlay])
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
                let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let began = type == AVAudioSession.InterruptionType.began.rawValue
                Task { @MainActor in
                    self?.onInterruption?(began)
                }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onRouteChange?()
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
                    self?.onRouteChange?()
                }
            }
        )
    }
}
