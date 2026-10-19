import SwiftData
import SwiftUI

/// What the user has memorized, shown as honest counts and a map of the whole Quran.
struct ProgressTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    @State private var browse = PlanBrowse.surahs
    @State private var search = ""
    @AppStorage(ProgressLayout.storageKey) private var layout = ProgressLayout.map
    @State private var gridWidth: CGFloat = 0
    private static let gridSpacing: CGFloat = 8

    /// Searching always shows names, whichever layout is chosen.
    private var showsList: Bool { layout == .list || !search.isEmpty }

    var body: some View {
        let snapshots = progress.map(\.snapshot)
        let index = ProgressIndex(snapshots)
        let insights = ProgressInsights.make(snapshots: snapshots, surahs: environment.quran.surahs, cycle: environment.settings.revisionCycle,
                                             now: .now, calendar: .current)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(insights)
                    revisionBanner(index)
                    if let plan = environment.settings.activePlan {
                        NavigationLink { PlanDetailView() } label: { PlanCard(plan: plan, index: index) }.buttonStyle(.plain)
                    }
                    map(index)
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
                insights.needsRevisionCount > 0 ? String(localized: "\(insights.needsRevisionCount) need revision") : nil
            ].compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(Color.secondaryWarm)
            } else if insights.memorizedCount == 0 {
                Text("When you can recite a passage from memory, mark it as memorized. It will show here.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
            }
        }
    }

    private var cycle: RevisionCycle { environment.settings.revisionCycle }

    /// Memorized surahs that have gone too long without a revision, with the most urgent one a tap away.
    @ViewBuilder
    private func revisionBanner(_ index: ProgressIndex) -> some View {
        let toRevise = index.surahsToRevise(environment.quran.surahs, cycle: cycle)
        if let first = toRevise.first {
            let needsRevision = toRevise.filter { $0.freshness == .needsRevision }.count
            WarmCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Circle().fill(first.freshness.color).frame(width: 10, height: 10)
                        Text(needsRevision > 0
                             ? (needsRevision == 1 ? String(localized: "1 surah needs revision") : String(localized: "\(needsRevision) surahs need revision"))
                             : (toRevise.count == 1 ? String(localized: "1 surah is fading") : String(localized: "\(toRevise.count) surahs are fading")))
                            .font(.headline)
                    }
                    Text(toRevise.prefix(3).map(\.surah.englishName).joined(separator: ", ") + (toRevise.count > 3 ? "…" : ""))
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm).lineLimit(1)
                    Button { revise(first.surah, index: index) } label: {
                        Label("Revise \(first.surah.englishName)", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("progress.revise")
                }
            }
        }
    }

    private func revise(_ surah: Surah, index: ProgressIndex) {
        environment.openReviews(ReviewPlanner.memorizedPassages(in: surah.range, snapshots: progress.map(\.snapshot), catalog: environment.quran))
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
            if !showsList { MapLegend() }
            // Surahs and juz share ids 1–30, so each browse mode needs its own identity
            // or SwiftUI keeps the surah buttons when showing juz.
            Group { if showsList { list(index) } else { grid(index) } }.id(browse)
        }
    }

    private func grid(_ index: ProgressIndex) -> some View {
        let minimum: CGFloat = browse == .surahs ? 44 : 56
        // Matches how the adaptive grid fits columns, so each surah knows whether it starts or ends a row.
        let columns = max(1, Int((gridWidth + Self.gridSpacing) / (minimum + Self.gridSpacing)))
        let reach = Self.gridSpacing / 2
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: Self.gridSpacing)], spacing: Self.gridSpacing) {
            switch browse {
            case .surahs:
                ForEach(environment.quran.surahs) { surah in
                    let spans = JuzSpan.spans(of: surah.range, in: environment.quran.juzs)
                    let column = (surah.number - 1) % columns
                    let endsRow = column == columns - 1 || surah.number == environment.quran.surahs.count
                    Button { open(.surah(number: surah.number)) } label: {
                        VStack(spacing: 4) {
                            MapTile(number: surah.number, range: surah.range, index: index, cycle: cycle)
                            JuzBar(spans: spans, leading: column == 0 ? 0 : reach, trailing: endsRow ? 0 : reach)
                        }
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(surah.englishName), \(juzLabel(spans)), \(SurahProgressSummary(surah: surah, index: index, cycle: cycle).text)")
                        .accessibilityIdentifier("progress.surah.\(surah.number)")
                }
            case .juz:
                ForEach(environment.quran.juzs) { juz in
                    Button { open(.juz(juz.number)) } label: {
                        MapTile(number: juz.number, range: juz.range, index: index, cycle: cycle)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Juz \(juz.number), \(index.count(.memorized, in: juz.range)) of \(juz.range.count) memorized")
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
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
                            ProgressListRow(number: surah.number, range: surah.range, index: index, cycle: cycle, title: surah.englishName,
                                            subtitle: "\(surah.translation) · \(surah.ayahCount) ayahs", arabicName: surah.arabicName)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("progress.list.surah.\(surah.number)")
                        if surah.id != surahs.last?.id { Divider().padding(.leading, 72) }
                    }
                case .juz:
                    ForEach(juzs) { juz in
                        Button { open(.juz(juz.number)) } label: {
                            ProgressListRow(number: juz.number, range: juz.range, index: index, cycle: cycle,
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

    private func juzLabel(_ spans: [JuzSpan]) -> String {
        guard let first = spans.first?.juz, let last = spans.last?.juz else { return "" }
        return first == last ? String(localized: "Juz \(first)") : String(localized: "Juz \(first) to \(last)")
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
    let cycle: RevisionCycle
    let title: String
    let subtitle: String
    let arabicName: String?

    var body: some View {
        let memorized = index.count(.memorized, in: range)
        let learning = index.count(.learning, in: range)
        let freshness = index.freshness(of: range, cycle: cycle)
        let tint = freshness?.color ?? Color.olive
        HStack(spacing: 14) {
            MapTile(number: number, range: range, index: index, cycle: cycle).frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.appBrownText).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Color.secondaryWarm).lineLimit(1)
                if memorized + learning > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(memorized), total: Double(range.count)).tint(tint)
                        Text(memorized == range.count ? (freshness ?? .fresh).memorizedLabel : "\(memorized)/\(range.count)")
                            .font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(tint)
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

/// A map square shaded by how much of its range is memorized, colored by how fresh it is.
private struct MapTile: View {
    let number: Int
    let range: VerseRange
    let index: ProgressIndex
    let cycle: RevisionCycle

    var body: some View {
        let memorized = index.count(.memorized, in: range)
        let learning = index.count(.learning, in: range)
        let fraction = Double(memorized) / Double(max(range.count, 1))
        let fill = index.freshness(of: range, cycle: cycle)?.color ?? Color.olive
        Text("\(number)")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(fraction >= 0.6 ? Color.white : Color.appBrownText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(memorized > 0 ? fill.opacity(0.25 + 0.75 * fraction) : Color.appWarmSurface))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(learning > 0 ? Color.bronze : Color.warmBorder.opacity(0.6), lineWidth: learning > 0 ? 1.5 : 0.5)
            }
    }
}

/// A thin line under a surah tile, split where a new juz begins, with the juz number at each start.
/// It reaches into the gaps beside the tile so a row of surahs reads as one line,
/// broken only where a juz begins.
private struct JuzBar: View {
    let spans: [JuzSpan]
    /// How far the line reaches into the gap on each side; zero at the ends of a row.
    let leading: CGFloat
    let trailing: CGFloat
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 12
    private static let barHeight: CGFloat = 3
    private static let labelGap: CGFloat = 2
    private static let labelSpacing: CGFloat = 2
    /// The break inside a tile matches the one a juz starting at a tile's edge leaves in the half gap before it.
    private static let breakWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let tileWidth = size.width - leading - trailing
            let segments = spans.reduce(into: [(span: JuzSpan, x: CGFloat, width: CGFloat)]()) { result, span in
                result.append((span, result.last.map { $0.x + $0.width } ?? leading, tileWidth * span.fraction))
            }
            for (offset, segment) in segments.enumerated() {
                // The line runs on into the gaps beside the tile, except before a juz that begins with this surah.
                let start = offset > 0 ? segment.x + Self.breakWidth / 2 : (segment.span.startsHere ? leading : 0)
                let end = offset < segments.count - 1 ? segment.x + segment.width - Self.breakWidth / 2 : size.width
                context.fill(Path(CGRect(x: start, y: 0, width: end - start, height: Self.barHeight)),
                             with: .color(Color.bronze.opacity(0.6)))
            }
            // A juz starting near the tile's end is pulled back inside it; one that would overlap the previous number is skipped.
            var labelEnd = -CGFloat.infinity
            for segment in segments where segment.span.startsHere {
                let label = context.resolve(Text("\(segment.span.juz)").font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Color.secondaryWarm))
                let width = label.measure(in: size).width
                let x = max(leading, min(segment.x, leading + tileWidth - width))
                guard x >= labelEnd else { continue }
                context.draw(label, at: CGPoint(x: x, y: Self.barHeight + Self.labelGap), anchor: .topLeading)
                labelEnd = x + width + Self.labelSpacing
            }
        }
        .frame(height: Self.barHeight + Self.labelGap + labelHeight)
        .padding(.leading, -leading)
        .padding(.trailing, -trailing)
        .accessibilityHidden(true)
    }
}

private struct MapLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(Freshness.allCases, id: \.self) { item($0.title, fill: $0.color, stroke: .clear) }
            item(MemorizationStatus.learning.title, fill: Color.appWarmSurface, stroke: Color.bronze)
        }
        .font(.caption2).foregroundStyle(Color.secondaryWarm)
        .accessibilityElement(children: .combine)
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
    let cycle: RevisionCycle

    var memorized: Int { index.count(.memorized, in: surah.range) }
    var learning: Int { index.count(.learning, in: surah.range) }

    var text: String {
        if memorized == surah.ayahCount { return (index.freshness(of: surah.range, cycle: cycle) ?? .fresh).memorizedLabel }
        if learning == 0 { return String(localized: "\(memorized) of \(surah.ayahCount) memorized") }
        return String(localized: "\(memorized) of \(surah.ayahCount) memorized · \(learning) learning")
    }
}
