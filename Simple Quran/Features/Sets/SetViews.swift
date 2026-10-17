import SwiftData
import SwiftUI

/// Earlier saved passages remain available with their recordings and settings.
struct SetListView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(filter: #Predicate<PracticeSet> { $0.deletedAt == nil }, sort: \PracticeSet.updatedAt, order: .reverse)
    private var sets: [PracticeSet]
    /// Presented from here because this list lives inside the Settings sheet.
    @State private var session: SessionRoute?

    private var savedPassages: [PracticeSet] {
        sets.filter { !environment.settings.generatedPracticeIDs.contains($0.id.uuidString) }
    }

    var body: some View {
        List {
            if savedPassages.isEmpty {
                Text("Any passages you saved before this update will appear here.")
                    .font(.subheadline).foregroundStyle(Color.secondaryWarm).warmListRow()
            }
            ForEach(savedPassages) { set in
                Button { session = environment.savedPracticeRoute(set) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(set.title).font(.headline).foregroundStyle(Color.appBrownText)
                        Text(PassageLabel.collection(set.orderedPassages.map(\.range), catalog: environment.quran))
                            .font(.caption).foregroundStyle(Color.secondaryWarm)
                    }.padding(.vertical, 8)
                }.warmListRow()
            }
        }
        .warmListChrome().navigationTitle("Older saved passages")
        .fullScreenCover(item: $session) { MemorizeSessionView(route: $0) }
    }
}
