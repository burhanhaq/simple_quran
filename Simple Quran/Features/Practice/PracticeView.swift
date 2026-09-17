import SwiftUI
import UIKit

struct PracticeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let practiceSet: PracticeSet
    @State private var showRating = false
    @State private var isCurrentMarkedForReview = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                verseList
                controls
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(practiceSet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { close() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Section(String(localized: "Repeat Each Ayah")) {
                            ForEach(RepeatCount.ayahPresets, id: \.self) { value in
                                Button(value.label) {
                                    apply { $0.ayahRepeatCount = value }
                                }
                            }
                        }
                        Section(String(localized: "Repeat Collection")) {
                            ForEach(RepeatCount.setPresets, id: \.self) { value in
                                Button(value.label) {
                                    apply { $0.setRepeatCount = value }
                                }
                            }
                        }
                        Section(String(localized: "Reading Layout")) {
                            ForEach(QuranReadingLayout.allCases) { layout in
                                Button {
                                    environment.settings.quranReadingLayout = layout
                                } label: {
                                    Label(
                                        layout.title,
                                        systemImage: environment.settings.quranReadingLayout == layout
                                            ? "checkmark"
                                            : layout.systemImage
                                    )
                                }
                            }
                        }
                        if environment.recorder.hasRecording {
                            Divider()
                            Button(String(localized: "Delete Recording"), systemImage: "trash", role: .destructive) {
                                environment.recorder.deleteLatest()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button(String(localized: "Done")) { showRating = true }
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
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                toggleCurrentReviewMark()
            } label: {
                Image(systemName: isCurrentMarkedForReview ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(isCurrentMarkedForReview ? Color.gold : Color.olive)
            .accessibilityLabel(
                isCurrentMarkedForReview
                    ? String(localized: "Remove ayah from review")
                    : String(localized: "Mark ayah for review")
            )

            Spacer(minLength: 4)

            Button {
                Task { await toggleRecord() }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: recordSystemImage)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                    if let countdownValue {
                        Text("\(countdownValue)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.dangerWarm, in: Circle())
                    }
                }
            }
            .foregroundStyle(isActivelyRecording ? Color.dangerWarm : Color.olive)
            .disabled(environment.recorder.phase == .finishing)
            .accessibilityIdentifier("practice.record")
            .accessibilityLabel(recordAccessibilityLabel)

            Spacer(minLength: 4)

            Button(action: togglePlayback) {
                Image(systemName: isPlaybackActive ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 46))
                    .frame(width: 52, height: 48)
                    .overlay(alignment: .topTrailing) {
                        if !environment.playback.snapshot.repetitionLabel.isEmpty {
                            Text(environment.playback.snapshot.repetitionLabel)
                                .font(.caption2.bold())
                                .foregroundStyle(Color.appBrownText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.appWarmSurface, in: Capsule())
                                .offset(x: 9, y: -2)
                        }
                    }
            }
            .foregroundStyle(Color.gold)
            .disabled(isRecordingBusy)
            .accessibilityIdentifier("practice.play")
            .accessibilityLabel(isPlaybackActive ? String(localized: "Pause") : String(localized: "Play"))

            Spacer(minLength: 4)

            Button(action: toggleRecordingPlayback) {
                Image(systemName: environment.recorder.isPlayingComparison ? "stop.fill" : "waveform")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(environment.recorder.hasRecording ? Color.olive : Color.secondaryWarm.opacity(0.55))
            .disabled(!environment.recorder.hasRecording || isRecordingBusy)
            .accessibilityLabel(
                environment.recorder.isPlayingComparison
                    ? String(localized: "Stop my recording")
                    : String(localized: "Play my recording")
            )
            .accessibilityHint(
                environment.recorder.hasRecording
                    ? ""
                    : String(localized: "Record this collection to enable playback")
            )

            Spacer(minLength: 4)

            Button {
                environment.playback.toggleArabicHidden()
            } label: {
                Image(systemName: environment.playback.snapshot.hideArabic ? "eye.slash.fill" : "eye")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Color.olive)
            .accessibilityLabel(
                environment.playback.snapshot.hideArabic
                    ? String(localized: "Show Arabic")
                    : String(localized: "Hide Arabic")
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Divider().overlay(Color.secondaryWarm.opacity(0.25))
        }
        .background(.regularMaterial)
    }

    private var ratingSheet: some View {
        NavigationStack {
            List {
                ForEach(RecallRating.allCases, id: \.self) { rating in
                    Button(rating.title) {
                        rate(rating)
                    }
                }
            }
            .navigationTitle(String(localized: "How did recall feel?"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip Rating")) { finishWithoutRating() }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
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
