import SwiftData
import SwiftUI

/// The daily home for memorizing: only what to do now, with everything else one tap away.
struct MemorizeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var verseProgress: [VerseProgress]
    @Query private var sessions: [PracticeSession]
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }) private var sets: [PracticeSet]
    @State private var showSettings = false
    @State private var picker: PlanPickerPurpose?
    @State private var pendingRange: VerseRange?
    @State private var showKnown = false

    private var snapshots: [VerseProgressSnapshot] { verseProgress.map(\.snapshot) }
    private var plan: LearningTarget? { environment.settings.activePlan }

    var body: some View {
        let index = ProgressIndex(snapshots)
        let next = plan?.nextPassage(catalog: environment.quran, byPage: environment.settings.practiceByPage) { index.status(of: $0) == .memorized }
        let reviews = ReviewPlanner.duePassages(snapshots: snapshots, catalog: environment.quran)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = environment.catalogLoadError { FriendlyErrorView(message: error) }
                    if environment.settings.showsStatusChangeNote { statusChangeNote }
                    todayCard(next: next, index: index)
                    if !reviews.isEmpty { reviewCard(reviews) }
                    if let plan {
                        NavigationLink { PlanDetailView() } label: { PlanCard(plan: plan, index: index) }
                            .buttonStyle(.plain).accessibilityIdentifier("memorize.plan")
                    }
                    if let resume = resumeRange(index: index, next: next) {
                        Button { environment.openSession(resume) } label: {
                            WarmCard {
                                HStack(spacing: 14) {
                                    WarmSymbol(systemName: "arrow.uturn.forward")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Pick up where you left off").font(.headline)
                                        Text(LearningPassage.referenceLabel(resume, catalog: environment.quran))
                                            .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("memorize.resume")
                    }
                    Button { picker = .oneOff } label: {
                        Label("Memorize something else", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(WarmButtonStyle(emphasis: .secondary)).accessibilityIdentifier("memorize.other")
                    activityLine
                }
                .foregroundStyle(Color.appBrownText)
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(AppTab.memorize.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("memorize.settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showKnown) {
                NavigationStack {
                    KnownSurahsView(continueTitle: String(localized: "Save")) {
                        environment.settings.showsStatusChangeNote = false
                        showKnown = false
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showKnown = false } } }
                }.tint(Color.bronze)
            }
            .sheet(item: $picker, onDismiss: {
                if let pendingRange {
                    self.pendingRange = nil
                    environment.openSession(pendingRange)
                }
            }) { purpose in
                PlanPickerView(purpose: purpose) { pendingRange = $0 }
            }
        }
    }

    /// Shown once after the update that made memorization an explicit claim.
    private var statusChangeNote: some View {
        WarmCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your progress now counts only what you mark as memorized").font(.headline)
                Text("Listening and practice still show as activity. If you already know some surahs, mark them so your progress is right.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                HStack(spacing: 12) {
                    Button("Mark what I know") { showKnown = true }
                        .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("note.markKnown")
                    Button("Got it") { environment.settings.showsStatusChangeNote = false }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("note.dismiss")
                }
            }
        }
    }

    private func todayCard(next: VerseRange?, index: ProgressIndex) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("TODAY", systemImage: "leaf")
                .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(.white.opacity(0.75))
            if let plan, let next {
                let started = index.status(of: plan.range) != .notStarted
                VStack(alignment: .leading, spacing: 8) {
                    Text(started ? "Continue \(surahName(next))" : "Begin \(surahName(next))")
                        .font(.system(.largeTitle, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text(LearningPassage.ayahLabel(next, catalog: environment.quran))
                        .font(.headline).foregroundStyle(.white.opacity(0.86))
                }
                Text("Listen, recite along, then try it from memory.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                heroButton(started ? "Continue memorizing" : "Start memorizing", identifier: "memorize.start") {
                    environment.openSession(next, planID: plan.id)
                }
            } else if let plan {
                Text("You’ve memorized all of \(plan.title(catalog: environment.quran)).")
                    .font(.system(.title, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text("Keep it fresh with review, or choose what to memorize next.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                heroButton("Choose your next plan", identifier: "memorize.choosePlan") { picker = .plan }
            } else {
                Text("What would you like to memorize?")
                    .font(.system(.largeTitle, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text("Pick a surah, a juz, or a few ayahs. We’ll take it a small passage at a time.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                heroButton("Choose a plan", identifier: "memorize.choosePlan") { picker = .plan }
                Button { environment.selectedTab = .quran } label: {
                    Text("Just read or listen").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { ArchMotif().frame(width: 160, height: 220).offset(x: 45, y: -35) }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.15, green: 0.33, blue: 0.26), Color(red: 0.07, green: 0.23, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }

    private func heroButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.right")
            }.font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20).frame(minHeight: 54)
                .background(Color(red: 0.85, green: 0.93, blue: 0.84), in: Capsule())
                .foregroundStyle(Color(red: 0.08, green: 0.23, blue: 0.17))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private func reviewCard(_ reviews: [VerseRange]) -> some View {
        Button { environment.openReviews(reviews) } label: {
            WarmCard {
                HStack(spacing: 14) {
                    WarmSymbol(systemName: "arrow.counterclockwise")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review").font(.headline)
                        Text(reviews.count == 1 ? "1 passage ready · \(LearningPassage.referenceLabel(reviews[0], catalog: environment.quran))" : "\(reviews.count) passages ready")
                            .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("memorize.review")
    }

    @ViewBuilder
    private var activityLine: some View {
        let insights = ProgressInsights.make(snapshots: [], activityDates: sessions.compactMap(\.endedAt) + snapshots.compactMap(\.lastPractisedAt),
                                             surahs: [], now: .now, calendar: .current)
        if insights.practicedToday {
            Label("You made time today.", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Color.olive)
        } else if insights.daysPracticedThisWeek > 0 {
            Label("You practiced \(insights.daysPracticedThisWeek) of the last 7 days.", systemImage: "calendar")
                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
        }
    }

    /// A one-off passage the user started recently and hasn't memorized yet.
    private func resumeRange(index: ProgressIndex, next: VerseRange?) -> VerseRange? {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        guard let recent = sets.filter({ ($0.lastPractisedAt ?? .distantPast) > weekAgo })
            .max(by: { ($0.lastPractisedAt ?? .distantPast) < ($1.lastPractisedAt ?? .distantPast) }),
              let range = recent.orderedPassages.first?.range,
              range != next,
              !(plan?.range.contains(range.startGlobalAyah) ?? false),
              index.status(of: range) != .memorized else { return nil }
        return range
    }

    private func surahName(_ range: VerseRange) -> String {
        environment.quran.verse(globalAyah: range.startGlobalAyah)
            .flatMap { environment.quran.surah(number: $0.surahNumber) }?.englishName ?? ""
    }
}
