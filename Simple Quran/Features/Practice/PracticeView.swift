import SwiftUI
import UIKit

struct PracticeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let practiceSet: PracticeSet
    @State private var showRating = false
    @State private var comparisonPlayer = AudioPreviewPlayer()

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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(String(localized: "Repeats")) {
                        ForEach(RepeatCount.ayahPresets, id: \.self) { value in
                            Button(String(localized: "Ayah \(value.label)")) {
                                apply { $0.ayahRepeatCount = value }
                            }
                        }
                    }
                }
            }
            .onAppear(perform: start)
            .onDisappear {
                environment.playback.pause()
                environment.recorder.stopRecording()
                environment.recorder.cancelComparisonPlayback()
                comparisonPlayer.cancel()
            }
            .onChange(of: environment.playback.snapshot.currentGlobalAyah) { _, ayah in
                comparisonPlayer.cancel()
                environment.recorder.cancelComparisonPlayback()
                if let ayah { environment.recorder.selectAyah(ayah) }
            }
            .sheet(isPresented: $showRating) {
                ratingSheet
            }
            .overlay(alignment: .top) {
                if environment.recorder.phase == .recording {
                    recordingBanner
                }
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

    private var verseList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(environment.playback.versesInSet) { verse in
                        QuranAyahText(
                            verse: verse,
                            isCurrent: verse.globalAyah == environment.playback.snapshot.currentGlobalAyah,
                            hidden: environment.playback.snapshot.hideArabic && verse.globalAyah == environment.playback.snapshot.currentGlobalAyah
                        )
                        .id(verse.globalAyah)
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
        VStack(spacing: 12) {
            if !environment.playback.snapshot.repetitionLabel.isEmpty {
                Text(String(localized: "Ayah repeat \(environment.playback.snapshot.repetitionLabel)"))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryWarm)
            }
            HStack(spacing: 22) {
                Button { environment.playback.skipBack() } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel(String(localized: "Previous ayah"))
                Button {
                    environment.playback.snapshot.isPlaying ? environment.playback.pause() : environment.playback.resume()
                } label: {
                    Image(systemName: environment.playback.snapshot.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }
                .accessibilityIdentifier("practice.play")
                .accessibilityLabel(environment.playback.snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                Button { environment.playback.skipForward() } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel(String(localized: "Next ayah"))
            }
            .foregroundStyle(Color.gold)
            HStack {
                Toggle(String(localized: "Hide Arabic"), isOn: hideBinding)
                    .tint(Color.olive)
                Button(String(localized: "Weak")) {
                    if let ayah = environment.playback.snapshot.currentGlobalAyah {
                        try? environment.store.markWeak(globalAyah: ayah, weak: true)
                    }
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Button(recordButtonTitle) { Task { await toggleRecord() } }
                    .buttonStyle(.borderedProminent)
                    .tint(environment.recorder.phase == .recording ? Color.dangerWarm : Color.olive)
                    .accessibilityIdentifier("practice.record")
                if environment.recorder.phase == .comparing {
                    Button(String(localized: "Compare")) { Task { await runComparison() } }
                        .buttonStyle(.bordered)
                    Button(String(localized: "Delete take"), role: .destructive) {
                        environment.recorder.deleteLatest()
                    }
                }
            }
            Button(String(localized: "Finish & rate")) { showRating = true }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var recordingBanner: some View {
        Text(String(localized: "Recording…"))
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.dangerWarm)
            .accessibilityAddTraits(.updatesFrequently)
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
                    Button(String(localized: "Skip")) { showRating = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var hideBinding: Binding<Bool> {
        Binding(
            get: { environment.playback.snapshot.hideArabic },
            set: { _ in environment.playback.toggleArabicHidden() }
        )
    }

    private var recordButtonTitle: String {
        switch environment.recorder.phase {
        case .recording: String(localized: "Stop")
        case .finishing: String(localized: "Saving…")
        case .countdown(let value): String(localized: "\(value)")
        default: String(localized: "Record ayah")
        }
    }

    private func start() {
        environment.playback.start(
            set: practiceSet,
            catalog: environment.quran,
            resume: true,
            allowStreaming: environment.settings.streamWhenMissing || environment.downloads.downloadedCount(in: practiceSet.orderedPassages.flatMap(\.range.globalAyahs)) == practiceSet.orderedPassages.map(\.range.count).reduce(0, +)
        )
        environment.playback.session = try? environment.store.startSession(for: practiceSet)
        if let ayah = environment.playback.snapshot.currentGlobalAyah {
            environment.recorder.selectAyah(ayah)
        }
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
            environment.playback.pause()
            guard let ayah = environment.playback.snapshot.currentGlobalAyah else { return }
            await environment.recorder.startRecording(globalAyah: ayah)
        }
    }

    private func runComparison() async {
        guard let ayah = environment.playback.snapshot.currentGlobalAyah else { return }
        environment.playback.pause()
        do {
            try await playReciter(ayah)
            try await environment.recorder.playLatest()
            try await playReciter(ayah)
        } catch is CancellationError {
            return
        } catch {
            environment.playback.userMessage = UserFacingMessage.from(.audioUnavailable)
        }
    }

    private func playReciter(_ ayah: Int) async throws {
        let url = environment.downloads.fileStore.urlIfReady(reciter: environment.audioSource.reciter, globalAyah: ayah)
            ?? (try? environment.audioSource.remoteURL(for: ayah))
        guard let url else { throw AppError.audioUnavailable }
        try await comparisonPlayer.play(url: url)
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
}
