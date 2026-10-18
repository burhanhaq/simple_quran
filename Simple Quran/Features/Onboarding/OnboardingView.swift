import SwiftUI

/// Why someone opened the app; it only decides where the app opens.
enum OnboardingIntent: String, CaseIterable, Identifiable {
    case memorize
    case readAndListen
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memorize: String(localized: "Memorize")
        case .readAndListen: String(localized: "Read and listen")
        case .both: String(localized: "Both")
        }
    }

    var detail: String {
        switch self {
        case .memorize: String(localized: "Learn surahs half a page at a time.")
        case .readAndListen: String(localized: "Open the Quran and listen to recitation.")
        case .both: String(localized: "Memorize, and read whenever you like.")
        }
    }

    var systemImage: String {
        switch self {
        case .memorize: AppTab.memorize.systemImage
        case .readAndListen: AppTab.quran.systemImage
        case .both: "sparkles"
        }
    }

    var startTab: AppTab { self == .readAndListen ? .quran : .memorize }
}

private enum OnboardingStep {
    case intent
    case known
    case plan
}

/// Three short, skippable questions on first launch. Reading-only people finish after the first.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var step = OnboardingStep.intent
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intent: intent
                case .known: KnownSurahsView(continueTitle: String(localized: "Continue")) { step = .plan }
                case .plan: plan
                }
            }
            .foregroundStyle(Color.appBrownText)
            .background(Color.parchment.ignoresSafeArea())
            .toolbar {
                if step != .intent {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { step == .known ? (step = .plan) : finish() }.accessibilityIdentifier("onboarding.skip")
                    }
                }
            }
        }
        .tint(Color.bronze)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showPicker, onDismiss: { if environment.settings.activePlan != nil { finish() } }) {
            PlanPickerView(purpose: .plan)
        }
    }

    private var intent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Assalamu alaikum").font(.subheadline.weight(.semibold)).foregroundStyle(Color.bronze)
                Text("What brings you here?").font(.system(.largeTitle, design: .serif))
                ForEach(OnboardingIntent.allCases) { option in
                    Button { choose(option) } label: {
                        WarmCard {
                            HStack(spacing: 14) {
                                WarmSymbol(systemName: option.systemImage)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title).font(.headline)
                                    Text(option.detail).font(.subheadline).foregroundStyle(Color.secondaryWarm)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("onboarding.intent.\(option.rawValue)")
                }
                Text("You can change this anytime in Settings.").font(.footnote).foregroundStyle(Color.secondaryWarm)
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }

    private var plan: some View {
        let index = ProgressIndex((try? environment.store.allProgress()) ?? [])
        let suggestions = PlanSuggestion.all(catalog: environment.quran).filter { index.status(of: $0.target.range) != .memorized }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What would you like to memorize next?").font(.system(.largeTitle, design: .serif))
                Text("This becomes your plan. You can memorize anything else too, and change your plan anytime.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                ForEach(suggestions) { suggestion in
                    Button {
                        environment.settings.setActivePlan(suggestion.target)
                        finish()
                    } label: {
                        WarmCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title).font(.headline)
                                    Text(suggestion.detail).font(.subheadline).foregroundStyle(Color.secondaryWarm)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("onboarding.plan.\(suggestion.id)")
                }
                Button { showPicker = true } label: {
                    Label("Choose something else", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                }.buttonStyle(WarmButtonStyle(emphasis: .secondary)).accessibilityIdentifier("onboarding.plan.other")
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
    }

    private func choose(_ option: OnboardingIntent) {
        environment.settings.startTab = option.startTab
        environment.selectedTab = option.startTab
        if option == .readAndListen { finish() } else { step = .known }
    }

    private func finish() {
        environment.settings.hasCompletedOnboarding = true
        dismiss()
    }
}

/// Common starting points offered as a first plan.
struct PlanSuggestion: Identifiable {
    let id: String
    let title: String
    let detail: String
    let target: LearningTarget

    static func all(catalog: some QuranCatalog) -> [PlanSuggestion] {
        var result: [PlanSuggestion] = []
        if let juz = catalog.juzs.first(where: { $0.number == 30 }) {
            result.append(PlanSuggestion(id: "juz30", title: String(localized: "Juz Amma"), detail: String(localized: "The last juz, short surahs from An-Naba to An-Naas"),
                                         target: LearningTarget(range: juz.range, juzNumber: 30)))
        }
        for number in [67, 36, 18] {
            guard let surah = catalog.surah(number: number) else { continue }
            result.append(PlanSuggestion(id: "surah\(number)", title: surah.englishName, detail: String(localized: "\(surah.ayahCount) ayahs"),
                                         target: LearningTarget(range: surah.range)))
        }
        return result
    }
}

/// A quick checklist of commonly memorized passages, marked as memorized on Continue.
struct KnownSurahsView: View {
    @Environment(AppEnvironment.self) private var environment
    let continueTitle: String
    let onDone: () -> Void
    @State private var selected: Set<VerseRange> = []
    @State private var showJuzAmma = false
    @State private var errorMessage: UserFacingMessage?

    private var common: [(String, VerseRange)] {
        var items: [(String, VerseRange)] = []
        if let fatiha = environment.quran.surah(number: 1) { items.append((fatiha.englishName, fatiha.range)) }
        if let kursi = try? environment.quran.range(surah: 2, startAyah: 255, endAyah: 255) { items.append((String(localized: "Ayat al-Kursi"), kursi)) }
        for number in [67, 36, 18, 55, 56] {
            if let surah = environment.quran.surah(number: number) { items.append((surah.englishName, surah.range)) }
        }
        return items
    }
    private var juzAmma: [Surah] { environment.quran.surahs.filter { ProgressInsights.juz30SurahRange.contains($0.number) } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Already know some surahs?").font(.system(.largeTitle, design: .serif))
                    Text("Tick what you can recite from memory. It counts as memorized and comes back for gentle review.")
                        .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                }.padding(.vertical, 8)
            }.listRowBackground(Color.clear)
            Section {
                ForEach(common, id: \.1) { title, range in row(title, range: range) }
            }
            Section {
                let all = Set(juzAmma.map(\.range))
                Button {
                    if all.isSubset(of: selected) { selected.subtract(all) } else { selected.formUnion(all) }
                } label: {
                    HStack {
                        Text("All of Juz Amma").font(.headline)
                        Spacer()
                        Image(systemName: all.isSubset(of: selected) ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(all.isSubset(of: selected) ? Color.olive : Color.secondaryWarm)
                    }.contentShape(Rectangle()).frame(minHeight: 44)
                }.buttonStyle(.plain).warmListRow().accessibilityIdentifier("known.juzAmma")
                DisclosureGroup("Choose individual surahs", isExpanded: $showJuzAmma) {
                    ForEach(juzAmma) { surah in row(surah.displayName, range: surah.range) }
                }.warmListRow()
            } header: { Text("Juz Amma") }
        }
        .warmListChrome()
        .safeAreaInset(edge: .bottom) {
            Button {
                do { try environment.store.markMemorized(ayahs: selected.flatMap(\.globalAyahs)) }
                catch { errorMessage = .from(.persistenceFailure); return }
                onDone()
            } label: {
                Text(selected.isEmpty ? continueTitle : "\(continueTitle) · \(selected.count) marked").frame(maxWidth: .infinity)
            }
            .buttonStyle(WarmButtonStyle()).padding(20).background(Color.appWarmSurface)
            .accessibilityIdentifier("known.continue")
        }
        .alert(errorMessage?.title ?? "", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage?.message ?? "") }
    }

    private func row(_ title: String, range: VerseRange) -> some View {
        let isSelected = selected.contains(range)
        return Button {
            if isSelected { selected.remove(range) } else { selected.insert(range) }
        } label: {
            HStack {
                Text(title).font(.headline).foregroundStyle(Color.appBrownText)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(isSelected ? Color.olive : Color.secondaryWarm)
            }.contentShape(Rectangle()).frame(minHeight: 44)
        }
        .buttonStyle(.plain).warmListRow()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("known.\(range.startGlobalAyah)")
    }
}
