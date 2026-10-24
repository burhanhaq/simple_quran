import SwiftData
import SwiftUI

/// The home for memorizing: today's checklist on top, the user's journey through the Quran below.
struct MemorizeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Query private var verseProgress: [VerseProgress]
    @State private var showSettings = false
    @State private var picker: PlanPickerPurpose?
    @State private var pendingStart: PendingStart?
    @State private var showKnown = false
    @State private var search = ""

    var body: some View {
        let snapshots = verseProgress.map(\.snapshot)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let error = environment.catalogLoadError { FriendlyErrorView(message: error) }
                    // Searching is for finding a surah on the map, so only the map shows.
                    if search.isEmpty {
                        if environment.settings.showsStatusChangeNote { statusChangeNote }
                        TodayCard(snapshots: snapshots, picker: $picker, showKnown: $showKnown)
                    }
                    JourneySection(snapshots: snapshots, search: search)
                    if search.isEmpty {
                        Button { picker = .oneOff } label: {
                            Label("Choose a surah, juz, or ayah range", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(WarmButtonStyle(emphasis: .secondary)).accessibilityIdentifier("memorize.other")
                    }
                }
                .foregroundStyle(Color.appBrownText)
                .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(AppTab.memorize.title)
            .searchable(text: $search, prompt: "Find a surah or juz")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings").accessibilityIdentifier("memorize.settings")
                }
            }
            // An open sheet keeps its old look when Appearance changes, and going back to System
            // doesn't reset it, so it takes the scheme this screen actually resolved to.
            .sheet(isPresented: $showSettings) { SettingsView().preferredColorScheme(colorScheme) }
            .sheet(isPresented: $showKnown) {
                NavigationStack {
                    KnownSurahsView(continueTitle: String(localized: "Save")) {
                        environment.settings.showsStatusChangeNote = false
                        showKnown = false
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showKnown = false } } }
                }.tint(Color.bronze)
            }
            .sheet(item: $picker, onDismiss: {
                if let pendingStart {
                    self.pendingStart = nil
                    environment.openSession(pendingStart.passage, scope: pendingStart.scope)
                }
            }) { purpose in
                PlanPickerView(purpose: purpose) { pendingStart = PendingStart(passage: $0, scope: $1) }
            }
        }
    }

    /// Shown once after the update that made memorization an explicit claim.
    private var statusChangeNote: some View {
        WarmCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your progress now counts only what you mark as memorized").font(.headline)
                Text("Listening and practice still show as activity. If you already know some surahs, mark them so your progress is right.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm)
                HStack(spacing: 12) {
                    Button("Mark what I know") { showKnown = true }
                        .buttonStyle(WarmButtonStyle()).accessibilityIdentifier("note.markKnown")
                    Button("Got it") { environment.settings.showsStatusChangeNote = false }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("note.dismiss")
                }
            }
        }
    }
}
