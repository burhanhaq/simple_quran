import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil && $0.archivedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    @State private var showSettings = false
    @State private var practiceSet: PracticeSet?
    @State private var errorMessage: UserFacingMessage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let loadError = environment.catalogLoadError {
                        FriendlyErrorView(message: loadError)
                    }
                    continueCard
                    dueSection
                    recentSection
                    statsRow
                }
                .padding()
            }
            .background(Color.parchment.ignoresSafeArea())
            .navigationTitle(String(localized: "Today"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("home.settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $practiceSet) { set in
                PracticeView(practiceSet: set)
            }
        }
    }

    @ViewBuilder
    private var continueCard: some View {
        let last = sets.first { $0.lastPractisedAt != nil }
        if let last {
            Button {
                practiceSet = last
            } label: {
                WarmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Continue last session"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.olive)
                        Text(last.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.appBrownText)
                        if let ayah = last.lastGlobalAyah, let verse = environment.quran.verse(globalAyah: ayah) {
                            Text(String(localized: "Resume at \(verse.reference)"))
                                .foregroundStyle(Color.secondaryWarm)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.continue")
        } else if sets.isEmpty {
            EmptyStateView(
                title: String(localized: "Create your first collection"),
                message: String(localized: "Save a passage, a surah, or a custom group of ayahs for focused practice."),
                actionTitle: String(localized: "Browse the Quran")
            ) {
                environment.selectedTab = .quran
            }
        }
    }

    private var dueSection: some View {
        let due = dueSets
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Due for review"))
                .font(.headline)
                .foregroundStyle(Color.appBrownText)
            if due.isEmpty {
                Text(String(localized: "Nothing is due today. Open a collection whenever you’re ready."))
                    .foregroundStyle(Color.secondaryWarm)
            } else {
                ForEach(due, id: \.id) { set in
                    setRow(set, badge: String(localized: "Due"))
                }
            }
        }
        .accessibilityIdentifier("home.due")
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Recently practiced"))
                .font(.headline)
                .foregroundStyle(Color.appBrownText)
            ForEach(sets.prefix(5), id: \.id) { set in
                setRow(set, badge: nil)
            }
        }
    }

    private var statsRow: some View {
        let progress = (try? environment.store.allProgress()) ?? []
        let learning = progress.filter { $0.recallState == .learning || $0.recallState == .strengthening }.count
        let dueAyahs = progress.filter(\.isDue).count
        let days = Set(progress.compactMap { $0.lastPractisedAt.map { Calendar.current.startOfDay(for: $0) } }).count
        return HStack {
            stat(String(localized: "Learning"), "\(learning)")
            stat(String(localized: "Due ayahs"), "\(dueAyahs)")
            stat(String(localized: "Days practiced"), "\(days)")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.title2.weight(.bold)).foregroundStyle(Color.gold)
                Text(title).font(.caption).foregroundStyle(Color.secondaryWarm)
            }
        }
    }

    private func setRow(_ set: PracticeSet, badge: String?) -> some View {
        Button {
            practiceSet = set
        } label: {
            WarmCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(set.title).font(.headline).foregroundStyle(Color.appBrownText)
                        Text(passageSummary(set)).font(.caption).foregroundStyle(Color.secondaryWarm)
                    }
                    Spacer()
                    if let badge {
                        StatusChip(title: badge, tint: .gold)
                    }
                    Image(systemName: "play.circle.fill").foregroundStyle(Color.gold).font(.title2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.set.\(set.id.uuidString)")
    }

    private var dueSets: [PracticeSet] {
        (try? environment.store.dueSets(now: .now)) ?? []
    }

    private func passageSummary(_ set: PracticeSet) -> String {
        let ranges = set.orderedPassages.map(\.range)
        let count = ranges.reduce(0) { $0 + $1.count }
        return String(localized: "\(count) ayahs · \(ranges.count) passages")
    }
}
