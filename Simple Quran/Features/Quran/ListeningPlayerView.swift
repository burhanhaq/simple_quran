import SwiftUI

/// All playback returns to the Quran reader.
struct ListeningPlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        let ayah = environment.playback.snapshot.currentGlobalAyah ?? 1
        let number = environment.quran.verse(globalAyah: ayah)?.surahNumber ?? 1
        QuranReaderView(destination: .surah(number: number, scrollToAyah: ayah), resumesPlayback: true)
    }
}
