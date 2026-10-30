import SwiftUI

/// Removes every reciter's downloaded recitation after a confirmation. Used in Settings and Privacy.
struct RemoveDownloadsButton: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirming = false

    var body: some View {
        Button(String(localized: "Remove downloaded recitation"), role: .destructive) {
            confirming = true
        }
        // The app's red: the system's falls short of AA on the white rows.
        .foregroundStyle(Color.dangerWarm)
        .accessibilityIdentifier("data.removeDownloads")
        .confirmationDialog(
            String(localized: "Remove downloaded recitation for every reciter?"),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove downloads"), role: .destructive) {
                environment.downloads.removeAll()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your progress stays. You can download recitation again at any time."))
        }
    }
}

/// Deletes every personal recording after a confirmation. Used in Settings and Privacy.
struct DeleteRecordingsButton: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirming = false

    var body: some View {
        Button(String(localized: "Delete all recordings"), role: .destructive) {
            confirming = true
        }
        .foregroundStyle(Color.dangerWarm)
        .accessibilityIdentifier("data.deleteRecordings")
        .confirmationDialog(
            String(localized: "Delete all personal recordings?"),
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete recordings"), role: .destructive) {
                environment.recorder.deleteAll()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This can't be undone."))
        }
    }
}
