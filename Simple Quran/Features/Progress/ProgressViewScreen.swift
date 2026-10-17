import SwiftData
import SwiftUI

struct ProgressViewScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]

    private var index: ProgressIndex { ProgressIndex(progress.map(\.snapshot)) }
    private var memorizedCount: Int { progress.filter { $0.snapshot.status == .memorized }.count }
    private var surahs: [Surah] {
        let index = index
        return environment.quran.surahs.filter { index.status(of: $0.range) != .notStarted }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(memorizedCount == 0 ? "Every ayah is a beginning." : "\(memorizedCount) ayahs memorized.")
                        .font(.system(.title, design: .serif))
                    Text("Your progress grows each time you return.").font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.padding(.vertical, 16)
            }.listRowBackground(Color.clear)
            Section { LearningFocusSection() }.listRowBackground(Color.clear)
            if surahs.isEmpty {
                Button("Choose a surah") { environment.selectedTab = .quran }.warmListRow()
            }
            let index = index
            ForEach(surahs) { surah in
                NavigationLink { SurahProgressView(surah: surah) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(surah.englishName).font(.headline)
                        Text(SurahProgressSummary(surah: surah, index: index).text)
                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                    }.padding(.vertical, 6)
                }.warmListRow()
            }
        }
        .foregroundStyle(Color.appBrownText).warmListChrome().navigationTitle("Your progress")
    }
}

struct SurahProgressView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    let surah: Surah
    @State private var knownRange: VerseRange?
    @State private var showKnown = false
    @State private var errorMessage: UserFacingMessage?

    private var passages: [VerseRange] {
        var result: [VerseRange] = []
        var start = surah.startGlobalAyah
        while start <= surah.endGlobalAyah, let range = LearningPassage.suggested(from: start, catalog: environment.quran) {
            result.append(range)
            start = range.endGlobalAyah + 1
        }
        return result
    }
    private var snapshots: [Int: VerseProgressSnapshot] { Dictionary(uniqueKeysWithValues: progress.map { ($0.globalAyah, $0.snapshot) }) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little more each time.").font(.system(.title2, design: .serif))
                    Text("Choose any passage to practice or revisit. These suggested passages can be changed in the reader.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                    Button("Read surah") { environment.openReader(.surah(number: surah.number)) }
                        .frame(minHeight: 44)
                }.padding(.vertical, 8)
            }.listRowBackground(Color.clear)
            Section("Your passages") {
                ForEach(passages, id: \.self) { range in
                    Button { environment.openPractice(range) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: statusSymbol(range)).foregroundStyle(Color.olive).frame(width: 24)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(LearningPassage.ayahLabel(range, catalog: environment.quran)).font(.headline)
                                Text(status(range)).font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.secondaryWarm)
                        }.padding(.vertical, 8)
                    }.buttonStyle(.plain).warmListRow()
                        .contextMenu {
                            Button("I already know these ayahs") { knownRange = range; showKnown = true }
                        }
                }
            }
            Section {
                Button("Review the whole surah") { environment.openPractice(.clamped(start: surah.startGlobalAyah, end: surah.endGlobalAyah)) }
                    .warmListRow()
                Button("I already know this surah") {
                    knownRange = .clamped(start: surah.startGlobalAyah, end: surah.endGlobalAyah)
                    showKnown = true
                }.warmListRow()
            }
        }
        .foregroundStyle(Color.appBrownText).warmListChrome().navigationTitle(surah.englishName)
        .confirmationDialog("Can you recite these ayahs from memory?", isPresented: $showKnown, titleVisibility: .visible) {
            Button("Yes, I know them") {
                guard let knownRange else { return }
                do { try environment.store.markMemorized(ayahs: knownRange.globalAyahs) }
                catch { errorMessage = .from(.persistenceFailure) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("We’ll remember this and suggest a review later.") }
        .alert(errorMessage?.title ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage?.message ?? "") }
    }

    private func status(_ range: VerseRange) -> String {
        let index = ProgressIndex(snapshots.values)
        if index.isDue(range) { return String(localized: "Ready to review") }
        switch index.status(of: range) {
        case .memorized: return String(localized: "Memorized · Review anytime")
        case .learning: return String(localized: "Learning")
        case .notStarted:
            return range.contains(environment.settings.learningStart) ? String(localized: "Continue here") : String(localized: "Not started")
        }
    }
    private func statusSymbol(_ range: VerseRange) -> String {
        let index = ProgressIndex(snapshots.values)
        if index.isDue(range) { return "arrow.counterclockwise" }
        return index.status(of: range).systemImage
    }
}

/// One line describing a surah's memorization, shared by progress lists.
struct SurahProgressSummary {
    let surah: Surah
    let index: ProgressIndex

    var memorized: Int { index.count(.memorized, in: surah.range) }
    var learning: Int { index.count(.learning, in: surah.range) }

    var text: String {
        if memorized == surah.ayahCount { return String(localized: "Memorized · Keep it fresh with review") }
        if learning == 0 { return String(localized: "\(memorized) of \(surah.ayahCount) memorized") }
        return String(localized: "\(memorized) of \(surah.ayahCount) memorized · \(learning) learning")
    }
}
