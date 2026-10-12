import SwiftUI

struct PassagePickerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let startAyah: Int
    let currentRange: VerseRange?
    let onChoose: (VerseRange, Bool) -> Void
    @State private var mode = 0
    @State private var first = 1
    @State private var last = 1
    @State private var pageNumber = 1

    private var surah: Surah? {
        environment.quran.verse(globalAyah: currentRange?.startGlobalAyah ?? startAyah).flatMap { environment.quran.surah(number: $0.surahNumber) }
    }
    private var selectedRange: VerseRange? {
        guard let surah else { return nil }
        if mode == 1 { return try? environment.quran.versesForPage(pageNumber) }
        let start = surah.startGlobalAyah + first - 1
        if mode == 0 { return LearningPassage.suggested(from: start, catalog: environment.quran) }
        return .clamped(start: start, end: surah.startGlobalAyah + last - 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Practice", selection: $mode) {
                        Text("A few ayahs").tag(0)
                        Text("One page").tag(1)
                        Text("Choose ayahs").tag(2)
                    }.pickerStyle(.inline).labelsHidden()
                } header: { Text("Choose what feels manageable") }
                if let surah {
                    if mode == 1 {
                        Section {
                            Picker("Page", selection: $pageNumber) {
                                ForEach(1...604, id: \.self) { Text("\($0)").tag($0) }
                            }
                        } footer: { Text("Page numbers follow the 604-page Madani mushaf. The ayah range is shown below.") }
                    } else {
                        Section(surah.englishName) {
                            Picker("Start at", selection: $first) {
                                ForEach(1...surah.ayahCount, id: \.self) { Text("Ayah \($0)").tag($0) }
                            }
                                .onChange(of: first) { _, value in if last < value { last = value } }
                            if mode == 2 {
                                Picker("End at", selection: $last) {
                                    ForEach(first...surah.ayahCount, id: \.self) { Text("Ayah \($0)").tag($0) }
                                }
                            }
                        }
                    }
                }
                if let range = selectedRange {
                    Section {
                        Text(PassageLabel.passage(range, catalog: environment.quran)).font(.headline)
                        Text(LearningPassage.ayahLabel(range, catalog: environment.quran)).foregroundStyle(Color.secondaryWarm)
                        Button {
                            onChoose(range, mode == 1)
                            dismiss()
                        } label: { Text("Practice this passage").frame(maxWidth: .infinity) }
                            .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("passage.start")
                    }
                }
            }
            .warmListChrome().navigationTitle("Your passage").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                let range = currentRange
                first = environment.quran.verse(globalAyah: range?.startGlobalAyah ?? startAyah)?.ayahInSurah ?? 1
                last = environment.quran.verse(globalAyah: range?.endGlobalAyah ?? startAyah)?.ayahInSurah ?? first
                last = min(surah?.ayahCount ?? last, max(first, last))
                pageNumber = environment.quran.verse(globalAyah: startAyah)?.page ?? 1
                mode = environment.settings.practiceByPage ? 1 : 0
            }
        }
    }
}
