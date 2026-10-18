import SwiftData
import SwiftUI

/// A surah or juz broken into mushaf pieces, each with its memorization status and quick actions.
struct PassageProgressView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    let title: String
    let range: VerseRange
    /// What "Read" opens: the surah or the juz itself.
    let destination: QuranDestination
    @State private var pendingMark: PendingMark?
    @State private var errorMessage: UserFacingMessage?

    /// Pieces grouped by surah, so a juz reads as the surahs it holds.
    private var groups: [SurahPieces] {
        let size = environment.settings.pieceSize
        return environment.quran.surahs.compactMap { surah -> SurahPieces? in
            let start = max(surah.startGlobalAyah, range.startGlobalAyah)
            let end = min(surah.endGlobalAyah, range.endGlobalAyah)
            guard start <= end else { return nil }
            let target = LearningTarget(range: .clamped(start: start, end: end))
            var pieces: [VerseRange] = []
            var cursor = start
            while let piece = target.passage(from: cursor, catalog: environment.quran, size: size) {
                pieces.append(piece)
                cursor = piece.endGlobalAyah + 1
            }
            return SurahPieces(surah: surah, pieces: pieces)
        }
    }

    var body: some View {
        let index = ProgressIndex(progress.map(\.snapshot))
        let memorized = index.count(.memorized, in: range)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(memorized) of \(range.count) ayahs memorized").font(.system(.title2, design: .serif))
                    ProgressView(value: Double(memorized), total: Double(range.count)).tint(Color.olive)
                    Text("Tap a passage to memorize or review it. Long-press to mark what you already know.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.padding(.vertical, 8)
            }.listRowBackground(Color.clear)
            let groups = groups
            ForEach(groups, id: \.surah.number) { group in
                Section {
                    ForEach(group.pieces, id: \.self) { passage in pieceRow(passage, index: index) }
                } header: {
                    Text(groups.count == 1 ? String(localized: "Memorize in parts") : group.surah.displayName)
                }
            }
            Section {
                if memorized > 0 {
                    Button("Review everything memorized here") {
                        environment.openReviews(ReviewPlanner.memorizedPassages(in: range, snapshots: progress.map(\.snapshot), catalog: environment.quran))
                    }.warmListRow()
                }
                if memorized < range.count {
                    Button("I already know all of this") { pendingMark = PendingMark(range: range, kind: .memorized) }.warmListRow()
                }
                Button("Read") { environment.openReader(destination) }.warmListRow()
            }
        }
        .foregroundStyle(Color.appBrownText).warmListChrome().navigationTitle(title)
        .confirmationDialog(pendingMark?.kind.question ?? "", isPresented: Binding(get: { pendingMark != nil }, set: { if !$0 { pendingMark = nil } }),
                            titleVisibility: .visible, presenting: pendingMark) { mark in
            Button(mark.kind.confirmTitle) { apply(mark) }
            Button("Cancel", role: .cancel) {}
        } message: { mark in Text(mark.kind.message) }
        .alert(errorMessage?.title ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage?.message ?? "") }
    }

    private func pieceRow(_ passage: VerseRange, index: ProgressIndex) -> some View {
        let status = index.status(of: passage)
        let due = index.isDue(passage)
        return Button { open(passage, status: status) } label: {
            HStack(spacing: 14) {
                Image(systemName: due ? "arrow.counterclockwise" : status.systemImage)
                    .foregroundStyle(status == .notStarted ? Color.secondaryWarm : Color.olive).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(LearningPassage.ayahLabel(passage, catalog: environment.quran)).font(.headline)
                    Text(statusText(passage, status: status, due: due, index: index))
                        .font(.caption).foregroundStyle(Color.secondaryWarm)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondaryWarm)
            }.padding(.vertical, 8)
        }.buttonStyle(.plain).warmListRow()
            .contextMenu { markMenu(passage, status: status) }
    }

    @ViewBuilder
    private func markMenu(_ passage: VerseRange, status: MemorizationStatus) -> some View {
        if status != .memorized {
            Button("I know these ayahs", systemImage: MemorizationStatus.memorized.systemImage) { pendingMark = PendingMark(range: passage, kind: .memorized) }
        } else {
            Button("These need a refresh", systemImage: "arrow.counterclockwise") { pendingMark = PendingMark(range: passage, kind: .needsRefresh) }
        }
    }

    private func statusText(_ passage: VerseRange, status: MemorizationStatus, due: Bool, index: ProgressIndex) -> String {
        if due { return String(localized: "Ready to review") }
        if status == .memorized { return status.title }
        let memorized = index.count(.memorized, in: passage)
        return memorized > 0 ? String(localized: "\(memorized) of \(passage.count) memorized") : status.title
    }

    /// Memorized passages open as a review of just those ayahs; anything else opens to learn.
    private func open(_ passage: VerseRange, status: MemorizationStatus) {
        if status == .memorized { environment.openReviews([passage]) } else { environment.openSession(passage, scope: range) }
    }

    private func apply(_ mark: PendingMark) {
        do {
            switch mark.kind {
            case .memorized: try environment.store.markMemorized(ayahs: mark.range.globalAyahs)
            case .needsRefresh: try environment.store.markNeedsRefresh(ayahs: mark.range.globalAyahs)
            }
        } catch { errorMessage = .from(.persistenceFailure) }
    }
}

private struct SurahPieces {
    let surah: Surah
    let pieces: [VerseRange]
}

private struct PendingMark {
    enum Kind {
        case memorized
        case needsRefresh

        var question: String {
            switch self {
            case .memorized: String(localized: "Can you recite these ayahs from memory?")
            case .needsRefresh: String(localized: "Review these ayahs again soon?")
            }
        }
        var confirmTitle: String {
            switch self {
            case .memorized: String(localized: "Yes, mark as memorized")
            case .needsRefresh: String(localized: "Yes, add to review")
            }
        }
        var message: String {
            switch self {
            case .memorized: String(localized: "They’ll count as memorized and come back for review later.")
            case .needsRefresh: String(localized: "They stay memorized and come back in your next review.")
            }
        }
    }

    let range: VerseRange
    let kind: Kind
}

/// One line describing a surah's memorization, shared by progress lists.
struct SurahProgressSummary {
    let surah: Surah
    let index: ProgressIndex

    var memorized: Int { index.count(.memorized, in: surah.range) }
    var learning: Int { index.count(.learning, in: surah.range) }

    var text: String {
        if memorized == surah.ayahCount { return String(localized: "Memorized") }
        if learning == 0 { return String(localized: "\(memorized) of \(surah.ayahCount) memorized") }
        return String(localized: "\(memorized) of \(surah.ayahCount) memorized · \(learning) learning")
    }
}
