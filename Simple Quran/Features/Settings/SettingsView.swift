import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showAcknowledgements = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Audio")) {
                    Toggle(String(localized: "Wi-Fi only downloads"), isOn: Bindable(environment.settings).wifiOnly)
                        .onChange(of: environment.settings.wifiOnly) { _, wifiOnly in
                            environment.downloads.updateCellular(!wifiOnly)
                        }
                    Toggle(String(localized: "Stream if an ayah isn’t downloaded"), isOn: Bindable(environment.settings).streamWhenMissing)
                    LabeledContent(String(localized: "Downloaded audio")) {
                        Text(ByteCountFormatter.string(fromByteCount: environment.downloads.fileStore.totalByteCount(), countStyle: .file))
                    }
                    Button(String(localized: "Remove downloaded recitation"), role: .destructive) {
                        try? environment.downloads.fileStore.removeAll()
                    }
                }
                Section(String(localized: "Recordings")) {
                    Button(String(localized: "Delete all recordings"), role: .destructive) {
                        environment.recorder.deleteAll()
                    }
                    Text(String(localized: "Recordings stay on this device and are never uploaded."))
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryWarm)
                }
                Section(String(localized: "About")) {
                    Button(String(localized: "Acknowledgements")) { showAcknowledgements = true }
                    Button(String(localized: "Privacy")) { showPrivacy = true }
                    LabeledContent(String(localized: "Page convention"), value: String(localized: "604-page Madani Hafs"))
                    LabeledContent(String(localized: "Reciter"), value: environment.audioSource.reciter.englishName)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAcknowledgements) { AcknowledgementsView() }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
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
            .navigationTitle(String(localized: "Acknowledgements"))
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "Simple Quran is local-first. Sets, progress, downloads, and recordings stay on this device in v1."))
                    Text(String(localized: "The microphone is used only when you record an ayah. Recordings never leave the device unless you later choose a backup feature."))
                    Text(String(localized: "Downloaded recitation can be deleted in Settings. Personal recordings can be deleted per ayah or all at once."))
                    Text(String(localized: "No account is required. No analytics SDK is included."))
                }
                .padding()
                .foregroundStyle(Color.appBrownText)
            }
            .background(Color.parchment)
            .navigationTitle(String(localized: "Privacy"))
        }
    }
}

