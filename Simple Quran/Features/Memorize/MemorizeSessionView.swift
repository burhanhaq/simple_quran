import SwiftData
import SwiftUI

/// The three steps of memorizing a passage. Suggested in order, but the user can move freely.
enum SessionStep: String, CaseIterable, Identifiable {
    case listen
    case reciteAlong
    case fromMemory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listen: String(localized: "Listen")
        case .reciteAlong: String(localized: "Recite along")
        case .fromMemory: String(localized: "From memory")
        }
    }

    var hint: String {
        switch self {
        case .listen: String(localized: "Listen a few times and follow the words.")
        case .reciteAlong: String(localized: "Recite with the reciter. Pause whenever you need.")
        case .fromMemory: String(localized: "Recite without looking. Tap an ayah to peek.")
        }
    }

    var next: SessionStep? {
        switch self {
        case .listen: .reciteAlong
        case .reciteAlong: .fromMemory
        case .fromMemory: nil
        }
    }
}

/// The user's own answer about a passage or an ayah. Nothing changes unless they give one.
enum CheckAnswer: String, Identifiable {
    case memorized
    case almost
    case stillLearning
    case stillSolid
    case shaky
    case forgot

    var id: String { rawValue }

    static func choices(for kind: SessionKind) -> [CheckAnswer] {
        switch kind {
        case .learn: [.memorized, .almost, .stillLearning]
        case .review: [.stillSolid, .shaky, .forgot]
        }
    }

    var rating: RecallRating {
        switch self {
        case .memorized, .stillSolid: .solid
        case .almost, .shaky: .comfortable
        case .stillLearning: .needsWork
        case .forgot: .again
        }
    }

    var title: String {
        switch self {
        case .memorized: String(localized: "Memorized")
        case .almost: String(localized: "Almost")
        case .stillLearning: String(localized: "Still learning")
        case .stillSolid: String(localized: "Still solid")
        case .shaky: String(localized: "Shaky")
        case .forgot: String(localized: "Forgot")
        }
    }

    var systemImage: String {
        switch self {
        case .memorized, .stillSolid: "checkmark.circle"
        case .almost, .shaky: "leaf"
        case .stillLearning, .forgot: "arrow.counterclockwise"
        }
    }
}

enum PracticePlaybackLifecycle {
    static func shouldPrepareNewSession(activeSetID: UUID?, currentGlobalAyah: Int?, openingSetID: UUID) -> Bool {
        activeSetID != openingSetID || currentGlobalAyah == nil
    }
}

/// A guided, never-blocking memorize session: listen, recite along, then recite from memory
/// and optionally say how it went. Leaving without answering keeps every ayah's status as it was.
struct MemorizeSessionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var progress: [VerseProgress]
    let route: SessionRoute

    @State private var practice: PracticeSet?
    @State private var range: VerseRange
    @State private var queue: [VerseRange]
    @State private var reviewsDone = 0
    @State private var step: SessionStep
    @State private var peeked: Set<Int> = []
    @State private var selectedAyah: Int?
    @State private var answer: CheckAnswer?
    @State private var adjusted: [Int: CheckAnswer] = [:]
    @State private var engaged = false
    /// Listening time already saved for this passage, so moving on never records it twice.
    @State private var committedSeconds: Double = 0
    @State private var initialized = false
    @State private var showPassage = false
    @State private var showOptions = false
    @State private var showAdjust = false
    @State private var errorMessage: UserFacingMessage?

    init(route: SessionRoute) {
        self.route = route
        _range = State(initialValue: route.range)
        _queue = State(initialValue: route.reviewQueue)
        _step = State(initialValue: route.kind == .review ? .fromMemory : .listen)
    }

    private var verses: [QuranVerse] { environment.quran.verses(in: range) }
    private var ownsPlayback: Bool { practice.map { environment.playback.activeSet?.id == $0.id } ?? false }
    private var currentAyah: Int? { ownsPlayback ? environment.playback.snapshot.currentGlobalAyah ?? selectedAyah : selectedAyah ?? verses.first?.globalAyah }
    private var playing: Bool { ownsPlayback && (environment.playback.snapshot.isPlaying || environment.playback.snapshot.isLoading) }
    private var hiddenAyahs: Set<Int> { step == .fromMemory ? Set(verses.map(\.globalAyah)).subtracting(peeked) : [] }
    private var plan: LearningTarget? { environment.settings.learningTargets.first { $0.id == route.planID } }
    private var recordingBusy: Bool {
        switch environment.recorder.phase {
        case .countdown, .recording, .finishing: true
        default: false
        }
    }
    private var surahTitle: String {
        verses.first.flatMap { environment.quran.surah(number: $0.surahNumber) }?.englishName ?? ""
    }
    private var nextPassage: VerseRange? {
        if route.kind == .review { return queue.first }
        if let plan {
            let index = ProgressIndex(progress.map(\.snapshot))
            return plan.passage(from: range.endGlobalAyah + 1, catalog: environment.quran, byPage: environment.settings.practiceByPage)
                ?? plan.nextPassage(catalog: environment.quran, byPage: environment.settings.practiceByPage) { $0 == range || index.status(of: $0) == .memorized }
        }
        return LearningPassage.next(after: range, catalog: environment.quran, byPage: environment.settings.practiceByPage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if verticalSizeClass == .compact {
                    HStack(spacing: 0) { text; controls.frame(width: 320) }
                } else {
                    text
                    controls
                }
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(surahTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .onAppear { initialize() }
            .onDisappear { environment.recorder.stopRecording(); environment.recorder.cancelComparisonPlayback() }
            .onChange(of: step) { _, newStep in
                peeked = []
                if newStep == .fromMemory { environment.playback.pause() }
            }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, ayah in
                guard ownsPlayback, let ayah else { return }
                selectedAyah = ayah
            }
            .sheet(isPresented: $showPassage) {
                PassagePickerView(startAyah: range.startGlobalAyah, currentRange: range, allowedRange: plan?.range) { newRange, byPage in
                    environment.settings.practiceByPage = byPage
                    move(to: newRange)
                }
            }
            .sheet(isPresented: $showOptions) { options }
            .sheet(isPresented: $showAdjust) { adjustSheet }
            .alert(errorMessage?.title ?? environment.playback.userMessage?.title ?? environment.recorder.userMessage?.title ?? "", isPresented: Binding(
                get: { errorMessage != nil || environment.playback.userMessage != nil || environment.recorder.userMessage != nil },
                set: { if !$0 { errorMessage = nil; environment.playback.userMessage = nil; environment.recorder.userMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(errorMessage?.message ?? environment.playback.userMessage?.message ?? environment.recorder.userMessage?.message ?? "")
            }
        }
        .tint(Color.bronze)
        .interactiveDismissDisabled(recordingBusy)
    }

    // MARK: - Layout

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if !dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                        Text(route.kind == .review ? reviewLabel : String(localized: "MEMORIZE"))
                            .font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Color.bronze)
                    }
                    Text(LearningPassage.ayahLabel(range, catalog: environment.quran))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.appBrownText)
                }
                Spacer(minLength: 0)
                Button("Change") { showPassage = true }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(recordingBusy).accessibilityIdentifier("session.change")
            }
            Picker("Step", selection: Binding(get: { step }, set: { step = $0; engaged = true })) {
                ForEach(SessionStep.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).disabled(recordingBusy).accessibilityIdentifier("session.step")
        }
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(Color.appWarmSurface)
    }

    private var reviewLabel: String {
        let total = reviewsDone + 1 + queue.count
        return total > 1 ? String(localized: "REVIEW \(reviewsDone + 1) OF \(total)") : String(localized: "REVIEW")
    }

    private var text: some View {
        QuranTextView(
            verses: verses,
            currentAyah: currentAyah,
            hiddenAyahs: hiddenAyahs,
            selectionEnabled: !recordingBusy,
            focusedAyah: selectedAyah,
            scrollToAyah: range.startGlobalAyah,
            onSelect: select
        ) { verse in
            let ayah = verse.globalAyah
            ForEach(CheckAnswer.choices(for: route.kind)) { choice in
                Button(choice.title, systemImage: adjusted[ayah] == choice ? "checkmark" : choice.systemImage) {
                    adjusted[ayah] = choice
                    engaged = true
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(step.hint).font(.footnote).foregroundStyle(Color.secondaryWarm)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 22) {
                Button { moveAyah(by: -1) } label: {
                    Image(systemName: "backward.end.fill").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Previous ayah").accessibilityIdentifier("session.previous")
                    .disabled(recordingBusy || currentAyah == verses.first?.globalAyah)
                Button { togglePlayback() } label: {
                    ZStack {
                        PlayGlyph(systemName: playing ? "pause.fill" : "play.fill", size: 56)
                        if ownsPlayback && environment.playback.snapshot.isLoading { ProgressView().tint(Color.goldButtonText) }
                    }
                }.accessibilityLabel(playing ? "Pause" : "Play").accessibilityIdentifier("session.play").disabled(recordingBusy)
                Button { moveAyah(by: 1) } label: {
                    Image(systemName: "forward.end.fill").font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Next ayah").accessibilityIdentifier("session.next")
                    .disabled(recordingBusy || currentAyah == verses.last?.globalAyah)
                if step != .listen { recordButton }
            }.frame(maxWidth: .infinity)
            if step == .fromMemory {
                checkCard
            } else if let next = step.next {
                Button { step = next; engaged = true } label: {
                    HStack { Text("Next: \(next.title)"); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
                }.buttonStyle(WarmButtonStyle()).disabled(recordingBusy).accessibilityIdentifier("session.nextStep")
            }
        }
        .buttonStyle(.plain).foregroundStyle(Color.bronze)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: 740)
        .background(Color.appWarmSurface)
        .overlay(alignment: .top) { Rectangle().fill(Color.warmBorder.opacity(0.6)).frame(height: 0.5) }
    }

    private var recordButton: some View {
        Button {
            if recordingBusy { environment.recorder.stopRecording() }
            else if let practice {
                environment.playback.pause()
                engaged = true
                Task { await environment.recorder.startRecording(collectionID: practice.id) }
            }
        } label: {
            Image(systemName: recordingBusy ? "stop.circle.fill" : "mic.circle")
                .font(.title2).frame(width: 44, height: 44)
        }
        .disabled(environment.recorder.phase == .finishing)
        .accessibilityLabel(recordingBusy ? "Stop recording" : "Record myself")
        .accessibilityIdentifier("session.record")
    }

    /// Optional and inline: answering is one tap, skipping is just tapping Done or Next.
    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How did it go?").font(.subheadline.weight(.semibold)).foregroundStyle(Color.appBrownText)
                Spacer()
                if environment.recorder.hasRecording {
                    Button(environment.recorder.isPlayingComparison ? "Stop" : "Hear myself") { toggleRecordingPlayback() }
                        .font(.footnote.weight(.semibold)).disabled(recordingBusy)
                }
            }
            HStack(spacing: 8) {
                ForEach(CheckAnswer.choices(for: route.kind)) { choice in
                    Button {
                        answer = answer == choice ? nil : choice
                        engaged = true
                    } label: {
                        Label(choice.title, systemImage: choice.systemImage)
                            .font(.footnote.weight(.semibold)).labelStyle(.titleOnly)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(answer == choice ? Color.olive : Color.appCollectedFill, in: Capsule())
                            .foregroundStyle(answer == choice ? Color.white : Color.appBrownText)
                    }
                    .accessibilityAddTraits(answer == choice ? .isSelected : [])
                    .accessibilityIdentifier("session.answer.\(choice.rawValue)")
                }
            }
            HStack {
                Button(adjusted.isEmpty ? "Some ayahs were different" : "\(adjusted.count) ayahs adjusted") { showAdjust = true }
                    .font(.footnote).frame(minHeight: 36).accessibilityIdentifier("session.adjust")
                Spacer()
                if let next = nextPassage {
                    Button { advance(to: next) } label: {
                        Label(route.kind == .review ? "Next review" : "Next passage", systemImage: "arrow.right").font(.footnote.weight(.semibold))
                    }.frame(minHeight: 36).accessibilityIdentifier("session.nextPassage")
                        .accessibilityHint(LearningPassage.referenceLabel(next, catalog: environment.quran))
                }
            }
        }.disabled(recordingBusy)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { leave(stopPlayback: false) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 32) }
                .accessibilityLabel("Close").accessibilityIdentifier("session.close").disabled(recordingBusy)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Repeat and pause", systemImage: "repeat") { showOptions = true }
                Button("Read the whole surah", systemImage: "book") {
                    commit()
                    environment.playback.stop()
                    if let verse = verses.first { environment.openReader(.surah(number: verse.surahNumber, scrollToAyah: verse.globalAyah)) }
                }
                ReadingLayoutMenu()
                Button("Download this audio", systemImage: "arrow.down.circle") {
                    environment.downloads.download(ayahs: verses.map(\.globalAyah))
                }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                .accessibilityLabel("Session options").disabled(recordingBusy)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { leave(stopPlayback: true) }
                .disabled(recordingBusy).accessibilityIdentifier("session.done")
        }
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
                    }
                    if environment.recorder.hasRecording {
                        Section("Your recording") {
                            Button("Delete recording", role: .destructive) { environment.recorder.deleteLatest() }
                        }
                    }
                }
            }
            .warmListChrome().navigationTitle("Repeat and pause").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOptions = false } } }
        }.presentationDetents([.medium, .large])
    }

    private var adjustSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("Only change the ayahs that went differently. The rest follow your answer for the passage.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.listRowBackground(Color.clear)
                ForEach(verses) { verse in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ayah \(verse.ayahInSurah)").font(.headline)
                        Picker("Ayah \(verse.ayahInSurah)", selection: Binding(
                            get: { adjusted[verse.globalAyah] },
                            set: { adjusted[verse.globalAyah] = $0; engaged = true }
                        )) {
                            Text("Same").tag(CheckAnswer?.none)
                            ForEach(CheckAnswer.choices(for: route.kind)) { Text($0.title).tag(Optional($0)) }
                        }.pickerStyle(.segmented)
                    }.padding(.vertical, 6).warmListRow()
                }
            }
            .warmListChrome().navigationTitle("Adjust ayahs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAdjust = false } } }
        }
    }

    // MARK: - Actions

    private func initialize() {
        guard !initialized else { return }
        initialized = true
        if route.resumePlayback, let active = environment.playback.activeSet {
            practice = active
            selectedAyah = environment.playback.snapshot.currentGlobalAyah
            environment.recorder.selectCollection(active.id)
            environment.lastSession = route
        } else if let saved = route.savedPractice {
            activate(saved, resume: true)
        } else {
            begin(range)
        }
    }

    private func begin(_ newRange: VerseRange) {
        do { activate(try environment.practice(for: newRange), resume: false) }
        catch { errorMessage = .from(.persistenceFailure) }
    }

    private func activate(_ set: PracticeSet, resume: Bool) {
        practice = set
        committedSeconds = 0
        if let first = set.orderedPassages.first?.range.startGlobalAyah, let last = set.orderedPassages.last?.range.endGlobalAyah {
            range = .clamped(start: first, end: last)
        }
        if PracticePlaybackLifecycle.shouldPrepareNewSession(activeSetID: environment.playback.activeSet?.id,
                                                              currentGlobalAyah: environment.playback.snapshot.currentGlobalAyah,
                                                              openingSetID: set.id) {
            environment.playback.start(set: set, catalog: environment.quran, resume: resume, allowStreaming: environment.settings.streamWhenMissing)
        }
        // Hiding is driven by the session step, never by the saved playback flag.
        if environment.playback.snapshot.hideArabic { environment.playback.toggleArabicHidden() }
        selectedAyah = environment.playback.snapshot.currentGlobalAyah ?? range.startGlobalAyah
        environment.recorder.selectCollection(set.id)
        environment.lastSession = SessionRoute(range: range, kind: route.kind, planID: route.planID, reviewQueue: queue)
        if route.kind == .learn { environment.settings.remember(range, targetID: route.planID) }
    }

    /// Saves activity and any answers the user gave. With no answer, statuses stay exactly as they were.
    private func commit() {
        guard engaged || environment.playback.listeningSeconds > committedSeconds, let practice else { return }
        let ayahs = verses.map(\.globalAyah)
        let index = ProgressIndex(progress.map(\.snapshot))
        do {
            if route.kind == .learn { try environment.store.beginLearning(ayahs: ayahs) }
            try environment.store.completePractice(practice, ayahs: ayahs, rating: nil, lastAyah: currentAyah,
                                                   seconds: environment.playback.listeningSeconds,
                                                   repetitions: environment.playback.repetitionCount)
            var byAnswer: [CheckAnswer: [Int]] = [:]
            for ayah in ayahs {
                guard let given = adjusted[ayah] ?? answer else { continue }
                // A review only speaks for ayahs that were memorized going in.
                if route.kind == .review && index.status(of: ayah) != .memorized { continue }
                byAnswer[given, default: []].append(ayah)
            }
            for (given, list) in byAnswer { try environment.store.applyRating(given.rating, ayahs: list, now: .now) }
            if route.kind == .learn, answer == .memorized, let next = nextPassage {
                environment.settings.remember(next, targetID: route.planID)
            }
        } catch { errorMessage = .from(.persistenceFailure) }
        engaged = false
        committedSeconds = environment.playback.listeningSeconds
        answer = nil
        adjusted = [:]
    }

    private func advance(to next: VerseRange) {
        if route.kind == .review {
            queue.removeFirst()
            reviewsDone += 1
        }
        move(to: next)
    }

    private func move(to newRange: VerseRange) {
        commit()
        range = newRange
        peeked = []
        step = route.kind == .review ? .fromMemory : .listen
        engaged = false
        begin(newRange)
    }

    private func leave(stopPlayback: Bool) {
        commit()
        if stopPlayback {
            environment.playback.stop()
            environment.lastSession = nil
        }
        dismiss()
    }

    private func select(_ ayah: Int) {
        if step == .fromMemory {
            if peeked.contains(ayah) { peeked.remove(ayah) } else { peeked.insert(ayah) }
            return
        }
        selectedAyah = ayah
        if ownsPlayback { environment.playback.move(to: ayah) }
    }

    private func moveAyah(by offset: Int) {
        guard let ayah = currentAyah, let index = verses.firstIndex(where: { $0.globalAyah == ayah }), verses.indices.contains(index + offset) else { return }
        let target = verses[index + offset].globalAyah
        selectedAyah = target
        if ownsPlayback { environment.playback.move(to: target) }
    }

    private func togglePlayback() {
        if playing { environment.playback.pause(); return }
        engaged = true
        if !ownsPlayback, let practice {
            environment.playback.start(set: practice, catalog: environment.quran, resume: true, allowStreaming: environment.settings.streamWhenMissing)
        }
        environment.playback.resume()
    }

    private func toggleRecordingPlayback() {
        if environment.recorder.isPlayingComparison { environment.recorder.cancelComparisonPlayback(); return }
        environment.playback.pause()
        Task {
            do { try await environment.recorder.playRecording() }
            catch is CancellationError {} catch { errorMessage = .from(.recordingFailed) }
        }
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
