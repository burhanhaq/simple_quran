import SwiftUI

struct ProgressViewScreen: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var snapshots: [VerseProgressSnapshot] = []

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Overview")) {
                    labeled(String(localized: "Currently learning"), "\(learningCount)")
                    labeled(String(localized: "Due for review"), "\(dueCount)")
                    labeled(String(localized: "Recall attempts"), "\(recallAttempts)")
                    labeled(String(localized: "Days practised"), "\(daysPractised)")
                }
                Section(String(localized: "Recent weak ayahs")) {
                    if weakAyahs.isEmpty {
                        Text(String(localized: "No ayahs are marked weak."))
                            .foregroundStyle(Color.secondaryWarm)
                    } else {
                        ForEach(weakAyahs, id: \.globalAyah) { item in
                            if let verse = environment.quran.verse(globalAyah: item.globalAyah) {
                                VStack(alignment: .leading) {
                                    Text(verse.reference).foregroundStyle(Color.appBrownText)
                                    Text(item.recallState.title).font(.caption).foregroundStyle(Color.olive)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .navigationTitle(String(localized: "Progress"))
            .onAppear {
                snapshots = (try? environment.store.allProgress()) ?? []
            }
        }
    }

    private var learningCount: Int {
        snapshots.filter { $0.recallState == .learning || $0.recallState == .strengthening }.count
    }

    private var dueCount: Int { snapshots.filter(\.isDue).count }
    private var recallAttempts: Int { snapshots.reduce(0) { $0 + $1.recallAttempts } }
    private var daysPractised: Int {
        Set(snapshots.compactMap { $0.lastPractisedAt.map { Calendar.current.startOfDay(for: $0) } }).count
    }

    private var weakAyahs: [VerseProgressSnapshot] {
        snapshots.filter(\.isWeak).sorted { ($0.lastPractisedAt ?? .distantPast) > ($1.lastPractisedAt ?? .distantPast) }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(Color.gold).fontWeight(.semibold)
        }
    }
}
