import SwiftUI

/// Compatibility entry point for previously saved passages. Uses the same reader.
struct PracticeView: View {
    @Environment(AppEnvironment.self) private var environment
    let practiceSet: PracticeSet

    var body: some View {
        let ayah = practiceSet.lastGlobalAyah ?? practiceSet.orderedPassages.first?.startGlobalAyah ?? 1
        let number = environment.quran.verse(globalAyah: ayah)?.surahNumber ?? 1
        QuranReaderView(destination: .surah(number: number, scrollToAyah: ayah), savedPractice: practiceSet,
                        resumesPlayback: environment.playback.activeSet?.id == practiceSet.id)
    }
}

enum PracticePlaybackLifecycle {
    static func shouldPrepareNewSession(activeSetID: UUID?, currentGlobalAyah: Int?, openingSetID: UUID) -> Bool {
        activeSetID != openingSetID || currentGlobalAyah == nil
    }
}
