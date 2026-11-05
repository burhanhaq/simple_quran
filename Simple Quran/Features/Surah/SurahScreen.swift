import SwiftData
import SwiftUI

/// The one place a surah opens, from any tab: the text, with a sheet on top that holds the
/// player, the surah's progress, and memorizing a piece in place.
struct SurahScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var progress: [VerseProgress]
    @State private var model: SurahScreenModel
    @State private var showsSheet = true
    @State private var showsTranslationNote = false
    /// Checking files is a filesystem call per ayah, so it runs when downloads finish, not on every render.
    @State private var audioDownloaded = false
    @State private var swipe = SurahSwipeState()

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
                ZStack {
                    // A new surah gets new text, so scrolling and following start fresh. Mushaf pages
                    // keep theirs: paging into the next surah mustn't rebuild the page being read.
                    text
                        .offset(x: swipe.offset)
                        .id(showsPages ? AnyHashable(QuranReadingLayout.page) : AnyHashable(ObjectIdentifier(model)))
                        .transition(arrival(width: geometry.size.width))
                }
                .safeAreaPadding(.bottom, textInset)
                .allowsHitTesting(swipe.phase.acceptsDrag)
                .background { reveal(in: geometry) }
                .overlay(alignment: .bottom) { fade.offset(y: -halfSheetTop(in: geometry)) }
                .animation(.snappy, value: textInset)
                .gesture(SurahSwipeGesture(
                    // Mushaf pages turn with their own swipe, through the whole Quran.
                    isEnabled: model.canSwitchSurah && swipe.phase.acceptsDrag && !showsPages,
                    onChange: {
                        dragChanged($0, width: geometry.size.width, revealY: visibleTextHeight(in: geometry) / 2)
                    },
                    onEnd: { dragEnded($0, velocityX: $1, width: geometry.size.width) },
                    onCancel: springBack
                ))
                .sensoryFeedback(.selection, trigger: swipe.isPastThreshold) { _, past in past }
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
            // Reciting, a peek while recording is exactly when it's needed.
            selectionEnabled: !model.recordingBusy || model.focus?.step == .recite,
            focusedAyah: model.selectedAyah,
            scrollToAyah: model.destination.scrollToAyah,
            focusRange: model.focus?.range,
            markedAyahs: model.focus?.slipped ?? [],
            isPlaying: model.isPlaying,
            followRequest: model.followRequest,
            onSelect: select,
            onPageSettled: pageSettled
        ) { verse in ayahMenu(verse) }
    }

    private var showsPages: Bool { environment.settings.displayedReadingLayout == .page }

    /// A tap on a neighbouring surah's ayah, sharing the page, moves the reader to that surah.
    private func select(_ ayah: Int) {
        guard model.passage.indexByAyah[ayah] == nil else { return model.select(ayah) }
        guard model.canSwitchSurah, let surah = environment.quran.verse(globalAyah: ayah)?.surahNumber else { return }
        arriveQuietly(at: .reader(ReaderRoute(destination: .surah(number: surah, scrollToAyah: ayah), sheet: .keeping(model.detent))))
        model.select(ayah)
    }

    /// Paging past the surah being read moves the reader to the surah now on the page; within it,
    /// the page becomes the reading place.
    private func pageSettled(on page: Int, toward side: ReaderNeighbor) {
        guard let mushafPage = environment.mushafPages?.layout.page(page) else { return }
        let ayahs = mushafPage.orderedAyahs
        guard model.canSwitchSurah,
              let destination = model.destination.settling(onPage: page, holding: ayahs, toward: side, in: environment.quran)
        else {
            if let ayah = mushafPage.orderedAyahs.first(where: { model.passage.indexByAyah[$0] != nil }) {
                model.pageTurned(to: ayah)
            }
            return
        }
        arriveQuietly(at: .reader(ReaderRoute(destination: destination, sheet: .keeping(model.detent))))
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

    private var textInset: CGFloat { model.textInset }

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
            if let surah = environment.quran.surah(number: verse.surahNumber), environment.settings.activePlan?.range != surah.range,
               !environment.settings.isQueued(surah.range) {
                Button("Memorize \(surah.englishName) next", systemImage: "text.badge.plus") {
                    environment.settings.queueNext(LearningTarget(range: surah.range))
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var settings = environment.settings
        ToolbarItem(placement: .principal) { title }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                model.close(index: index)
                dismiss()
            } label: { Image(systemName: "chevron.down").frame(width: 32, height: 32) }
                .accessibilityLabel("Close").accessibilityIdentifier("surah.close").disabled(model.recordingBusy)
        }
        // One button on each side keeps the title centered whatever its length.
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if model.focus != nil {
                    Button("Repeat and pause", systemImage: "repeat") { model.showsOptions = true }
                    Button("Change passage", systemImage: "slider.horizontal.3") { model.showsPassagePicker = true }
                }
                // Shown in every layout: turning it on anywhere else shows ayah by ayah.
                Toggle(isOn: $settings.showsTranslation) {
                    Label(String(localized: "Translation"), systemImage: "translate")
                }
                .accessibilityIdentifier("surah.translation")
                ReadingLayoutMenu()
                Button(audioDownloaded ? "Audio downloaded" : downloading ? "Downloading audio…" : "Download this audio",
                       systemImage: audioDownloaded ? "checkmark.circle" : "arrow.down.circle") {
                    environment.downloads.download(ayahs: model.passage.ayahIDs)
                }.disabled(audioDownloaded || downloading)
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Options").accessibilityIdentifier("surah.options").disabled(model.recordingBusy)
        }
    }

    // MARK: - Next and previous surah

    /// The title moves with the text, so the new name comes in from the same side.
    private var title: some View {
        ZStack {
            Text(model.title)
                .font(.headline)
                .lineLimit(1)
                .id(model.title)
                .transition(titleTransition)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityActions {
            ForEach(ReaderNeighbor.allCases, id: \.self) { side in
                if model.canSwitchSurah, swipe.phase.acceptsDrag, model.neighbor(side) != nil {
                    Button(model.destination.neighborCaption(side)) { switchSurah(side, width: 0) }
                }
            }
        }
    }

    private var titleTransition: AnyTransition {
        guard !reduceMotion, let side = swipe.side else { return .opacity }
        let shift = side == .next ? -SurahSwipe.titleShift : SurahSwipe.titleShift
        return .asymmetric(insertion: .offset(x: shift).combined(with: .opacity),
                           removal: .offset(x: -shift).combined(with: .opacity))
    }

    /// The old text is already off screen when it goes; the new one slides in from where the
    /// neighbour's name was. With Reduce Motion the two cross-fade instead.
    private func arrival(width: CGFloat) -> AnyTransition {
        guard !reduceMotion, let side = swipe.side else { return .opacity }
        return .asymmetric(insertion: .offset(x: SurahSwipe.arrivalOffset(from: side, width: width)).combined(with: .opacity),
                           removal: .opacity)
    }

    @ViewBuilder
    private func reveal(in geometry: GeometryProxy) -> some View {
        if let reveal = swipe.reveal {
            let width = geometry.size.width
            let progress = SurahSwipe.progress(for: reveal.offset, width: width)
            // Centered in the strip the text uncovers.
            let x = reveal.side == .next ? reveal.offset / 2 : width + reveal.offset / 2
            SurahNeighborReveal(side: reveal.side, caption: reveal.caption,
                                title: reveal.destination.title(in: environment.quran),
                                arabicName: reveal.destination.arabicName(in: environment.quran))
                .scaleEffect(0.9 + 0.1 * progress)
                .opacity(swipe.showsReveal ? progress : 0)
                .position(x: x, y: reveal.centerY)
        }
    }

    private func visibleTextHeight(in geometry: GeometryProxy) -> CGFloat {
        let covered = model.detent == SurahSheetDetent.half ? halfSheetTop(in: geometry) : textInset
        return max(geometry.size.height - covered, 0)
    }

    private func dragChanged(_ translationX: CGFloat, width: CGFloat, revealY: CGFloat) {
        let side = SurahSwipe.side(for: translationX)
        let neighbor = model.neighbor(side)
        let offset = SurahSwipe.offset(for: translationX, hasNeighbor: neighbor != nil)
        swipe.phase = .dragging
        swipe.offset = offset
        swipe.reveal = neighbor.map {
            SurahReveal(side: side, destination: $0, caption: model.destination.neighborCaption(side),
                        offset: offset, centerY: revealY)
        }
        swipe.isPastThreshold = neighbor != nil && SurahSwipe.progress(for: translationX, width: width) >= 1
    }

    private func dragEnded(_ translationX: CGFloat, velocityX: CGFloat, width: CGFloat) {
        let available = Set(ReaderNeighbor.allCases.filter { model.neighbor($0) != nil })
        let projected = SurahSwipe.projectedEnd(translationX: translationX, velocityX: velocityX)
        guard let side = SurahSwipe.outcome(translationX: translationX, projectedEndX: projected,
                                            width: width, available: available) else {
            springBack()
            return
        }
        switchSurah(side, width: width)
    }

    private func springBack() {
        guard swipe.phase == .dragging else { return }
        swipe.isPastThreshold = false
        withAnimation(.snappy) {
            swipe.offset = 0
            swipe.reveal?.offset = 0
        } completion: {
            // A new drag may have started while the text was on its way back.
            if swipe.phase == .dragging, swipe.offset == 0 { swipe = SurahSwipeState() }
        }
    }

    /// Slides this surah out the way the finger went, then brings the neighbour in from the other
    /// side. The sheet stays up and follows the new surah; nothing is presented again.
    private func switchSurah(_ side: ReaderNeighbor, width: CGFloat) {
        guard model.canSwitchSurah, swipe.phase.acceptsDrag,
              let neighbor = model.neighbor(side), let route = model.neighborRoute(side) else { return }
        model.leaveForNeighbor()
        // From VoiceOver there's no drag, so nothing was uncovered; the transitions still need the side.
        if swipe.side != side {
            swipe.reveal = SurahReveal(side: side, destination: neighbor, caption: model.destination.neighborCaption(side),
                                       offset: 0, centerY: 0)
            swipe.showsReveal = false
        }
        swipe.phase = .leaving
        guard !reduceMotion, width > 0 else { arrive(at: route); return }
        // Starts at speed and ends exactly on time, so the next surah follows without a pause.
        withAnimation(.easeOut(duration: SurahSwipe.leavingDuration)) {
            let target = SurahSwipe.leavingOffset(toward: side, width: width)
            swipe.offset = target
            swipe.reveal?.offset = target
        } completion: {
            arrive(at: route)
        }
    }

    private func arrive(at route: AppRoute) {
        swipe.phase = .arriving
        let next = SurahScreenModel(route: route, environment: environment)
        next.prefersFullCoach = prefersFullCoach
        let duration = SurahSwipe.arrivalDuration
        withAnimation(reduceMotion ? .easeInOut(duration: duration) : .easeOut(duration: duration)) {
            model = next
            model.start()
            swipe.offset = 0
            swipe.isPastThreshold = false
            swipe.showsReveal = false
        } completion: {
            swipe = SurahSwipeState()
        }
        model.savePosition()
        AccessibilityNotification.Announcement(model.title).post()
    }

    /// Moves to another surah without sliding the text, for mushaf pages that already show it.
    /// Nothing animates, so the sheet changes to the new surah at once instead of cross-fading.
    private func arriveQuietly(at route: AppRoute) {
        model.leaveForNeighbor()
        let next = SurahScreenModel(route: route, environment: environment)
        next.prefersFullCoach = prefersFullCoach
        withTransaction(Transaction(animation: nil)) {
            model = next
            model.start()
        }
        model.savePosition()
        AccessibilityNotification.Announcement(model.title).post()
    }

    private func refreshAudioDownloaded() {
        let ids = model.passage.ayahIDs
        audioDownloaded = !ids.isEmpty && environment.downloads.downloadedCount(in: ids) == ids.count
    }
}

/// Shown once, when translation first switches another layout to ayah by ayah.
private struct TranslationLayoutNote: View {
    var onDismiss: () -> Void

    private static var visibleDuration: Duration { .seconds(6) }
    private var message: String {
        String(localized: "Translations show ayah by ayah. Turn translation off to go back to your layout.")
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
