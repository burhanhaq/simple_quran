import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var verseProgress: [VerseProgress]
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }) private var saved: [PracticeSet]
    @State private var showSettings = false

    private var currentRange: VerseRange? {
        let start = environment.settings.learningStart
        if environment.quran.verse(globalAyah: start) != nil,
           environment.quran.verse(globalAyah: environment.settings.learningEnd) != nil {
            return .clamped(start: start, end: environment.settings.learningEnd)
        }
        if let recent = saved.filter({ $0.lastPractisedAt != nil }).max(by: { ($0.lastPractisedAt ?? .distantPast) < ($1.lastPractisedAt ?? .distantPast) }),
           let start = recent.lastGlobalAyah ?? recent.orderedPassages.first?.startGlobalAyah {
            return LearningPassage.suggested(from: start, catalog: environment.quran)
        }
        return LearningPassage.suggested(from: 1, catalog: environment.quran)
    }
    private var currentSurah: Surah? {
        currentRange.flatMap { environment.quran.verse(globalAyah: $0.startGlobalAyah) }
            .flatMap { environment.quran.surah(number: $0.surahNumber) }
    }
    private var hasStarted: Bool { environment.settings.learningStart > 0 || verseProgress.contains { $0.lastPractisedAt != nil } }
    private var reviewRange: VerseRange? {
        let due = verseProgress.map(\.snapshot).filter { $0.isDue }.sorted { ($0.nextReviewAt ?? .distantPast) < ($1.nextReviewAt ?? .distantPast) }
        guard let first = due.first, let verse = environment.quran.verse(globalAyah: first.globalAyah) else { return nil }
        let ids = Set(due.map(\.globalAyah))
        var end = first.globalAyah
        while end < first.globalAyah + 2, ids.contains(end + 1), environment.quran.verse(globalAyah: end + 1)?.surahNumber == verse.surahNumber { end += 1 }
        return .clamped(start: first.globalAyah, end: end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("One small step at a time.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                    if let error = environment.catalogLoadError { FriendlyErrorView(message: error) }
                    hero
                    if let range = reviewRange {
                        Button { environment.openPractice(range, isReview: true) } label: {
                            WarmCard {
                                HStack(spacing: 14) {
                                    WarmSymbol(systemName: "arrow.counterclockwise")
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("A little review").font(.headline)
                                        Text(PassageLabel.passage(range, catalog: environment.quran)).font(.subheadline).foregroundStyle(Color.secondaryWarm)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("home.review")
                    }
                    if let surah = currentSurah, hasStarted {
                        NavigationLink { SurahProgressView(surah: surah) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Your time with \(surah.englishName)").font(.headline)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.subheadline)
                                }
                                let count = verseProgress.filter { $0.globalAyah >= surah.startGlobalAyah && $0.globalAyah <= surah.endGlobalAyah && ($0.exposureCount > 0 || $0.recallAttempts > 0) }.count
                                ProgressView(value: Double(count), total: Double(surah.ayahCount)).tint(Color.olive)
                                Text(count == 0 ? "A place to begin. A little more each time." : "\(count) ayahs practiced · View progress")
                                    .font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("home.progress")
                    }
                    if let verse = environment.quran.verse(globalAyah: environment.settings.readingAyah),
                       let surah = environment.quran.surah(number: verse.surahNumber) {
                        Button { environment.openReader(.surah(number: surah.number, scrollToAyah: verse.globalAyah)) } label: {
                            Label("Continue reading · \(surah.englishName)", systemImage: "book")
                                .font(.subheadline).frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                    if verseProgress.contains(where: { $0.lastPractisedAt.map { Calendar.current.isDateInToday($0) } ?? false }) {
                        Label("You made time today.", systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(Color.olive)
                    }
                    NavigationLink { ProgressViewScreen() } label: {
                        Label("Your progress", systemImage: "leaf").font(.subheadline).frame(minHeight: 44)
                    }
                }
                .foregroundStyle(Color.appBrownText)
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("home.settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(hasStarted ? "YOUR NEXT STEP" : "A SMALL BEGINNING", systemImage: "leaf")
                .font(.caption.weight(.semibold)).tracking(1.6).foregroundStyle(.white.opacity(0.75))
            if let surah = currentSurah, let range = currentRange {
                VStack(alignment: .leading, spacing: 8) {
                    Text(hasStarted ? "Continue \(surah.englishName)" : "Begin with \(surah.englishName)")
                        .font(.system(.largeTitle, design: .serif).weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Text(LearningPassage.ayahLabel(range, catalog: environment.quran))
                        .font(.headline).foregroundStyle(.white.opacity(0.86))
                }
                Text(hasStarted ? "Listen, repeat, and take your time." : "A few ayahs. A moment of focus.\nBegin at your own pace.")
                    .font(.subheadline).lineSpacing(4).foregroundStyle(.white.opacity(0.8))
                Button { environment.openPractice(range) } label: {
                    HStack {
                        Text(hasStarted ? "Continue practice" : "Start practicing")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }.font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20).frame(minHeight: 54)
                        .background(Color(red: 0.85, green: 0.93, blue: 0.84), in: Capsule())
                        .foregroundStyle(Color(red: 0.08, green: 0.23, blue: 0.17))
                }.buttonStyle(.plain).accessibilityIdentifier(hasStarted ? "home.continue" : "home.startPractice")
                Button { environment.selectedTab = .quran } label: {
                    Text("Choose a surah").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { ArchMotif().frame(width: 160, height: 220).offset(x: 45, y: -35) }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.15, green: 0.33, blue: 0.26), Color(red: 0.07, green: 0.23, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
}
