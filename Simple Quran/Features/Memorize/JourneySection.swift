import SwiftData
import SwiftUI

/// The user's journey through the whole Quran: a map of what they've memorized, with honest counts below it.
struct JourneySection: View {
    @Environment(AppEnvironment.self) private var environment
    let snapshots: [VerseProgressSnapshot]
    let search: String
    @State private var browse = PlanBrowse.surahs
    @AppStorage(ProgressLayout.storageKey) private var layout = ProgressLayout.map
    @AppStorage(ProgressOrder.storageKey) private var order = ProgressOrder.fromAnNas
    /// Juz the user unfolded from a "not started" line.
    @State private var revealedJuz: Set<Int> = []
    /// Juz the user opened or closed by hand; the rest start open.
    @State private var juzOpen: [Int: Bool] = [:]
    private static let gridSpacing: CGFloat = 8

    /// Searching always shows names, whichever layout is chosen.
    private var showsList: Bool { layout == .list || !search.isEmpty }

    var body: some View {
        let index = ProgressIndex(snapshots)
        let insights = ProgressInsights.make(snapshots: snapshots, surahs: environment.quran.surahs, cycle: environment.settings.revisionCycle,
                                             now: .now, calendar: .current)
        VStack(alignment: .leading, spacing: 24) {
            map(index)
            if search.isEmpty { memorizedSummary(insights) }
        }
    }

    private func memorizedSummary(_ insights: ProgressInsights) -> some View {
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

    /// The chosen order while browsing; best match first while searching.
    private var surahs: [Surah] {
        search.isEmpty ? order.arranged(environment.quran.surahs) : environment.quran.surahs(matching: search)
    }

    private var juzs: [JuzSection] {
        search.isEmpty ? order.arranged(environment.quran.juzs) : environment.quran.juzs(matching: search)
    }

    private func map(_ index: ProgressIndex) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Your journey").font(.system(.title2, design: .serif).weight(.medium))
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
            HStack(spacing: 12) {
                Text("Start from").font(.subheadline).foregroundStyle(Color.secondaryWarm)
                Spacer()
                Picker("Start from", selection: $order.animation(.snappy)) {
                    ForEach(ProgressOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                .accessibilityIdentifier("progress.order")
            }
            if !showsList { MapLegend() }
            // Surahs and juz share ids 1–30, so each browse mode needs its own identity
            // or SwiftUI keeps the surah buttons when showing juz.
            Group { if showsList { list(index) } else { grid(index) } }.id(browse)
        }
    }

    @ViewBuilder
    private func grid(_ index: ProgressIndex) -> some View {
        switch browse {
        case .surahs:
            juzMap(index)
        case .juz:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: Self.gridSpacing)], spacing: Self.gridSpacing) {
                ForEach(order.arranged(environment.quran.juzs)) { juz in
                    Button { open(.juz(juz.number)) } label: {
                        MapTile(number: juz.number, range: juz.range, index: index, cycle: cycle)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Juz \(juz.number), \(index.count(.memorized, in: juz.range)) of \(juz.range.count) memorized")
                }
            }
        }
    }

    /// Surahs grouped by juz, with the juz not started yet folded out of the way so the user's own progress is near the top.
    private func juzMap(_ index: ProgressIndex) -> some View {
        let rows = ProgressMap.rows(environment.quran.juzs, order: order, revealed: revealedJuz) { index.status(of: $0.range) != .notStarted }
        return LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                switch row {
                case .juz(let juz): juzSection(juz, index: index)
                case .unstarted(let numbers): unstartedRow(numbers)
                }
            }
        }
    }

    private func juzSection(_ juz: JuzSection, index: ProgressIndex) -> some View {
        let isOpen = juzOpen[juz.number] ?? true
        return VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { juzOpen[juz.number] = !isOpen } } label: {
                JuzHeader(juz: juz, index: index, cycle: cycle, isOpen: isOpen)
            }.buttonStyle(.plain)
            if isOpen {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: Self.gridSpacing)], spacing: Self.gridSpacing) {
                    ForEach(order.arranged(ProgressMap.surahs(in: juz, from: environment.quran.surahs))) { part in
                        Button { open(.surah(number: part.surah.number)) } label: {
                            MapTile(number: part.surah.number, range: part.range, index: index, cycle: cycle)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(part.surah.englishName), \(SurahProgressSummary(surah: part.surah, index: index, cycle: cycle).text)")
                            // A surah that runs across juz shows in each; only the juz it begins in carries its plain identifier.
                            .accessibilityIdentifier(part.startsHere ? "progress.surah.\(part.surah.number)" : "progress.surah.\(part.surah.number).juz.\(juz.number)")
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    /// A quiet divider standing in for a run of juz not started yet, so it reads as a gap in the map; tapping it lays them out.
    private func unstartedRow(_ numbers: ClosedRange<Int>) -> some View {
        Button { withAnimation(.snappy) { revealedJuz.formUnion(numbers) } } label: {
            HStack(spacing: 10) {
                Rectangle().fill(Color.warmBorder).frame(height: 1)
                HStack(spacing: 4) {
                    Text(numbers.count == 1 ? "Juz \(numbers.lowerBound) · not started" : "Juz \(numbers.lowerBound)–\(numbers.upperBound) · not started")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.footnote).foregroundStyle(Color.secondaryWarm).fixedSize()
                Rectangle().fill(Color.warmBorder).frame(height: 1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(numbers.count == 1 ? "Juz \(numbers.lowerBound), not started" : "Juz \(numbers.lowerBound) to \(numbers.upperBound), not started")
        .accessibilityHint("Shows their surahs")
        .accessibilityIdentifier("progress.unstarted.\(numbers.lowerBound)")
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

/// A juz's name and a bar of how much of it is memorized; tapping it shows or hides its surahs.
private struct JuzHeader: View {
    let juz: JuzSection
    let index: ProgressIndex
    let cycle: RevisionCycle
    let isOpen: Bool
    /// Keeps a sliver of the bar visible once anything is memorized, even a few ayahs of a long juz.
    private static let minimumVisibleFraction = 0.03

    var body: some View {
        let memorized = index.count(.memorized, in: juz.range)
        let fraction = memorized == 0 ? 0 : max(Double(memorized) / Double(max(juz.range.count, 1)), Self.minimumVisibleFraction)
        HStack(spacing: 12) {
            Text("Juz \(juz.number)").font(.headline).frame(minWidth: 64, alignment: .leading)
            ProgressView(value: fraction).tint(index.freshness(of: juz.range, cycle: cycle)?.color ?? Color.olive)
            Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Juz \(juz.number), \(memorized) of \(juz.range.count) ayahs memorized")
        .accessibilityValue(isOpen ? "Shown" : "Hidden")
        .accessibilityIdentifier("progress.juz.\(juz.number)")
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
