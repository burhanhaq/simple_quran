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
    private var freshness: Freshness? { span.flatMap { index.freshness(of: $0, cycle: environment.settings.revisionCycle) } }
    /// A short surah is one piece, so there are no parts to list.
    private var hasParts: Bool { model.pieces.count > 1 }

    var body: some View {
        ScrollView {
            Group {
                // Lazy only for a long parts list. A fitted sheet measures its content, and a lazy
                // stack estimates the rows it hasn't built, so the height would shift with the sheet.
                if hasParts {
                    LazyVStack(alignment: .leading, spacing: 22) { sections }
                } else {
                    VStack(alignment: .leading, spacing: 22) { sections }
                }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, hasParts ? 28 : 4)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .fitsSheet(model, .overview, when: !hasParts)
        }
        .scrollBounceBehavior(.basedOnSize)
        // At peek height a drag should open the sheet, not scroll what's hidden below the player.
        .scrollDisabled(model.detent == SurahSheetDetent.peek)
        .animation(.snappy, value: model.undo?.id)
    }

    @ViewBuilder
    private var sections: some View {
        peekBar
        header
        status
        revision
        actions
        knownRow
        queueRow
        if hasParts { piecesList }
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
        if total > 0, memorized == total, let freshness, freshness != .fresh { return freshness.title }
        guard memorized > 0, memorized < total else { return statusLine }
        return String(localized: "\(memorized)/\(total)")
    }

    private var position: String? {
        guard let ayah = model.currentAyah, let position = model.passage.indexByAyah[ayah] else { return nil }
        return String(localized: "Ayah \(position + 1) of \(model.verses.count)")
    }

    private var statusLine: String {
        if total > 0 && memorized == total { return (freshness ?? .fresh).memorizedLabel }
        if memorized > 0 { return String(localized: "\(memorized) of \(total) memorized") }
        let learning = span.map { index.count(.learning, in: $0) } ?? 0
        return learning > 0 ? MemorizationStatus.learning.title : MemorizationStatus.notStarted.title
    }

    private var statusColor: Color {
        if total > 0 && memorized == total { return (freshness ?? .fresh).color }
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
        let needsRevision = index.needsRevisionCount(in: span, cycle: environment.settings.revisionCycle)
        if needsRevision > 0 { parts.append(String(localized: "\(needsRevision) need revision")) }
        return parts.joined(separator: " · ")
    }

    /// How fresh the memorized ayahs are, when they were last revised, and a one-tap "Revised today".
    @ViewBuilder
    private var revision: some View {
        if let span, let freshness {
            let history = index.history(of: span)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(freshness.color).frame(width: 9, height: 9)
                    Text(freshness.title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    // Only once everything here is fresh; a part revised today doesn't make the rest fresh.
                    if freshness == .fresh, history.lastRevisedAt.map(Calendar.current.isDateInToday) == true {
                        Label("Revised today", systemImage: "checkmark")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.olive)
                    } else {
                        Button("Revised today") { withAnimation(.snappy) { model.markRevised(span) } }
                            .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                            .accessibilityHint("Marks the memorized ayahs here as revised")
                            .accessibilityIdentifier("surah.revisedToday")
                    }
                }
                if let line = historyLine(history, oldest: freshness == .fresh ? nil : index.oldestRevision(in: span)) {
                    Text(line).font(.caption).foregroundStyle(Color.secondaryWarm).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.parchment.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.tightRadius))
            .accessibilityElement(children: .contain)
        }
    }

    /// Once something is fading, the oldest revision explains why; otherwise the latest of each kind.
    private func historyLine(_ history: RevisionHistory, oldest: Date?) -> String? {
        let parts = [
            oldest.map { String(localized: "Oldest revision \(Self.relativeDay($0))") },
            history.lastRecitedAt.map { String(localized: "Recited \(Self.relativeDay($0))") },
            history.lastHeardAt.map { String(localized: "Listened \(Self.relativeDay($0))") },
            oldest == nil ? history.lastRevisedAt.map { String(localized: "Revised \(Self.relativeDay($0))") } : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "today", "yesterday", or "3 weeks ago": revision is counted in days, not hours.
    private static func relativeDay(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "today") }
        return calendar.startOfDay(for: date).formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    private var action: SurahAction? { SurahAction.make(pieces: model.pieces, index: index) }

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
            return String(localized: "Continue · \(LearningPassage.ayahLabel(piece, catalog: environment.quran))")
        case .revise: return String(localized: "Revise")
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

    /// Lines this surah up after what the user is memorizing now, or says it already is.
    @ViewBuilder
    private var queueRow: some View {
        let settings = environment.settings
        if case .surah(let number, _) = model.destination, model.readingRanges == nil, memorized < total,
           let surah = environment.quran.surah(number: number), let current = settings.activePlan, current.range != surah.range {
            if settings.isQueued(surah.range) {
                Label("Memorizing next, after \(current.title(catalog: environment.quran))", systemImage: "checkmark")
                    .font(.subheadline).foregroundStyle(Color.olive)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("surah.queued")
            } else {
                Button { withAnimation(.snappy) { settings.queueNext(LearningTarget(range: surah.range)) } } label: {
                    Label("Memorize \(surah.englishName) next", systemImage: "text.badge.plus")
                }
                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("surah.queue")
            }
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memorize in parts").font(.subheadline.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
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
            ForEach(groups) { group in
                if groups.count > 1 {
                    Text(group.surah.displayName).font(.footnote.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
                        .padding(.top, 6)
                }
                // Lazy so Al-Baqarah's pages only build as they scroll into view.
                LazyVStack(spacing: 0) {
                    ForEach(group.pages) { page in
                        PageRow(model: model, page: page, index: index)
                        if page != group.pages.last { Divider().padding(.leading, 50) }
                    }
                }
                .background(Color.parchment.opacity(0.6), in: RoundedRectangle(cornerRadius: AppTheme.tightRadius))
            }
        }
    }
}

/// One mushaf page: its place in the surah, its opening words, and a chip for each piece on it.
/// The row opens the page's next piece; a chip opens that piece.
private struct PageRow: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel
    let page: SurahPageRow
    let index: ProgressIndex

    var body: some View {
        let range = page.range
        let status = index.status(of: range)
        let due = index.isDue(range)
        let freshness = index.freshness(of: range, cycle: environment.settings.revisionCycle)
        HStack(spacing: 12) {
            Button { model.open(page, index: index) } label: {
                HStack(spacing: 12) {
                    Image(systemName: due ? "arrow.counterclockwise" : status.systemImage)
                        .foregroundStyle(status == .notStarted ? Color.secondaryWarm : (due ? Freshness.needsRevision : freshness ?? .fresh).color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Page \(page.pageInSurah)").font(.headline).fixedSize()
                            Spacer(minLength: 0)
                            Text(page.openingWords).font(.quran(.listName)).lineLimit(1)
                                .environment(\.layoutDirection, .rightToLeft)
                                .accessibilityHidden(true)
                        }
                        Text(caption(range: range, status: status, due: due, freshness: freshness))
                            .font(.caption).foregroundStyle(Color.secondaryWarm).lineLimit(1)
                    }
                    if page.pieces.count == 1 {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("surah.page.\(page.mushafPage)")
            if page.pieces.count > 1 {
                HStack(spacing: 4) {
                    ForEach(page.pieces, id: \.self) { chip($0) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contextMenu {
            if status != .memorized {
                Button("I know this page", systemImage: MemorizationStatus.memorized.systemImage) { model.markKnown(range, index: index) }
            } else {
                Button("This page needs revision", systemImage: "arrow.counterclockwise") { model.markNeedsRevision(range) }
            }
        }
    }

    private func caption(range: VerseRange, status: MemorizationStatus, due: Bool, freshness: Freshness?) -> String {
        let state: String
        if due {
            state = Freshness.needsRevision.title
        } else if status == .memorized {
            state = (freshness ?? .fresh).memorizedLabel
        } else {
            let memorized = index.count(.memorized, in: range)
            state = memorized > 0 ? String(localized: "\(memorized) of \(range.count) memorized") : status.title
        }
        return [String(localized: "p. \(page.mushafPage)"), LearningPassage.ayahLabel(range, catalog: environment.quran), state]
            .joined(separator: " · ")
    }

    private func chip(_ piece: VerseRange) -> some View {
        let status = index.status(of: piece)
        let freshness = index.freshness(of: piece, cycle: environment.settings.revisionCycle)
        return Button { model.open(piece, index: index) } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill(status, freshness: freshness))
                .frame(width: 14, height: 22)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LearningPassage.ayahLabel(piece, catalog: environment.quran)), \(status == .memorized ? (freshness ?? .fresh).memorizedLabel : status.title)")
        .accessibilityIdentifier("surah.piece.\(piece.startGlobalAyah)")
    }

    private func fill(_ status: MemorizationStatus, freshness: Freshness?) -> Color {
        switch status {
        case .memorized: (freshness ?? .fresh).color
        case .learning: Color.bronze.opacity(0.6)
        case .notStarted: Color.warmBorder
        }
    }
}

/// Reports the content's natural height so the sheet can rest fitted to it.
private struct SheetFit: ViewModifier {
    let model: SurahScreenModel
    let sheetContent: SurahSheetContent
    let isActive: Bool

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            if isActive { model.fitSheet(sheetContent, to: height) }
        }
    }
}

private extension View {
    func fitsSheet(_ model: SurahScreenModel, _ content: SurahSheetContent, when isActive: Bool = true) -> some View {
        modifier(SheetFit(model: model, sheetContent: content, isActive: isActive))
    }
}

// MARK: - Memorizing a piece

/// Coaches one piece in place, a step at a time: Listen with the player and repeat count, Recite
/// with the text hidden and the recorder, then Check with the text back and the answers. Every step
/// has the same rows, so the sheet keeps its height. Answering stays optional: Done or Next skips it.
private struct FocusCoach: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel
    let focus: MemorizeFocus
    let index: ProgressIndex

    /// Every step's tools get the recorder's height, so the steps line up.
    private static let toolsHeight: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                promptRow
                tools.frame(maxWidth: .infinity, minHeight: Self.toolsHeight)
                footer
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 4)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .fitsSheet(model, model.sheetContent)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.snappy, value: focus.step)
    }

    /// The passage name opens the picker, so it never competes with Done for the row.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Color.bronze)
                Button { model.showsPassagePicker = true } label: {
                    HStack(spacing: 4) {
                        Text(LearningPassage.referenceLabel(focus.range, catalog: environment.quran))
                            .font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Color.bronze)
                    }
                    .frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Choose another passage")
                .accessibilityIdentifier("session.change")
            }
            Spacer(minLength: 0)
            Button("Done") { model.finishFocus(index: index) }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .accessibilityIdentifier("session.done")
        }
        .disabled(model.recordingBusy)
    }

    private var label: String {
        if focus.kind == .review {
            let total = focus.reviewsDone + 1 + focus.queue.count
            return total > 1 ? String(localized: "REVISE \(focus.reviewsDone + 1) OF \(total)") : String(localized: "REVISE")
        }
        let pieces = model.pieces
        if let position = pieces.firstIndex(of: focus.range), pieces.count > 1 {
            return String(localized: "PIECE \(position + 1) OF \(pieces.count)")
        }
        return String(localized: "MEMORIZE")
    }

    /// What the step asks, with the ayahs marked so far. Checking, it says how to mark one.
    private var promptRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(focus.step.prompt).foregroundStyle(Color.secondaryWarm)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if focus.step == .check || !focus.slipped.isEmpty {
                Text(markedSummary)
                    .foregroundStyle(focus.slipped.isEmpty ? Color.secondaryWarm : Color.dangerWarm)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("session.marked")
            }
        }
        .font(.footnote)
    }

    private var markedSummary: String {
        switch focus.slipped.count {
        case 0: String(localized: "Tap any ayah you slipped on")
        case 1: String(localized: "1 ayah marked")
        default: String(localized: "\(focus.slipped.count) ayahs marked")
        }
    }

    @ViewBuilder
    private var tools: some View {
        switch focus.step {
        case .listen: player
        case .recite: RecitationBar(model: model)
        case .check: answers
        }
    }

    private var player: some View {
        HStack(spacing: 6) {
            Button { model.step(by: -1) } label: {
                Image(systemName: "backward.end.fill").font(.body).frame(width: 36, height: 44)
            }
            .accessibilityLabel("Previous ayah").accessibilityIdentifier("session.previous")
            .disabled(!model.canStepBack)
            Button { model.togglePlayback() } label: {
                ZStack {
                    PlayGlyph(systemName: model.isPlaying ? "pause.fill" : "play.fill", size: 48)
                    if model.isLoading { ProgressView().tint(Color.goldButtonText) }
                }
            }
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play").accessibilityIdentifier("session.play")
            Button { model.step(by: 1) } label: {
                Image(systemName: "forward.end.fill").font(.body).frame(width: 36, height: 44)
            }
            .accessibilityLabel("Next ayah").accessibilityIdentifier("session.next")
            .disabled(!model.canStepForward)
            if let practice = focus.practice { RepeatChip(model: model, practice: practice).padding(.leading, 4) }
        }
        .buttonStyle(.plain).foregroundStyle(Color.bronze)
    }

    private var answers: some View {
        HStack(spacing: 8) {
            ForEach(CheckAnswer.choices(for: focus.kind)) { choice in
                let selected = focus.answer == choice
                let tint = choice.rating.color
                Button { model.answer(choice) } label: {
                    // The icon drops out when the three don't fit with it.
                    ViewThatFits(in: .horizontal) {
                        Label {
                            Text(choice.title)
                        } icon: {
                            Image(systemName: choice.systemImage)
                                .symbolVariant(selected ? .fill : .none)
                                .foregroundStyle(selected ? Color.appWarmSurface : tint)
                        }
                        .labelStyle(.titleAndIcon)
                        Text(choice.title)
                    }
                    .font(.footnote.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? tint : tint.opacity(0.14), in: Capsule())
                    .overlay { Capsule().strokeBorder(tint.opacity(selected ? 0 : 0.35)) }
                    .foregroundStyle(selected ? Color.appWarmSurface : Color.appBrownText)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("session.answer.\(choice.rawValue)")
            }
        }
    }

    /// Back a step beside the way on: the next step, then the next passage, or finishing.
    /// With large text the two stack.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { footerButtons }
            VStack(spacing: 10) { footerButtons }
        }
        .disabled(model.recordingBusy)
    }

    @ViewBuilder
    private var footerButtons: some View {
        if let previous = focus.step.previous {
            Button { model.setStep(previous) } label: {
                Label(backTitle(to: previous), systemImage: previous == .listen ? "headphones" : "arrow.counterclockwise")
                    .lineLimit(1)
            }
            .buttonStyle(WarmButtonStyle(emphasis: .secondary))
            .accessibilityIdentifier("session.back")
        }
        onButton
    }

    @ViewBuilder
    private var onButton: some View {
        if let next = focus.step.next {
            Button { model.setStep(next) } label: {
                Text(onTitle(to: next)).lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle())
            .accessibilityIdentifier("session.\(next.rawValue)")
        } else if let passage = model.nextPassage(index: index) {
            Button { model.advance(to: passage, index: index) } label: {
                Text(focus.kind == .review ? "Next to revise" : "Next piece").lineLimit(1).frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle())
            .accessibilityHint(LearningPassage.referenceLabel(passage, catalog: environment.quran))
            .accessibilityIdentifier("session.nextPassage")
        } else {
            Button { model.finishFocus(index: index) } label: {
                Text("Finish").frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle())
            .accessibilityIdentifier("session.finish")
        }
    }

    private func onTitle(to step: CoachStep) -> String {
        switch step {
        case .listen: String(localized: "Listen")
        case .recite: String(localized: "Recite from memory")
        case .check: String(localized: "Check")
        }
    }

    private func backTitle(to step: CoachStep) -> String {
        switch step {
        case .listen: String(localized: "Listen")
        case .recite: String(localized: "Recite again")
        case .check: String(localized: "Check")
        }
    }
}

/// Record yourself reciting, then hear it back. Starting turns the mic into a stop button with
/// a short animation; recording shows a pulsing dot and a running timer.
private struct RecitationBar: View {
    @Environment(AppEnvironment.self) private var environment
    let model: SurahScreenModel

    private var recorder: RecitationRecordingController { environment.recorder }
    private var isActive: Bool { recorder.phase == .starting || recorder.phase == .recording }

    var body: some View {
        HStack(spacing: 14) {
            recordButton
            status
            Spacer(minLength: 0)
            if !isActive, recorder.hasRecording, recorder.phase != .finishing {
                Button { recorder.deleteLatest() } label: {
                    Image(systemName: "trash").font(.body).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(Color.secondaryWarm)
                .accessibilityLabel("Delete recording").accessibilityIdentifier("session.deleteRecording")
            }
        }
        .animation(.spring(duration: 0.4), value: recorder.phase)
    }

    private var recordButton: some View {
        Button { model.toggleRecording() } label: {
            ZStack {
                Circle().fill(isActive ? Color.dangerWarm : Color.appCollectedFill)
                Image(systemName: isActive ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.white : Color.bronze)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 56, height: 56)
            .scaleEffect(recorder.phase == .starting ? 1.12 : 1)
            .overlay {
                if recorder.phase == .starting {
                    Circle().strokeBorder(Color.dangerWarm.opacity(0.5), lineWidth: 3)
                        .scaleEffect(1.3)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(recorder.phase == .finishing)
        .accessibilityLabel(isActive ? "Stop recording" : "Record myself")
        .accessibilityIdentifier("session.record")
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.phase {
        case .starting:
            Text("Starting…").font(.subheadline.weight(.medium)).foregroundStyle(Color.dangerWarm)
        case .recording:
            HStack(spacing: 8) {
                Image(systemName: "circle.fill").font(.caption2).foregroundStyle(Color.dangerWarm)
                    .symbolEffect(.pulse, options: .repeating)
                if let start = recorder.recordingStartedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                Text("Recording").font(.subheadline).foregroundStyle(Color.secondaryWarm)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.recording")
        case .finishing:
            ProgressView()
        case .idle, .comparing:
            if recorder.hasRecording {
                Button { model.toggleRecordingPlayback() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: recorder.isPlayingComparison ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your recitation").font(.subheadline.weight(.semibold))
                            if let duration = recorder.latestDuration {
                                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.caption).monospacedDigit().foregroundStyle(Color.secondaryWarm)
                            }
                        }
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Color.bronze)
                .accessibilityLabel(recorder.isPlayingComparison ? "Stop your recitation" : "Play your recitation")
                .accessibilityIdentifier("session.playRecording")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record yourself").font(.subheadline.weight(.semibold))
                    Text("Optional. Play it back to check.").font(.caption).foregroundStyle(Color.secondaryWarm)
                }
            }
        }
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
                }
            }
            .warmListChrome().navigationTitle("Repeat and pause").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.showsOptions = false } } }
        }
        .presentationDetents([.medium, .large])
        .tint(Color.bronze)
    }
}
