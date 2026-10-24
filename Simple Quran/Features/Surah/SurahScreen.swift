import SwiftData
import SwiftUI

/// The one place a surah opens, from any tab: the text, with a sheet on top that holds the
/// player, the surah's progress, and memorizing a piece in place.
struct SurahScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Query private var progress: [VerseProgress]
    @State private var model: SurahScreenModel
    @State private var showsSheet = true
    @State private var showsTranslationNote = false
    /// Checking files is a filesystem call per ayah, so it runs when downloads finish, not on every render.
    @State private var audioDownloaded = false

    init(route: AppRoute, environment: AppEnvironment) {
        _model = State(initialValue: SurahScreenModel(route: route, environment: environment))
    }

    private var index: ProgressIndex { ProgressIndex(progress.map(\.snapshot)) }
    private var prefersFullCoach: Bool { dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact }

    private var downloading: Bool {
        model.passage.ayahIDs.contains { environment.downloads.jobs[$0]?.status == .downloading }
    }
    private var readyJobCount: Int {
        model.passage.ayahIDs.reduce(0) { $0 + (environment.downloads.jobs[$1]?.status == .ready ? 1 : 0) }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            GeometryReader { geometry in
                text
                    .safeAreaPadding(.bottom, textInset)
                    .overlay(alignment: .bottom) { fade.offset(y: -halfSheetTop(in: geometry)) }
                    .animation(.snappy, value: textInset)
            }
            .overlay(alignment: .top) {
                if showsTranslationNote {
                    TranslationLayoutNote { showsTranslationNote = false }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showsTranslationNote)
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showsSheet) {
                SurahSheet(model: model)
                    .presentationDetents(model.detents, selection: $model.detent)
                    .presentationBackgroundInteraction(.enabled(upThrough: model.interactionLimit))
                    .presentationBackground(Color.appWarmSurface)
                    .presentationContentInteraction(.scrolls)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
                    .tint(Color.bronze)
            }
            .onAppear {
                model.prefersFullCoach = prefersFullCoach
                model.start()
            }
            .onChange(of: prefersFullCoach) { _, full in model.prefersFullCoach = full }
            .onChange(of: environment.settings.showsTranslation) { _, shows in
                if environment.settings.needsTranslationLayoutNote {
                    environment.settings.hasSeenTranslationLayoutNote = true
                    showsTranslationNote = true
                } else if !shows {
                    showsTranslationNote = false
                }
            }
            .onDisappear {
                model.savePosition()
                environment.recorder.stopRecording()
                environment.recorder.cancelComparisonPlayback()
            }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, ayah in model.playbackMoved(to: ayah) }
            .task(id: AudioCheck(ayahIDs: model.passage.ayahIDs, readyJobs: readyJobCount)) { refreshAudioDownloaded() }
        }
        .tint(Color.bronze)
        .interactiveDismissDisabled(model.recordingBusy)
    }

    private var text: some View {
        QuranTextView(
            verses: model.verses,
            currentAyah: model.currentAyah,
            hiddenAyahs: model.hiddenAyahs,
            // Testing, a peek while recording is exactly when it's needed.
            selectionEnabled: !model.recordingBusy || model.focus?.mode == .test,
            focusedAyah: model.selectedAyah,
            scrollToAyah: model.destination.scrollToAyah,
            focusRange: model.focus?.range,
            markedAyahs: model.focus?.slipped ?? [],
            onSelect: model.select
        ) { verse in ayahMenu(verse) }
    }

    /// The text fades into the sheet so the opening ayahs read as part of it.
    @ViewBuilder
    private var fade: some View {
        if model.detent == SurahSheetDetent.half {
            LinearGradient(colors: [Color.parchment.opacity(0), Color.parchment], startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Keeps the ayah being read or memorized clear of the shorter sheet heights. At half height
    /// the text stays full length behind the sheet, so the surah's opening shows above it.
    private var textInset: CGFloat {
        switch model.detent {
        case SurahSheetDetent.coach: SurahSheetDetent.coachHeight
        case SurahSheetDetent.check: SurahSheetDetent.checkHeight
        default: SurahSheetDetent.peekHeight
        }
    }

    private func halfSheetTop(in geometry: GeometryProxy) -> CGFloat {
        let windowHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        return max(windowHeight / 2 - geometry.safeAreaInsets.bottom, 0)
    }

    @ViewBuilder
    private func ayahMenu(_ verse: QuranVerse) -> some View {
        let ayah = verse.globalAyah
        // While memorizing, tapping the ayah is how it's marked, so there's nothing to add here.
        if model.focus == nil {
            Button("Memorize from here", systemImage: "leaf") {
                if let piece = LearningPassage.piece(from: ayah, size: environment.settings.pieceSize, catalog: environment.quran) {
                    model.memorize(piece)
                }
            }
            Button("I know this ayah", systemImage: MemorizationStatus.memorized.systemImage) {
                model.markKnown(.clamped(start: ayah, end: ayah), index: index)
            }
            if let surah = environment.quran.surah(number: verse.surahNumber), environment.settings.activePlan?.range != surah.range {
                Button("Make \(surah.englishName) my plan", systemImage: "bookmark") {
                    environment.settings.setActivePlan(LearningTarget(range: surah.range))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var settings = environment.settings
        ToolbarItem(placement: .topBarLeading) {
            Button {
                model.close(index: index)
                dismiss()
            } label: { Image(systemName: "chevron.down").frame(width: 32, height: 32) }
                .accessibilityLabel("Close").accessibilityIdentifier("surah.close").disabled(model.recordingBusy)
        }
        // Shown in both layouts: turning it on in continuous text shows ayah by ayah.
        ToolbarItem(placement: .topBarTrailing) {
            Toggle(isOn: $settings.showsTranslation) {
                Label(String(localized: "Translation"), systemImage: "translate")
            }
            .toggleStyle(.button)
            .accessibilityIdentifier("surah.translation")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if model.focus != nil {
                    Button("Repeat and pause", systemImage: "repeat") { model.showsOptions = true }
                    Button("Change passage", systemImage: "slider.horizontal.3") { model.showsPassagePicker = true }
                }
                ReadingLayoutMenu()
                Button(audioDownloaded ? "Audio downloaded" : downloading ? "Downloading audio…" : "Download this audio",
                       systemImage: audioDownloaded ? "checkmark.circle" : "arrow.down.circle") {
                    environment.downloads.download(ayahs: model.passage.ayahIDs)
                }.disabled(audioDownloaded || downloading)
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Options").accessibilityIdentifier("surah.options").disabled(model.recordingBusy)
        }
    }

    private func refreshAudioDownloaded() {
        let ids = model.passage.ayahIDs
        audioDownloaded = !ids.isEmpty && environment.downloads.downloadedCount(in: ids) == ids.count
    }
}

/// Shown once, when translation first switches continuous text to ayah by ayah.
private struct TranslationLayoutNote: View {
    var onDismiss: () -> Void

    private static var visibleDuration: Duration { .seconds(6) }
    private var message: String {
        String(localized: "Translations show ayah by ayah. Turn translation off to go back to continuous text.")
    }

    var body: some View {
        Button(action: onDismiss) {
            Label {
                Text(message).multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "translate").foregroundStyle(Color.bronze)
            }
            .font(.footnote)
            .foregroundStyle(Color.appBrownText)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color.appWarmSurface, in: RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityHint(String(localized: "Dismiss"))
        .accessibilityIdentifier("surah.translationNote")
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .task {
            guard (try? await Task.sleep(for: Self.visibleDuration)) != nil else { return }
            onDismiss()
        }
    }
}

private struct AudioCheck: Equatable {
    var ayahIDs: [Int]
    var readyJobs: Int
}
