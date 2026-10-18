import SwiftData
import SwiftUI

/// The surah screen's sheet: the player and overview while reading, the coach while memorizing.
/// Everything else the screen presents comes from here, since the sheet is always up.
struct SurahSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    let model: SurahScreenModel

    private var index: ProgressIndex { ProgressIndex(progress.map(\.snapshot)) }

    var body: some View {
        @Bindable var model = model
        let index = index
        Group {
            if let focus = model.focus {
                FocusCoach(model: model, focus: focus, index: index)
            } else {
                ReadingOverview(model: model, index: index)
            }
        }
        .foregroundStyle(Color.appBrownText)
        .sheet(isPresented: $model.showsOptions) { RepeatOptions(model: model) }
        .sheet(isPresented: $model.showsAdjust) { AdjustAyahs(model: model) }
        .sheet(isPresented: $model.showsPassagePicker) {
            if let focus = model.focus {
                PassagePickerView(startAyah: focus.range.startGlobalAyah, currentRange: focus.range, allowedRange: model.planRange) { newRange, size in
                    if let size { environment.settings.pieceSize = size }
                    model.move(to: newRange, index: index)
                }
            }
        }
        .alert(alertTitle, isPresented: Binding(
            get: { model.errorMessage != nil || environment.playback.userMessage != nil
                || environment.recorder.userMessage != nil || environment.downloads.userMessage != nil },
            set: {
                guard !$0 else { return }
                model.errorMessage = nil
                environment.playback.userMessage = nil
                environment.recorder.userMessage = nil
                environment.downloads.userMessage = nil
            }
        )) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
    }

    private var message: UserFacingMessage? {
        model.errorMessage ?? environment.playback.userMessage ?? environment.recorder.userMessage ?? environment.downloads.userMessage
    }
    private var alertTitle: String { message?.title ?? "" }
    private var alertMessage: String { message?.message ?? "" }
}

// MARK: - Reading

private struct ReadingOverview: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel
    let index: ProgressIndex

    private var span: VerseRange? { model.span }
    private var memorized: Int { span.map { index.count(.memorized, in: $0) } ?? 0 }
    private var total: Int { span?.count ?? 0 }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                peekBar
                header
                status
                PieceStrip(model: model, index: index)
                actions
                knownRow
                piecesList
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 28)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.snappy, value: model.undo?.id)
    }

    // The part that shows at peek height: what this is, where playback is, and play.
    private var peekBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title).font(.headline).lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    statusRow(statusLine).fixedSize()
                    statusRow(compactStatusLine)
                }
                .font(.caption).foregroundStyle(Color.secondaryWarm)
            }
            Spacer(minLength: 0)
            Button { model.step(by: -1) } label: {
                Image(systemName: "backward.end.fill").font(.body).frame(width: 40, height: 44)
            }
            .disabled(!model.canStepBack)
            .accessibilityLabel("Previous ayah").accessibilityIdentifier("reader.previous")
            Button { model.togglePlayback() } label: {
                ZStack {
                    PlayGlyph(systemName: model.isPlaying ? "pause.fill" : "play.fill", size: 48)
                    if model.isLoading { ProgressView().tint(Color.goldButtonText) }
                }
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play").accessibilityIdentifier("quran.play")
            Button { model.step(by: 1) } label: {
                Image(systemName: "forward.end.fill").font(.body).frame(width: 40, height: 44)
            }
            .disabled(!model.canStepForward)
            .accessibilityLabel("Next ayah").accessibilityIdentifier("reader.next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.bronze)
    }

    private func statusRow(_ status: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(status).lineLimit(1)
            if let position {
                Text(verbatim: "·")
                Text(position).monospacedDigit().lineLimit(1).accessibilityIdentifier("reader.position")
            }
        }
    }

    private var compactStatusLine: String {
        guard memorized > 0, memorized < total else { return statusLine }
        return String(localized: "\(memorized)/\(total)")
    }

    private var position: String? {
        guard let ayah = model.currentAyah, let position = model.passage.indexByAyah[ayah] else { return nil }
        return String(localized: "Ayah \(position + 1) of \(model.verses.count)")
    }

    private var statusLine: String {
        if total > 0 && memorized == total { return String(localized: "Memorized") }
        if memorized > 0 { return String(localized: "\(memorized) of \(total) memorized") }
        let learning = span.map { index.count(.learning, in: $0) } ?? 0
        return learning > 0 ? MemorizationStatus.learning.title : MemorizationStatus.notStarted.title
    }

    private var statusColor: Color {
        if total > 0 && memorized == total { return Color.olive }
        let started = span.map { index.status(of: $0) != .notStarted } ?? false
        return started ? Color.bronze : Color.warmBorder
    }

    @ViewBuilder
    private var header: some View {
        if case .surah(let number, _) = model.destination, model.readingRanges == nil, let surah = environment.quran.surah(number: number) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(surah.translation).font(.system(.title3, design: .serif))
                    Text(surahDetails(surah)).font(.caption).foregroundStyle(Color.secondaryWarm)
                }
                Spacer(minLength: 8)
                Text(surah.arabicName).font(.quran(.listName)).multilineTextAlignment(.trailing)
            }
        } else if let span {
            Text(LearningPassage.referenceLabel(span, catalog: environment.quran))
                .font(.system(.title3, design: .serif)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func surahDetails(_ surah: Surah) -> String {
        let verses = model.verses
        var parts = [String(localized: "\(surah.ayahCount) ayahs"), surah.revelation]
        if let first = verses.first, let last = verses.last {
            parts.append(first.page == last.page ? String(localized: "Page \(first.page)") : String(localized: "Pages \(first.page)–\(last.page)"))
        }
        return parts.joined(separator: " · ")
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(memorized), total: Double(max(total, 1))).tint(Color.olive)
            Text(statusDetails).font(.caption).foregroundStyle(Color.secondaryWarm)
        }
    }

    private var statusDetails: String {
        guard let span else { return "" }
        var parts = [String(localized: "\(memorized) of \(total) ayahs memorized")]
        let learning = index.count(.learning, in: span)
        if learning > 0 { parts.append(String(localized: "\(learning) learning")) }
        let refresh = index.needsRefreshCount(in: span)
        if refresh > 0 { parts.append(String(localized: "\(refresh) need a refresh")) }
        return parts.joined(separator: " · ")
    }

    private var action: SurahAction? { SurahAction.make(pieces: model.pieces, chosen: model.chosenPiece, index: index) }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { model.togglePlayback() } label: {
                Label(model.isPlaying ? "Pause" : "Listen", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle(emphasis: .secondary)).accessibilityIdentifier("surah.listen")
            if let action {
                Button { model.perform(action) } label: {
                    Text(title(for: action)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }
                .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("surah.memorize")
            }
        }
    }

    private func title(for action: SurahAction) -> String {
        switch action {
        case .start: return String(localized: "Start memorizing")
        case .continue(let piece):
            let label = LearningPassage.ayahLabel(piece, catalog: environment.quran)
            return model.chosenPiece == nil ? String(localized: "Continue · \(label)") : String(localized: "Memorize \(label)")
        case .revise(let pieces):
            guard model.chosenPiece != nil, let piece = pieces.first else { return String(localized: "Revise") }
            return String(localized: "Revise \(LearningPassage.ayahLabel(piece, catalog: environment.quran))")
        }
    }

    @ViewBuilder
    private var knownRow: some View {
        if model.undo != nil {
            HStack {
                Label("Marked as memorized", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.olive)
                Spacer()
                Button("Undo") { model.undoMark() }
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("surah.undo")
            }
            .padding(.horizontal, 18).frame(minHeight: 48)
            .background(Color.appCollectedFill, in: Capsule())
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let span, memorized < total {
            Button(knownTitle) { model.markKnown(span, index: index) }
                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("surah.markKnown")
        }
    }

    private var knownTitle: String {
        guard model.readingRanges == nil else { return String(localized: "I already know these ayahs") }
        switch model.destination {
        case .surah: return String(localized: "I already know this surah")
        case .juz: return String(localized: "I already know this juz")
        case .page: return String(localized: "I already know this page")
        }
    }

    private var piecesList: some View {
        let groups = model.groups
        return ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 10) {
                Text(groups.count == 1 ? String(localized: "Memorize in parts") : group.surah.displayName)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
                // Lazy so Al-Baqarah's hundred pieces only build as they scroll into view.
                LazyVStack(spacing: 0) {
                    ForEach(group.pieces, id: \.self) { piece in
                        PieceRow(model: model, piece: piece, index: index)
                        if piece != group.pieces.last { Divider().padding(.leading, 52) }
                    }
                }
                .background(Color.parchment.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.tightRadius))
            }
        }
    }
}

/// The surah drawn as its pieces, each colored by how far along it is. Tapping one shows it in the text.
private struct PieceStrip: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel
    let index: ProgressIndex

    /// Up to this many pieces share the width; longer surahs scroll.
    private static let fittingCount = 18

    var body: some View {
        let pieces = model.pieces
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pieces.count == 1 ? String(localized: "1 piece") : String(localized: "\(pieces.count) pieces"))
                    .font(.caption.weight(.medium)).foregroundStyle(Color.secondaryWarm)
                Spacer()
                Menu {
                    Picker("Piece size", selection: Bindable(environment.settings).pieceSize) {
                        ForEach(PieceSize.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(environment.settings.pieceSize.title)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }.font(.caption.weight(.semibold))
                }
                .accessibilityIdentifier("surah.pieceSize")
            }
            if pieces.count <= Self.fittingCount {
                HStack(spacing: 4) {
                    ForEach(pieces, id: \.self) { segment($0).frame(maxWidth: .infinity) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 4) {
                        ForEach(pieces, id: \.self) { segment($0).frame(width: 16) }
                    }
                }
            }
            if let chosen = model.chosenPiece {
                Text("\(LearningPassage.ayahLabel(chosen, catalog: environment.quran)) · \(index.status(of: chosen).title)")
                    .font(.caption).foregroundStyle(Color.secondaryWarm)
            }
        }
    }

    private func segment(_ piece: VerseRange) -> some View {
        let status = index.status(of: piece)
        let chosen = model.chosenPiece == piece
        return Button { withAnimation(.snappy) { model.choose(piece) } } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill(status))
                .frame(height: chosen ? 20 : 14)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(chosen ? Color.appBrownText : .clear, lineWidth: 1.5)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LearningPassage.ayahLabel(piece, catalog: environment.quran)), \(status.title)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func fill(_ status: MemorizationStatus) -> Color {
        switch status {
        case .memorized: Color.olive
        case .learning: Color.bronze.opacity(0.6)
        case .notStarted: Color.warmBorder.opacity(0.55)
        }
    }
}

private struct PieceRow: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel
    let piece: VerseRange
    let index: ProgressIndex

    var body: some View {
        let status = index.status(of: piece)
        let due = index.isDue(piece)
        Button { model.open(piece, index: index) } label: {
            HStack(spacing: 14) {
                Image(systemName: due ? "arrow.counterclockwise" : status.systemImage)
                    .foregroundStyle(status == .notStarted ? Color.secondaryWarm : Color.olive).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LearningPassage.ayahLabel(piece, catalog: environment.quran)).font(.headline)
                    Text(statusText(status: status, due: due)).font(.caption).foregroundStyle(Color.secondaryWarm)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondaryWarm)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("surah.piece.\(piece.startGlobalAyah)")
        .contextMenu {
            if status != .memorized {
                Button("I know these ayahs", systemImage: MemorizationStatus.memorized.systemImage) { model.markKnown(piece, index: index) }
            } else {
                Button("These need a refresh", systemImage: "arrow.counterclockwise") { model.markNeedsRefresh(piece) }
            }
        }
    }

    private func statusText(status: MemorizationStatus, due: Bool) -> String {
        if due { return String(localized: "Ready to review") }
        if status == .memorized { return status.title }
        let memorized = index.count(.memorized, in: piece)
        return memorized > 0 ? String(localized: "\(memorized) of \(piece.count) memorized") : status.title
    }
}

// MARK: - Memorizing a piece

/// Coaches one piece in place: the steps as a path, the player with its repeat count, and the
/// optional check. Answering is one tap; skipping it is just Done or Next.
private struct FocusCoach: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let model: SurahScreenModel
    let focus: MemorizeFocus
    let index: ProgressIndex

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                StepPath(current: focus.step) { model.setStep($0) }
                    .disabled(model.recordingBusy)
                Text(focus.step.hint).font(.footnote).foregroundStyle(Color.secondaryWarm)
                controls
                if focus.step == .fromMemory {
                    checkCard
                } else if let next = focus.step.next {
                    Button { model.setStep(next) } label: {
                        HStack { Text("Next: \(next.title)"); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WarmButtonStyle()).disabled(model.recordingBusy).accessibilityIdentifier("session.nextStep")
                }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 24)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// One row when it fits; with large text the buttons move under the passage name.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                passageName
                Spacer(minLength: 0)
                headerButtons
            }
            VStack(alignment: .leading, spacing: 4) {
                passageName
                HStack(spacing: 20) { headerButtons }
            }
        }
    }

    private var passageName: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Color.bronze)
            Text(LearningPassage.referenceLabel(focus.range, catalog: environment.quran))
                .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var headerButtons: some View {
        Button("Change") { model.showsPassagePicker = true }
            .font(.subheadline).frame(minHeight: 44)
            .disabled(model.recordingBusy).accessibilityIdentifier("session.change")
        Button("Done") { model.finishFocus(index: index) }
            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            .disabled(model.recordingBusy).accessibilityIdentifier("session.done")
    }

    private var label: String {
        if focus.kind == .review {
            let total = focus.reviewsDone + 1 + focus.queue.count
            return total > 1 ? String(localized: "REVIEW \(focus.reviewsDone + 1) OF \(total)") : String(localized: "REVIEW")
        }
        let pieces = model.pieces
        if let position = pieces.firstIndex(of: focus.range), pieces.count > 1 {
            return String(localized: "PIECE \(position + 1) OF \(pieces.count)")
        }
        return String(localized: "MEMORIZE")
    }

    private var controls: some View {
        HStack(spacing: verticalSizeClass == .compact ? 10 : 18) {
            Button { model.step(by: -1) } label: {
                Image(systemName: "backward.end.fill").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous ayah").accessibilityIdentifier("session.previous")
            .disabled(model.recordingBusy || !model.canStepBack)
            Button { model.togglePlayback() } label: {
                ZStack {
                    PlayGlyph(systemName: model.isPlaying ? "pause.fill" : "play.fill", size: 56)
                    if model.isLoading { ProgressView().tint(Color.goldButtonText) }
                }
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play").accessibilityIdentifier("session.play")
            .disabled(model.recordingBusy)
            Button { model.step(by: 1) } label: {
                Image(systemName: "forward.end.fill").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next ayah").accessibilityIdentifier("session.next")
            .disabled(model.recordingBusy || !model.canStepForward)
            if focus.step != .listen { recordButton }
            if let practice = focus.practice { RepeatChip(model: model, practice: practice) }
        }
        .buttonStyle(.plain).foregroundStyle(Color.bronze)
        .frame(maxWidth: .infinity)
    }

    private var recordButton: some View {
        Button { model.toggleRecording() } label: {
            Image(systemName: model.recordingBusy ? "stop.circle.fill" : "mic.circle")
                .font(.title2).frame(width: 44, height: 44)
        }
        .disabled(environment.recorder.phase == .finishing)
        .accessibilityLabel(model.recordingBusy ? "Stop recording" : "Record myself")
        .accessibilityIdentifier("session.record")
    }

    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How did it go?").font(.subheadline.weight(.semibold))
                Spacer()
                if environment.recorder.hasRecording {
                    Button(environment.recorder.isPlayingComparison ? "Stop" : "Hear myself") { model.toggleRecordingPlayback() }
                        .font(.footnote.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                ForEach(CheckAnswer.choices(for: focus.kind)) { choice in
                    let selected = focus.answer == choice
                    Button { model.answer(choice) } label: {
                        Text(choice.title)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selected ? Color.olive : Color.appCollectedFill, in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.appBrownText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("session.answer.\(choice.rawValue)")
                }
            }
            HStack {
                Button(focus.adjusted.isEmpty ? "Some ayahs were different" : "\(focus.adjusted.count) ayahs adjusted") { model.showsAdjust = true }
                    .font(.footnote).frame(minHeight: 36).accessibilityIdentifier("session.adjust")
                Spacer()
                if let next = model.nextPassage(index: index) {
                    Button { model.advance(to: next, index: index) } label: {
                        Label(focus.kind == .review ? "Next review" : "Next piece", systemImage: "arrow.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(minHeight: 36).accessibilityIdentifier("session.nextPassage")
                    .accessibilityHint(LearningPassage.referenceLabel(next, catalog: environment.quran))
                }
            }
        }
        .disabled(model.recordingBusy)
    }
}

/// Listen → Recite along → From memory, as a path the user can jump along. With large text
/// the steps stack instead, so the coach never grows wider than the screen.
private struct StepPath: View {
    let current: SessionStep
    let onSelect: (SessionStep) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(SessionStep.allCases) { step in
                    button(step).fixedSize()
                    if step != SessionStep.allCases.last {
                        Rectangle().fill(isDone(step) ? Color.olive.opacity(0.6) : Color.warmBorder)
                            .frame(minWidth: 6, maxWidth: .infinity, maxHeight: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SessionStep.allCases) { button($0) }
            }
        }
    }

    private func isDone(_ step: SessionStep) -> Bool {
        (SessionStep.allCases.firstIndex(of: step) ?? 0) < (SessionStep.allCases.firstIndex(of: current) ?? 0)
    }

    private func button(_ step: SessionStep) -> some View {
        Button { onSelect(step) } label: {
            HStack(spacing: 5) {
                Image(systemName: isDone(step) ? "checkmark.circle.fill" : step == current ? "circle.inset.filled" : "circle")
                    .font(.caption)
                Text(step.title).font(.caption.weight(step == current ? .semibold : .regular))
            }
            .foregroundStyle(step == current ? Color.appBrownText : isDone(step) ? Color.olive : Color.secondaryWarm)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(step == current ? .isSelected : [])
        .accessibilityIdentifier("session.step.\(step.rawValue)")
    }
}

/// The repeat count stays in view so it's never a surprise; the full options are one tap further.
private struct RepeatChip: View {
    let model: SurahScreenModel
    let practice: PracticeSet

    var body: some View {
        let repeats = practice.settings.ayahRepeatCount
        Menu {
            Picker("Repeat each ayah", selection: model.setting(\.ayahRepeatCount, in: practice)) {
                ForEach(RepeatCount.ayahPresets) { Text($0.label).tag($0) }
            }
            Button("Repeat and pause", systemImage: "slider.horizontal.3") { model.showsOptions = true }
        } label: {
            Text(repeats.label).font(.subheadline.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 32)
                .background(Color.appCollectedFill, in: Capsule())
        }
        .disabled(model.recordingBusy)
        .accessibilityLabel("Repeat each ayah, \(repeats.label)")
        .accessibilityIdentifier("session.repeat")
    }
}

private struct RepeatOptions: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel

    var body: some View {
        NavigationStack {
            Form {
                if let practice = model.focus?.practice {
                    Section("Listen and repeat") {
                        Picker("Repeat each ayah", selection: model.setting(\.ayahRepeatCount, in: practice)) {
                            ForEach(RepeatCount.ayahPresets) { Text($0.label).tag($0) }
                        }
                        Picker("Repeat passage", selection: model.setting(\.setRepeatCount, in: practice)) {
                            ForEach(RepeatCount.setPresets) { Text($0.label).tag($0) }
                        }
                        Stepper("Pause between ayahs: \(practice.settings.pauseSeconds)s", value: model.setting(\.pauseSeconds, in: practice), in: 0...5)
                        Toggle("Move to the next ayah myself", isOn: model.setting(\.advanceManually, in: practice))
                    }
                    if environment.recorder.hasRecording {
                        Section("Your recording") {
                            Button("Delete recording", role: .destructive) { environment.recorder.deleteLatest() }
                        }
                    }
                }
            }
            .warmListChrome().navigationTitle("Repeat and pause").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.showsOptions = false } } }
        }
        .presentationDetents([.medium, .large])
        .tint(Color.bronze)
    }
}

private struct AdjustAyahs: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Only change the ayahs that went differently. The rest follow your answer for the passage.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.listRowBackground(Color.clear)
                if let focus = model.focus {
                    ForEach(environment.quran.verses(in: focus.range)) { verse in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Ayah \(verse.ayahInSurah)").font(.headline)
                            Picker("Ayah \(verse.ayahInSurah)", selection: Binding(
                                get: { model.focus?.adjusted[verse.globalAyah] },
                                set: { model.adjust(verse.globalAyah, to: $0) }
                            )) {
                                Text("Same").tag(CheckAnswer?.none)
                                ForEach(CheckAnswer.choices(for: focus.kind)) { Text($0.title).tag(Optional($0)) }
                            }.pickerStyle(.segmented)
                        }.padding(.vertical, 6).warmListRow()
                    }
                }
            }
            .warmListChrome().navigationTitle("Adjust ayahs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.showsAdjust = false } } }
        }
        .tint(Color.bronze)
    }
}
