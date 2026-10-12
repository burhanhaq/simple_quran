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
    @State private var navigationPath: [QuranDestination] = []

    var body: some View {
        @Bindable var environment = environment
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            WarmSymbol(systemName: environment.isCollectingAyahs ? "rectangle.stack.badge.plus" : "book.pages", size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(environment.isCollectingAyahs ? String(localized: "Build your practice") : String(localized: "Read. Listen. Remember."))
                                    .font(.headline).foregroundStyle(Color.appBrownText)
                                Text(environment.isCollectingAyahs ? String(localized: "Choose a passage to make your own.") : String(localized: "114 surahs · one place to begin"))
                                    .font(.caption).foregroundStyle(Color.secondaryWarm)
                            }
                        }
                        Picker(String(localized: "Browse"), selection: $mode) {
                            ForEach(QuranBrowseMode.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if environment.isCollectingAyahs {
                    collectListBanner
                }
                if !query.isEmpty {
                    searchSection
                } else {
                    switch mode {
                    case .surahs:
                        ForEach(environment.quran.surahs) { surah in
                            NavigationLink(value: QuranDestination.surah(number: surah.number)) {
                                HStack(spacing: 12) {
                                    Text("\(surah.number)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.bronze)
                                        .monospacedDigit()
                                        .frame(width: 38, height: 38)
                                        .background(Color.appCollectedFill, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(surah.englishName)
                                            .font(.headline)
                                            .foregroundStyle(Color.appBrownText)
                                        Text("\(surah.translation) · \(surah.ayahCount) ayahs")
                                            .font(.caption)
                                            .foregroundStyle(Color.secondaryWarm)
                                    }
                                    Spacer()
                                    Text(surah.arabicName)
                                        .font(.quran(size: 23))
                                        .foregroundStyle(Color.appBrownText)
                                        .multilineTextAlignment(.leading)
                                        .environment(\.layoutDirection, .rightToLeft)
                                }
                                .padding(.vertical, 8)
                            }
                            .warmListRow()
                            .accessibilityIdentifier("quran.surah.\(surah.number)")
                        }
                    case .juz:
                        ForEach(environment.quran.juzs) { juz in
                            NavigationLink(value: QuranDestination.juz(juz.number)) {
                                Text(
                                    juz.number == 30
                                        ? String(localized: "Juz \(juz.number) · Amma")
                                        : String(localized: "Juz \(juz.number)")
                                )
                                .foregroundStyle(Color.appBrownText)
                            }
                            .warmListRow()
                            .accessibilityIdentifier("quran.juz.\(juz.number)")
                        }
                    case .pages:
                        ForEach(environment.quran.pages) { page in
                            NavigationLink(value: QuranDestination.page(page.number)) {
                                Text(String(localized: "Page \(page.number)"))
                                    .foregroundStyle(Color.appBrownText)
                            }
                            .warmListRow()
                            .accessibilityIdentifier("quran.page.\(page.number)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .warmListChrome()
            .navigationTitle(String(localized: "Quran"))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Surah, juz, page, or 18:1-10"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !environment.collectionDraft.passages.isEmpty {
                        Button(String(localized: "Collection · \(environment.collectionDraft.passages.count)")) {
                            environment.presentCollectionEditor()
                        }
                        .accessibilityIdentifier("quran.openDraft")
                    }
                }
            }
            .sheet(isPresented: $environment.isPresentingCollectionEditor) {
                SetEditorView(draft: environment.collectionDraft) { _ in
                    environment.clearCollectionDraft()
                }
            }
            .navigationDestination(for: QuranDestination.self) { destination in
                QuranReaderView(destination: destination)
            }
        }
    }

    private var collectListBanner: some View {
        Section {
            Text(String(localized: "Choose a surah, juz, or page, then tap the first and last ayah."))
                .font(.footnote)
                .foregroundStyle(Color.secondaryWarm)
                .listRowBackground(Color.appCollectedFill)
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        let hits = environment.quran.search(query).hits
        Section(String(localized: "Results")) {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
            ForEach(hits) { hit in
                Button {
                    apply(hit)
                } label: {
                    VStack(alignment: .leading) {
                        Text(hit.title).foregroundStyle(Color.appBrownText)
                        Text(hit.subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                }
                .warmListRow()
            }
        }
    }

    private func apply(_ hit: QuranSearchHit) {
        switch hit.kind {
        case .surah(let number):
            navigationPath.append(.surah(number: number))
        case .juz(let number):
            navigationPath.append(.juz(number))
        case .page(let number):
            navigationPath.append(.page(number))
        case .verse(let ayah):
            if let verse = environment.quran.verse(globalAyah: ayah) {
                navigationPath.append(.surah(number: verse.surahNumber, scrollToAyah: ayah))
            }
        case .range(let range):
            guard let verse = environment.quran.verse(globalAyah: range.startGlobalAyah) else { return }
            environment.collectionDraft.append(range)
            environment.isCollectingAyahs = true
            navigationPath.append(.surah(number: verse.surahNumber, scrollToAyah: range.startGlobalAyah))
        }
    }
}
