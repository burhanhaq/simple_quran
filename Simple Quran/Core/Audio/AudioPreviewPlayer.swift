import AVFoundation
import Foundation

/// Event-driven one-shot playback used by recitation comparison. It deliberately
/// owns no practice queue state and completes only when AVPlayer reports success
/// or failure.
@MainActor
final class AudioPreviewPlayer {
    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var continuation: CheckedContinuation<Void, Error>?

    func play(url: URL) async throws {
        cancel()
        try AudioSessionController.shared.configure(.playback)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                Task { @MainActor in
                    guard let self, let item, item.status == .failed else { return }
                    self.complete(.failure(item.error ?? AppError.audioUnavailable))
                }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.complete(.success(())) }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                Task { @MainActor in self?.complete(.failure(error ?? AppError.audioUnavailable)) }
            }
            player.play()
        }
    }

    func cancel() {
        guard continuation != nil else {
            cleanup()
            return
        }
        complete(.failure(CancellationError()))
    }

    private func complete(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        cleanup()
        continuation.resume(with: result)
    }

    private func cleanup() {
        player?.pause()
        player = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        endObserver = nil
        failureObserver = nil
    }
}
