import SwiftUI

/// The persistent mini player opens here without preparing or interrupting its queue.
struct ListeningPlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var isActive: Bool {
        environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading
    }

    private var currentVerse: QuranVerse? {
        environment.playback.snapshot.currentGlobalAyah.flatMap { environment.quran.verse(globalAyah: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Label(String(localized: "NOW LISTENING"), systemImage: "headphones")
                        .font(.caption.weight(.semibold)).tracking(2)
                        .foregroundStyle(Color.bronze)
                    if let verse = currentVerse {
                        VStack(spacing: 12) {
                            Text(environment.quran.surah(number: verse.surahNumber)?.arabicName ?? "")
                                .font(.quran(size: 34))
                            Text(environment.playback.snapshot.setTitle)
                                .font(.system(.title, design: .serif).weight(.medium))
                            Text(environment.audioSource.reciter.englishName)
                                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                        }
                        WarmCard {
                            QuranAyahText(verse: verse, isCurrent: false, hidden: false)
                        }
                        Text(String(localized: "Ayah \(verse.ayahInSurah) · \(environment.quran.surah(number: verse.surahNumber)?.englishName ?? "")"))
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.secondaryWarm)
                        transport
                        NavigationLink {
                            QuranReaderView(destination: .surah(number: verse.surahNumber, scrollToAyah: verse.globalAyah))
                        } label: {
                            Label(String(localized: "Follow in the Quran"), systemImage: "book")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WarmButtonStyle(emphasis: .secondary))
                    }
                    if let message = environment.playback.userMessage {
                        FriendlyErrorView(message: message) {
                            environment.playback.userMessage = nil
                            environment.playback.resume()
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.appBrownText)
            .background(Color.parchment.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { environment.playback.skipBack() } label: {
                Image(systemName: "backward.end.fill").font(.title2).frame(width: 48, height: 48)
            }
            .accessibilityLabel(String(localized: "Previous ayah"))
            Button {
                if isActive { environment.playback.pause() }
                else { environment.playback.resume() }
            } label: {
                PlayGlyph(systemName: isActive ? "pause.fill" : "play.fill", size: 76)
            }
            .accessibilityLabel(isActive ? String(localized: "Pause") : String(localized: "Play"))
            .accessibilityIdentifier("player.toggle")
            Button { environment.playback.skipForward() } label: {
                Image(systemName: "forward.end.fill").font(.title2).frame(width: 48, height: 48)
            }
            .accessibilityLabel(String(localized: "Next ayah"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.bronze)
    }
}
