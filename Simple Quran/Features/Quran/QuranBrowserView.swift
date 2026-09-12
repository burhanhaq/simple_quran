import SwiftUI

enum QuranBrowseMode: String, CaseIterable, Identifiable {
    case surahs
    case juz
    case pages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surahs: String(localized: "Surahs")
        case .juz: String(localized: "Juz")
        case .pages: String(localized: "Pages")
        }
    }
}

struct QuranBrowserView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var mode: QuranBrowseMode = .surahs
    @State private var query = ""
    @State private var draft = SetDraft()
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    searchSection
                }
                switch mode {
                case .surahs:
                    ForEach(environment.quran.surahs) { surah in
                        NavigationLink {
                            SurahDetailView(surah: surah, draft: draft)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(surah.displayName).foregroundStyle(Color.appBrownText)
                                Text("\(surah.arabicName) · \(surah.ayahCount)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondaryWarm)
                            }
                        }
                        .accessibilityIdentifier("quran.surah.\(surah.number)")
                    }
                case .juz:
                    ForEach(environment.quran.juzs) { juz in
                        Button {
                            if let range = try? environment.quran.versesForJuz(juz.number) {
                                draft.append(range)
                                showEditor = true
                            }
                        } label: {
                            Text(juz.number == 30 ? String(localized: "Juz \(juz.number) · Amma") : String(localized: "Juz \(juz.number)"))
                                .foregroundStyle(Color.appBrownText)
                        }
                    }
                case .pages:
                    ForEach(environment.quran.pages) { page in
                        Button {
                            if let range = try? environment.quran.versesForPage(page.number) {
                                draft.append(range)
                                showEditor = true
                            }
                        } label: {
                            Text(String(localized: "Page \(page.number)"))
                                .foregroundStyle(Color.appBrownText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .navigationTitle(String(localized: "Quran"))
            .searchable(text: $query, prompt: String(localized: "Surah, juz, page, or 18:1-10"))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(String(localized: "Browse"), selection: $mode) {
                        ForEach(QuranBrowseMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !draft.passages.isEmpty {
                        Button(String(localized: "Set (\(draft.passages.count))")) {
                            showEditor = true
                        }
                        .accessibilityIdentifier("quran.openDraft")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                SetEditorView(draft: draft) {
                    draft = SetDraft()
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let hits = environment.quran.search(query).hits
        Section(String(localized: "Results")) {
            ForEach(hits) { hit in
                Button {
                    apply(hit)
                } label: {
                    VStack(alignment: .leading) {
                        Text(hit.title).foregroundStyle(Color.appBrownText)
                        Text(hit.subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                }
            }
        }
    }

    private func apply(_ hit: QuranSearchHit) {
        switch hit.kind {
        case .surah(let number):
            if let surah = environment.quran.surah(number: number) {
                // Leave the user on the surah page for finer selection.
                draft.titleHint = surah.englishName
            }
        case .juz(let number):
            if let range = try? environment.quran.versesForJuz(number) {
                draft.append(range)
                draft.titleHint = number == 30 ? "Juz Amma" : "Juz \(number)"
                showEditor = true
            }
        case .page(let number):
            if let range = try? environment.quran.versesForPage(number) {
                draft.append(range)
                draft.titleHint = "Page \(number)"
                showEditor = true
            }
        case .verse(let ayah):
            if let range = try? VerseRange(startGlobalAyah: ayah, endGlobalAyah: ayah) {
                draft.append(range)
                showEditor = true
            }
        case .range(let range):
            draft.append(range)
            showEditor = true
        }
    }
}

@Observable
final class SetDraft {
    var existingID: UUID?
    var title: String = ""
    var titleHint: String = ""
    var passages: [OrderedPassage] = []
    var settings: PracticeSettings = .default

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !titleHint.isEmpty { return titleHint }
        return String(localized: "Untitled set")
    }

    func append(_ range: VerseRange) {
        passages.append(OrderedPassage(order: passages.count, range: range))
        if titleHint.isEmpty {
            titleHint = "\(range.startGlobalAyah)–\(range.endGlobalAyah)"
        }
    }
}

struct SurahDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let surah: Surah
    var draft: SetDraft
    @State private var startAyah: Int?
    @State private var showEditor = false

    var body: some View {
        let verses = environment.quran.verses(in: (try? VerseRange(startGlobalAyah: surah.startGlobalAyah, endGlobalAyah: surah.endGlobalAyah)) ?? (try! VerseRange(startGlobalAyah: 1, endGlobalAyah: 1)))
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(verses) { verse in
                    Button {
                        select(verse)
                    } label: {
                        QuranAyahText(
                            verse: verse,
                            isCurrent: isSelected(verse),
                            hidden: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ayah.\(verse.globalAyah)")
                }
            }
            .padding()
        }
        .background(Color.parchment.ignoresSafeArea())
        .navigationTitle(surah.englishName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                if let startAyah {
                    Text(String(localized: "Start \(surah.number):\(startAyah). Tap an end ayah."))
                        .font(.caption)
                        .foregroundStyle(Color.secondaryWarm)
                } else {
                    Text(String(localized: "Tap an ayah to start a range."))
                        .font(.caption)
                        .foregroundStyle(Color.secondaryWarm)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Whole surah")) {
                    if let range = try? environment.quran.range(surah: surah.number, startAyah: 1, endAyah: surah.ayahCount) {
                        draft.append(range)
                        draft.titleHint = surah.englishName
                        showEditor = true
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            SetEditorView(draft: draft)
        }
    }

    private func select(_ verse: QuranVerse) {
        if let start = startAyah {
            let startIndex = min(start, verse.ayahInSurah)
            let endIndex = max(start, verse.ayahInSurah)
            if let range = try? environment.quran.range(surah: surah.number, startAyah: startIndex, endAyah: endIndex) {
                draft.append(range)
                draft.titleHint = "\(surah.englishName) \(startIndex)–\(endIndex)"
                startAyah = nil
                showEditor = true
            }
        } else {
            startAyah = verse.ayahInSurah
        }
    }

    private func isSelected(_ verse: QuranVerse) -> Bool {
        startAyah == verse.ayahInSurah
    }
}
