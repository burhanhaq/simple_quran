import SwiftUI

/// The top of the Memorize screen: today's checklist (at most one passage to learn and one to revise),
/// with what the user is memorizing underneath.
struct TodayCard: View {
    @Environment(AppEnvironment.self) private var environment
    let snapshots: [VerseProgressSnapshot]
    @Binding var picker: PlanPickerPurpose?
    @Binding var showKnown: Bool
    @AppStorage(ProgressOrder.storageKey) private var order = ProgressOrder.fromAnNas

    private var settings: AppSettings { environment.settings }

    var body: some View {
        let plan = settings.activePlan
        let today = TodayPlan(targets: settings.learningTargets, active: plan, snapshots: snapshots, catalog: environment.quran,
                              size: settings.pieceSize, cycle: settings.revisionCycle, log: settings.dailyLog)
        VStack(alignment: .leading, spacing: 14) {
            Label("TODAY", systemImage: "leaf")
                .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(.white.opacity(0.75))
            if let learn = today.learn, let plan {
                checklist(today, learn: learn, plan: plan)
                footer(plan)
            } else {
                gettingStarted
                if let revise = today.revise { reviseRow(revise, isHighlighted: false) }
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { ArchMotif().frame(width: 160, height: 220).offset(x: 45, y: -35) }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [TodayPalette.top, TodayPalette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    // MARK: - Checklist

    @ViewBuilder
    private func checklist(_ today: TodayPlan, learn: TodayPlan.LearnRow, plan: LearningTarget) -> some View {
        if today.isAllDone {
            Text("Done for today")
                .font(.system(.title, design: .serif).weight(.medium)).accessibilityIdentifier("memorize.doneForToday")
        }
        VStack(spacing: 6) {
            learnRow(learn, plan: plan)
            if let revise = today.revise {
                // The first thing left to do stands out; once learning is done, that's the revision.
                let learnIsDone = if case .done = learn { true } else { false }
                reviseRow(revise, isHighlighted: learnIsDone)
            }
            if today.isAllDone, case .done(_, let next?) = learn {
                TodayRow(systemImage: "plus", title: String(localized: "Next: \(LearningPassage.referenceLabel(next, catalog: environment.quran))"),
                         style: .outlined) {
                    environment.openSession(next, planID: plan.id)
                }.accessibilityIdentifier("memorize.keepGoing")
            }
        }
    }

    @ViewBuilder
    private func learnRow(_ learn: TodayPlan.LearnRow, plan: LearningTarget) -> some View {
        switch learn {
        case .next(let passage, let targetID, let started):
            TodayRow(title: String(localized: "Memorize \(surahName(passage))"),
                     subtitle: started ? LearningPassage.ayahLabel(passage, catalog: environment.quran)
                        : String(localized: "\(LearningPassage.ayahLabel(passage, catalog: environment.quran)) · Listen, recite, check"),
                     style: .highlighted) {
                environment.openSession(passage, planID: targetID)
            }.accessibilityIdentifier("memorize.start")
        case .done(let learned, _):
            TodayRow(title: String(localized: "Memorize \(surahName(learned))"),
                     subtitle: LearningPassage.ayahLabel(learned, catalog: environment.quran), style: .done)
        case .beginNext(let target, let passage):
            TodayRow(title: String(localized: "Begin \(target.title(catalog: environment.quran))"),
                     subtitle: String(localized: "You’ve memorized all of \(plan.title(catalog: environment.quran))"), style: .highlighted) {
                settings.setActivePlan(target)
                environment.openSession(passage, planID: target.id)
            }.accessibilityIdentifier("memorize.start")
        case .finished(let target):
            TodayRow(title: String(localized: "Choose what to memorize next"),
                     subtitle: String(localized: "You’ve memorized all of \(target.title(catalog: environment.quran))"), style: .highlighted) {
                picker = .plan
            }.accessibilityIdentifier("memorize.choosePlan")
        }
    }

    @ViewBuilder
    private func reviseRow(_ revise: TodayPlan.ReviseRow, isHighlighted: Bool) -> some View {
        switch revise {
        case .due(let surahName, let ayahs, let passages, let freshness, let more):
            let details = [ayahs, freshness.title, more > 0 ? String(localized: "\(more) more") : nil].compactMap { $0 }
            TodayRow(title: String(localized: "Revise \(surahName)"), subtitle: details.joined(separator: " · "),
                     style: isHighlighted ? .highlighted : .plain) {
                environment.openReviews(passages)
            }.accessibilityIdentifier("memorize.revise")
        case .done:
            TodayRow(title: String(localized: "Revised today"), style: .done)
        }
    }

    /// What the user is memorizing, with how far they've come; opens its details.
    private func footer(_ plan: LearningTarget) -> some View {
        let index = ProgressIndex(snapshots)
        let memorized = index.count(.memorized, in: plan.range)
        return NavigationLink { PlanDetailView() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memorizing").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(plan.title(catalog: environment.quran)).font(.headline)
                    ProgressView(value: Double(memorized), total: Double(max(plan.range.count, 1)))
                        .tint(TodayPalette.highlight).padding(.top, 2)
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(localized: "\(memorized) of \(plan.range.count) ayahs memorized"))
        .accessibilityIdentifier("memorize.plan")
    }

    // MARK: - Getting started

    /// Nothing chosen yet: suggest the usual first surah for the order the user reads the map in.
    @ViewBuilder
    private var gettingStarted: some View {
        let suggested = environment.quran.surah(number: order == .fromAnNas ? Self.lastSurah : Self.firstSurah)
        VStack(alignment: .leading, spacing: 8) {
            Text("Where would you like to begin?")
                .font(.system(.largeTitle, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Text(order == .fromAnNas ? "Most people start with the short surahs at the end." : "We’ll take it half a page at a time.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }
        if let suggested {
            HeroButton(title: String(localized: "Start with \(suggested.englishName)")) { start(suggested) }
                .accessibilityIdentifier("memorize.startSuggested")
        }
        VStack(spacing: 0) {
            Button { picker = .plan } label: {
                Text("Choose a different surah").frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("memorize.choosePlan")
            Button { showKnown = true } label: {
                Text("I already know some surahs").frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("memorize.markKnown")
        }
        .buttonStyle(.plain).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.9))
    }

    private static let firstSurah = 1
    private static let lastSurah = 114

    private func start(_ surah: Surah) {
        settings.setActivePlan(LearningTarget(range: surah.range))
        guard let plan = settings.activePlan,
              let passage = plan.nextPassage(catalog: environment.quran, size: settings.pieceSize, isMemorized: { _ in false }) else { return }
        environment.openSession(passage, planID: plan.id)
    }

    private func surahName(_ range: VerseRange) -> String {
        environment.quran.verse(globalAyah: range.startGlobalAyah)
            .flatMap { environment.quran.surah(number: $0.surahNumber) }?.englishName ?? ""
    }
}

/// The Today card's own greens, drawn on its dark background in light and dark mode alike.
private enum TodayPalette {
    static let top = Color(red: 0.15, green: 0.33, blue: 0.26)
    static let bottom = Color(red: 0.07, green: 0.23, blue: 0.18)
    static let highlight = Color(red: 0.85, green: 0.93, blue: 0.84)
    static let onHighlight = Color(red: 0.08, green: 0.23, blue: 0.17)
    static let tick = Color(red: 0.62, green: 0.88, blue: 0.69)
}

/// One line of today's checklist.
private struct TodayRow: View {
    enum Style {
        /// The next thing to do.
        case highlighted
        case plain
        /// Something extra, not part of today's list.
        case outlined
        case done
    }

    var systemImage: String?
    let title: String
    var subtitle: String?
    let style: Style
    var action: (() -> Void)?

    var body: some View {
        if let action, style != .done {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage ?? (style == .done ? "checkmark.circle.fill" : "circle"))
                .font(.title3)
                .foregroundStyle(style == .done ? TodayPalette.tick : style == .highlighted ? TodayPalette.onHighlight : .white.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).strikethrough(style == .done)
                    .foregroundStyle(style == .done ? .white.opacity(0.6) : style == .highlighted ? TodayPalette.onHighlight : .white)
                if let subtitle {
                    Text(subtitle).font(.caption)
                        .foregroundStyle(style == .highlighted ? TodayPalette.onHighlight.opacity(0.75) : .white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if style != .done {
                Image(systemName: style == .highlighted ? "arrow.right" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(style == .highlighted ? TodayPalette.onHighlight : .white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 54)
        .background {
            switch style {
            case .highlighted: RoundedRectangle(cornerRadius: 18).fill(TodayPalette.highlight)
            case .outlined: RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            case .plain, .done: Color.clear
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(style == .done ? [] : .isButton)
        .accessibilityValue(style == .done ? String(localized: "Done") : "")
    }
}

/// The card's main button when there's no checklist yet.
private struct HeroButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.right")
            }.font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20).frame(minHeight: 54)
                .background(TodayPalette.highlight, in: Capsule())
                .foregroundStyle(TodayPalette.onHighlight)
        }.buttonStyle(.plain)
    }
}
