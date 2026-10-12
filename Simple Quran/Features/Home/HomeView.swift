import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @Query private var verseProgress: [VerseProgress]
    @State private var showSettings = false
    @State private var practiceSet: PracticeSet?
    @State private var errorMessage: UserFacingMessage?

    var body: some View {
        let insights = progressInsights
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(String(localized: "Make space for the Quran."))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryWarm)
                        .padding(.top, -8)
                    if let loadError = environment.catalogLoadError {
                        FriendlyErrorView(message: loadError)
                    }
                    practiceHero
                    dailyRhythm(insights)
                    quickActions
                    if !needsAttention.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: String(localized: "Ready to revisit"), subtitle: String(localized: "A little review goes a long way."))
                            ForEach(needsAttention.prefix(3), id: \.set.id) { item in
                                setRow(item.set, subtitle: String(localized: "\(item.dueCount) ayahs to review"))
                            }
                        }
                        .accessibilityIdentifier("home.due")
                    }
                    listeningSection
                    if !recentPractisedSets.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeading(title: String(localized: "Your recent practice"))
                            ForEach(recentPractisedSets, id: \.id) { set in
                                setRow(set, subtitle: passageSummary(set))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color.parchment.ignoresSafeArea())
            .parchmentNavigationBar()
            .navigationTitle(String(localized: "Today"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(String(localized: "Settings"))
                        .accessibilityIdentifier("home.settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $practiceSet) { PracticeView(practiceSet: $0) }
            .navigationDestination(for: QuranDestination.self) { QuranReaderView(destination: $0) }
            .alert(errorMessage?.title ?? "", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: { Text(errorMessage?.message ?? "") }
        }
    }

    private var practiceHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(String(localized: "YOUR DAILY PRACTICE"), systemImage: "sparkle")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Color(red: 0.74, green: 0.87, blue: 0.77))
            Text(lastPractisedSet == nil
                 ? String(localized: "A little each day.\nRemember for life.")
                 : String(localized: "Keep the words\nclose to your heart."))
                .font(.system(.largeTitle, design: .serif).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let last = lastPractisedSet {
                VStack(alignment: .leading, spacing: 5) {
                    Text(last.title).font(.headline)
                    Text(passageSummary(last)).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
            } else {
                Text(String(localized: "Listen. Repeat. Recite.\nBegin your memorization with Al-Fatihah."))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(3)
            }
            Button {
                if let last = lastPractisedSet { practiceSet = last } else { startFirstPractice() }
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(lastPractisedSet == nil ? String(localized: "Practice Al-Fatihah") : String(localized: "Continue practice"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .frame(minHeight: 52)
                .foregroundStyle(Color(red: 0.09, green: 0.23, blue: 0.17))
                .background(Color(red: 0.82, green: 0.93, blue: 0.83), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(lastPractisedSet == nil ? "home.startPractice" : "home.continue")
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            ArchMotif().frame(width: 190, height: 280).offset(x: 48, y: -36)
        }
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.32, blue: 0.25), Color(red: 0.06, green: 0.22, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private func dailyRhythm(_ insights: ProgressInsights) -> some View {
        HStack(spacing: 16) {
            Image(systemName: insights.practicedToday ? "checkmark.seal.fill" : "leaf")
                .font(.title2).foregroundStyle(Color.bronze)
            VStack(alignment: .leading, spacing: 4) {
                Text(insights.practicedToday ? String(localized: "You made time today") : String(localized: "Small steps, lasting connection"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.appBrownText)
                Text(insights.currentStreak > 0 ? String(localized: "\(insights.currentStreak) day streak · keep growing") : String(localized: "Your practice grows one ayah at a time."))
                    .font(.caption).foregroundStyle(Color.secondaryWarm)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("home.habit")
    }

    private var quickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { listenAction; collectAction }
            VStack(spacing: 12) { listenAction; collectAction }
        }
    }

    private var listenAction: some View {
        Button { environment.enterQuranToListen() } label: {
            actionCard(title: String(localized: "Just listen"), subtitle: String(localized: "Find your calm"), symbol: "headphones")
        }
        .buttonStyle(.plain).accessibilityIdentifier("empty.listen")
    }

    private var collectAction: some View {
        Button { environment.enterQuranForCollecting() } label: {
            actionCard(title: String(localized: "Memorize"), subtitle: String(localized: "Choose your ayahs"), symbol: "rectangle.stack.badge.plus")
        }
        .buttonStyle(.plain).accessibilityIdentifier("empty.collect")
    }

    private func actionCard(title: String, subtitle: String, symbol: String) -> some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(Color.bronze)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Color.appBrownText)
                    Text(subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                }
            }
        }
    }

    private var listeningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: String(localized: "A moment with the Quran"))
                Spacer()
                Button(String(localized: "See all")) { environment.enterQuranToListen() }
                    .font(.subheadline.weight(.medium))
            }
            ForEach([1, 112, 113, 114], id: \.self) { number in
                if let surah = environment.quran.surah(number: number) {
                    NavigationLink(value: QuranDestination.surah(number: number)) {
                        HStack(spacing: 14) {
                            WarmSymbol(systemName: "waveform", size: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(surah.englishName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.appBrownText)
                                Text("\(surah.translation) · \(surah.ayahCount) ayahs").font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startFirstPractice() {
        guard let range = QuranDestination.surah(number: 1).range(in: environment.quran) else { return }
        if let existing = sets.first(where: { $0.orderedPassages.map(\.range) == [range] }) {
            practiceSet = existing
            return
        }
        do {
            practiceSet = try environment.store.createSet(
                title: environment.quran.surah(number: 1)?.englishName ?? "Al-Fatihah",
                passages: [range], settings: .default
            )
        } catch { errorMessage = UserFacingMessage.from(.persistenceFailure) }
    }

    private func setRow(_ set: PracticeSet, subtitle: String) -> some View {
        Button { practiceSet = set } label: {
            WarmCard {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(set.title).font(.headline).foregroundStyle(Color.appBrownText)
                        Text(subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                    Spacer()
                    PlayGlyph()
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
