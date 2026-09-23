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
                Section(String(localized: "Reading")) {
                    Picker(String(localized: "Appearance"), selection: Bindable(environment.settings).appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
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
                    LabeledContent(String(localized: "Downloaded audio")) {
                        Text(ByteCountFormatter.string(fromByteCount: environment.downloads.fileStore.totalByteCount(), countStyle: .file))
                    }
                    .warmListRow()
                    Button(String(localized: "Remove downloaded recitation"), role: .destructive) {
                        confirmRemoveDownloads = true
                    }
                    .warmListRow()
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Quran text"))
                        .font(.headline)
                    Text("Tanzil Quran Text, Tanzil Project, Creative Commons Attribution 3.0. The Uthmani text is bundled verbatim except for stripping a leading BOM when present. Updates: https://tanzil.net")
                    Text(String(localized: "Typography"))
                        .font(.headline)
                    Text("Amiri Quran is licensed under the SIL Open Font License 1.1.")
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
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Simple Quran is local-first. Collections, progress, downloads, and recordings stay on this device."))
                    Text(String(localized: "The microphone is used only when you record a collection. Recordings never leave the device unless you later choose a backup feature."))
                    Text(String(localized: "Downloaded recitation can be deleted in Settings. Personal recordings can be deleted per collection or all at once."))
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
