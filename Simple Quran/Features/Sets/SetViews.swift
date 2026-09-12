import SwiftData
import SwiftUI

struct SetListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @State private var draft = SetDraft()
    @State private var showEditor = false
    @State private var practiceSet: PracticeSet?

    var body: some View {
        NavigationStack {
            List {
                let active = sets.filter { $0.archivedAt == nil }
                let archived = sets.filter { $0.archivedAt != nil }
                Section(String(localized: "My sets")) {
                    if active.isEmpty {
                        EmptyStateView(
                            title: String(localized: "No sets yet"),
                            message: String(localized: "Build a set from the Quran tab, then it will appear here for quick practice."),
                            actionTitle: String(localized: "Open Quran")
                        ) {
                            environment.selectedTab = .quran
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(active, id: \.persistentModelID) { set in
                            NavigationLink {
                                SetDetailView(practiceSet: set)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.title).foregroundStyle(Color.appBrownText)
                                    Text(summary(set)).font(.caption).foregroundStyle(Color.secondaryWarm)
                                }
                            }
                            .accessibilityIdentifier("sets.row.\(set.id.uuidString)")
                        }
                    }
                }
                if !archived.isEmpty {
                    Section(String(localized: "Archived")) {
                        ForEach(archived, id: \.persistentModelID) { set in
                            NavigationLink {
                                SetDetailView(practiceSet: set)
                            } label: {
                                Text(set.title).foregroundStyle(Color.secondaryWarm)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .navigationTitle(String(localized: "My Sets"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draft = SetDraft()
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("sets.create")
                }
            }
            .sheet(isPresented: $showEditor) {
                SetEditorView(draft: draft)
            }
        }
    }

    private func summary(_ set: PracticeSet) -> String {
        let count = set.orderedPassages.map(\.range.count).reduce(0, +)
        return String(localized: "\(count) ayahs")
    }
}

struct SetDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let practiceSet: PracticeSet
    @State private var showPractice = false
    @State private var showEditor = false
    @State private var errorMessage: UserFacingMessage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WarmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(practiceSet.title).font(.title2.weight(.bold)).foregroundStyle(Color.appBrownText)
                        Text(String(localized: "\(ayahCount) ayahs · \(practiceSet.orderedPassages.count) passages"))
                            .foregroundStyle(Color.secondaryWarm)
                        downloadStatus
                    }
                }
                ForEach(practiceSet.orderedPassages, id: \.id) { passage in
                    passageCard(passage)
                }
                HStack {
                    Button(String(localized: "Practise")) { showPractice = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.gold)
                        .accessibilityIdentifier("set.practise")
                    Button(String(localized: "Download")) {
                        environment.downloads.download(ayahs: allAyahs)
                    }
                    .buttonStyle(.bordered)
                }
                HStack {
                    Button(practiceSet.archivedAt == nil ? String(localized: "Archive") : String(localized: "Unarchive")) {
                        try? environment.store.archive(practiceSet, archived: practiceSet.archivedAt == nil)
                    }
                    Button(String(localized: "Delete"), role: .destructive) {
                        try? environment.store.delete(practiceSet)
                        dismiss()
                    }
                }
            }
            .padding()
        }
        .background(Color.parchment.ignoresSafeArea())
        .navigationTitle(String(localized: "Set"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Edit")) {
                    showEditor = true
                }
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            PracticeView(practiceSet: practiceSet)
        }
        .sheet(isPresented: $showEditor) {
            SetEditorView(draft: draftFromSet())
        }
        .alert(errorMessage?.title ?? "", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage?.message ?? "")
        }
    }

    private var ayahCount: Int {
        practiceSet.orderedPassages.map(\.range.count).reduce(0, +)
    }

    private var allAyahs: [Int] {
        practiceSet.orderedPassages.flatMap(\.range.globalAyahs)
    }

    private var downloadStatus: some View {
        let ready = environment.downloads.downloadedCount(in: allAyahs)
        let estimate = environment.downloads.estimate(for: allAyahs)
        return Text(String(localized: "\(ready)/\(allAyahs.count) downloaded · \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) remaining"))
            .font(.caption)
            .foregroundStyle(Color.olive)
    }

    private func passageCard(_ passage: PracticePassage) -> some View {
        let verses = environment.quran.verses(in: passage.range)
        let first = verses.first
        let last = verses.last
        return WarmCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title(for: verses))
                    .font(.headline)
                    .foregroundStyle(Color.appBrownText)
                if let first, let last {
                    Text("\(first.reference) – \(last.reference)")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryWarm)
                }
            }
        }
    }

    private func title(for verses: [QuranVerse]) -> String {
        let surahs = Set(verses.map(\.surahNumber)).sorted()
        let names = surahs.compactMap { environment.quran.surah(number: $0)?.englishName }
        return names.joined(separator: ", ")
    }

    private func draftFromSet() -> SetDraft {
        let draft = SetDraft()
        draft.existingID = practiceSet.id
        draft.title = practiceSet.title
        draft.passages = practiceSet.orderedPassages.map { OrderedPassage(id: $0.id, order: $0.order, range: $0.range) }
        draft.settings = practiceSet.settings
        return draft
    }
}

struct SetEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    var draft: SetDraft
    var onSaved: (() -> Void)?
    @State private var errorMessage: UserFacingMessage?

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Name")) {
                    TextField(String(localized: "Set name"), text: Bindable(draft).title)
                        .accessibilityIdentifier("set.editor.title")
                }
                Section(String(localized: "Passages")) {
                    if draft.passages.isEmpty {
                        Text(String(localized: "Add ayahs from the Quran tab. A set can mix passages from different surahs."))
                            .foregroundStyle(Color.secondaryWarm)
                    }
                    ForEach(Array(draft.passages.enumerated()), id: \.element.id) { index, passage in
                        HStack {
                            Text(label(for: passage.range))
                            Spacer()
                            Button(role: .destructive) {
                                draft.passages.remove(at: index)
                                reindex()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .onMove { indices, newOffset in
                        draft.passages.move(fromOffsets: indices, toOffset: newOffset)
                        reindex()
                    }
                }
                Section(String(localized: "Practice defaults")) {
                    Picker(String(localized: "Repeat ayah"), selection: Bindable(draft).settings.ayahRepeatCount) {
                        ForEach(RepeatCount.ayahPresets) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    Picker(String(localized: "Repeat set"), selection: Bindable(draft).settings.setRepeatCount) {
                        ForEach(RepeatCount.setPresets) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    Stepper(value: Bindable(draft).settings.pauseSeconds, in: 0...5) {
                        Text(String(localized: "Pause \(draft.settings.pauseSeconds)s"))
                    }
                    Toggle(String(localized: "Hide Arabic for recall"), isOn: Bindable(draft).settings.hideArabic)
                    Toggle(String(localized: "Advance manually"), isOn: Bindable(draft).settings.advanceManually)
                }
            }
            .navigationTitle(draft.existingID == nil ? String(localized: "New set") : String(localized: "Edit set"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) { save() }
                        .disabled(draft.passages.isEmpty)
                        .accessibilityIdentifier("set.editor.save")
                }
            }
        }
        .alert(errorMessage?.title ?? "", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage?.message ?? "")
        }
    }

    private func label(for range: VerseRange) -> String {
        guard let first = environment.quran.verse(globalAyah: range.startGlobalAyah),
              let last = environment.quran.verse(globalAyah: range.endGlobalAyah)
        else { return "\(range.startGlobalAyah)–\(range.endGlobalAyah)" }
        return "\(first.reference) – \(last.reference)"
    }

    private func reindex() {
        for index in draft.passages.indices {
            draft.passages[index].order = index
        }
    }

    private func save() {
        let ranges = draft.passages.sorted { $0.order < $1.order }.map(\.range)
        do {
            if let id = draft.existingID, let set = try environment.store.set(id: id) {
                try environment.store.updateSet(set, title: draft.resolvedTitle, passages: ranges, settings: draft.settings)
            } else {
                _ = try environment.store.createSet(title: draft.resolvedTitle, passages: ranges, settings: draft.settings)
            }
            onSaved?()
            dismiss()
        } catch {
            errorMessage = UserFacingMessage.from(.persistenceFailure)
        }
    }
}
