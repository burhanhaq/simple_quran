import SwiftData
import SwiftUI

/// What the user has memorized, shown as honest counts and a map of the whole Quran.
struct ProgressTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    @Query private var sessions: [PracticeSession]
    @State private var browse = PlanBrowse.surahs
    @State private var search = ""
    @AppStorage(ProgressLayout.storageKey) private var layout = ProgressLayout.map

    /// Searching always shows names, whichever layout is chosen.
    private var showsList: Bool { layout == .list || !search.isEmpty }

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
            .searchable(text: $search, prompt: browse == .surahs ? "Find a surah" : "Find a juz")
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
    }

    private var surahs: [Surah] {
        environment.quran.surahs.filter {
            search.isEmpty || "\($0.number) \($0.englishName) \($0.arabicName) \($0.translation) \($0.aliases.joined(separator: " "))"
                .localizedCaseInsensitiveContains(search)
        }
    }

    private var juzs: [JuzSection] {
        environment.quran.juzs.filter { search.isEmpty || "Juz \($0.number) \($0.number == 30 ? "Amma" : "")".localizedCaseInsensitiveContains(search) }
    }

    private func map(_ index: ProgressIndex) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("The Quran").font(.title3.weight(.semibold))
                Spacer()
                if !showsList { MapLegend() }
                Button { withAnimation(.snappy) { layout = layout == .map ? .list : .map } } label: {
                    Image(systemName: layout == .map ? "list.bullet" : "square.grid.3x3").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(Color.bronze)
                .accessibilityLabel(layout == .map ? "Show as list" : "Show as map")
                .accessibilityIdentifier("progress.layout")
            }
            Picker("Browse", selection: $browse) {
                ForEach(PlanBrowse.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            // Surahs and juz share ids 1–30, so each browse mode needs its own identity
            // or SwiftUI keeps the surah buttons when showing juz.
            Group { if showsList { list(index) } else { grid(index) } }.id(browse)
        }
    }

    private func grid(_ index: ProgressIndex) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: browse == .surahs ? 44 : 56), spacing: 8)], spacing: 8) {
            switch browse {
            case .surahs:
                ForEach(environment.quran.surahs) { surah in
                    Button { open(.surah(number: surah.number)) } label: {
                        MapTile(number: surah.number, range: surah.range, index: index)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(surah.englishName), \(SurahProgressSummary(surah: surah, index: index).text)")
                        .accessibilityIdentifier("progress.surah.\(surah.number)")
                }
            case .juz:
                ForEach(environment.quran.juzs) { juz in
                    Button { open(.juz(juz.number)) } label: {
                        MapTile(number: juz.number, range: juz.range, index: index)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Juz \(juz.number), \(index.count(.memorized, in: juz.range)) of \(juz.range.count) memorized")
                }
            }
        }
    }

    @ViewBuilder
    private func list(_ index: ProgressIndex) -> some View {
        let empty = browse == .surahs ? surahs.isEmpty : juzs.isEmpty
        if empty {
            ContentUnavailableView.search(text: search)
        } else {
            LazyVStack(spacing: 0) {
                switch browse {
                case .surahs:
                    ForEach(surahs) { surah in
                        Button { open(.surah(number: surah.number)) } label: {
                            ProgressListRow(number: surah.number, range: surah.range, index: index, title: surah.englishName,
                                            subtitle: "\(surah.translation) · \(surah.ayahCount) ayahs", arabicName: surah.arabicName)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("progress.list.surah.\(surah.number)")
                        if surah.id != surahs.last?.id { Divider().padding(.leading, 72) }
                    }
                case .juz:
                    ForEach(juzs) { juz in
                        Button { open(.juz(juz.number)) } label: {
                            ProgressListRow(number: juz.number, range: juz.range, index: index,
                                            title: PassageLabel.passage(juz.range, catalog: environment.quran),
                                            subtitle: LearningPassage.referenceLabel(juz.range, catalog: environment.quran), arabicName: nil)
                        }.buttonStyle(.plain)
                        if juz.id != juzs.last?.id { Divider().padding(.leading, 72) }
                    }
                }
            }
            .background(Color.appWarmSurface, in: RoundedRectangle(cornerRadius: AppTheme.tightRadius))
        }
    }

    /// Opens the surah screen with its overview up, so progress and pieces are the first thing seen.
    private func open(_ destination: QuranDestination) {
        environment.openReader(destination, sheet: .half)
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

enum ProgressLayout: String {
    case map
    case list

    static let storageKey = "progress.layout"
}

/// A named row for the list layout: the map square, the name, and how much is memorized.
private struct ProgressListRow: View {
    let number: Int
    let range: VerseRange
    let index: ProgressIndex
    let title: String
    let subtitle: String
    let arabicName: String?

    var body: some View {
        let memorized = index.count(.memorized, in: range)
        let learning = index.count(.learning, in: range)
        HStack(spacing: 14) {
            MapTile(number: number, range: range, index: index).frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.appBrownText).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Color.secondaryWarm).lineLimit(1)
                if memorized + learning > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(memorized), total: Double(range.count)).tint(Color.olive)
                        Text(memorized == range.count ? String(localized: "Memorized") : "\(memorized)/\(range.count)")
                            .font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(Color.olive)
                    }
                }
            }
            Spacer(minLength: 8)
            if let arabicName {
                Text(arabicName).font(.quran(.listName)).foregroundStyle(Color.appBrownText).multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
