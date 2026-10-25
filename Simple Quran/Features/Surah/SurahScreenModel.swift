import SwiftUI

/// Where the surah screen's sheet rests. Reading uses peek, half and full; memorizing a piece
/// fits the coach so the text above stays in view, and can shrink to a slim coach at peek.
/// A one-piece surah's overview fits too, since it has no parts list to fill half the screen.
/// Heights are above the home indicator.
enum SurahSheetDetent {
    static let peekHeight: CGFloat = 88
    static let peek = PresentationDetent.height(peekHeight)
    static let half = PresentationDetent.medium
    static let full = PresentationDetent.large
    /// Measured heights round up to this step, so small layout changes don't move the sheet.
    static let fitStep: CGFloat = 8
    /// Measured changes this small are layout noise from the sheet moving, not new content.
    static let fitTolerance: CGFloat = 1
    /// Opening a piece to recite holds its text in view this long, so the sheet settles before it hides.
    static let textHideDelay: Duration = .milliseconds(350)

    static func fitted(_ height: CGFloat) -> PresentationDetent { .height(height) }

    static func rounded(_ height: CGFloat) -> CGFloat { (height / fitStep).rounded(.up) * fitStep }
}

/// What the sheet shows, each fitted to its own measured height. The coach keeps one height
/// across its steps, so moving through them never moves the text.
enum SurahSheetContent: Hashable {
    case overview
    case coach

    /// Used until the content has been measured once.
    var estimatedHeight: CGFloat {
        switch self {
        case .overview: 400
        case .coach: 250
        }
    }
}

/// The height the reader opens at: readers start with the text in full view, memorizers with the overview.
enum SurahSheetStart: Hashable {
    case peek
    case half

    var detent: PresentationDetent { self == .peek ? SurahSheetDetent.peek : SurahSheetDetent.half }

    /// Moving to the next surah keeps the sheet as it was: still at peek, or back at the middle.
    static func keeping(_ detent: PresentationDetent) -> SurahSheetStart {
        detent == SurahSheetDetent.peek ? .peek : .half
    }
}

/// A surah's pieces in reading order, grouped by surah so a juz reads as the surahs it holds.
struct SurahPieceGroup: Identifiable {
    let surah: Surah
    let pieces: [VerseRange]
    let pages: [SurahPageRow]
    var id: Int { surah.number }
}

/// The pieces that start on one mushaf page, named the way memorizers know a page:
/// its place in the surah and its opening words.
struct SurahPageRow: Identifiable, Equatable {
    /// How many words of the page's opening the row shows.
    static let openingWordCount = 4

    let mushafPage: Int
    /// 1 for the page the surah starts on.
    let pageInSurah: Int
    let pieces: [VerseRange]
    let openingWords: String

    var id: Int { mushafPage }
    var range: VerseRange { .clamped(start: pieces[0].startGlobalAyah, end: pieces[pieces.count - 1].endGlobalAyah) }

    /// Groups a surah's pieces by the page their first ayah is on.
    static func rows(for pieces: [VerseRange], in surah: Surah, catalog: some QuranCatalog) -> [SurahPageRow] {
        guard let firstPage = catalog.verse(globalAyah: surah.startGlobalAyah)?.page else { return [] }
        var rows: [SurahPageRow] = []
        var current: (page: Int, pieces: [VerseRange])?
        func close() {
            guard let current else { return }
            let range = VerseRange.clamped(start: current.pieces[0].startGlobalAyah, end: current.pieces[current.pieces.count - 1].endGlobalAyah)
            rows.append(SurahPageRow(mushafPage: current.page, pageInSurah: current.page - firstPage + 1,
                                     pieces: current.pieces, openingWords: openingWords(of: range, catalog: catalog)))
        }
        for piece in pieces {
            guard let page = catalog.verse(globalAyah: piece.startGlobalAyah)?.page else { continue }
            if current?.page == page {
                current?.pieces.append(piece)
            } else {
                close()
                current = (page, [piece])
            }
        }
        close()
        return rows
    }

    /// The first few words, reading on into the next ayah when the first is shorter.
    static func openingWords(of range: VerseRange, catalog: some QuranCatalog) -> String {
        var words: [Substring] = []
        var hasMore = false
        for ayah in range.globalAyahs {
            guard let verse = catalog.verse(globalAyah: ayah) else { break }
            let ayahWords = verse.text.split(whereSeparator: \.isWhitespace)
            let room = openingWordCount - words.count
            words += ayahWords.prefix(room)
            if ayahWords.count > room || (words.count == openingWordCount && ayah != range.endGlobalAyah) {
                hasMore = true
                break
            }
        }
        return words.joined(separator: " ") + (hasMore ? "…" : "")
    }
}

/// What the overview's main button does for the pieces in view.
enum SurahAction: Equatable {
    case start(VerseRange)
    case `continue`(VerseRange)
    case revise([VerseRange])

    /// Revise once every ayah is memorized, continue once any is started, otherwise start.
    static func make(pieces: [VerseRange], index: ProgressIndex) -> SurahAction? {
        guard !pieces.isEmpty else { return nil }
        guard let next = pieces.first(where: { index.status(of: $0) != .memorized }) else { return .revise(pieces) }
        let started = pieces.contains { index.status(of: $0) != .notStarted }
        return started ? .continue(next) : .start(next)
    }
}

/// An "I already know this" claim that can still be taken back.
struct MarkUndo: Identifiable {
    let id = UUID()
    let ayahs: [Int]
    /// Each ayah's progress before the claim; missing means it had none.
    let previous: [Int: VerseProgressSnapshot]
}

/// Rebuilds the pieces only when the passage or piece size changes, so long surahs stay smooth.
@MainActor
final class SurahPieceCache {
    private var key: Key?
    private var cached: [SurahPieceGroup] = []

    private struct Key: Equatable {
        var span: VerseRange
        var size: PieceSize
    }

    func groups(for span: VerseRange?, size: PieceSize, catalog: some QuranCatalog) -> [SurahPieceGroup] {
        guard let span else { return [] }
        let key = Key(span: span, size: size)
        guard key != self.key else { return cached }
        cached = catalog.surahs.compactMap { surah in
            let start = max(surah.startGlobalAyah, span.startGlobalAyah)
            let end = min(surah.endGlobalAyah, span.endGlobalAyah)
            guard start <= end else { return nil }
            let target = LearningTarget(range: .clamped(start: start, end: end))
            var pieces: [VerseRange] = []
            var cursor = start
            while let piece = target.passage(from: cursor, catalog: catalog, size: size) {
                pieces.append(piece)
                cursor = piece.endGlobalAyah + 1
            }
            return SurahPieceGroup(surah: surah, pieces: pieces, pages: SurahPageRow.rows(for: pieces, in: surah, catalog: catalog))
        }
        self.key = key
        return cached
    }
}

/// One surah screen for reading, listening, and memorizing. Reading never changes an ayah's
/// status; only focusing a piece to memorize (and then answering) does.
@MainActor
@Observable
final class SurahScreenModel {
    @ObservationIgnored let environment: AppEnvironment
    @ObservationIgnored private let opening: AppRoute
    @ObservationIgnored private let passageCache = ReaderPassageCache()
    @ObservationIgnored private let pieceCache = SurahPieceCache()
    @ObservationIgnored private var started = false

    var destination: QuranDestination
    /// Reading playback resumed from the mini player can cover other ranges than the destination.
    var readingRanges: [VerseRange]?
    var readingName: String?
    var selectedAyah: Int?
    var detent: PresentationDetent
    var focus: MemorizeFocus?
    var undo: MarkUndo?
    var errorMessage: UserFacingMessage?
    var showsOptions = false
    var showsPassagePicker = false
    /// Changes whenever the user asks to see the current ayah, so the text follows playback again
    /// after they scrolled away.
    private(set) var followRequest = 0
    /// True for a moment after a piece opens, so the text hides after the sheet has changed, not with it.
    private var holdsText = false
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// Measured sheet content, kept across screens so the next surah opens at the right height.
    private var fittedHeights = SurahScreenModel.rememberedHeights
    /// The unrounded heights last taken, to tell real changes from sub-point layout noise.
    @ObservationIgnored private var measuredHeights: [SurahSheetContent: CGFloat] = [:]
    @ObservationIgnored private static var rememberedHeights: [SurahSheetContent: CGFloat] = [:]
    /// Large text and landscape need the whole coach, so memorizing uses the full sheet there.
    var prefersFullCoach = false {
        didSet {
            guard prefersFullCoach != oldValue, focus != nil else { return }
            detent = coachDetent
        }
    }

    init(route: AppRoute, environment: AppEnvironment) {
        self.environment = environment
        opening = route
        switch route {
        case .reader(let reader):
            destination = reader.destination
            detent = reader.sheet.detent
        case .session(let session):
            let surah = environment.quran.verse(globalAyah: session.range.startGlobalAyah)?.surahNumber ?? 1
            destination = .surah(number: surah, scrollToAyah: session.range.startGlobalAyah)
            let content = SurahSheetContent.coach
            detent = SurahSheetDetent.fitted(Self.rememberedHeights[content] ?? content.estimatedHeight)
        }
        if detent == SurahSheetDetent.half { detent = middleDetent }
    }

    // MARK: - What's on screen

    private var quran: BundledQuranCatalog { environment.quran }
    private var playback: PlaybackCoordinator { environment.playback }

    var ranges: [VerseRange] {
        readingRanges ?? destination.range(in: quran).map { [$0] } ?? []
    }
    var passage: ReaderPassage { passageCache.passage(for: ranges, catalog: quran) }
    var verses: [QuranVerse] { passage.verses }
    /// Everything in view as one range, for counts and pieces.
    var span: VerseRange? {
        guard let first = passage.ayahIDs.first, let last = passage.ayahIDs.last else { return nil }
        return .clamped(start: first, end: last)
    }
    var title: String { readingName ?? destination.title(in: quran) }
    var groups: [SurahPieceGroup] { pieceCache.groups(for: span, size: environment.settings.pieceSize, catalog: quran) }
    var pieces: [VerseRange] { groups.flatMap(\.pieces) }

    // MARK: - Sheet heights

    var sheetContent: SurahSheetContent { focus == nil ? .overview : .coach }

    /// A short surah is one piece, so its overview has no parts list and fits its content.
    var fitsOverview: Bool { pieces.count <= 1 }

    private func fittedHeight(_ content: SurahSheetContent) -> CGFloat {
        fittedHeights[content] ?? content.estimatedHeight
    }

    private func fittedDetent(_ content: SurahSheetContent) -> PresentationDetent {
        SurahSheetDetent.fitted(fittedHeight(content))
    }

    /// Where reading rests between peek and full.
    var middleDetent: PresentationDetent { fitsOverview ? fittedDetent(.overview) : SurahSheetDetent.half }

    /// Memorizing can shrink to the slim coach at peek height, except while checking.
    var detents: Set<PresentationDetent> {
        guard let focus else { return [SurahSheetDetent.peek, middleDetent, SurahSheetDetent.full] }
        let coach: Set = [fittedDetent(sheetContent), SurahSheetDetent.full]
        return focus.step.allowsSlimCoach ? coach.union([SurahSheetDetent.peek]) : coach
    }

    /// The coach shrunk to one row, so more of the text shows.
    var isCoachSlim: Bool { focus != nil && detent == SurahSheetDetent.peek }

    /// The text stays scrollable and tappable while the sheet is below this height.
    var interactionLimit: PresentationDetent { focus == nil ? middleDetent : fittedDetent(sheetContent) }

    /// True while the sheet sits at a height fitted to its content.
    private var isFitted: Bool {
        (focus != nil || fitsOverview) && detent == fittedDetent(sheetContent)
    }

    /// Keeps the ayah being read or memorized clear of the shorter sheet heights. At half height
    /// the text stays full length behind the sheet, so the surah's opening shows above it.
    var textInset: CGFloat { isFitted ? fittedHeight(sheetContent) : SurahSheetDetent.peekHeight }

    /// Takes the content's natural height; a sheet resting at the old fit follows the new one.
    /// Only what's on screen counts; a view leaving during a switch still reports its old height.
    /// Moving the sheet shifts layout by a fraction of a point, so changes within the tolerance are
    /// ignored; otherwise a height on a rounding step flips the sheet back and forth.
    func fitSheet(_ content: SurahSheetContent, to height: CGFloat) {
        guard content == sheetContent, height > 0 else { return }
        if let measured = measuredHeights[content], abs(measured - height) <= SurahSheetDetent.fitTolerance { return }
        measuredHeights[content] = height
        let fitted = SurahSheetDetent.rounded(height)
        guard fitted != fittedHeights[content] else { return }
        let wasFitted = isFitted
        fittedHeights[content] = fitted
        Self.rememberedHeights[content] = fitted
        if wasFitted { withAnimation(.snappy) { detent = fittedDetent(content) } }
    }

    private var ownsReading: Bool { playback.activeSet == nil && playback.isPrepared(for: ranges) }
    private var ownsFocus: Bool { focus?.practice.map { playback.activeSet?.id == $0.id } ?? false }
    var ownsPlayback: Bool { focus == nil ? ownsReading : ownsFocus }
    var isPlaying: Bool { ownsPlayback && (playback.snapshot.isPlaying || playback.snapshot.isLoading) }
    var isLoading: Bool { ownsPlayback && playback.snapshot.isLoading }

    var currentAyah: Int? {
        if let focus {
            return ownsFocus ? playback.snapshot.currentGlobalAyah ?? selectedAyah : selectedAyah ?? focus.range.startGlobalAyah
        }
        return ownsReading ? playback.snapshot.currentGlobalAyah : selectedAyah ?? verses.first?.globalAyah
    }

    /// The ayahs the arrows step through: the piece while memorizing, everything otherwise.
    private var stepAyahs: [Int] { focus.map { $0.range.globalAyahs } ?? passage.ayahIDs }
    var canStepBack: Bool { currentAyah != stepAyahs.first }
    var canStepForward: Bool { currentAyah != stepAyahs.last }

    var recordingBusy: Bool {
        switch environment.recorder.phase {
        case .starting, .recording, .finishing: true
        default: false
        }
    }

    // MARK: - Opening

    func start() {
        guard !started else { return }
        started = true
        switch opening {
        case .reader(let reader):
            selectedAyah = reader.destination.scrollToAyah ?? ranges.first?.startGlobalAyah
            if reader.resumePlayback {
                readingRanges = playback.passageRanges
                readingName = playback.snapshot.setTitle
                selectedAyah = playback.snapshot.currentGlobalAyah
            } else if !ownsReading {
                playback.pause()
            }
        case .session(let session):
            focus = MemorizeFocus(route: session)
            detent = coachDetent
            if session.resumePlayback, let active = playback.activeSet {
                focus?.practice = active
                selectedAyah = playback.snapshot.currentGlobalAyah
                environment.recorder.selectCollection(active.id)
                environment.lastSession = session
            } else if let saved = session.savedPractice {
                activate(saved, resume: true)
            } else {
                begin(session.range)
            }
        }
    }

    // MARK: - Reading

    func togglePlayback() {
        if isPlaying { playback.pause(); return }
        followRequest += 1
        if let focus {
            self.focus?.engaged = true
            if !ownsFocus, let practice = focus.practice {
                playback.start(set: practice, catalog: quran, resume: true, allowStreaming: environment.settings.streamWhenMissing)
            }
        } else if !ownsReading {
            playback.startListening(title: title, passages: ranges, fromAyah: currentAyah,
                                    catalog: quran, allowStreaming: environment.settings.streamWhenMissing)
        }
        playback.resume()
    }

    func select(_ ayah: Int) {
        followRequest += 1
        if let focus {
            // Only the piece answers taps while memorizing; the rest is context.
            // Past listening, a tap opens or marks an ayah instead of moving playback.
            guard focus.range.contains(ayah) else { return }
            if focus.step != .listen {
                self.focus?.tap(ayah)
                return
            }
            selectedAyah = ayah
            if ownsFocus { playback.move(to: ayah) }
            return
        }
        selectedAyah = ayah
        if ownsReading { playback.move(to: ayah) }
        savePosition()
    }

    func step(by offset: Int) {
        let ayahs = stepAyahs
        guard let ayah = currentAyah, let index = ayahs.firstIndex(of: ayah), ayahs.indices.contains(index + offset) else { return }
        let target = ayahs[index + offset]
        followRequest += 1
        selectedAyah = target
        if ownsPlayback { playback.move(to: target) }
        if focus == nil { savePosition() }
    }

    func savePosition() {
        guard focus == nil, let ayah = currentAyah else { return }
        environment.settings.readingAyah = ayah
    }

    func playbackMoved(to ayah: Int?) {
        guard ownsPlayback, let ayah else { return }
        selectedAyah = ayah
        savePosition()
    }

    // MARK: - Marking

    /// Marks everything in view as memorized right away; the claim can be undone for a few seconds.
    func markKnown(_ range: VerseRange, index: ProgressIndex) {
        let ayahs = range.globalAyahs
        var previous: [Int: VerseProgressSnapshot] = [:]
        for ayah in ayahs { previous[ayah] = index.snapshot(for: ayah) }
        do { try environment.store.markMemorized(ayahs: ayahs, now: .now) }
        catch { errorMessage = .from(.persistenceFailure); return }
        let mark = MarkUndo(ayahs: ayahs, previous: previous)
        undo = mark
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.undo?.id == mark.id { self?.undo = nil }
        }
    }

    func undoMark() {
        guard let undo else { return }
        do { try environment.store.restoreProgress(undo.previous, ayahs: undo.ayahs) }
        catch { errorMessage = .from(.persistenceFailure) }
        self.undo = nil
    }

    /// "Revised today" for the memorized ayahs in range; the rest are left as they are.
    func markRevised(_ range: VerseRange) {
        do {
            try environment.store.markRevised(ayahs: range.globalAyahs, now: .now)
            environment.settings.recordRevised()
        } catch { errorMessage = .from(.persistenceFailure) }
    }

    func markNeedsRevision(_ range: VerseRange) {
        do { try environment.store.markNeedsRevision(ayahs: range.globalAyahs, now: .now) }
        catch { errorMessage = .from(.persistenceFailure) }
    }

    // MARK: - Memorizing a piece

    func perform(_ action: SurahAction) {
        switch action {
        case .start(let piece), .continue(let piece): memorize(piece)
        case .revise(let pieces): revise(pieces)
        }
    }

    /// Opens a piece from the list: memorized pieces come back as a review, anything else to learn.
    func open(_ piece: VerseRange, index: ProgressIndex) {
        if index.status(of: piece) == .memorized { revise([piece]) } else { memorize(piece) }
    }

    /// Opens a page: its first unfinished piece, or a review of the whole page once it's all memorized.
    func open(_ page: SurahPageRow, index: ProgressIndex) {
        if let next = page.pieces.first(where: { index.status(of: $0) != .memorized }) { memorize(next) } else { revise(page.pieces) }
    }

    func memorize(_ piece: VerseRange) {
        beginFocus(SessionRoute(range: piece, kind: .learn, scope: span))
    }

    func revise(_ pieces: [VerseRange]) {
        guard let first = pieces.first else { return }
        beginFocus(SessionRoute(range: first, kind: .review, reviewQueue: Array(pieces.dropFirst())))
    }

    private func beginFocus(_ route: SessionRoute) {
        savePosition()
        playback.pause()
        undo = nil
        followRequest += 1
        holdTextWhileSheetSettles()
        withAnimation(.snappy) {
            focus = MemorizeFocus(route: route)
            detent = coachDetent
        }
        begin(route.range)
    }

    private var coachDetent: PresentationDetent {
        if prefersFullCoach { return SurahSheetDetent.full }
        return fittedDetent(sheetContent)
    }

    /// Brings the slim coach back to its full height.
    func expandCoach() {
        withAnimation(.snappy) { detent = coachDetent }
    }

    /// The text in view hides while reciting, except while the user hears their recording back,
    /// so they can follow it and mark where they slipped.
    var hiddenAyahs: Set<Int> {
        guard let focus, !holdsText, !environment.recorder.isPlayingComparison else { return [] }
        return focus.hiddenAyahs
    }

    /// Keeps the text in view while the sheet changes, then hides it as its own step.
    private func holdTextWhileSheetSettles() {
        holdTask?.cancel()
        holdsText = true
        holdTask = Task { [weak self] in
            guard (try? await Task.sleep(for: SurahSheetDetent.textHideDelay)) != nil else { return }
            withAnimation(.easeInOut) { self?.holdsText = false }
        }
    }

    /// Moving between steps keeps the marks; only moving to another piece clears them.
    /// The reciter is for listening, so it pauses once the user recites. Checking needs the
    /// answers in view, so it brings back the whole coach.
    func setStep(_ step: CoachStep) {
        guard focus != nil, focus?.step != step else { return }
        withAnimation(.snappy) {
            if !step.allowsSlimCoach, isCoachSlim { detent = coachDetent }
            focus?.go(to: step)
        }
        focus?.engaged = true
        if step == .listen { environment.recorder.cancelComparisonPlayback() } else { playback.pause() }
    }

    func answer(_ choice: CheckAnswer) {
        let current = focus?.answer
        focus?.answer = current == choice ? nil : choice
        focus?.engaged = true
    }

    /// "Next passage" for the piece in focus: the next in its plan, review queue, or scope.
    func nextPassage(index: ProgressIndex) -> VerseRange? {
        guard let focus else { return nil }
        if focus.kind == .review { return focus.queue.first }
        let size = environment.settings.pieceSize
        if let plan = environment.settings.learningTargets.first(where: { $0.id == focus.planID }) {
            return plan.passage(from: focus.range.endGlobalAyah + 1, catalog: quran, size: size)
                ?? plan.nextPassage(catalog: quran, size: size) { $0 == focus.range || index.status(of: $0) == .memorized }
        }
        return LearningTarget(range: scope(of: focus)).passage(from: focus.range.endGlobalAyah + 1, catalog: quran, size: size)
    }

    private func scope(of focus: MemorizeFocus) -> VerseRange {
        if let scope = focus.scope, scope.contains(focus.range.startGlobalAyah) { return scope }
        return quran.verse(globalAyah: focus.range.startGlobalAyah)
            .flatMap { quran.surah(number: $0.surahNumber) }?.range ?? focus.range
    }

    var planRange: VerseRange? {
        environment.settings.learningTargets.first { $0.id == focus?.planID }?.range
    }

    func advance(to next: VerseRange, index: ProgressIndex) {
        if focus?.kind == .review {
            focus?.queue.removeFirst()
            focus?.reviewsDone += 1
        }
        move(to: next, index: index)
    }

    func move(to newRange: VerseRange, index: ProgressIndex) {
        commit(index: index)
        followRequest += 1
        withAnimation(.snappy) {
            focus?.move(to: newRange)
            showInText(newRange)
            // A sheet the user moved to full or slim stays there.
            if detent != SurahSheetDetent.full, !isCoachSlim { detent = coachDetent }
        }
        begin(newRange)
    }

    /// Leaves memorizing and goes back to reading where the piece sits.
    func finishFocus(index: ProgressIndex) {
        guard let focus else { return }
        commit(index: index)
        environment.recorder.stopRecording()
        environment.recorder.cancelComparisonPlayback()
        playback.stop()
        environment.lastSession = nil
        withAnimation(.snappy) {
            self.focus = nil
            selectedAyah = focus.range.startGlobalAyah
            detent = middleDetent
        }
    }

    // MARK: - Next and previous surah

    /// Only while reading: memorizing or revising stays on its piece until it's finished.
    var canSwitchSurah: Bool { focus == nil && !recordingBusy && errorMessage == nil }

    func neighbor(_ side: ReaderNeighbor) -> QuranDestination? { destination.neighbor(side, in: quran) }

    func neighborRoute(_ side: ReaderNeighbor) -> AppRoute? {
        guard let neighbor = neighbor(side) else { return nil }
        return .reader(ReaderRoute(destination: neighbor, sheet: .keeping(detent)))
    }

    /// Saves the place, and stops this surah's audio so the next one opens fresh instead of the
    /// mini player carrying on with this one. Audio from elsewhere was already paused on opening.
    func leaveForNeighbor() {
        savePosition()
        undo = nil
        environment.recorder.cancelComparisonPlayback()
        if ownsPlayback { playback.stop() }
    }

    /// Closing the screen keeps playback going for the mini player; answers are saved first.
    func close(index: ProgressIndex) {
        if focus != nil { commit(index: index) } else { savePosition() }
    }

    /// Keeps the piece's surah on screen when "Next passage" crosses into another one.
    private func showInText(_ range: VerseRange) {
        guard !(span?.contains(range.startGlobalAyah) ?? false),
              let verse = quran.verse(globalAyah: range.startGlobalAyah) else { return }
        destination = .surah(number: verse.surahNumber, scrollToAyah: range.startGlobalAyah)
        readingRanges = nil
        readingName = nil
    }

    private func begin(_ range: VerseRange) {
        do { activate(try environment.practice(for: range), resume: false) }
        catch { errorMessage = .from(.persistenceFailure) }
    }

    private func activate(_ set: PracticeSet, resume: Bool) {
        guard focus != nil else { return }
        focus?.practice = set
        focus?.committedSeconds = 0
        if let first = set.orderedPassages.first?.range.startGlobalAyah, let last = set.orderedPassages.last?.range.endGlobalAyah {
            focus?.range = .clamped(start: first, end: last)
        }
        if PracticePlaybackLifecycle.shouldPrepareNewSession(activeSetID: playback.activeSet?.id,
                                                              currentGlobalAyah: playback.snapshot.currentGlobalAyah,
                                                              openingSetID: set.id) {
            playback.start(set: set, catalog: quran, resume: resume, allowStreaming: environment.settings.streamWhenMissing)
        }
        // Hiding is driven by the step, never by the saved playback flag.
        if playback.snapshot.hideArabic { playback.toggleArabicHidden() }
        guard let focus else { return }
        showInText(focus.range)
        selectedAyah = playback.snapshot.currentGlobalAyah.flatMap { focus.range.contains($0) ? $0 : nil } ?? focus.range.startGlobalAyah
        environment.recorder.selectCollection(set.id)
        environment.lastSession = focus.route
        if focus.kind == .learn { environment.settings.remember(focus.range, targetID: focus.planID) }
    }

    /// Saves activity and any answers. With no answer, statuses stay exactly as they were.
    func commit(index: ProgressIndex) {
        guard let focus, let practice = focus.practice,
              focus.engaged || playback.listeningSeconds > focus.committedSeconds else { return }
        let ayahs = focus.range.globalAyahs
        do {
            // Only focusing a piece to memorize starts learning; reading and listening never do.
            if focus.kind == .learn { try environment.store.beginLearning(ayahs: ayahs) }
            try environment.store.completePractice(practice, ayahs: ayahs, rating: nil, lastAyah: currentAyah,
                                                   seconds: playback.listeningSeconds,
                                                   repetitions: playback.repetitionCount)
            for (given, list) in focus.ratings(isMemorized: { index.status(of: $0) == .memorized }) {
                try environment.store.applyRating(given.rating, ayahs: list, now: .now)
            }
            if focus.kind == .learn, focus.answer == .memorized, let next = nextPassage(index: index) {
                environment.settings.remember(next, targetID: focus.planID)
            }
            // Ticks today's checklist: learning counts only for what the user is memorizing.
            switch focus.kind {
            case .learn where focus.planID != nil: environment.settings.recordLearned(focus.range)
            case .learn: break
            case .review: environment.settings.recordRevised()
            }
        } catch { errorMessage = .from(.persistenceFailure) }
        self.focus?.engaged = false
        self.focus?.committedSeconds = playback.listeningSeconds
        self.focus?.answer = nil
        self.focus?.slipped = []
    }

    // MARK: - Recording and repeat

    func toggleRecording() {
        if recordingBusy { environment.recorder.stopRecording(); return }
        guard let practice = focus?.practice else { return }
        playback.pause()
        focus?.engaged = true
        Task { await environment.recorder.startRecording(collectionID: practice.id) }
    }

    func toggleRecordingPlayback() {
        if environment.recorder.isPlayingComparison { environment.recorder.cancelComparisonPlayback(); return }
        playback.pause()
        Task {
            do { try await environment.recorder.playRecording() }
            catch is CancellationError {} catch { errorMessage = .from(.recordingFailed) }
        }
    }

    /// Changes to an app-made passage become the memorize preference, so the next piece plays the same way.
    func setting<Value>(_ keyPath: WritableKeyPath<PracticeSettings, Value>, in practice: PracticeSet) -> Binding<Value> {
        Binding(get: { practice.settings[keyPath: keyPath] }, set: { [self] value in
            var settings = practice.settings
            settings[keyPath: keyPath] = value
            if ownsFocus { playback.applySettingsAndRestart(settings) } else { practice.settings = settings }
            if environment.settings.generatedPracticeIDs.contains(practice.id.uuidString) {
                environment.settings.memorizePlayback = settings.keepingHideArabic(of: environment.settings.memorizePlayback)
            }
            do { try environment.store.save() } catch { errorMessage = .from(.persistenceFailure) }
        })
    }
}
