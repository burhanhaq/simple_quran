import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @Query private var verseProgress: [VerseProgress]
    @State private var showSettings = false
    @State private var practiceSet: PracticeSet?

    var body: some View {
        let insights = progressInsights
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let loadError = environment.catalogLoadError {
                        FriendlyErrorView(message: loadError)
                    }
                    habitCard(insights)
                    continueCard
                    if !sets.isEmpty {
                        needsAttentionSection(practicedToday: insights.practicedToday)
                    }
                    recentSection
                }
                .padding()
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(String(localized: "Today"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("home.settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $practiceSet) { set in
                PracticeView(practiceSet: set)
            }
        }
    }

    @ViewBuilder
    private func habitCard(_ insights: ProgressInsights) -> some View {
        if insights.practicedCount > 0 {
            WarmCard {
                VStack(alignment: .leading, spacing: 6) {
                    if insights.practicedToday {
                        Text(String(localized: "Practiced today"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.appBrownText)
                        if insights.currentStreak > 1 {
                            Text(String(localized: "\(insights.currentStreak) day streak"))
                                .foregroundStyle(Color.olive)
                        }
                    } else if insights.currentStreak > 0 {
                        Text(String(localized: "Keep your \(insights.currentStreak) day streak"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.appBrownText)
                    } else {
                        Text(String(localized: "A short session keeps your ayahs fresh"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.appBrownText)
                    }
                }
            }
            .accessibilityIdentifier("home.habit")
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        if let last = lastPractisedSet {
            Button {
                practiceSet = last
            } label: {
                WarmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Continue last session"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.olive)
                        Text(last.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.appBrownText)
                        if let ayah = last.lastGlobalAyah, let verse = environment.quran.verse(globalAyah: ayah) {
                            Text(String(localized: "Resume at \(verse.reference)"))
                                .foregroundStyle(Color.secondaryWarm)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continue")
        } else if sets.isEmpty {
            EmptyStateView(
                title: String(localized: "Start with the Quran"),
                message: String(localized: "Listen to a surah, or collect ayahs to review later."),
                actionTitle: String(localized: "Listen to a surah"),
                actionIdentifier: "empty.listen",
                secondaryTitle: String(localized: "Save a passage to review"),
                secondaryAction: { environment.enterQuranForCollecting() }
            ) {
                environment.enterQuranToListen()
            }
        }
    }

    private func needsAttentionSection(practicedToday: Bool) -> some View {
        let due = needsAttention
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Needs attention"))
                .font(.headline)
                .foregroundStyle(Color.appBrownText)
            if due.isEmpty {
                Text(
                    practicedToday
                        ? String(localized: "Your ayahs are fresh. Open a collection if you want to keep going.")
                        : String(localized: "Pick up a collection whenever you’re ready.")
                )
                .foregroundStyle(Color.secondaryWarm)
            } else {
                ForEach(due, id: \.set.id) { item in
                    setRow(item.set, subtitle: String(localized: "\(item.dueCount) ayahs need review"))
                }
            }
        }
        .accessibilityIdentifier("home.due")
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = recentPractisedSets
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Recently practiced"))
                    .font(.headline)
                    .foregroundStyle(Color.appBrownText)
                ForEach(recent, id: \.id) { set in
                    setRow(set, subtitle: passageSummary(set))
                }
            }
        }
    }

    private func setRow(_ set: PracticeSet, subtitle: String) -> some View {
        Button {
            practiceSet = set
        } label: {
            WarmCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.title).font(.headline).foregroundStyle(Color.appBrownText)
                        Text(subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill").foregroundStyle(Color.gold).font(.title2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.set.\(set.id.uuidString)")
    }

    private var snapshots: [VerseProgressSnapshot] {
        verseProgress.map(\.snapshot)
    }

    private var progressInsights: ProgressInsights {
        ProgressInsights.make(
            snapshots: snapshots,
            surahs: environment.quran.surahs,
            now: .now,
            calendar: .current
        )
    }

    private var lastPractisedSet: PracticeSet? {
        sets
            .filter { $0.lastPractisedAt != nil }
            .max { ($0.lastPractisedAt ?? .distantPast) < ($1.lastPractisedAt ?? .distantPast) }
    }

    private var needsAttention: [(set: PracticeSet, dueCount: Int)] {
        let now = Date()
        return sets.compactMap { set in
            let count = ProgressInsights.dueAyahCount(
                in: set.orderedPassages.map(\.range),
                snapshots: snapshots,
                now: now
            )
            return count > 0 ? (set, count) : nil
        }
    }

    private var recentPractisedSets: [PracticeSet] {
        let continueID = lastPractisedSet?.id
        return Array(
            sets
                .filter { $0.lastPractisedAt != nil && $0.id != continueID }
                .sorted { ($0.lastPractisedAt ?? .distantPast) > ($1.lastPractisedAt ?? .distantPast) }
                .prefix(3)
        )
    }

    private func passageSummary(_ set: PracticeSet) -> String {
        let ranges = set.orderedPassages.map(\.range)
        let count = ranges.reduce(0) { $0 + $1.count }
        return String(localized: "\(count) ayahs · \(ranges.count) passages")
    }
}
