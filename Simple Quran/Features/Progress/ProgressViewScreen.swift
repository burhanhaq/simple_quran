import SwiftData
import SwiftUI

struct ProgressViewScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var verseProgress: [VerseProgress]
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @State private var practiceSet: PracticeSet?

    var body: some View {
        let insights = progressInsights
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if insights.knownCount == 0 && insights.practicedCount == 0 {
                        EmptyStateView(
                            title: String(localized: "See your progress here"),
                            message: String(localized: "Practice your first ayah. Start with Al-Fatihah or a short surah from Juz 30."),
                            actionTitle: String(localized: "Browse the Quran")
                        ) {
                            environment.selectedTab = .quran
                        }
                    } else {
                        if insights.knownCount == 0 {
                            practicedWithoutStrengthCard(insights.practicedCount)
                        } else {
                            heroCard(insights)
                        }
                        completedSurahsCard(insights.completedSurahs)
                        closestCard(insights.closestInProgress)
                        juz30Card(insights)
                        needsWorkSection(insights.weakAyahs)
                        habitFooter(insights)
                    }
                }
                .padding()
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(String(localized: "Progress"))
            .fullScreenCover(item: $practiceSet) { set in
                PracticeView(practiceSet: set)
            }
        }
    }

    private func practicedWithoutStrengthCard(_ practicedCount: Int) -> some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "You’ve practiced \(practicedCount) ayahs"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.appBrownText)
                Text(String(localized: "Rate a session to see strength."))
                    .foregroundStyle(Color.secondaryWarm)
            }
        }
        .accessibilityIdentifier("progress.practiced")
    }

    private func heroCard(_ insights: ProgressInsights) -> some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(insights.knownCount)")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.goldShine)
                Text(String(localized: "Ayahs you know"))
                    .font(.headline)
                    .foregroundStyle(Color.appBrownText)
                Text(String(localized: "across \(insights.surahsWithKnownAyahs) surahs"))
                    .foregroundStyle(Color.secondaryWarm)
                StrengthBar(
                    needsWork: insights.needsWorkCount,
                    growing: insights.growingCount,
                    strong: insights.strongCount
                )
                strengthLegend(insights)
            }
        }
        .accessibilityIdentifier("progress.hero")
    }

    private func strengthLegend(_ insights: ProgressInsights) -> some View {
        HStack(spacing: 14) {
            ForEach(MasteryStrength.legendOrder, id: \.self) { strength in
                let count = insights.count(of: strength)
                if count > 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: strength))
                            .frame(width: 8, height: 8)
                        Text("\(strength.title) · \(count)")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryWarm)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completedSurahsCard(_ surahs: [Surah]) -> some View {
        if !surahs.isEmpty {
            WarmCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "\(surahs.count) surahs complete"))
                        .font(.headline)
                        .foregroundStyle(Color.appBrownText)
                    Text(surahs.map(\.englishName).joined(separator: " · "))
                        .foregroundStyle(Color.olive)
                }
            }
            .accessibilityIdentifier("progress.completed")
        }
    }

    @ViewBuilder
    private func closestCard(_ item: InProgressSurah?) -> some View {
        if let item {
            WarmCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Closest to complete"))
                        .font(.headline)
                        .foregroundStyle(Color.appBrownText)
                    Text("\(item.surah.englishName) \(item.knownCount)/\(item.ayahCount)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.goldShine)
                }
            }
            .accessibilityIdentifier("progress.closest")
        }
    }

    @ViewBuilder
    private func juz30Card(_ insights: ProgressInsights) -> some View {
        if insights.juz30HasProgress {
            WarmCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Juz 30"))
                        .font(.headline)
                        .foregroundStyle(Color.appBrownText)
                    Text(
                        String(
                            localized: "\(insights.juz30CompletedCount) of \(ProgressInsights.juz30SurahCount) surahs"
                        )
                    )
                    .foregroundStyle(Color.olive)
                }
            }
            .accessibilityIdentifier("progress.juz30")
        }
    }

    @ViewBuilder
    private func needsWorkSection(_ ayahs: [VerseProgressSnapshot]) -> some View {
        if !ayahs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Needs work"))
                    .font(.headline)
                    .foregroundStyle(Color.appBrownText)
                ForEach(ayahs, id: \.globalAyah) { item in
                    if let verse = environment.quran.verse(globalAyah: item.globalAyah) {
                        weakAyahRow(item, verse: verse)
                    }
                }
            }
            .accessibilityIdentifier("progress.weak")
        }
    }

    @ViewBuilder
    private func weakAyahRow(_ item: VerseProgressSnapshot, verse: QuranVerse) -> some View {
        let collection = collection(containing: item.globalAyah)
        if let collection {
            Button {
                practiceSet = collection
            } label: {
                weakAyahCard(verse: verse, showsPlay: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.weak.\(item.globalAyah)")
        } else {
            weakAyahCard(verse: verse, showsPlay: false)
                .accessibilityIdentifier("progress.weak.\(item.globalAyah)")
        }
    }

    private func weakAyahCard(verse: QuranVerse, showsPlay: Bool) -> some View {
        WarmCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verse.reference)
                        .font(.headline)
                        .foregroundStyle(Color.appBrownText)
                    Text(MasteryStrength.needsWork.title)
                        .font(.caption)
                        .foregroundStyle(Color.olive)
                }
                Spacer()
                if showsPlay {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.goldShine)
                        .font(.title2)
                }
            }
        }
    }

    @ViewBuilder
    private func habitFooter(_ insights: ProgressInsights) -> some View {
        if insights.practicedCount > 0 {
            WarmCard {
                HStack {
                    if insights.currentStreak > 0 {
                        Text(String(localized: "\(insights.currentStreak) day streak"))
                            .font(.headline)
                            .foregroundStyle(Color.appBrownText)
                    } else {
                        Text(String(localized: "Practice days"))
                            .font(.headline)
                            .foregroundStyle(Color.appBrownText)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Array(insights.lastSevenDays.enumerated()), id: \.offset) { _, practiced in
                            Circle()
                                .fill(practiced ? Color.gold : Color.secondaryWarm.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Last seven days"))
                }
            }
            .accessibilityIdentifier("progress.habit")
        }
    }

    private var progressInsights: ProgressInsights {
        ProgressInsights.make(
            snapshots: verseProgress.map(\.snapshot),
            surahs: environment.quran.surahs,
            now: .now,
            calendar: .current
        )
    }

    private func collection(containing globalAyah: Int) -> PracticeSet? {
        sets.first { set in
            set.orderedPassages.contains { $0.range.contains(globalAyah) }
        }
    }

    private func color(for strength: MasteryStrength) -> Color {
        switch strength {
        case .strong: .gold
        case .growing: .olive
        case .needsWork: .dangerWarm
        }
    }
}

private extension MasteryStrength {
    static let legendOrder: [MasteryStrength] = [.strong, .growing, .needsWork]
}

private struct StrengthBar: View {
    var needsWork: Int
    var growing: Int
    var strong: Int

    private struct Segment: Identifiable {
        var id: MasteryStrength
        var count: Int
        var color: Color
    }

    private var segments: [Segment] {
        [
            Segment(id: .strong, count: strong, color: .gold),
            Segment(id: .growing, count: growing, color: .olive),
            Segment(id: .needsWork, count: needsWork, color: .dangerWarm)
        ]
        .filter { $0.count > 0 }
    }

    private var total: Int { needsWork + growing + strong }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(segments) { segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: barWidth(for: segment.count, in: geo.size.width))
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Recall strength"))
    }

    private func barWidth(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let spacing = CGFloat(max(segments.count - 1, 0)) * 3
        let usable = max(totalWidth - spacing, 0)
        return usable * CGFloat(count) / CGFloat(total)
    }
}
