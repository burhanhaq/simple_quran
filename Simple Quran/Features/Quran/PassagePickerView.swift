import SwiftUI

struct PassagePickerView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let startAyah: Int
    let currentRange: VerseRange?
    var allowedRange: VerseRange? = nil
    let onChoose: (VerseRange, Bool) -> Void
    @State private var initialized = false
    @State private var mode = 2
    @State private var first = 1
    @State private var last = 1
    @State private var pageNumber = 1

    private var availablePages: [PageSection] {
        environment.quran.pages.filter {
            guard let allowedRange else { return true }
            return $0.endGlobalAyah >= allowedRange.startGlobalAyah && $0.startGlobalAyah <= allowedRange.endGlobalAyah
        }
    }

    private var selectedRange: VerseRange? {
        let selection: VerseRange?
        switch mode {
        case 0: selection = LearningPassage.suggested(from: first, catalog: environment.quran)
        case 1: selection = try? environment.quran.versesForPage(pageNumber)
        default: selection = try? VerseRange(startGlobalAyah: first, endGlobalAyah: last)
        }
        guard let selection else { return nil }
        guard let allowedRange else { return selection }
        let start = max(selection.startGlobalAyah, allowedRange.startGlobalAyah)
        let end = min(selection.endGlobalAyah, allowedRange.endGlobalAyah)
        return try? VerseRange(startGlobalAyah: start, endGlobalAyah: end)
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
                } header: { Text("Make it your own") }
                  footer: { Text("Choose a small passage or set the exact ayahs you want to practice.") }
                if mode == 1 {
                    Section {
                        Picker("Page", selection: $pageNumber) {
                            ForEach(availablePages) { Text("\($0.number)").tag($0.number) }
                        }.pickerStyle(.wheel).frame(height: 140)
                    } header: { Text("Madani mushaf · 604 pages") }
                } else {
                    AyahRangeFields(first: $first, last: $last, showsEnd: mode == 2, bounds: allowedRange)
                }
                if verticalSizeClass == .compact { Section { rangeSummary } }
            }
            .warmListChrome().navigationTitle("Your passage").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    if verticalSizeClass != .compact { rangeSummary }
                    Button {
                        guard let range = selectedRange else { return }
                        onChoose(range, mode == 1)
                        dismiss()
                    } label: { Text("Practice this passage").frame(maxWidth: .infinity) }
                        .buttonStyle(WarmButtonStyle()).disabled(selectedRange == nil).accessibilityIdentifier("passage.start")
                }.padding(20).background(Color.appWarmSurface)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                first = currentRange?.startGlobalAyah ?? startAyah
                last = currentRange?.endGlobalAyah ?? first
                pageNumber = environment.quran.verse(globalAyah: first)?.page ?? 1
                // Opening an existing passage must preserve its exact boundaries.
                mode = currentRange == nil ? 0 : 2
                if environment.settings.practiceByPage, let range = currentRange,
                   let page = try? environment.quran.versesForPage(pageNumber),
                   range.startGlobalAyah == max(page.startGlobalAyah, allowedRange?.startGlobalAyah ?? 1),
                   range.endGlobalAyah == min(page.endGlobalAyah, allowedRange?.endGlobalAyah ?? QuranCatalogMetrics.ayahCount) {
                    mode = 1
                }
            }
        }.tint(Color.bronze)
    }

    @ViewBuilder private var rangeSummary: some View {
        if let range = selectedRange {
            Text(LearningPassage.referenceLabel(range, catalog: environment.quran)).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(range.count) ayahs · At your own pace").font(.caption).foregroundStyle(Color.secondaryWarm)
        } else {
            Text("Choose a page within your focus.").font(.subheadline)
        }
    }
}

/// Wheel controls keep long surahs easy to adjust and never permit an inverted range.
struct AyahRangeFields: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppEnvironment.self) private var environment
    @Binding var first: Int
    @Binding var last: Int
    var showsEnd = true
    var bounds: VerseRange? = nil

    private var availableSurahs: [Surah] {
        environment.quran.surahs.filter {
            guard let bounds else { return true }
            return $0.endGlobalAyah >= bounds.startGlobalAyah && $0.startGlobalAyah <= bounds.endGlobalAyah
        }
    }

    var body: some View {
        Section {
            if verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 24) {
                    VStack(spacing: 16) { surahControls }.frame(maxWidth: .infinity)
                    ayahWheels.frame(maxWidth: .infinity)
                }
            } else {
                surahControls
                ayahWheels
            }
        } header: { Text(showsEnd ? "Ayah range" : "Start here") }
          footer: { Text(showsEnd ? "Both the first and last ayah are included." : "We’ll suggest a few ayahs from this starting point.") }
    }

    @ViewBuilder private var surahControls: some View {
        surahPicker("Start surah", value: $first, isStart: true)
        if showsEnd { surahPicker("End surah", value: $last, isStart: false) }
    }

    private var ayahWheels: some View {
        HStack(spacing: 0) {
            ayahWheel("From ayah", value: $first, isStart: true)
            if showsEnd {
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(Color.secondaryWarm).accessibilityHidden(true)
                ayahWheel("To ayah", value: $last, isStart: false)
            }
        }
    }

    private func surahPicker(_ title: String, value: Binding<Int>, isStart: Bool) -> some View {
        Picker(title, selection: Binding(
            get: { environment.quran.verse(globalAyah: value.wrappedValue)?.surahNumber ?? 1 },
            set: { number in
                guard let surah = environment.quran.surah(number: number) else { return }
                let start = max(surah.startGlobalAyah, bounds?.startGlobalAyah ?? 1)
                value.wrappedValue = isStart ? start : max(first, start)
                if isStart && last < first { last = first }
            }
        )) {
            ForEach(availableSurahs.filter { isStart || $0.endGlobalAyah >= first }) { surah in
                Text(surah.displayName).tag(surah.number)
            }
        }.pickerStyle(.navigationLink)
            .accessibilityIdentifier(isStart ? "range.startSurah" : "range.endSurah")
    }

    private func ayahWheel(_ title: String, value: Binding<Int>, isStart: Bool) -> some View {
        VStack(spacing: 0) {
            Text(isStart ? "From" : "To").font(.caption.weight(.semibold)).foregroundStyle(Color.secondaryWarm)
            if let verse = environment.quran.verse(globalAyah: value.wrappedValue),
               let surah = environment.quran.surah(number: verse.surahNumber) {
                let lower = max(surah.startGlobalAyah, bounds?.startGlobalAyah ?? 1, isStart ? 1 : first)
                let upper = min(surah.endGlobalAyah, bounds?.endGlobalAyah ?? QuranCatalogMetrics.ayahCount)
                if lower <= upper {
                    Picker(title, selection: Binding(get: { value.wrappedValue }, set: { ayah in
                        value.wrappedValue = ayah
                        if isStart && last < first { last = first }
                    })) {
                        ForEach(lower...upper, id: \.self) { ayah in
                            Text("\(ayah - surah.startGlobalAyah + 1)").tag(ayah)
                        }
                    }.pickerStyle(.wheel).frame(height: 140).clipped()
                        .accessibilityIdentifier(isStart ? "range.first" : "range.last")
                }
            }
        }.frame(maxWidth: .infinity)
    }
}
