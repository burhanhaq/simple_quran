import SwiftUI
import UIKit

/// What the app does with your information, in the same terms as the full policy on the website.
struct PrivacyView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.title)
                        .foregroundStyle(Color.bronze)
                        .accessibilityHidden(true)
                    Text(String(localized: "Simple Quran doesn’t collect your data"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.summary, id: \.self) { point in
                            Label {
                                Text(point)
                            } icon: {
                                Image(systemName: "checkmark").foregroundStyle(Color.bronze)
                            }
                            .font(.subheadline)
                        }
                    }
                    Text(String(localized: "We don’t sell or share your data, and we don’t use it for advertising. We don’t receive it at all."))
                        .font(.footnote)
                        .foregroundStyle(Color.secondaryWarm)
                }
                .padding(.vertical, 8)
                .warmListRow()
            }

            Section {
                PolicyRow(
                    title: String(localized: "Memorization progress"),
                    detail: String(localized: "What you’ve memorized, what you’re working on, and when you last revised, so the app can show your progress and what needs revision."),
                    keep: String(localized: "Until you remove the app. It’s part of your iCloud or computer backup, which Apple handles.")
                )
                PolicyRow(
                    title: String(localized: "Recordings of your recitation"),
                    detail: String(localized: "So you can play your recitation back beside the reciter."),
                    keep: String(localized: "Until you delete them or remove the app. Left out of backups.")
                )
                PolicyRow(
                    title: String(localized: "Downloaded recitation"),
                    detail: String(localized: "So you can listen without a connection."),
                    keep: String(localized: "Until you remove downloads or the app.")
                )
                PolicyRow(
                    title: String(localized: "Settings"),
                    detail: String(localized: "Your choices, such as appearance, reciter, and download preferences."),
                    keep: String(localized: "Until you remove the app.")
                )
            } header: {
                Text(String(localized: "Stays on this iPhone"))
                    .warmSectionText()
            }

            Section {
                PolicyRow(
                    title: String(localized: "Requests for recitation audio"),
                    detail: String(localized: "When you play or download an ayah that isn’t on this iPhone, the app asks \(SourceLinks.audioServiceName) for that audio file. Like any internet request, it includes your IP address. No account, identifier, or personal content is sent, and nothing is sent to \(AppIdentity.publisher)."),
                    keep: nil
                )
                Link(destination: SourceLinks.audioServiceTerms) {
                    ExternalLinkLabel(String(localized: "Al Quran Cloud’s terms"))
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Sent to a service"))
                    .warmSectionText()
            }

            Section {
                PolicyRow(
                    title: String(localized: "Microphone"),
                    detail: String(localized: "Used only while you record your recitation. Everything else works without it."),
                    keep: nil
                )
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    ExternalLinkLabel(String(localized: "Change in Settings"))
                }
                .warmListRow()
            } header: {
                Text(String(localized: "Permissions"))
                    .warmSectionText()
            } footer: {
                Text(String(localized: "The app asks before using the microphone. You can change your mind at any time in Settings → Privacy & Security → Microphone."))
                    .warmSectionText()
            }

            Section {
                RemoveDownloadsButton().warmListRow()
                DeleteRecordingsButton().warmListRow()
            } header: {
                Text(String(localized: "Your controls"))
                    .warmSectionText()
            } footer: {
                Text(String(localized: "Removing the app deletes everything it stored on this iPhone. Because we never receive your data, there’s nothing to delete on our side."))
                    .warmSectionText()
            }

            Section {
                Link(destination: AppLinks.privacyPolicy) {
                    ExternalLinkLabel(String(localized: "Read the full privacy policy"))
                }
                .accessibilityIdentifier("privacy.fullPolicy")
                .warmListRow()
                Link(destination: AppLinks.mail(.privacy)) {
                    ExternalLinkLabel(String(localized: "Questions? \(AppLinks.email)"), systemImage: "envelope")
                }
                .warmListRow()
            } footer: {
                Text(String(localized: "Effective \(AppLinks.privacyEffectiveDate.formatted(date: .long, time: .omitted)). \(AppIdentity.name) is made by \(AppIdentity.publisher), an independent software studio."))
                    .warmSectionText()
            }
        }
        .tint(Color.bronze)
        .warmListChrome()
        .navigationTitle(String(localized: "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let summary = [
        String(localized: "No account, analytics, ads, or tracking."),
        String(localized: "Your progress and recordings stay on this iPhone."),
        String(localized: "The only thing the app fetches is recitation audio.")
    ]
}

/// One kind of data: what it is and why, and optionally how long it's kept.
private struct PolicyRow: View {
    let title: String
    let detail: String
    let keep: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Color.secondaryWarm)
            if let keep {
                Text(keep).font(.footnote).foregroundStyle(Color.secondaryWarm)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .warmListRow()
    }
}

/// A row that leaves the app: its title, with an arrow so it's clear it opens elsewhere.
struct ExternalLinkLabel: View {
    let title: String
    var systemImage = "arrow.up.right"

    init(_ title: String, systemImage: String = "arrow.up.right") {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.bronze)
            Spacer(minLength: 8)
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.secondaryWarm)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
