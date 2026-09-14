import SwiftData
import SwiftUI

struct SetListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @State private var practiceSet: PracticeSet?

    var body: some View {
        NavigationStack {
            List {
                let active = sets.filter { $0.archivedAt == nil }
                let archived = sets.filter { $0.archivedAt != nil }
                Section(String(localized: "Collections")) {
                    if active.isEmpty {
                        EmptyStateView(
                            title: String(localized: "No collections yet"),
                            message: String(localized: "Choose ayahs in the Quran and save them together for quick practice."),
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
                                HStack(spacing: 12) {
                                    Image(systemName: "text.book.closed")
                                        .font(.title3)
                                        .foregroundStyle(Color.gold)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(set.title).font(.headline).foregroundStyle(Color.appBrownText)
                                        Text(summary(set)).font(.caption).foregroundStyle(Color.secondaryWarm)
                                    }
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
            .navigationTitle(String(localized: "Collections"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        environment.selectedTab = .quran
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("sets.create")
                }
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
                Button {
                    showPractice = true
                } label: {
                    Label(String(localized: "Start Practice"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.gold)
                .accessibilityIdentifier("set.practise")
                Button {
                        environment.downloads.download(ayahs: allAyahs)
                } label: {
                    Label(String(localized: "Download for Offline Practice"), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Color.parchment.ignoresSafeArea())
        .navigationTitle(String(localized: "Collection"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(String(localized: "Edit Collection"), systemImage: "pencil") {
                        showEditor = true
                    }
                    Button(
                        practiceSet.archivedAt == nil ? String(localized: "Archive Collection") : String(localized: "Restore Collection"),
                        systemImage: practiceSet.archivedAt == nil ? "archivebox" : "arrow.uturn.backward"
                    ) {
                        do {
                            try environment.store.archive(practiceSet, archived: practiceSet.archivedAt == nil)
                        } catch {
                            errorMessage = UserFacingMessage.from(.persistenceFailure)
                        }
                    }
                    Divider()
                    Button(String(localized: "Delete Collection"), systemImage: "trash", role: .destructive) {
                        do {
                            environment.recorder.deleteRecordings(for: practiceSet.id)
                            try environment.store.delete(practiceSet)
                            dismiss()
                        } catch {
                            errorMessage = UserFacingMessage.from(.persistenceFailure)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fullScreenCover(isPresented: $showPractice) {
            PracticeView(practiceSet: practiceSet)
        }
        .sheet(isPresented: $showEditor) {
            SetEditorView(draft: draftFromSet())
        }
        .alert(errorMessage?.title ?? environment.downloads.userMessage?.title ?? "", isPresented: Binding(
            get: { errorMessage != nil || environment.downloads.userMessage != nil },
            set: { if !$0 {
                errorMessage = nil
                environment.downloads.userMessage = nil
            } }
        )) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage?.message ?? environment.downloads.userMessage?.message ?? "")
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
        let relevantJobs = allAyahs.compactMap { environment.downloads.jobs[$0] }
        let downloading = relevantJobs.filter { $0.status == .downloading }
        let failed = relevantJobs.filter { $0.status == .failed }
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "\(ready)/\(allAyahs.count) downloaded · \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) remaining"))
                .font(.caption)
                .foregroundStyle(Color.olive)
            if !downloading.isEmpty {
                ProgressView(value: downloading.map(\.fraction).reduce(0, +), total: Double(downloading.count))
                Button(String(localized: "Cancel downloads")) {
                    environment.downloads.cancelAll()
                }
                .font(.caption)
            }
            if !failed.isEmpty {
                Button(String(localized: "Retry failed downloads")) {
                    environment.downloads.download(ayahs: failed.map(\.globalAyah))
                }
                .font(.caption)
            }
        }
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
                    TextField(String(localized: "Collection name"), text: Bindable(draft).title)
                        .accessibilityIdentifier("set.editor.title")
                }
                Section(String(localized: "Passages")) {
                    if draft.passages.isEmpty {
                        Text(String(localized: "Add ayahs from the Quran tab. A collection can include passages from different surahs."))
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
                    Picker(String(localized: "Repeat collection"), selection: Bindable(draft).settings.setRepeatCount) {
                        ForEach(RepeatCount.setPresets) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    Stepper(value: Bindable(draft).settings.pauseSeconds, in: 0...5) {
                        Text(draft.settings.pauseSeconds == 0
                             ? String(localized: "Pause after ayah: Off")
                             : String(localized: "Pause after ayah: \(draft.settings.pauseSeconds)s"))
                    }
                    Toggle(String(localized: "Hide Arabic for recall"), isOn: Bindable(draft).settings.hideArabic)
                    Toggle(String(localized: "Advance manually"), isOn: Bindable(draft).settings.advanceManually)
                }
            }
            .navigationTitle(draft.existingID == nil ? String(localized: "New Collection") : String(localized: "Edit Collection"))
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
