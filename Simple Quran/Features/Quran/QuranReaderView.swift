import SwiftUI

/// Reading, listening and practice share the text, navigation and audio session.
struct QuranReaderView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let destination: QuranDestination
    var initialPracticeRange: VerseRange? = nil
    var savedPractice: PracticeSet? = nil
    var resumesPlayback = false
    var isReview = false
    var targetID: UUID? = nil
    @State private var detachedFromTarget = false
    @State private var practice: PracticeSet?
    @State private var readingRanges: [VerseRange]?
    @State private var readingName: String?
    @State private var selectedAyah: Int?
    @State private var initialized = false
    @State private var showPassage = false
    @State private var showOptions = false
    @State private var showFinish = false
    @State private var finished = false
    @State private var errorMessage: UserFacingMessage?

    private var ranges: [VerseRange] {
        practice?.orderedPassages.map(\.range) ?? readingRanges ?? destination.range(in: environment.quran).map { [$0] } ?? []
    }
    private var verses: [QuranVerse] {
        var seen = Set<Int>()
        return ranges.flatMap { environment.quran.verses(in: $0) }.filter { seen.insert($0.globalAyah).inserted }
    }
    private var currentAyah: Int? {
        ownsPlayback ? environment.playback.snapshot.currentGlobalAyah : selectedAyah ?? verses.first?.globalAyah
    }
    private var ownsPlayback: Bool {
        if let practice { return environment.playback.activeSet?.id == practice.id }
        return environment.playback.activeSet == nil && environment.playback.isPrepared(for: ranges)
    }
    private var downloading: Bool {
        verses.contains { environment.downloads.jobs[$0.globalAyah]?.status == .downloading }
    }
    private var audioDownloaded: Bool {
        !verses.isEmpty && environment.downloads.downloadedCount(in: verses.map(\.globalAyah)) == verses.count
    }
    private var playing: Bool { ownsPlayback && (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading) }
    private var hidesText: Bool { practice != nil && ownsPlayback && environment.playback.snapshot.hideArabic }
    private var recordingBusy: Bool {
        switch environment.recorder.phase {
        case .countdown, .recording, .finishing: true
        default: false
        }
    }
    private var title: String {
        if practice == nil { return readingName ?? destination.title(in: environment.quran) }
        guard let first = verses.first, let last = verses.last, first.surahNumber == last.surahNumber else {
            return practice?.title ?? destination.title(in: environment.quran)
        }
        return environment.quran.surah(number: first.surahNumber)?.englishName ?? destination.title(in: environment.quran)
    }
    private var passageLabel: String { ranges.map { LearningPassage.ayahLabel($0, catalog: environment.quran) }.joined(separator: ", ") }
    private var practicePageLabel: String {
        guard environment.settings.practiceByPage, let first = verses.first, let last = verses.last,
              first.page == last.page else { return "" }
        return "Page \(first.page) · "
    }
    private var learningTarget: LearningTarget? {
        guard !detachedFromTarget else { return nil }
        return environment.settings.learningTargets.first { $0.id == targetID }
    }
    private var nextRange: VerseRange? {
        guard ranges.count == 1, let range = ranges.first else { return nil }
        if let learningTarget {
            return learningTarget.passage(from: range.endGlobalAyah + 1, catalog: environment.quran,
                                          byPage: environment.settings.practiceByPage)
        }
        return LearningPassage.next(after: range, catalog: environment.quran, byPage: environment.settings.practiceByPage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if practice != nil { passageHeader }
                if verticalSizeClass == .compact {
                    HStack(spacing: 0) {
                        readingContent
                        controls.frame(width: 290)
                    }
                } else {
                    readingContent
                    controls
                }
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 32, height: 32) }
                        .accessibilityLabel("Close reader").accessibilityIdentifier("reader.close")
                        .disabled(recordingBusy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if practice != nil {
                            Button("Read full surah", systemImage: "book") { leavePractice() }
                            Button("Practice tools", systemImage: "slider.horizontal.3") { showOptions = true }
                        }
                        ReadingLayoutMenu()
                        Button(audioDownloaded ? "Audio saved on this device" : downloading ? "Saving audio…" : "Download this audio", systemImage: audioDownloaded ? "checkmark.circle" : "arrow.down.circle") {
                            environment.downloads.download(ayahs: verses.map(\.globalAyah))
                        }.disabled(audioDownloaded || downloading)
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                    .accessibilityLabel("Reader options").disabled(recordingBusy)
                }
            }
            .onAppear { initialize() }
            .onDisappear { savePosition(); environment.recorder.stopRecording(); environment.recorder.cancelComparisonPlayback() }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, ayah in
                guard ownsPlayback, let ayah else { return }
                selectedAyah = ayah
                savePosition()
            }
            .sheet(isPresented: $showPassage) {
                PassagePickerView(startAyah: currentAyah ?? verses.first?.globalAyah ?? 1,
                                  currentRange: practice?.orderedPassages.first?.range, allowedRange: learningTarget?.range) { range, byPage in
                    environment.settings.practiceByPage = byPage
                    beginPractice(range)
                }
            }
            .sheet(isPresented: $showOptions) { options }
            .sheet(isPresented: $showFinish) { finishSheet }
            .alert(errorMessage?.title ?? environment.playback.userMessage?.title ?? environment.recorder.userMessage?.title ?? environment.downloads.userMessage?.title ?? "", isPresented: Binding(
                get: { errorMessage != nil || environment.playback.userMessage != nil || environment.recorder.userMessage != nil || environment.downloads.userMessage != nil },
                set: { if !$0 { errorMessage = nil; environment.playback.userMessage = nil; environment.recorder.userMessage = nil; environment.downloads.userMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(errorMessage?.message ?? environment.playback.userMessage?.message ?? environment.recorder.userMessage?.message ?? environment.downloads.userMessage?.message ?? "")
            }
        }
        .tint(Color.bronze)
    }

    private var passageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                    Text(isReview ? "A LITTLE REVIEW" : "YOUR PRACTICE").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Color.bronze)
                }
                Text(practicePageLabel + passageLabel).font(.subheadline.weight(.medium)).foregroundStyle(Color.appBrownText)
            }
            Spacer(minLength: 0)
            Button("Change") { showPassage = true }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .disabled(recordingBusy).accessibilityIdentifier("practice.change")
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Color.appWarmSurface)
    }

    @ViewBuilder
    private var readingContent: some View {
        if environment.settings.quranReadingLayout == .mushaf {
            MushafFlowView(
                verses: hidesText ? verses.map { verse in
                    var hidden = verse
                    hidden.text = MushafTextBuilder.hiddenPlaceholder
                    return hidden
                } : verses,
                currentGlobalAyah: currentAyah,
                hidesCurrentAyah: false,
                selectionEnabled: !recordingBusy,
                focusedAyah: selectedAyah,
                onSelect: select
            )
        } else { ayahList }
    }

    private var ayahList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if let first = verses.first, let surah = environment.quran.surah(number: first.surahNumber) {
                        VStack(spacing: 8) {
                            ReadingBanner(title: surah.arabicName, isArabic: true)
                            Text(practice == nil ? "\(surah.translation) · \(surah.ayahCount) ayahs" : "Listen, repeat, then try from memory.")
                                .font(.caption).foregroundStyle(Color.secondaryWarm)
                        }.padding(.vertical, 20)
                    }
                    ForEach(verses) { verse in
                        Button { select(verse.globalAyah) } label: {
                            VStack(spacing: 0) {
                                if verse.showsBasmalaBefore { BasmalaHeader() }
                                QuranAyahText(verse: verse, isCurrent: verse.globalAyah == currentAyah,
                                              hidden: hidesText)
                            }
                        }
                        .buttonStyle(.plain).disabled(recordingBusy)
                        .id(verse.globalAyah)
                        .accessibilityIdentifier("ayah.\(verse.globalAyah)")
                        .accessibilityHint("Select this ayah")
                        .contextMenu {
                            Button("Practice from here", systemImage: "leaf") {
                                if let range = LearningPassage.suggested(from: verse.globalAyah, catalog: environment.quran) { beginPractice(range) }
                            }
                            Button("Revisit this ayah", systemImage: "bookmark") {
                                do { try environment.store.markWeak(globalAyah: verse.globalAyah, weak: true) }
                                catch { errorMessage = .from(.persistenceFailure) }
                            }
                        }
                    }
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, environment.settings.quranReadingLayout == .mushaf ? 12 : 22)
                .frame(maxWidth: 740).frame(maxWidth: .infinity)
            }
            .onChange(of: currentAyah) { _, ayah in
                if let ayah { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(ayah, anchor: .center) } }
            }
            .task { if let ayah = destination.scrollToAyah { proxy.scrollTo(ayah, anchor: .center) } }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if practice != nil {
                HStack {
                    Button { showOptions = true } label: {
                        if dynamicTypeSize.isAccessibilitySize { Text("Repeat") }
                        else { Label("Repeat · \(environment.playback.snapshot.ayahRepeat.label)", systemImage: "repeat") }
                    }.accessibilityIdentifier("practice.options")
                    Spacer()
                    Button {
                        environment.playback.toggleArabicHidden()
                        do { try environment.store.save() } catch { errorMessage = .from(.persistenceFailure) }
                    } label: {
                        if dynamicTypeSize.isAccessibilitySize { Text(hidesText ? "Show text" : "Hide text") }
                        else { Label(hidesText ? "Show text" : "Hide text", systemImage: hidesText ? "eye" : "eye.slash") }
                    }.accessibilityIdentifier("practice.hideArabic")
                }
                .font(.subheadline.weight(.medium)).frame(minHeight: 44).disabled(recordingBusy)
            }
            HStack(spacing: 28) {
                Button { step(-1) } label: {
                    Image(systemName: "backward.end.fill").font(.title3).frame(width: 48, height: 48)
                }.accessibilityLabel("Previous ayah").accessibilityIdentifier("practice.previous")
                    .disabled(recordingBusy || currentAyah == verses.first?.globalAyah)
                Button { togglePlayback() } label: {
                    ZStack {
                        PlayGlyph(systemName: playing ? "pause.fill" : "play.fill", size: 56)
                        if ownsPlayback && environment.playback.snapshot.isLoading { ProgressView().tint(Color.goldButtonText) }
                    }
                }.accessibilityLabel(playing ? "Pause" : "Play")
                    .accessibilityIdentifier(practice == nil ? "quran.play" : "practice.play").disabled(recordingBusy)
                Button { step(1) } label: {
                    Image(systemName: "forward.end.fill").font(.title3).frame(width: 48, height: 48)
                }.accessibilityLabel("Next ayah").accessibilityIdentifier("practice.next")
                    .disabled(recordingBusy || currentAyah == verses.last?.globalAyah)
            }.frame(maxWidth: .infinity)
            if let ayah = currentAyah, let index = verses.firstIndex(where: { $0.globalAyah == ayah }) {
                Text("Ayah \(index + 1) of \(verses.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(Color.secondaryWarm)
            }
            if downloading {
                HStack(spacing: 8) { ProgressView(); Text("Saving audio for offline use…").font(.caption) }
            }
            if practice != nil {
                Button {
                    environment.playback.pause()
                    environment.recorder.cancelComparisonPlayback()
                    finished = false
                    showFinish = true
                } label: { Text("Finish practice").frame(maxWidth: .infinity) }
                    .buttonStyle(WarmButtonStyle(emphasis: .secondary))
                    .disabled(recordingBusy).accessibilityIdentifier("practice.finish")
            } else {
                Button {
                    let start = currentAyah ?? verses.first?.globalAyah ?? 1
                    if case .page = destination, let range = ranges.first {
                        environment.settings.practiceByPage = true
                        beginPractice(range)
                    } else if let range = LearningPassage.suggested(from: start, catalog: environment.quran) {
                        environment.settings.practiceByPage = false
                        beginPractice(range)
                    }
                } label: { Label("Practice these ayahs", systemImage: "leaf").frame(maxWidth: .infinity) }
                    .buttonStyle(WarmButtonStyle(emphasis: .secondary)).accessibilityIdentifier("reader.practice")
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.bronze)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
        .frame(maxWidth: 740)
        .background(Color.appWarmSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color.warmBorder.opacity(0.6)).frame(height: 0.5) }
    }

    private var options: some View {
        NavigationStack {
            Form {
                if let practice {
                    Section("Listen and repeat") {
                        Picker("Repeat each ayah", selection: setting(\.ayahRepeatCount, in: practice)) {
                            ForEach(RepeatCount.ayahPresets) { Text($0.label).tag($0) }
                        }
                        Picker("Repeat passage", selection: setting(\.setRepeatCount, in: practice)) {
                            ForEach(RepeatCount.setPresets) { Text($0.label).tag($0) }
                        }
                        Stepper("Pause between ayahs: \(practice.settings.pauseSeconds)s", value: setting(\.pauseSeconds, in: practice), in: 0...5)
                        Toggle("Move to the next ayah myself", isOn: setting(\.advanceManually, in: practice))
                    }.disabled(recordingBusy)
                    Section {
                        Button {
                            if recordingBusy { environment.recorder.stopRecording() }
                            else {
                                environment.playback.pause()
                                Task { await environment.recorder.startRecording(collectionID: practice.id) }
                            }
                        } label: {
                            Label(recordingLabel, systemImage: recordingBusy ? "stop.circle" : "mic")
                        }.disabled(environment.recorder.phase == .finishing).accessibilityIdentifier("practice.record")
                        if environment.recorder.hasRecording {
                            Button(environment.recorder.isPlayingComparison ? "Stop recording playback" : "Listen to my recording") {
                                if environment.recorder.isPlayingComparison { environment.recorder.cancelComparisonPlayback() }
                                else {
                                    environment.playback.pause()
                                    Task {
                                        do { try await environment.recorder.playRecording() }
                                        catch is CancellationError {} catch { errorMessage = .from(.recordingFailed) }
                                    }
                                }
                            }.disabled(recordingBusy)
                            Button("Delete recording", role: .destructive) { environment.recorder.deleteLatest() }.disabled(recordingBusy)
                        }
                    } header: { Text("Try it aloud") } footer: { Text("Record yourself, then listen back. Your recording stays on this device.") }
                    Section {
                        Button("Revisit this ayah later") {
                            guard let ayah = currentAyah else { return }
                            do { try environment.store.markWeak(globalAyah: ayah, weak: true); showOptions = false }
                            catch { errorMessage = .from(.persistenceFailure) }
                        }
                    }.disabled(recordingBusy)
                }
            }
            .warmListChrome().navigationTitle("Practice tools").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOptions = false }.disabled(recordingBusy) } }
        }.interactiveDismissDisabled(recordingBusy)
    }

    private var recordingLabel: String {
        switch environment.recorder.phase {
        case .countdown(let count): "Starting in \(count) · Cancel"
        case .recording: "Stop recording"
        case .finishing: "Saving recording…"
        default: "Record myself"
        }
    }

    private var finishSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if finished {
                        WarmSymbol(systemName: "checkmark", size: 58)
                        Text("A little more,\na little closer.").font(.system(.largeTitle, design: .serif))
                        Text("You practiced \(passageLabel.lowercased()).").foregroundStyle(Color.secondaryWarm)
                        Button {
                            showFinish = false
                            environment.playback.stop()
                            dismiss()
                        } label: { Text("Done for today").frame(maxWidth: .infinity) }
                            .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("practice.done")
                        if let range = ranges.first, ranges.count == 1,
                           let first = verses.first, first.ayahInSurah > 1,
                           range.startGlobalAyah > (learningTarget?.range.startGlobalAyah ?? 1) {
                            Button("Include the previous ayah") {
                                showFinish = false
                                beginPractice(.clamped(start: range.startGlobalAyah - 1, end: range.endGlobalAyah))
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                        Button("Practice again") { finished = false; showFinish = false; restartPractice() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        if let next = nextRange {
                            Button("Next passage · \(LearningPassage.ayahLabel(next, catalog: environment.quran))") {
                                showFinish = false
                                beginPractice(next)
                            }.frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("practice.nextPassage")
                        } else if let learningTarget {
                            Text("You’ve reached the end of \(learningTarget.title(catalog: environment.quran)). Return anytime to revisit these ayahs.")
                                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                        } else if let first = verses.first, let surah = environment.quran.surah(number: first.surahNumber) {
                            Text("You’ve reached the end of \(surah.englishName). Return anytime to bring the ayahs together.")
                                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                            Button("Choose another surah") {
                                showFinish = false
                                environment.playback.stop()
                                environment.selectedTab = .quran
                                dismiss()
                            }.frame(maxWidth: .infinity, minHeight: 44)
                            Button("Review the whole surah") {
                                showFinish = false
                                beginPractice(.clamped(start: surah.startGlobalAyah, end: surah.endGlobalAyah))
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else {
                        Text("How did this passage feel?").font(.system(.title, design: .serif))
                        Text(passageLabel).foregroundStyle(Color.secondaryWarm)
                        Text("Think about all the ayahs in this passage. You can keep practicing for as long as you need.")
                            .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                        ratingButton("Needs more practice", detail: "I’d like to spend more time here.", symbol: "arrow.counterclockwise", rating: .needsWork)
                        ratingButton("Getting comfortable", detail: "I remembered with a little help.", symbol: "leaf", rating: .comfortable)
                        ratingButton("Recalled from memory", detail: "I recited these ayahs without looking.", symbol: "checkmark.circle", rating: .solid)
                        Button("Finish without rating") { complete(rating: nil) }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }.padding(26).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.appBrownText).background(Color.parchment.ignoresSafeArea())
            .toolbar {
                if !finished { ToolbarItem(placement: .cancellationAction) { Button("Keep practicing") { showFinish = false } } }
            }
        }
        .interactiveDismissDisabled(finished)
    }

    private func ratingButton(_ title: String, detail: String, symbol: String, rating: RecallRating) -> some View {
        Button { complete(rating: rating) } label: {
            WarmCard {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.title2).foregroundStyle(Color.bronze)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.headline)
                        Text(detail).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                    Spacer(minLength: 0)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("practice.rate.\(rating.rawValue)")
    }

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        if !resumesPlayback && !ownsPlayback { environment.playback.pause() }
        selectedAyah = destination.scrollToAyah ?? ranges.first?.startGlobalAyah
        if resumesPlayback {
            practice = environment.playback.activeSet
            readingRanges = environment.playback.passageRanges
            readingName = environment.playback.snapshot.setTitle
            selectedAyah = environment.playback.snapshot.currentGlobalAyah
        } else if let savedPractice {
            activate(savedPractice)
        } else if let initialPracticeRange {
            beginPractice(initialPracticeRange)
        }
    }

    private func beginPractice(_ requestedRange: VerseRange) {
        let range: VerseRange
        if let learningTarget {
            guard let bounded = try? VerseRange(
                startGlobalAyah: max(requestedRange.startGlobalAyah, learningTarget.range.startGlobalAyah),
                endGlobalAyah: min(requestedRange.endGlobalAyah, learningTarget.range.endGlobalAyah)
            ) else { return }
            range = bounded
        } else { range = requestedRange }
        do { let set = try environment.practice(for: range); activate(set) }
        catch { errorMessage = .from(.persistenceFailure) }
    }

    private func activate(_ set: PracticeSet) {
        savePosition()
        practice = set
        finished = false
        environment.playback.start(set: set, catalog: environment.quran, resume: true, allowStreaming: environment.settings.streamWhenMissing)
        // Recall always starts as an explicit choice in this session.
        if environment.playback.snapshot.hideArabic { environment.playback.toggleArabicHidden() }
        selectedAyah = environment.playback.snapshot.currentGlobalAyah
        environment.recorder.selectCollection(set.id)
        environment.activePracticeIsReview = isReview
        environment.activePracticeTargetID = learningTarget?.id
        if !isReview, let range = set.orderedPassages.first?.range { environment.settings.remember(range, targetID: learningTarget?.id) }
    }

    private func leavePractice() {
        savePosition()
        if let ayah = currentAyah, let verse = environment.quran.verse(globalAyah: ayah),
           let surah = environment.quran.surah(number: verse.surahNumber) {
            readingRanges = [.clamped(start: surah.startGlobalAyah, end: surah.endGlobalAyah)]
            readingName = surah.englishName
            selectedAyah = ayah
        }
        environment.playback.stop()
        practice = nil
        detachedFromTarget = true
        environment.activePracticeTargetID = nil
        finished = false
    }

    private func restartPractice() {
        guard let practice else { return }
        practice.lastGlobalAyah = ranges.first?.startGlobalAyah
        activate(practice)
    }

    private func togglePlayback() {
        if playing { environment.playback.pause(); return }
        if !ownsPlayback {
            environment.playback.startListening(title: title, passages: ranges, fromAyah: currentAyah,
                                                catalog: environment.quran, allowStreaming: environment.settings.streamWhenMissing)
        }
        environment.playback.resume()
    }

    private func select(_ ayah: Int) {
        selectedAyah = ayah
        if ownsPlayback { environment.playback.move(to: ayah) }
        savePosition()
    }

    private func step(_ offset: Int) {
        guard let ayah = currentAyah, let index = verses.firstIndex(where: { $0.globalAyah == ayah }), verses.indices.contains(index + offset) else { return }
        select(verses[index + offset].globalAyah)
    }

    private func savePosition() {
        guard let ayah = currentAyah else { return }
        if let practice {
            practice.lastGlobalAyah = ayah
            do { try environment.store.save() } catch { errorMessage = .from(.persistenceFailure) }
        } else { environment.settings.readingAyah = ayah }
    }

    private func complete(rating: RecallRating?) {
        guard let practice, !finished else { return }
        do {
            try environment.store.completePractice(practice, ayahs: verses.map(\.globalAyah),
                                                   rating: rating, lastAyah: currentAyah,
                                                   seconds: environment.playback.listeningSeconds,
                                                   repetitions: environment.playback.repetitionCount)
            if !isReview, rating == .solid, let next = nextRange { environment.settings.remember(next, targetID: learningTarget?.id) }
            finished = true
        } catch { errorMessage = .from(.persistenceFailure) }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<PracticeSettings, Value>, in practice: PracticeSet) -> Binding<Value> {
        Binding(get: { practice.settings[keyPath: keyPath] }, set: { value in
            var settings = practice.settings
            settings[keyPath: keyPath] = value
            environment.playback.applySettingsAndRestart(settings)
            do { try environment.store.save() } catch { errorMessage = .from(.persistenceFailure) }
        })
    }
}
