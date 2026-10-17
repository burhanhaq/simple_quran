import SwiftData
import SwiftUI

struct QuranBrowserView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query private var progress: [VerseProgress]
    @State private var browseJuz = false
    @State private var query = ""
    @State private var showPage = false
    @State private var page = 1
    @State private var pendingPage: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Read. Listen. Remember.")
                            .font(.system(.title2, design: .serif)).foregroundStyle(Color.appBrownText)
                        Picker("Browse Quran", selection: $browseJuz) {
                            Text("Surahs").tag(false)
                            Text("Juz").tag(true)
                        }.pickerStyle(.segmented)
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                if !query.isEmpty {
                    let hits = environment.quran.search(query).hits
                    if hits.isEmpty { ContentUnavailableView.search(text: query).listRowBackground(Color.clear) }
                    ForEach(hits) { hit in
                        Button { open(hit) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(hit.title).font(.headline).foregroundStyle(Color.appBrownText)
                                Text(hit.subtitle).font(.caption).foregroundStyle(Color.secondaryWarm)
                            }.padding(.vertical, 6)
                        }.warmListRow()
                    }
                } else if browseJuz {
                    ForEach(environment.quran.juzs) { juz in
                        Button { environment.openReader(.juz(juz.number)) } label: {
                            HStack(spacing: 14) {
                                numberBadge(juz.number)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(juz.number == 30 ? "Juz 30 · Amma" : "Juz \(juz.number)").font(.headline)
                                    if let verse = environment.quran.verse(globalAyah: juz.startGlobalAyah), let surah = environment.quran.surah(number: verse.surahNumber) {
                                        Text("From \(surah.englishName) · Ayah \(verse.ayahInSurah)").font(.caption).foregroundStyle(Color.secondaryWarm)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 10).foregroundStyle(Color.appBrownText)
                        }.warmListRow().accessibilityIdentifier("quran.juz.\(juz.number)")
                    }
                } else {
                    ForEach(environment.quran.surahs) { surah in
                        Button { environment.openReader(.surah(number: surah.number)) } label: {
                            HStack(spacing: 14) {
                                numberBadge(surah.number)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(surah.englishName).font(.headline)
                                    Text("\(surah.translation) · \(surah.ayahCount) ayahs").font(.caption).foregroundStyle(Color.secondaryWarm)
                                    let count = memorizedCount(surah)
                                    if count > 0 {
                                        Text(count == surah.ayahCount ? "Memorized" : "\(count) ayahs memorized")
                                            .font(.caption.weight(.medium)).foregroundStyle(Color.olive)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(surah.arabicName).font(.quran(size: 23)).multilineTextAlignment(.trailing)
                            }.padding(.vertical, 10).foregroundStyle(Color.appBrownText)
                        }.warmListRow().accessibilityIdentifier("quran.surah.\(surah.number)")
                    }
                }
            }
            .listStyle(.insetGrouped).warmListChrome().navigationTitle("Quran")
            .searchable(text: $query, prompt: "Find a surah, ayah, or page")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPage = true } label: { Image(systemName: "book.pages") }
                        .accessibilityLabel("Go to a page").accessibilityIdentifier("quran.goToPage")
                }
            }
            .sheet(isPresented: $showPage, onDismiss: {
                if let pendingPage {
                    self.pendingPage = nil
                    environment.openReader(.page(pendingPage))
                }
            }) {
                NavigationStack {
                    Form {
                        Picker("Page", selection: $page) {
                            ForEach(1...604, id: \.self) { Text("Page \($0)").tag($0) }
                        }.pickerStyle(.wheel)
                        Button("Open page") {
                            pendingPage = page
                            showPage = false
                        }.frame(maxWidth: .infinity).buttonStyle(WarmButtonStyle())
                    }.warmListChrome().navigationTitle("Go to a page").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPage = false } } }
                }.presentationDetents([.medium, .large])
            }
        }
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)").font(.caption.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Color.bronze).frame(width: 38, height: 38)
            .background(Color.appCollectedFill, in: RoundedRectangle(cornerRadius: 12))
    }
    private func memorizedCount(_ surah: Surah) -> Int {
        progress.filter { surah.range.contains($0.globalAyah) && $0.snapshot.status == .memorized }.count
    }
    private func open(_ hit: QuranSearchHit) {
        switch hit.kind {
        case .surah(let number): environment.openReader(.surah(number: number))
        case .juz(let number): environment.openReader(.juz(number))
        case .page(let number): environment.openReader(.page(number))
        case .verse(let ayah):
            if let verse = environment.quran.verse(globalAyah: ayah) { environment.openReader(.surah(number: verse.surahNumber, scrollToAyah: ayah)) }
        case .range(let range): environment.openPractice(range)
        }
    }
}
