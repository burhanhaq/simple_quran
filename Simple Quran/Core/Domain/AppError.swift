import Foundation

nonisolated enum AppError: Error, Equatable, Sendable {
    case invalidRange
    case missingQuranData
    case corruptQuranData(String)
    case persistenceFailure
    case audioUnavailable
    case downloadFailed
    case httpStatus(Int)
    case invalidAudio
    case notEnoughStorage
    case microphoneDenied
    case recordingFailed
    case offlineAudioMissing
    case cancelled
}

nonisolated struct UserFacingMessage: Equatable, Sendable {
    let title: String
    let message: String
    let recovery: String?

    static func from(_ error: AppError) -> UserFacingMessage {
        switch error {
        case .invalidRange:
            UserFacingMessage(
                title: String(localized: "That selection isn’t valid"),
                message: String(localized: "Choose a continuous range of ayahs, with the first ayah before the last."),
                recovery: String(localized: "Adjust the start and end ayahs, then try again.")
            )
        case .missingQuranData, .corruptQuranData:
            UserFacingMessage(
                title: String(localized: "The Quran text couldn’t be loaded"),
                message: String(localized: "The bundled text is missing or unreadable. Reinstall the app to restore it."),
                recovery: nil
            )
        case .persistenceFailure:
            UserFacingMessage(
                title: String(localized: "Your progress couldn’t be saved"),
                message: String(localized: "Please try again. Your previous sets and ratings are still on this device."),
                recovery: String(localized: "If this keeps happening, restart the app.")
            )
        case .audioUnavailable:
            UserFacingMessage(
                title: String(localized: "Recitation isn’t available right now"),
                message: String(localized: "Check your connection, or download this set to practise offline."),
                recovery: String(localized: "Connect to the internet or open Downloads to save audio.")
            )
        case .downloadFailed, .httpStatus(_):
            UserFacingMessage(
                title: String(localized: "Download didn’t finish"),
                message: String(localized: "The recitation couldn’t be saved. Nothing already on this device was removed."),
                recovery: String(localized: "Try again on a stable connection.")
            )
        case .invalidAudio:
            UserFacingMessage(
                title: String(localized: "Downloaded audio is invalid"),
                message: String(localized: "The server response was not playable recitation, so it was not saved."),
                recovery: String(localized: "Try the download again later.")
            )
        case .notEnoughStorage:
            UserFacingMessage(
                title: String(localized: "Not enough storage"),
                message: String(localized: "Free some space on this device before downloading more recitation."),
                recovery: String(localized: "Remove unused downloads in Settings.")
            )
        case .microphoneDenied:
            UserFacingMessage(
                title: String(localized: "Microphone access is off"),
                message: String(localized: "Recording stays on this device and is only used so you can compare your recitation with the reciter."),
                recovery: String(localized: "Turn on Microphone for Simple Quran in Settings.")
            )
        case .recordingFailed:
            UserFacingMessage(
                title: String(localized: "Recording didn’t complete"),
                message: String(localized: "Your previous takes are still saved. Try recording this ayah again."),
                recovery: nil
            )
        case .offlineAudioMissing:
            UserFacingMessage(
                title: String(localized: "This ayah isn’t downloaded"),
                message: String(localized: "Download the set to keep practising without a connection."),
                recovery: String(localized: "Download audio, or connect to the internet.")
            )
        case .cancelled:
            UserFacingMessage(
                title: String(localized: "Cancelled"),
                message: String(localized: "Nothing changed."),
                recovery: nil
            )
        }
    }
}
