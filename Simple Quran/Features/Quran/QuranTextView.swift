import SwiftUI

/// Quran text in the user's chosen layout for the surah screen, reading or memorizing a piece.
struct QuranTextView<AyahMenu: View>: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let verses: [QuranVerse]
    let currentAyah: Int?
    var hiddenAyahs: Set<Int> = []
    var selectionEnabled = true
    var focusedAyah: Int? = nil
    var scrollToAyah: Int? = nil
    /// The piece being memorized; everything else fades back.
    var focusRange: VerseRange? = nil
    /// Ayahs marked as slipped while testing.
    var markedAyahs: Set<Int> = []
    /// Shown under the surah banner in ayah-by-ayah layout.
    var caption: String? = nil
    /// Playback is running, so a scroll by hand pauses following it.
    var isPlaying = false
    /// Changes when the user asks to see the current ayah, by picking one, stepping, or pressing play.
    var followRequest = 0
    let onSelect: (Int) -> Void
    @ViewBuilder var ayahMenu: (QuranVerse) -> AyahMenu

    /// The ayah centered in ayah-by-ayah layout. Seeded before the first layout so a deep
    /// ayah opens in place instead of jumping there after the list appears.
    @State private var listPosition: Int?
    @State private var seededListPosition = false
    @State private var follow = AutoFollow()
    @State private var resumeTask: Task<Void, Never>?

    /// Translation always shows ayah by ayah; continuous text stays Arabic only.
    private var translation: BundledTranslation? {
        environment.settings.showsTranslation ? environment.translations.current : nil
    }

    /// Playback moves within this many ayahs scroll with animation; longer jumps go straight
    /// there, since animating through hundreds of lazy rows stutters.
    private static var animatedFollowDistance: Int { 3 }
    /// Coming back after the user scrolled away animates from a little further.
    private static var animatedResumeDistance: Int { 12 }
    private static var followAnimation: Animation { .easeInOut(duration: 0.35) }

    var body: some View {
        Group {
            if environment.settings.displayedReadingLayout == .mushaf {
                MushafFlowView(
                    verses: verses,
                    currentGlobalAyah: currentAyah,
                    hiddenAyahs: hiddenAyahs,
                    basmala: environment.quran.basmala,
                    selectionEnabled: selectionEnabled,
                    focusedAyah: focusedAyah,
                    focusRange: focusRange,
                    markedAyahs: markedAyahs,
                    isFollowing: !follow.isPaused,
                    onSelect: onSelect
                )
            } else { ayahList }
        }
        // Switching layouts, such as turning translation on, keeps the place instead of reopening the surah.
        .onChange(of: environment.settings.displayedReadingLayout) { _, _ in seededListPosition = true }
        .onScrollPhaseChange { _, phase in scrollPhaseChanged(to: phase) }
        .onChange(of: followRequest) { _, _ in resumeFollowing() }
        .overlay(alignment: .top) { returnButton }
        .animation(.snappy, value: follow.showsReturnButton(isPlaying: isPlaying))
        .onDisappear { resumeTask?.cancel() }
    }

    @ViewBuilder
    private var returnButton: some View {
        if follow.showsReturnButton(isPlaying: isPlaying) {
            Button(action: resumeFollowing) {
                Label(String(localized: "Current ayah"), systemImage: "location.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Color.appWarmSurface, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.bronze)
            .frame(minHeight: 44)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityHint(String(localized: "Scrolls back to the ayah being played"))
            .accessibilityIdentifier("quran.currentAyah")
        }
    }

    /// A drag pauses following; once scrolling settles, following comes back after a rest.
    private func scrollPhaseChanged(to phase: ScrollPhase) {
        switch phase {
        case .interacting:
            resumeTask?.cancel()
            follow.userScrolled(isPlaying: isPlaying)
        case .idle where follow.isPaused:
            resumeTask?.cancel()
            resumeTask = Task {
                guard (try? await Task.sleep(for: AutoFollow.resumeAfterIdle)) != nil else { return }
                resumeFollowing()
            }
        default:
            break
        }
    }

    private func resumeFollowing() {
        resumeTask?.cancel()
        resumeTask = nil
        guard follow.isPaused else { return }
        follow.resume()
        // Continuous text scrolls back itself when following resumes.
        guard environment.settings.displayedReadingLayout != .mushaf, let ayah = currentAyah else { return }
        let distance = listPosition.map { abs($0 - ayah) } ?? .max
        if reduceMotion || distance > Self.animatedResumeDistance {
            listPosition = ayah
        } else {
            withAnimation(Self.followAnimation) { listPosition = ayah }
        }
    }

    private var ayahList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let first = verses.first, let surah = environment.quran.surah(number: first.surahNumber) {
                    VStack(spacing: 8) {
                        ReadingBanner(title: surah.arabicName, isArabic: true)
                        Text(caption ?? "\(surah.translation) · \(surah.ayahCount) ayahs")
                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                    }.padding(.vertical, 20)
                }
                ForEach(verses) { verse in
                    Button { onSelect(verse.globalAyah) } label: {
                        VStack(spacing: 0) {
                            if verse.showsBasmalaBefore { BasmalaHeader() }
                            QuranAyahText(verse: verse, isCurrent: verse.globalAyah == currentAyah,
                                          hidden: hiddenAyahs.contains(verse.globalAyah),
                                          marked: markedAyahs.contains(verse.globalAyah),
                                          translation: translation?.text(globalAyah: verse.globalAyah))
                        }
                        .opacity(focusRange.map { $0.contains(verse.globalAyah) ? 1 : MushafTextBuilder.dimmedAlpha } ?? 1)
                    }
                    .buttonStyle(.plain).disabled(!selectionEnabled)
                    .id(verse.globalAyah)
                    .accessibilityIdentifier("ayah.\(verse.globalAyah)")
                    .accessibilityHint("Select this ayah")
                    .contextMenu { ayahMenu(verse) }
                }
                Color.clear.frame(height: 12)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 22)
            .frame(maxWidth: 740).frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: focusRange)
        .scrollPosition(id: $listPosition, anchor: .center)
        .onAppear(perform: seedListPosition)
        .task(id: environment.settings.showsTranslation) {
            if environment.settings.showsTranslation { await environment.translations.loadIfNeeded() }
        }
        .onChange(of: currentAyah) { previous, ayah in
            guard let ayah, !follow.isPaused else { return }
            let distance = previous.map { abs($0 - ayah) } ?? .max
            if reduceMotion || distance > Self.animatedFollowDistance {
                listPosition = ayah
            } else {
                withAnimation(Self.followAnimation) { listPosition = ayah }
            }
        }
    }

    /// Opens at the requested ayah. After a switch from continuous text it keeps the ayah being
    /// played or memorized in view, the way continuous text does.
    private func seedListPosition() {
        let target = seededListPosition ? currentAyah ?? focusedAyah : scrollToAyah
        seededListPosition = true
        // The first ayah is already at the top; centering it would hide the surah banner.
        guard let target, target != verses.first?.globalAyah else { return }
        listPosition = target
    }
}
