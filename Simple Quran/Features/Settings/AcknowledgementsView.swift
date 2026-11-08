import SwiftUI

/// The sources the app is built on: the Quran text, its typeface, the translation, and the recitation.
struct AcknowledgementsView: View {
    @Environment(AppEnvironment.self) private var environment
    private let edition = TranslationEdition.default

    var body: some View {
        List {
            Section {
                CreditText(String(localized: "Uthmani Hafs text (QPC Hafs) published by the King Fahd Glorious Quran Printing Complex in Madinah and distributed by the Quranic Universal Library. It’s bundled unchanged; the app draws each ayah’s number separately."))
                Link(destination: SourceLinks.quranicUniversalLibrary) {
                    ExternalLinkLabel(String(localized: "Quranic Universal Library"))
                }
                .warmListRow()
                Link(destination: SourceLinks.qurancomplex) {
                    ExternalLinkLabel(String(localized: "King Fahd Glorious Quran Printing Complex"))
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Quran text"))
                    .warmSectionText()
            }

            Section {
                CreditText(String(localized: "KFGQPC HAFS Uthmanic Script, version 22, © King Fahd Glorious Quran Printing Complex. Used free of charge under its license and bundled unmodified."))
                NavigationLink {
                    LicenseTextView(title: String(localized: "Font license"), resource: LicenseTextView.Resource.kfgqpcFont)
                } label: {
                    Text(String(localized: "License"))
                }
                .accessibilityIdentifier("acknowledgements.fontLicense")
                .warmListRow()
                Link(destination: SourceLinks.qurancomplexFonts) {
                    ExternalLinkLabel(String(localized: "King Fahd Complex fonts"))
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Typeface"))
                    .warmSectionText()
            }

            Section {
                CreditText(String(localized: "\(edition.title) English translation, issued by \(edition.publisher), from QuranEnc.com. The text is bundled unchanged; footnotes aren’t shown yet."))
                if let version = environment.translations.current?.version {
                    LabeledContent(String(localized: "Version"), value: version).warmListRow()
                }
                Link(destination: edition.sourceURL) {
                    ExternalLinkLabel(String(localized: "QuranEnc.com"))
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Translation"))
                    .warmSectionText()
            }

            Section {
                ForEach(environment.reciters.catalog.reciters) { reciter in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reciter.englishName)
                        Text(reciter.arabicName)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryWarm)
                            .environment(\.layoutDirection, .rightToLeft)
                            .arabicAccessibilityLabel(reciter.arabicName)
                    }
                    .accessibilityElement(children: .combine)
                    .warmListRow()
                }
                Link(destination: SourceLinks.audioService) {
                    ExternalLinkLabel(SourceLinks.audioServiceName)
                }
                .warmListRow()
                Link(destination: SourceLinks.everyAyah) {
                    ExternalLinkLabel(SourceLinks.everyAyahName)
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Recitation"))
                    .warmSectionText()
            } footer: {
                Text(String(localized: "Streamed and downloaded from \(SourceLinks.audioServiceName) and \(SourceLinks.everyAyahName) for personal and educational use. Copyright remains with each reciter."))
                    .warmSectionText()
            }

            Section {
                LabeledContent(String(localized: "Page layout"), value: String(localized: "604-page Madani Hafs")).warmListRow()
            } footer: {
                Text(String(localized: "Used to browse by page and to divide memorizing into pieces. The text flows on screen; it isn’t a page-for-page copy of a printed mushaf."))
                    .warmSectionText()
            }

            Section {
            } footer: {
                Text(String(localized: "\(AppIdentity.name) \(AppIdentity.displayVersion) · Made by \(AppIdentity.publisher)"))
                    .frame(maxWidth: .infinity)
                    .warmSectionText()
            }
        }
        .tint(Color.bronze)
        .warmListChrome()
        .navigationTitle(String(localized: "Acknowledgements"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await environment.translations.loadIfNeeded(edition) }
    }
}

private struct CreditText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.vertical, 4)
            .warmListRow()
    }
}

/// A license bundled with the app, shown in full.
struct LicenseTextView: View {
    enum Resource: String {
        case kfgqpcFont = "KFGQPC-LICENSE"

        static let fileExtension = "txt"
    }

    let title: String
    let resource: Resource

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .foregroundStyle(Color.appBrownText)
        .background(Color.parchment.ignoresSafeArea())
        .parchmentNavigationBar()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var text: String {
        Bundle.main.url(forResource: resource.rawValue, withExtension: Resource.fileExtension)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? String(localized: "The license couldn’t be loaded. It’s available from the King Fahd Glorious Quran Printing Complex.")
    }
}
