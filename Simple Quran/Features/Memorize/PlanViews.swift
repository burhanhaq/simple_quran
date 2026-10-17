import SwiftData
import SwiftUI

enum PlanPickerPurpose: String, Identifiable {
    /// Choose the one plan that drives "New" each day.
    case plan
    /// Memorize anything else now without changing the plan.
    case oneOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: String(localized: "Choose your plan")
        case .oneOff: String(localized: "Memorize something else")
        }
    }
}

/// Compact plan summary used on the Memorize and Progress tabs.
struct PlanCard: View {
    @Environment(AppEnvironment.self) private var environment
    let plan: LearningTarget
    let index: ProgressIndex

    var body: some View {
        let memorized = index.count(.memorized, in: plan.range)
        WarmCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("YOUR PLAN").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.secondaryWarm)
                        Text(plan.title(catalog: environment.quran)).font(.headline)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                }
                ProgressView(value: Double(memorized), total: Double(plan.range.count)).tint(Color.olive)
                Text("\(memorized) of \(plan.range.count) ayahs memorized")
                    .font(.caption).foregroundStyle(Color.secondaryWarm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One picker for choosing a plan or a one-off passage: a surah, a juz, or an ayah range.
struct PlanPickerView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [VerseProgress]
    let purpose: PlanPickerPurpose
    /// Called with the passage to start once the picker has dismissed (one-off only).
    var onStart: (VerseRange) -> Void = { _ in }
    @State private var browse = PlanBrowse.surahs
    @State private var search = ""
    @State private var selection: LearningTarget?
    @State private var showRange = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Browse", selection: $browse) {
                        ForEach(PlanBrowse.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).listRowBackground(Color.clear)
                    switch browse {
                    case .surahs:
                        ForEach(environment.quran.surahs.filter {
                            search.isEmpty || "\($0.displayName) \($0.arabicName) \($0.translation) \($0.aliases.joined(separator: " "))".localizedCaseInsensitiveContains(search)
                        }) { surah in
                            row(LearningTarget(range: surah.range), title: surah.displayName, subtitle: "\(surah.ayahCount) ayahs")
                        }
                    case .juz:
                        ForEach(environment.quran.juzs.filter { search.isEmpty || "Juz \($0.number)".localizedCaseInsensitiveContains(search) }) { juz in
                            row(LearningTarget(range: juz.range, juzNumber: juz.number), title: "Juz \(juz.number)",
                                subtitle: LearningPassage.referenceLabel(juz.range, catalog: environment.quran))
                        }
                    }
                } header: {
                    Button { showRange = true } label: { Label("Choose an ayah range", systemImage: "slider.horizontal.3").frame(minHeight: 44) }
                        .textCase(nil).accessibilityIdentifier("plan.custom")
                }
            }
            .warmListChrome().navigationTitle(purpose.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: browse == .surahs ? "Find a surah" : "Find a juz")
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showRange) {
                AyahRangeEditor(range: selection?.range ?? .clamped(start: 1, end: 7), isNew: true) { selection = LearningTarget(range: $0) }
            }
        }.tint(Color.bronze)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let selection {
                Text(selection.title(catalog: environment.quran)).font(.subheadline.weight(.semibold))
            } else if verticalSizeClass != .compact {
                Text(purpose == .plan ? "Choose one surah, juz, or ayah range" : "Choose what to memorize now")
                    .font(.caption).foregroundStyle(Color.secondaryWarm)
            }
            switch purpose {
            case .plan:
                Button { makePlan() } label: { Text("Set as my plan").frame(maxWidth: .infinity) }
                    .buttonStyle(WarmButtonStyle()).disabled(selection == nil).accessibilityIdentifier("plan.save")
            case .oneOff:
                Button { start() } label: { Text("Start memorizing").frame(maxWidth: .infinity) }
                    .buttonStyle(WarmButtonStyle()).disabled(selection == nil).accessibilityIdentifier("plan.start")
                Button("Make it my plan instead") { makePlan() }
                    .frame(minHeight: 44).disabled(selection == nil).accessibilityIdentifier("plan.makePlan")
            }
        }.padding(20).background(Color.appWarmSurface)
    }

    private func row(_ target: LearningTarget, title: String, subtitle: String) -> some View {
        let selected = selection?.range == target.range
        let isPlan = environment.settings.activePlan?.range == target.range
        return Button { selection = selected ? nil : target } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(Color.appBrownText)
                    Text(isPlan ? "Your current plan" : subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? Color.olive : Color.secondaryWarm)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).warmListRow()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("plan.select.\(target.juzNumber.map { "juz.\($0)" } ?? "ayah.\(target.range.startGlobalAyah)")")
    }

    private func makePlan() {
        guard let selection else { return }
        environment.settings.setActivePlan(selection)
        dismiss()
    }

    private func start() {
        guard let selection else { return }
        let index = ProgressIndex(progress.map(\.snapshot))
        let byPage = environment.settings.practiceByPage
        let passage = selection.nextPassage(catalog: environment.quran, byPage: byPage) { index.status(of: $0) == .memorized }
            ?? selection.passage(catalog: environment.quran, byPage: byPage)
        if let passage { onStart(passage) }
        dismiss()
    }
}

enum PlanBrowse: String, CaseIterable, Identifiable {
    case surahs
    case juz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surahs: String(localized: "Surahs")
        case .juz: String(localized: "Juz")
        }
    }
}

/// Pick a custom ayah range for a plan or a one-off passage.
struct AyahRangeEditor: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let range: VerseRange
    var isNew = false
    var unavailableRanges: [VerseRange] = []
    let onSave: (VerseRange) -> Void
    @State private var initialized = false
    @State private var first = 1
    @State private var last = 7

    private var selection: VerseRange { .clamped(start: first, end: last) }

    var body: some View {
        NavigationStack {
            Form {
                AyahRangeFields(first: $first, last: $last)
                if verticalSizeClass == .compact {
                    Section { rangeSummary }
                }
            }
                .warmListChrome().navigationTitle(isNew ? "Choose ayahs" : "Edit ayah range").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        if verticalSizeClass != .compact { rangeSummary }
                        Button {
                            onSave(selection)
                            dismiss()
                        } label: { Text(isNew ? "Use this range" : "Save range").frame(maxWidth: .infinity) }
                            .buttonStyle(WarmButtonStyle()).disabled(unavailableRanges.contains(selection)).accessibilityIdentifier("plan.range.save")
                    }.padding(20).background(Color.appWarmSurface)
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear {
                    guard !initialized else { return }
                    initialized = true
                    first = range.startGlobalAyah
                    last = range.endGlobalAyah
                }
        }.tint(Color.bronze)
    }

    private var rangeSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LearningPassage.referenceLabel(selection, catalog: environment.quran)).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(unavailableRanges.contains(selection) ? "This range is already selected." : "\(selection.count) ayahs")
                .font(.caption).foregroundStyle(Color.secondaryWarm)
        }
    }
}


/// The active plan, its progress, and the other plans waiting their turn.
struct PlanDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [VerseProgress]
    @State private var showRange = false
    @State private var showRemove = false
    @State private var picker: PlanPickerPurpose?

    var body: some View {
        let index = ProgressIndex(progress.map(\.snapshot))
        ScrollView {
            if let plan = environment.settings.activePlan {
                let memorized = index.count(.memorized, in: plan.range)
                let learning = index.count(.learning, in: plan.range)
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("YOUR PLAN", systemImage: "bookmark")
                            .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.bronze)
                        Text(plan.title(catalog: environment.quran)).font(.system(.largeTitle, design: .serif))
                        Text(LearningPassage.referenceLabel(plan.range, catalog: environment.quran)).font(.subheadline).foregroundStyle(Color.secondaryWarm)
                    }
                    WarmCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(memorized) of \(plan.range.count) ayahs memorized").font(.headline)
                            ProgressView(value: Double(memorized), total: Double(plan.range.count)).tint(Color.olive)
                            if learning > 0 {
                                Text("\(learning) ayahs in progress").font(.subheadline).foregroundStyle(Color.secondaryWarm)
                            }
                        }
                    }
                    if let next = plan.nextPassage(catalog: environment.quran, byPage: environment.settings.practiceByPage, isMemorized: { index.status(of: $0) == .memorized }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NEXT").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.secondaryWarm)
                            Text(LearningPassage.referenceLabel(next, catalog: environment.quran)).font(.headline)
                            Button { environment.openSession(next, planID: plan.id) } label: {
                                Label("Memorize this passage", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(WarmButtonStyle()).accessibilityIdentifier("plan.memorizeNext")
                        }
                    }
                    if memorized > 0 {
                        Button {
                            environment.openReviews(ReviewPlanner.memorizedPassages(in: plan.range, snapshots: progress.map(\.snapshot), catalog: environment.quran))
                        } label: {
                            Label("Review what you’ve memorized", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }.buttonStyle(WarmButtonStyle(emphasis: .secondary))
                    }
                    upNext(excluding: plan, index: index)
                    VStack(spacing: 4) {
                        Button { picker = .plan } label: { Label("Choose a different plan", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity, minHeight: 44) }
                            .accessibilityIdentifier("plan.change")
                        Button { showRange = true } label: { Label("Edit ayah range", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44) }
                            .accessibilityIdentifier("plan.edit")
                        Button("Remove this plan", role: .destructive) { showRemove = true }.frame(minHeight: 44)
                    }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.appBrownText).background(Color.parchment.ignoresSafeArea())
        .navigationTitle("Your plan").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picker) { PlanPickerView(purpose: $0) }
        .sheet(isPresented: $showRange) {
            if let plan = environment.settings.activePlan {
                AyahRangeEditor(range: plan.range) { range in
                    guard range != plan.range, let index = environment.settings.learningTargets.firstIndex(where: { $0.id == plan.id }) else { return }
                    environment.settings.learningTargets[index].range = range
                    environment.settings.learningTargets[index].juzNumber = nil
                    environment.settings.learningTargets[index].resumeRange = nil
                }
            }
        }
        .confirmationDialog("Remove this plan?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove plan", role: .destructive) {
                if let plan = environment.settings.activePlan { environment.settings.removePlan(id: plan.id) }
                dismiss()
            }
        } message: { Text("Ayahs you’ve memorized stay memorized.") }
    }

    @ViewBuilder
    private func upNext(excluding plan: LearningTarget, index: ProgressIndex) -> some View {
        let others = environment.settings.learningTargets.filter { $0.id != plan.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("UP NEXT").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.secondaryWarm)
                ForEach(others) { other in
                    WarmCard {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(other.title(catalog: environment.quran)).font(.headline)
                                Text("\(index.count(.memorized, in: other.range)) of \(other.range.count) memorized")
                                    .font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                            Spacer(minLength: 0)
                            Button("Switch") { environment.settings.setActivePlan(other) }
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { environment.settings.removePlan(id: other.id) }
                    }
                }
            }
        }
    }
}
