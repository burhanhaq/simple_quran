import SwiftUI
import UIKit

struct PracticeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let practiceSet: PracticeSet
    @State private var showRating = false
    @State private var showOptions = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCurrentMarkedForReview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sessionHeader
                if verticalSizeClass == .compact {
                    HStack(spacing: 0) {
                        verseList
                        controls.frame(width: 320)
                    }
                } else {
                    verseList
                    controls
                }
            }
            .background(Color.parchment.ignoresSafeArea())
            .parchmentNavigationBar()
            .navigationTitle(practiceSet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { close() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(String(localized: "Practice options"), systemImage: "slider.horizontal.3") { showOptions = true }
                            .disabled(isRecordingBusy)
                        ReadingLayoutMenu()
                        if environment.recorder.hasRecording {
                            Divider()
                            Button(String(localized: "Delete Recording"), systemImage: "trash", role: .destructive) {
                                environment.recorder.deleteLatest()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button(String(localized: "Finish")) {
                        environment.playback.pause()
                        environment.recorder.stopRecording()
                        environment.recorder.cancelComparisonPlayback()
                        showRating = true
                    }
                    .accessibilityIdentifier("practice.finish")
                }
            }
            .onAppear {
                start()
                loadCurrentReviewState()
            }
            .onDisappear {
                environment.recorder.stopRecording()
                environment.recorder.cancelComparisonPlayback()
            }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, _ in
                environment.recorder.cancelComparisonPlayback()
                loadCurrentReviewState()
            }
            .sheet(isPresented: $showOptions) { practiceOptions }
            .sheet(isPresented: $showRating) {
                ratingSheet
            }
            .alert(
                environment.playback.userMessage?.title ?? environment.recorder.userMessage?.title ?? "",
                isPresented: Binding(
                    get: { environment.playback.userMessage != nil || environment.recorder.userMessage != nil },
                    set: { if !$0 {
                        environment.playback.userMessage = nil
                        environment.recorder.userMessage = nil
                    }}
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
                if environment.recorder.userMessage?.title == UserFacingMessage.from(.microphoneDenied).title {
                    Button(String(localized: "Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } message: {
                Text(environment.playback.userMessage?.message ?? environment.recorder.userMessage?.message ?? "")
            }
        }
    }

    @ViewBuilder
    private var verseList: some View {
        switch environment.settings.quranReadingLayout {
        case .ayahByAyah:
            ayahByAyahList
        case .mushaf:
            MushafFlowView(
                verses: environment.playback.versesInSet,
                currentGlobalAyah: environment.playback.snapshot.currentGlobalAyah,
                hidesCurrentAyah: environment.playback.snapshot.hideArabic,
                selectionEnabled: !isAyahSelectionLocked,
                onSelect: selectAyah
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var ayahByAyahList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(environment.playback.versesInSet) { verse in
                        Button {
                            selectAyah(verse.globalAyah)
                        } label: {
                            VStack(spacing: 2) {
                                if verse.showsBasmalaBefore {
                                    BasmalaHeader()
                                }
                                QuranAyahText(
                                    verse: verse,
                                    isCurrent: verse.globalAyah == environment.playback.snapshot.currentGlobalAyah,
                                    hidden: environment.playback.snapshot.hideArabic && verse.globalAyah == environment.playback.snapshot.currentGlobalAyah
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .allowsHitTesting(!isAyahSelectionLocked)
                        .id(verse.globalAyah)
                        .accessibilityIdentifier("practice.ayah.\(verse.globalAyah)")
                        .accessibilityHint(String(localized: "Select this ayah"))
                    }
                }
                .padding()
            }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, newValue in
                if let newValue {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var sessionHeader: some View {
        let verses = environment.playback.versesInSet
        let position = verses.firstIndex { $0.globalAyah == environment.playback.snapshot.currentGlobalAyah }.map { $0 + 1 } ?? 0
        return VStack(spacing: 10) {
            HStack {
                if !dynamicTypeSize.isAccessibilitySize {
                    Label(String(localized: "PRACTICE"), systemImage: "leaf")
                        .font(.caption2.weight(.semibold)).tracking(1.5)
                    Spacer(minLength: 16)
                }
                Text(String(localized: "Ayah \(position) of \(verses.count)"))
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(Color.secondaryWarm)
            ProgressView(value: Double(position), total: Double(max(verses.count, 1)))
                .tint(Color.bronze)
                .accessibilityLabel(String(localized: "Position in collection"))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack {
                Button { showOptions = true } label: {
                    Label(String(localized: "Repeat · \(environment.playback.snapshot.ayahRepeat.label)"), systemImage: "repeat")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Color.appCollectedFill, in: Capsule())
                }
                .disabled(isRecordingBusy)
                .accessibilityIdentifier("practice.options")
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize || isRecordingBusy {
                    Text(isRecordingBusy ? recordAccessibilityLabel : environment.audioSource.reciter.englishName)
                        .font(.caption).foregroundStyle(isRecordingBusy ? Color.dangerWarm : Color.secondaryWarm)
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack(spacing: 36) {
                Button {
                    environment.recorder.cancelComparisonPlayback()
                    environment.playback.skipBack()
                } label: {
                    Image(systemName: "backward.end.fill").font(.title2).frame(width: 48, height: 48)
                }
                .disabled(isRecordingBusy)
                .accessibilityLabel(String(localized: "Previous ayah"))
                .accessibilityIdentifier("practice.previous")
                Button(action: togglePlayback) {
                    ZStack {
                        PlayGlyph(systemName: isPlaybackActive ? "pause.fill" : "play.fill", size: 64)
                        if environment.playback.snapshot.isLoading {
                            Circle().stroke(Color.goldButtonText.opacity(0.6), lineWidth: 2).padding(5)
                        }
                    }
                }
                .disabled(isRecordingBusy)
                .accessibilityIdentifier("practice.play")
                .accessibilityLabel(isPlaybackActive ? String(localized: "Pause") : String(localized: "Play"))
                Button {
                    environment.recorder.cancelComparisonPlayback()
                    environment.playback.skipForward()
                } label: {
                    Image(systemName: "forward.end.fill").font(.title2).frame(width: 48, height: 48)
                }
                .disabled(isRecordingBusy)
                .accessibilityLabel(String(localized: "Next ayah"))
                .accessibilityIdentifier("practice.next")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                Button(action: toggleCurrentReviewMark) {
                    toolLabel(isCurrentMarkedForReview ? String(localized: "Marked") : String(localized: "Review"), symbol: isCurrentMarkedForReview ? "bookmark.fill" : "bookmark", selected: isCurrentMarkedForReview)
                }
                .accessibilityLabel(isCurrentMarkedForReview ? String(localized: "Remove ayah from review") : String(localized: "Mark ayah for review"))
                Button { Task { await toggleRecord() } } label: {
                    toolLabel(isActivelyRecording ? String(localized: "Stop") : String(localized: "Record"), symbol: recordSystemImage, selected: isActivelyRecording)
                }
                .disabled(environment.recorder.phase == .finishing)
                .accessibilityIdentifier("practice.record")
                .accessibilityLabel(recordAccessibilityLabel)
                Button(action: toggleRecordingPlayback) {
                    toolLabel(String(localized: "Compare"), symbol: environment.recorder.isPlayingComparison ? "stop.fill" : "waveform", selected: environment.recorder.isPlayingComparison)
                }
                .disabled(!environment.recorder.hasRecording || isRecordingBusy)
                .accessibilityLabel(environment.recorder.isPlayingComparison ? String(localized: "Stop my recording") : String(localized: "Play my recording"))
                .accessibilityHint(environment.recorder.hasRecording ? "" : String(localized: "Record this collection to enable playback"))
                Button {
                    environment.playback.toggleArabicHidden()
                    do { try environment.store.save() }
                    catch { environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure) }
                } label: {
                    toolLabel(environment.playback.snapshot.hideArabic ? String(localized: "Reveal") : String(localized: "Hide text"), symbol: environment.playback.snapshot.hideArabic ? "eye.slash" : "eye", selected: environment.playback.snapshot.hideArabic)
                }
                .accessibilityIdentifier("practice.hideArabic")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.bronze)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(Color.appWarmSurface)
        .overlay(alignment: .top) { Color.warmBorder.opacity(0.6).frame(height: 0.5) }
    }

    private func toolLabel(_ title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 19)).frame(height: 24)
            Text(title).font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(selected ? Color.bronze : Color.secondaryWarm)
        .contentShape(Rectangle())
    }

    private var practiceOptions: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Repeat each ayah"), selection: Binding(
                        get: { practiceSet.settings.ayahRepeatCount },
                        set: { value in apply { $0.ayahRepeatCount = value } }
                    )) {
                        ForEach(RepeatCount.ayahPresets) { Text($0.label).tag($0) }
                    }.warmListRow()
                    Picker(String(localized: "Repeat collection"), selection: Binding(
                        get: { practiceSet.settings.setRepeatCount },
                        set: { value in apply { $0.setRepeatCount = value } }
                    )) {
                        ForEach(RepeatCount.setPresets) { Text($0.label).tag($0) }
                    }.warmListRow()
                } header: { Text(String(localized: "Listen & repeat")) }
                Section {
                    Stepper(value: Binding(
                        get: { practiceSet.settings.pauseSeconds },
                        set: { value in apply { $0.pauseSeconds = value } }
                    ), in: 0...5) {
                        Text(String(localized: "Pause between ayahs: \(practiceSet.settings.pauseSeconds)s"))
                    }.warmListRow()
                    Toggle(String(localized: "Advance manually"), isOn: Binding(
                        get: { practiceSet.settings.advanceManually },
                        set: { value in apply { $0.advanceManually = value } }
                    )).warmListRow()
                } header: { Text(String(localized: "Your pace")) }
                  footer: { Text(String(localized: "Leave a pause to recite aloud, or use Next to move on when you’re ready.")) }
            }
            .warmListChrome()
            .navigationTitle(String(localized: "Practice options"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { showOptions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var ratingSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RecallRating.allCases, id: \.self) { rating in
                        Button { rate(rating) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: ratingSymbol(rating))
                                    .font(.title3).foregroundStyle(Color.bronze)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rating.title).font(.headline).foregroundStyle(Color.appBrownText)
                                    Text(ratingDetail(rating)).font(.caption).foregroundStyle(Color.secondaryWarm)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                            .padding(.vertical, 6)
                        }
                        .warmListRow()
                    }
                } footer: {
                    Text(String(localized: "An honest reflection helps you choose what to revisit next."))
                }
            }
            .warmListChrome()
            .navigationTitle(String(localized: "How did recall feel?"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip Rating")) { finishWithoutRating() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    private func ratingSymbol(_ rating: RecallRating) -> String {
        switch rating {
        case .again: "arrow.counterclockwise"
        case .needsWork: "leaf"
        case .comfortable: "checkmark.circle"
        case .solid: "checkmark.seal"
        }
    }

    private func ratingDetail(_ rating: RecallRating) -> String {
        switch rating {
        case .again: String(localized: "I’d like to listen and try again.")
        case .needsWork: String(localized: "I remembered some, with a little help.")
        case .comfortable: String(localized: "I recalled it with a few pauses.")
        case .solid: String(localized: "I recited it confidently from memory.")
        }
    }

    private var isPlaybackActive: Bool {
        environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading
    }

    private var isRecordingBusy: Bool {
        switch environment.recorder.phase {
        case .countdown, .recording, .finishing: true
        case .idle, .comparing: false
        }
    }

    private var isActivelyRecording: Bool {
        switch environment.recorder.phase {
        case .countdown, .recording: true
        case .idle, .finishing, .comparing: false
        }
    }

    private var isAyahSelectionLocked: Bool { isRecordingBusy }

    private var countdownValue: Int? {
        guard case .countdown(let value) = environment.recorder.phase else { return nil }
        return value
    }

    private var recordSystemImage: String {
        switch environment.recorder.phase {
        case .countdown, .recording: "stop.circle.fill"
        case .finishing: "hourglass"
        case .idle, .comparing: "mic.fill"
        }
    }

    private var recordAccessibilityLabel: String {
        switch environment.recorder.phase {
        case .recording: String(localized: "Stop recording")
        case .finishing: String(localized: "Saving recording")
        case .countdown(let value): String(localized: "Recording in \(value)")
        case .idle: String(localized: "Record this collection")
        case .comparing: String(localized: "Record this collection again")
        }
    }

    private func start() {
        if PracticePlaybackLifecycle.shouldPrepareNewSession(
            activeSetID: environment.playback.activeSet?.id,
            currentGlobalAyah: environment.playback.snapshot.currentGlobalAyah,
            openingSetID: practiceSet.id
        ) {
            environment.playback.start(
                set: practiceSet,
                catalog: environment.quran,
                resume: true,
                allowStreaming: environment.settings.streamWhenMissing || environment.downloads.downloadedCount(in: practiceSet.orderedPassages.flatMap(\.range.globalAyahs)) == practiceSet.orderedPassages.map(\.range.count).reduce(0, +)
            )
        }
        environment.recorder.selectCollection(practiceSet.id)
    }

    private func close() {
        environment.playback.pause()
        do {
            if let session = environment.playback.session {
                try environment.store.finishSession(
                    session,
                    coveredAyahs: environment.playback.coveredAyahs.count,
                    repetitions: environment.playback.repetitionCount,
                    lastAyah: environment.playback.snapshot.currentGlobalAyah,
                    completed: false,
                    rating: nil
                )
            }
            try environment.store.recordExposure(
                ayahs: Array(environment.playback.coveredAyahs),
                seconds: environment.playback.listeningSeconds
            )
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
            return
        }
        environment.playback.stop()
        dismiss()
    }

    private func apply(_ update: (inout PracticeSettings) -> Void) {
        var settings = practiceSet.settings
        update(&settings)
        environment.playback.applySettingsAndRestart(settings)
        do {
            try environment.store.save()
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
        }
    }

    private func toggleRecord() async {
        switch environment.recorder.phase {
        case .recording, .countdown:
            environment.recorder.stopRecording()
        case .finishing:
            return
        default:
            guard beginSessionIfNeeded() else { return }
            environment.playback.pause()
            environment.recorder.cancelComparisonPlayback()
            await environment.recorder.startRecording(collectionID: practiceSet.id)
        }
    }

    private func togglePlayback() {
        if isPlaybackActive {
            environment.playback.pause()
        } else {
            guard beginSessionIfNeeded() else { return }
            environment.recorder.cancelComparisonPlayback()
            environment.playback.resume()
        }
    }

    private func toggleRecordingPlayback() {
        if environment.recorder.isPlayingComparison {
            environment.recorder.cancelComparisonPlayback()
        } else {
            Task { await playMyRecording() }
        }
    }

    private func playMyRecording() async {
        guard beginSessionIfNeeded() else { return }
        environment.playback.pause()
        do {
            try await environment.recorder.playRecording()
        } catch is CancellationError {
            return
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.recordingFailed)
        }
    }

    private func selectAyah(_ globalAyah: Int) {
        guard !isAyahSelectionLocked else { return }
        environment.recorder.cancelComparisonPlayback()
        environment.playback.move(to: globalAyah)
    }

    private func toggleCurrentReviewMark() {
        guard let ayah = environment.playback.snapshot.currentGlobalAyah else { return }
        let newValue = !isCurrentMarkedForReview
        do {
            try environment.store.markWeak(globalAyah: ayah, weak: newValue)
            isCurrentMarkedForReview = newValue
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
        }
    }

    private func loadCurrentReviewState() {
        guard let ayah = environment.playback.snapshot.currentGlobalAyah else {
            isCurrentMarkedForReview = false
            return
        }
        do {
            isCurrentMarkedForReview = try environment.store.isMarkedWeak(globalAyah: ayah)
        } catch {
            isCurrentMarkedForReview = false
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
        }
    }

    private func beginSessionIfNeeded() -> Bool {
        guard environment.playback.session == nil else { return true }
        do {
            environment.playback.session = try environment.store.startSession(for: practiceSet)
            return true
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
            return false
        }
    }

    private func rate(_ rating: RecallRating) {
        environment.playback.pause()
        let ayahs = Array(environment.playback.coveredAyahs)
        do {
            try environment.store.recordExposure(
                ayahs: ayahs,
                seconds: environment.playback.listeningSeconds
            )
            try environment.store.applyRating(rating, ayahs: ayahs, now: .now)
            if let session = environment.playback.session {
                try environment.store.finishSession(
                    session,
                    coveredAyahs: ayahs.count,
                    repetitions: environment.playback.repetitionCount,
                    lastAyah: environment.playback.snapshot.currentGlobalAyah,
                    completed: true,
                    rating: rating
                )
            }
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
            return
        }
        showRating = false
        environment.playback.stop()
        dismiss()
    }

    private func finishWithoutRating() {
        environment.playback.pause()
        let ayahs = Array(environment.playback.coveredAyahs)
        do {
            try environment.store.recordExposure(
                ayahs: ayahs,
                seconds: environment.playback.listeningSeconds
            )
            if let session = environment.playback.session {
                try environment.store.finishSession(
                    session,
                    coveredAyahs: ayahs.count,
                    repetitions: environment.playback.repetitionCount,
                    lastAyah: environment.playback.snapshot.currentGlobalAyah,
                    completed: true,
                    rating: nil
                )
            }
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.persistenceFailure)
            return
        }
        showRating = false
        environment.playback.stop()
        dismiss()
    }
}

enum PracticePlaybackLifecycle {
    static func shouldPrepareNewSession(
        activeSetID: UUID?,
        currentGlobalAyah: Int?,
        openingSetID: UUID
    ) -> Bool {
        activeSetID != openingSetID || currentGlobalAyah == nil
    }
}
