import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    Picker(String(localized: "Reading layout"), selection: Bindable(environment.settings).displayedReadingLayout) {
                        ForEach(QuranReadingLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .warmListRow()
                    Toggle(String(localized: "Show translation"), isOn: Bindable(environment.settings).showsTranslation)
                        .accessibilityIdentifier("settings.translation")
                        .warmListRow()
                } header: {
                    Text(String(localized: "Make it yours")).warmSectionText()
                }
                Section {
                    NavigationLink {
                        ReciterPickerView()
                    } label: {
                        LabeledContent(String(localized: "Reciter"), value: environment.audioSource.reciter.englishName)
                    }
                    .accessibilityIdentifier("settings.reciter")
                    .warmListRow()
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
                        Text(ByteCountFormatter.string(fromByteCount: environment.downloads.fileStore.totalByteCountAllReciters(), countStyle: .file))
                    }
                    .warmListRow()
                    RemoveDownloadsButton().warmListRow()
                } header: {
                    Text(String(localized: "Audio")).warmSectionText()
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
                } header: {
                    Text(String(localized: "Memorize")).warmSectionText()
                } footer: {
                    Text(String(localized: "Pieces follow the Madani mushaf page. A short surah is always one piece. Memorized surahs fade when they go longer than this without a revision; listening, reciting, and \u{201C}Revised today\u{201D} all count.")).warmSectionText()
                }
                Section {
                    DeleteRecordingsButton().warmListRow()
                } header: {
                    Text(String(localized: "Recordings")).warmSectionText()
                } footer: {
                    Text(String(localized: "Recordings stay on this iPhone and are never uploaded.")).warmSectionText()
                }
                Section {
                    NavigationLink(String(localized: "Privacy")) { PrivacyView() }
                        .accessibilityIdentifier("settings.privacy")
                        .warmListRow()
                    NavigationLink(String(localized: "Acknowledgements")) { AcknowledgementsView() }
                        .accessibilityIdentifier("settings.acknowledgements")
                        .warmListRow()
                    Link(destination: AppLinks.mail(.support)) {
                        ExternalLinkLabel(String(localized: "Contact support"), systemImage: "envelope")
                    }
                    .warmListRow()
                    Link(destination: AppLinks.website) {
                        ExternalLinkLabel(String(localized: "Website"))
                    }
                    .warmListRow()
                    LabeledContent(String(localized: "Version"), value: AppIdentity.displayVersion)
                        .accessibilityIdentifier("settings.version")
                        .warmListRow()
                } header: {
                    Text(String(localized: "About")).warmSectionText()
                } footer: {
                    Text(String(localized: "Made by \(AppIdentity.publisher)")).warmSectionText()
                }
            }
            .warmListChrome()
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        // On the stack, not the list, so a failed removal shows from Privacy too.
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
