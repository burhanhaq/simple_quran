import SwiftData
import SwiftUI

struct ProgressViewScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]

    private var practiced: Set<Int> { Set(progress.filter { $0.exposureCount > 0 || $0.recallAttempts > 0 }.map(\.globalAyah)) }
    private var surahs: [Surah] {
        environment.quran.surahs.filter { surah in practiced.contains { $0 >= surah.startGlobalAyah && $0 <= surah.endGlobalAyah } }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(practiced.isEmpty ? "Every ayah is a beginning." : "\(practiced.count) ayahs practiced.")
                        .font(.system(.title, design: .serif))
                    Text("Your progress grows each time you return.").font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.padding(.vertical, 16)
            }.listRowBackground(Color.clear)
            Section { LearningFocusSection() }.listRowBackground(Color.clear)
            if surahs.isEmpty {
                Button("Choose a surah") { environment.selectedTab = .quran }.warmListRow()
            }
            ForEach(surahs) { surah in
                NavigationLink { SurahProgressView(surah: surah) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(surah.englishName).font(.headline)
                        let count = practiced.filter { $0 >= surah.startGlobalAyah && $0 <= surah.endGlobalAyah }.count
                        Text(count == surah.ayahCount ? "Whole surah practiced · Keep it close with review" : "\(count) ayahs practiced")
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
                do { try environment.store.applyRating(.solid, ayahs: knownRange.globalAyahs, now: .now) }
                catch { errorMessage = .from(.persistenceFailure) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("We’ll remember this and suggest a review later.") }
        .alert(errorMessage?.title ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage?.message ?? "") }
    }

    private func status(_ range: VerseRange) -> String {
        let items = range.globalAyahs.compactMap { snapshots[$0] }
        if items.contains(where: { $0.isDue }) { return "Ready to revisit" }
        if items.count == range.count && items.allSatisfy({ $0.lastRating == .solid }) { return "Recalled from memory" }
        if items.count == range.count && items.allSatisfy({ $0.exposureCount > 0 || $0.recallAttempts > 0 }) { return "Practiced · Revisit anytime" }
        if range.contains(environment.settings.learningStart) { return "Continue here" }
        if items.contains(where: { $0.exposureCount > 0 || $0.recallAttempts > 0 }) { return "In progress" }
        return "Ready when you are"
    }
    private func statusSymbol(_ range: VerseRange) -> String {
        let items = range.globalAyahs.compactMap { snapshots[$0] }
        if items.contains(where: { $0.isDue }) { return "arrow.counterclockwise" }
        if items.count == range.count && items.allSatisfy({ $0.exposureCount > 0 || $0.recallAttempts > 0 }) { return "checkmark.circle" }
        return range.contains(environment.settings.learningStart) ? "leaf" : "circle"
    }
}
