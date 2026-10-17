import SwiftData
import SwiftUI

/// What the user has memorized, shown as honest counts and a map of the whole Quran.
struct ProgressTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    @Query private var sessions: [PracticeSession]
    @State private var browse = PlanBrowse.surahs

    var body: some View {
        let snapshots = progress.map(\.snapshot)
        let index = ProgressIndex(snapshots)
        let insights = ProgressInsights.make(snapshots: snapshots, activityDates: sessions.compactMap(\.endedAt),
                                             surahs: environment.quran.surahs, now: .now, calendar: .current)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(insights)
                    if let plan = environment.settings.activePlan {
                        NavigationLink { PlanDetailView() } label: { PlanCard(plan: plan, index: index) }.buttonStyle(.plain)
                    }
                    map(index)
                    activity(insights)
                }
                .foregroundStyle(Color.appBrownText)
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(AppTab.progress.title)
            .navigationDestination(for: Surah.self) { PassageProgressView(title: $0.englishName, range: $0.range) }
            .navigationDestination(for: JuzSection.self) { PassageProgressView(title: "Juz \($0.number)", range: $0.range) }
        }
    }

    private func header(_ insights: ProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(insights.memorizedCount)")
                .font(.system(size: 56, weight: .medium, design: .serif)).monospacedDigit()
                .accessibilityIdentifier("progress.memorizedCount")
            Text(insights.memorizedCount == 1 ? "ayah memorized" : "ayahs memorized").font(.headline)
            let details = [
                insights.learningCount > 0 ? String(localized: "\(insights.learningCount) learning") : nil,
                insights.needsRefreshCount > 0 ? String(localized: "\(insights.needsRefreshCount) need a refresh") : nil
            ].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.secondaryWarm)
            } else if insights.memorizedCount == 0 {
                Text("When you can recite a passage from memory, mark it as memorized. It will show here.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func map(_ index: ProgressIndex) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("The Quran").font(.title3.weight(.semibold))
                Spacer()
                MapLegend()
            }
            Picker("Browse", selection: $browse) {
                ForEach(PlanBrowse.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: browse == .surahs ? 44 : 56), spacing: 8)], spacing: 8) {
                switch browse {
                case .surahs:
                    ForEach(environment.quran.surahs) { surah in
                        NavigationLink(value: surah) {
                            MapTile(number: surah.number, range: surah.range, index: index)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(surah.englishName), \(SurahProgressSummary(surah: surah, index: index).text)")
                            .accessibilityIdentifier("progress.surah.\(surah.number)")
                    }
                case .juz:
                    ForEach(environment.quran.juzs) { juz in
                        NavigationLink(value: juz) {
                            MapTile(number: juz.number, range: juz.range, index: index)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Juz \(juz.number), \(index.count(.memorized, in: juz.range)) of \(juz.range.count) memorized")
                    }
                }
            }
        }
    }

    private func activity(_ insights: ProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days you practiced").font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(Array(insights.lastSevenDays.enumerated()), id: \.offset) { offset, practiced in
                    VStack(spacing: 6) {
                        Circle().fill(practiced ? Color.olive : Color.warmBorder.opacity(0.5)).frame(width: 18, height: 18)
                        Text(weekdayInitial(daysAgo: 6 - offset)).font(.caption2).foregroundStyle(Color.secondaryWarm)
                    }.frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Practiced \(insights.daysPracticedThisWeek) of the last 7 days")
            Text("Practice time is shown here. It doesn’t change what counts as memorized.")
                .font(.caption).foregroundStyle(Color.secondaryWarm)
        }
    }

    private func weekdayInitial(daysAgo: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return day.formatted(.dateTime.weekday(.narrow))
    }
}

/// A map square shaded by how much of its range is memorized.
private struct MapTile: View {
    let number: Int
    let range: VerseRange
    let index: ProgressIndex

    var body: some View {
        let memorized = index.count(.memorized, in: range)
        let learning = index.count(.learning, in: range)
        let fraction = Double(memorized) / Double(max(range.count, 1))
        Text("\(number)")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(fraction >= 0.6 ? Color.white : Color.appBrownText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(memorized > 0 ? Color.olive.opacity(0.25 + 0.75 * fraction) : Color.appWarmSurface))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(learning > 0 ? Color.bronze : Color.warmBorder.opacity(0.6), lineWidth: learning > 0 ? 1.5 : 0.5)
            }
    }
}

private struct MapLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            item(MemorizationStatus.memorized.title, fill: Color.olive, stroke: .clear)
            item(MemorizationStatus.learning.title, fill: Color.appWarmSurface, stroke: Color.bronze)
        }.font(.caption2).foregroundStyle(Color.secondaryWarm)
    }

    private func item(_ title: String, fill: Color, stroke: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 10, height: 10)
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(stroke, lineWidth: 1) }
            Text(title)
        }
    }
}
