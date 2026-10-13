import SwiftData
import SwiftUI

struct LearningFocusSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    @State private var showAdd = false

    private var practiced: Set<Int> {
        Set(progress.filter { $0.exposureCount > 0 || $0.recallAttempts > 0 }.map(\.globalAyah))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your focus").font(.title3.weight(.semibold))
                Spacer()
                Button { showAdd = true } label: { Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
                    .accessibilityLabel("Add a focus").accessibilityIdentifier("focus.add")
            }
            if environment.settings.learningTargets.isEmpty {
                Button { showAdd = true } label: {
                    WarmCard {
                        HStack(spacing: 14) {
                            WarmSymbol(systemName: "bookmark")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Choose what you’re learning").font(.headline)
                                Text("Track surahs, a whole juz, or your own ayah ranges.")
                                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                            }
                            Image(systemName: "plus.circle").foregroundStyle(Color.bronze)
                        }
                    }
                }.buttonStyle(.plain)
            } else {
                ForEach(environment.settings.learningTargets) { target in
                    NavigationLink { LearningFocusDetail(targetID: target.id) } label: {
                        WarmCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(target.title(catalog: environment.quran)).font(.headline)
                                        let count = practiced.filter { target.range.contains($0) }.count
                                        Text("\(count) of \(target.range.count) ayahs practiced")
                                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.bronze)
                                }
                                ProgressView(value: Double(practiced.filter { target.range.contains($0) }.count), total: Double(target.range.count))
                                    .tint(Color.olive)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("focus.item.\(target.range.startGlobalAyah).\(target.range.endGlobalAyah)")
                }
            }
        }.foregroundStyle(Color.appBrownText)
            .sheet(isPresented: $showAdd) { AddLearningFocusView() }
    }
}

struct AddLearningFocusView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var search = ""
    @State private var selections: [LearningTarget] = []
    @State private var showRange = false

    var body: some View {
        NavigationStack {
            List {
                if verticalSizeClass != .compact {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("A surah, a juz, or a few ayahs.").font(.system(.title2, design: .serif))
                            Text("Choose as many as you like. Each keeps its own place, and every ayah you practice counts toward your progress.")
                                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                        }.padding(.vertical, 4)
                        Button { showRange = true } label: { Label("Choose an ayah range", systemImage: "slider.horizontal.3").frame(minHeight: 44) }
                            .accessibilityIdentifier("focus.custom")
                    }.listRowBackground(Color.clear)
                }
                if selections.contains(where: { $0.juzNumber == nil && !isWholeSurah($0.range) }) {
                    Section("Your ranges") {
                        ForEach(selections.filter { $0.juzNumber == nil && !isWholeSurah($0.range) }) { target in
                            selectionRow(target, title: target.title(catalog: environment.quran), subtitle: "\(target.range.count) ayahs")
                        }
                    }
                }
                Section {
                    Picker("Browse", selection: $mode) {
                        Text("Surahs").tag(0)
                        Text("Juz").tag(1)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear)
                    if mode == 0 {
                        ForEach(environment.quran.surahs.filter {
                            search.isEmpty || "\($0.displayName) \($0.arabicName) \($0.translation) \($0.aliases.joined(separator: " "))".localizedCaseInsensitiveContains(search)
                        }) { surah in
                            selectionRow(LearningTarget(range: .clamped(start: surah.startGlobalAyah, end: surah.endGlobalAyah)),
                                         title: surah.displayName, subtitle: "\(surah.ayahCount) ayahs · Whole surah")
                        }
                    } else {
                        ForEach(environment.quran.juzs.filter { search.isEmpty || "Juz \($0.number)".localizedCaseInsensitiveContains(search) }) { juz in
                            let range = VerseRange.clamped(start: juz.startGlobalAyah, end: juz.endGlobalAyah)
                            selectionRow(LearningTarget(range: range, juzNumber: juz.number), title: "Juz \(juz.number)",
                                         subtitle: LearningPassage.referenceLabel(range, catalog: environment.quran))
                        }
                    }
                }
            }
            .warmListChrome().navigationTitle("Add a focus").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: mode == 0 ? "Find a surah" : "Find a juz")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if verticalSizeClass != .compact {
                        Text(selections.isEmpty ? "Select surahs or juz to get started" : "\(selections.count) selected")
                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                    Button {
                        environment.settings.addTargets(selections)
                        dismiss()
                    } label: { Text(selections.isEmpty ? "Add to your focus" : "Add to your focus · \(selections.count)").frame(maxWidth: .infinity) }
                        .buttonStyle(WarmButtonStyle()).disabled(selections.isEmpty).accessibilityIdentifier("focus.save")
                }.padding(20).background(Color.appWarmSurface)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if verticalSizeClass == .compact {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Choose ayahs") { showRange = true }.accessibilityIdentifier("focus.custom")
                    }
                }
            }
            .sheet(isPresented: $showRange) {
                FocusRangeEditor(range: .clamped(start: 1, end: 7), isNew: true,
                                 unavailableRanges: environment.settings.learningTargets.map(\.range) + selections.map(\.range)) { range in
                    guard !isTracked(range), !selections.contains(where: { $0.range == range }) else { return }
                    selections.append(LearningTarget(range: range))
                }
            }
        }.tint(Color.bronze)
    }

    private func isTracked(_ range: VerseRange) -> Bool { environment.settings.learningTargets.contains { $0.range == range } }
    private func isWholeSurah(_ range: VerseRange) -> Bool {
        environment.quran.surahs.contains { $0.startGlobalAyah == range.startGlobalAyah && $0.endGlobalAyah == range.endGlobalAyah }
    }

    private func selectionRow(_ target: LearningTarget, title: String, subtitle: String) -> some View {
        let tracked = isTracked(target.range)
        let selected = selections.contains { $0.range == target.range }
        return Button {
            if selected { selections.removeAll { $0.range == target.range } }
            else { selections.append(target) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(Color.appBrownText)
                    Text(tracked ? "Already in your focus" : subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                }
                Spacer(minLength: 0)
                Image(systemName: tracked ? "checkmark.seal.fill" : selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected || tracked ? Color.olive : Color.secondaryWarm)
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(tracked).warmListRow()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("focus.select.\(target.juzNumber.map { "juz.\($0)" } ?? "ayah.\(target.range.startGlobalAyah)")")
    }
}

struct FocusRangeEditor: View {
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
                        } label: { Text(isNew ? "Add this range" : "Save range").frame(maxWidth: .infinity) }
                            .buttonStyle(WarmButtonStyle()).disabled(unavailableRanges.contains(selection)).accessibilityIdentifier("focus.range.save")
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

struct LearningFocusDetail: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query private var progress: [VerseProgress]
    let targetID: UUID
    @State private var showRange = false
    @State private var showRemove = false

    private var target: LearningTarget? { environment.settings.learningTargets.first { $0.id == targetID } }

    var body: some View {
        ScrollView {
            if let target {
                let practiced = progress.filter { target.range.contains($0.globalAyah) && ($0.exposureCount > 0 || $0.recallAttempts > 0) }.count
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(target.juzNumber == nil ? "YOUR FOCUS" : "WHOLE JUZ", systemImage: "bookmark")
                            .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.bronze)
                        Text(target.title(catalog: environment.quran)).font(.system(.largeTitle, design: .serif))
                        Text(LearningPassage.referenceLabel(target.range, catalog: environment.quran)).font(.subheadline).foregroundStyle(Color.secondaryWarm)
                    }
                    WarmCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(practiced) of \(target.range.count) ayahs practiced").font(.headline)
                            ProgressView(value: Double(practiced), total: Double(target.range.count)).tint(Color.olive)
                            Text(practiced == target.range.count ? "You’ve spent time with every ayah. Return whenever you’d like to review." : "A little at a time. Your place is saved as you go.")
                                .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                        }
                    }
                    if let passage = target.passage(catalog: environment.quran, byPage: environment.settings.practiceByPage) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(practiced == target.range.count ? "RETURN TO YOUR PRACTICE" : "NEXT PRACTICE").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.secondaryWarm)
                            Text(PassageLabel.passage(passage, catalog: environment.quran)).font(.headline)
                            Button { environment.openPractice(passage, targetID: target.id) } label: {
                                Label(target.resumeRange == nil ? "Start practicing" : "Continue practice", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(WarmButtonStyle()).accessibilityIdentifier("focus.practice")
                        }
                    }
                    VStack(spacing: 12) {
                        Button { environment.openPractice(target.range, isReview: true, targetID: target.id) } label: {
                            Label("Practice all \(target.range.count) ayahs", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }.buttonStyle(WarmButtonStyle(emphasis: .secondary))
                        Button { showRange = true } label: {
                            Label("Edit ayah range", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityIdentifier("focus.edit")
                    }
                    Text("Progress is shared across overlapping surahs, juz, and ayah ranges.")
                        .font(.caption).foregroundStyle(Color.secondaryWarm)
                    Button("Remove from your focus", role: .destructive) { showRemove = true }.frame(minHeight: 44)
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.appBrownText).background(Color.parchment.ignoresSafeArea())
        .navigationTitle("Your focus").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRange) {
            if let target {
                FocusRangeEditor(range: target.range, unavailableRanges: environment.settings.learningTargets.filter { $0.id != targetID }.map(\.range)) { range in
                    guard let index = environment.settings.learningTargets.firstIndex(where: { $0.id == targetID }) else { return }
                    guard range != target.range else { return }
                    environment.settings.learningTargets[index].range = range
                    environment.settings.learningTargets[index].juzNumber = nil
                    environment.settings.learningTargets[index].resumeRange = nil
                    if environment.settings.activeTargetID == targetID { environment.settings.activeTargetID = nil }
                }
            }
        }
        .confirmationDialog("Remove this focus?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove focus", role: .destructive) {
                environment.settings.learningTargets.removeAll { $0.id == targetID }
                if environment.settings.activeTargetID == targetID { environment.settings.activeTargetID = nil }
                dismiss()
            }
        } message: { Text("Your ayah progress and practice history will stay saved.") }
    }
}
