import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showAcknowledgements = false
    @State private var showPrivacy = false
    @State private var confirmRemoveDownloads = false
    @State private var confirmRemoveRecordings = false

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Make it yours")) {
                    Picker(String(localized: "Open the app to"), selection: Bindable(environment.settings).startTab) {
                        ForEach([AppTab.memorize, AppTab.quran], id: \.self) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .accessibilityIdentifier("settings.startTab")
                    .warmListRow()
                    Picker(String(localized: "Appearance"), selection: Bindable(environment.settings).appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
                    .warmListRow()
                    Picker(String(localized: "Reading layout"), selection: Bindable(environment.settings).quranReadingLayout) {
                        ForEach(QuranReadingLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .warmListRow()
                }
                Section(String(localized: "Audio")) {
                    Toggle(String(localized: "Wi-Fi only downloads"), isOn: Bindable(environment.settings).wifiOnly)
                        .onChange(of: environment.settings.wifiOnly) { _, wifiOnly in
                            environment.downloads.updateCellular(!wifiOnly)
                        }
                        .warmListRow()
                    Toggle(String(localized: "Stream if an ayah isn’t downloaded"), isOn: Bindable(environment.settings).streamWhenMissing)
                        .warmListRow()
                    Toggle(String(localized: "Download audio as it plays"), isOn: Bindable(environment.settings).downloadWhilePlaying)
                        .accessibilityIdentifier("settings.downloadWhilePlaying")
                        .warmListRow()
                    LabeledContent(String(localized: "Downloaded audio")) {
                        Text(ByteCountFormatter.string(fromByteCount: environment.downloads.fileStore.totalByteCount(), countStyle: .file))
                    }
                    .warmListRow()
                    Button(String(localized: "Remove downloaded recitation"), role: .destructive) {
                        confirmRemoveDownloads = true
                    }
                    .warmListRow()
                }
                Section {
                    Picker(String(localized: "Piece size"), selection: Bindable(environment.settings).pieceSize) {
                        ForEach(PieceSize.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("settings.pieceSize")
                    .warmListRow()
                    Picker(String(localized: "Repeat each ayah"), selection: Bindable(environment.settings).memorizePlayback.ayahRepeatCount) {
                        ForEach(RepeatCount.ayahPresets) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("settings.ayahRepeat")
                    .warmListRow()
                    Picker(String(localized: "Revise what I know"), selection: Bindable(environment.settings).revisionCycle) {
                        ForEach(RevisionCycle.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("settings.revisionCycle")
                    .warmListRow()
                    NavigationLink(String(localized: "Older saved passages")) { SetListView() }.warmListRow()
                } header: {
                    Text(String(localized: "Memorize"))
                } footer: {
                    Text(String(localized: "Pieces follow the Madani mushaf page. A short surah is always one piece. Memorized surahs fade when they go longer than this without a revision; listening, reciting, and \u{201C}Revised today\u{201D} all count."))
                }
                Section(String(localized: "Recordings")) {
                    Button(String(localized: "Delete all recordings"), role: .destructive) {
                        confirmRemoveRecordings = true
                    }
                    .warmListRow()
                    Text(String(localized: "Recordings stay on this device and are never uploaded."))
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryWarm)
                        .warmListRow()
                }
                Section(String(localized: "About")) {
                    Button(String(localized: "Acknowledgements")) { showAcknowledgements = true }
                        .warmListRow()
                    Button(String(localized: "Privacy")) { showPrivacy = true }
                        .warmListRow()
                    LabeledContent(String(localized: "Page convention"), value: String(localized: "604-page Madani Hafs"))
                        .warmListRow()
                    LabeledContent(String(localized: "Reciter"), value: environment.audioSource.reciter.englishName)
                        .warmListRow()
                }
            }
            .warmListChrome()
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAcknowledgements) { AcknowledgementsView() }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .confirmationDialog(
                String(localized: "Remove all downloaded recitation?"),
                isPresented: $confirmRemoveDownloads,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove downloads"), role: .destructive) {
                    environment.downloads.removeAll()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(
                String(localized: "Delete all personal recordings?"),
                isPresented: $confirmRemoveRecordings,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete recordings"), role: .destructive) {
                    environment.recorder.deleteAll()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .alert(
                environment.downloads.userMessage?.title ?? "",
                isPresented: Binding(
                    get: { environment.downloads.userMessage != nil },
                    set: { if !$0 { environment.downloads.userMessage = nil } }
                )
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(environment.downloads.userMessage?.message ?? "")
            }
        }
    }
}

struct AcknowledgementsView: View {
    @Environment(AppEnvironment.self) private var environment
    private let edition = TranslationEdition.default

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Quran text"))
                        .font(.headline)
                    Text("Uthmani Hafs text published by the King Fahd Glorious Quran Printing Complex (qurancomplex.gov.sa), distributed by the Quranic Universal Library (qul.tarteel.ai). It is bundled unchanged, except that ayah numbers are drawn separately.")
                    Text(String(localized: "Typography"))
                        .font(.headline)
                    Text("KFGQPC HAFS Uthmanic Script font © King Fahd Glorious Quran Printing Complex, used free of charge under its license and bundled unmodified.")
                    Text(String(localized: "Translation"))
                        .font(.headline)
                    Text("\(edition.title) English translation, issued by \(edition.publisher), from QuranEnc.com\(translationVersion). Bundled unchanged; footnotes are not shown.")
                    Link(edition.sourceURL.absoluteString, destination: edition.sourceURL)
                        .tint(Color.bronze)
                    Text(String(localized: "Audio"))
                        .font(.headline)
                    Text("Abdul Rahman Al-Sudais recitations are streamed or downloaded from Al Quran Cloud / islamic.network for personal and educational use. Copyright remains with the reciter.")
                }
                .padding()
                .foregroundStyle(Color.appBrownText)
            }
            .background(Color.parchment)
            .parchmentNavigationBar()
            .navigationTitle(String(localized: "Acknowledgements"))
            .task { await environment.translations.loadIfNeeded(edition) }
        }
    }

    private var translationVersion: String {
        guard let version = environment.translations.current?.version else { return "" }
        return ", version \(version)"
    }
}

struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Simple Quran is local-first. Saved passages, progress, downloads, and recordings stay on this device."))
                    Text(String(localized: "The microphone is used only when you record a passage. Recordings never leave the device unless you later choose a backup feature."))
                    Text(String(localized: "Downloaded recitation can be deleted in Settings. Personal recordings can be deleted per passage or all at once."))
                    Text(String(localized: "No account is required. No analytics SDK is included."))
                }
                .padding()
                .foregroundStyle(Color.appBrownText)
            }
            .background(Color.parchment)
            .parchmentNavigationBar()
            .navigationTitle(String(localized: "Privacy"))
        }
    }
}
