import SwiftUI

/// Chooses whose recitation plays everywhere in the app. Each reciter keeps their own downloads.
struct ReciterPickerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var preview = AudioPreviewPlayer()
    @State private var previewingID: String?
    @State private var storedBytes: [String: Int64] = [:]

    /// Al-Fatiha 1:1, a short sample every reciter has.
    private static let previewAyah = 1

    var body: some View {
        List {
            Section {
                ForEach(environment.reciters.catalog.reciters) { reciter in
                    row(reciter)
                }
            } footer: {
                Text(String(localized: "Downloads are kept for each reciter, so switching back still works offline."))
                    .warmSectionText()
            }
        }
        .warmListChrome()
        .navigationTitle(String(localized: "Reciter"))
        .onAppear(perform: refreshSizes)
        .onDisappear(perform: stopPreview)
    }

    private func row(_ reciter: Reciter) -> some View {
        let isSelected = reciter.id == environment.audioSource.reciter.id
        let bytes = storedBytes[reciter.id] ?? 0
        return HStack(spacing: 12) {
            Button {
                stopPreview()
                environment.selectReciter(reciter)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reciter.englishName)
                            .foregroundStyle(Color.appBrownText)
                        Text(reciter.arabicName)
                            .arabicAccessibilityLabel(reciter.arabicName)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryWarm)
                        if bytes > 0 {
                            Text(String(localized: "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) downloaded"))
                                .font(.caption)
                                .foregroundStyle(Color.secondaryWarm)
                        }
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.bronze)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            Button {
                togglePreview(reciter)
            } label: {
                Image(systemName: previewingID == reciter.id ? "stop.circle" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(Color.bronze)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(previewingID == reciter.id
                ? String(localized: "Stop sample")
                : String(localized: "Play a sample of \(reciter.englishName)"))
        }
        // Removing downloads is never one accidental full swipe away.
        .swipeActions(allowsFullSwipe: false) {
            if !isSelected, bytes > 0 {
                Button(role: .destructive) {
                    environment.downloads.remove(reciterID: reciter.id)
                    refreshSizes()
                } label: {
                    Label(String(localized: "Remove downloads"), systemImage: "trash")
                }
            }
        }
        .warmListRow()
        .accessibilityIdentifier("reciter.\(reciter.id)")
    }

    private func togglePreview(_ reciter: Reciter) {
        if previewingID == reciter.id {
            stopPreview()
            return
        }
        let catalog = environment.reciters.catalog
        let local = environment.downloads.fileStore.with(reciter: reciter)
            .urlIfReady(reciter: reciter, globalAyah: Self.previewAyah)
        guard let url = local ?? (try? catalog.audioSource(for: reciter).remoteURL(for: Self.previewAyah)) else { return }
        environment.playback.pause()
        previewingID = reciter.id
        Task {
            try? await preview.play(url: url)
            if previewingID == reciter.id { previewingID = nil }
        }
    }

    private func stopPreview() {
        preview.cancel()
        previewingID = nil
    }

    private func refreshSizes() {
        let files = environment.downloads.fileStore
        storedBytes = Dictionary(uniqueKeysWithValues: environment.reciters.catalog.reciters.map {
            ($0.id, files.byteCount(reciterID: $0.id))
        })
    }
}
