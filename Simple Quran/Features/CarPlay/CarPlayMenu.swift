import Foundation

/// SF Symbols the car shows on rows and Now Playing buttons.
nonisolated enum CarPlaySymbol: String, Hashable, Sendable {
    case newAyahs = "leaf"
    case revise = "arrow.counterclockwise"
    case memorized = "checkmark.circle"
    case done = "checkmark"
    case surah = "book"
    case juz = "books.vertical"
    case resume = "play.circle"
    case phone = "iphone"
    case reciter = "person.wave.2"
    case repeatAyah = "repeat"
    case selected = "checkmark.circle.fill"
}

/// What a row plays. The car only listens, so none of these change what's memorized or tick Today.
nonisolated enum CarPlayAction: Hashable, Sendable {
    /// A passage of something the user is memorizing, played with their memorize repeats.
    case memorize(passage: VerseRange, targetID: UUID)
    /// Everything due for revision, once each, back to back.
    case revise([VerseRange])
    /// What the user has memorized of one surah.
    case memorized(surah: Int, passages: [VerseRange])
    /// A whole surah, starting at `fromAyah` when given.
    case surah(Int, fromAyah: Int?)
    case juz(Int)

    func passages(in catalog: BundledQuranCatalog) -> [VerseRange] {
        switch self {
        case .memorize(let passage, _): [passage]
        case .revise(let passages), .memorized(_, let passages): passages
        case .surah(let number, _): catalog.surah(number: number).map { [$0.range] } ?? []
        case .juz(let number): catalog.juzs.first { $0.number == number }.map { [$0.range] } ?? []
        }
    }

    /// Where listening starts; nil is the beginning.
    var startAyah: Int? {
        if case .surah(_, let fromAyah) = self { return fromAyah }
        return nil
    }

    /// The name playback shows, matching what the phone shows for the same listening.
    func title(in catalog: BundledQuranCatalog) -> String {
        switch self {
        case .memorize(let passage, _): PassageLabel.passage(passage, catalog: catalog)
        case .revise: String(localized: "Revision")
        case .memorized(let surah, _), .surah(let surah, _): QuranDestination.surah(number: surah).title(in: catalog)
        case .juz(let number): QuranDestination.juz(number).title(in: catalog)
        }
    }
}

nonisolated enum CarPlayTap: Hashable, Sendable {
    case play(CarPlayAction)
    case browseJuz(Int)
}

nonisolated struct CarPlayRow: Hashable, Sendable {
    var title: String
    var detail: String?
    var symbol: CarPlaySymbol
    /// Nil for a row that only tells the user something.
    var tap: CarPlayTap?
    var isPlaying = false
}

nonisolated struct CarPlaySection: Hashable, Sendable {
    var header: String?
    var rows: [CarPlayRow]
}

/// The rows CarPlay shows, worked out from the same state as the phone's screens.
nonisolated enum CarPlayMenu {
    // MARK: - Memorize tab

    /// Today's checklist as rows to listen to, then everything the user has memorized.
    static func memorize(today: TodayPlan, activePlanID: UUID?, snapshots: [VerseProgressSnapshot],
                         catalog: BundledQuranCatalog, order: ProgressOrder, ayahRepeat: RepeatCount) -> [CarPlaySection] {
        var todayRows = [learnRow(today.learn, activePlanID: activePlanID, catalog: catalog, ayahRepeat: ayahRepeat)]
        if let revise = today.revise { todayRows.append(reviseRow(revise)) }
        var sections = [CarPlaySection(header: String(localized: "Today"), rows: todayRows)]
        let memorized = memorizedRows(snapshots: snapshots, catalog: catalog, order: order)
        if !memorized.isEmpty { sections.append(CarPlaySection(header: String(localized: "Memorized"), rows: memorized)) }
        return sections
    }

    private static func learnRow(_ learn: TodayPlan.LearnRow?, activePlanID: UUID?, catalog: BundledQuranCatalog,
                                 ayahRepeat: RepeatCount) -> CarPlayRow {
        let repeats = ayahRepeat == .one ? nil : String(localized: "Each ayah \(ayahRepeat.label)")
        func details(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " · ") }

        switch learn {
        case nil:
            return CarPlayRow(title: String(localized: "Choose what to memorize on your iPhone"), symbol: .phone)
        case .next(let passage, let targetID, _):
            return CarPlayRow(title: String(localized: "Memorize \(surahName(passage, catalog: catalog))"),
                              detail: details(LearningPassage.ayahLabel(passage, catalog: catalog), repeats),
                              symbol: .newAyahs, tap: .play(.memorize(passage: passage, targetID: targetID)))
        case .done(let learned, _):
            // Listening again to what was learned today is the most useful thing on a drive home.
            return CarPlayRow(title: String(localized: "Memorize \(surahName(learned, catalog: catalog))"),
                              detail: details(String(localized: "Done today"), LearningPassage.ayahLabel(learned, catalog: catalog)),
                              symbol: .done, tap: activePlanID.map { .play(.memorize(passage: learned, targetID: $0)) })
        case .beginNext(let target, let passage):
            return CarPlayRow(title: String(localized: "Begin \(target.title(catalog: catalog))"),
                              detail: details(LearningPassage.ayahLabel(passage, catalog: catalog), repeats),
                              symbol: .newAyahs, tap: .play(.memorize(passage: passage, targetID: target.id)))
        case .finished(let target):
            return CarPlayRow(title: String(localized: "Choose what to memorize next on your iPhone"),
                              detail: String(localized: "You’ve memorized all of \(target.title(catalog: catalog))"), symbol: .phone)
        }
    }

    private static func reviseRow(_ revise: TodayPlan.ReviseRow) -> CarPlayRow {
        switch revise {
        case .due(let surahName, let ayahs, let passages, let freshness, let more):
            let details = [ayahs, freshness.title, more > 0 ? String(localized: "\(more) more") : nil].compactMap { $0 }
            return CarPlayRow(title: String(localized: "Revise \(surahName)"), detail: details.joined(separator: " · "),
                              symbol: .revise, tap: .play(.revise(passages)))
        case .done:
            return CarPlayRow(title: String(localized: "Revised today"), symbol: .done)
        }
    }

    /// Surahs with anything memorized, in the order the user's journey runs.
    private static func memorizedRows(snapshots: [VerseProgressSnapshot], catalog: BundledQuranCatalog,
                                      order: ProgressOrder) -> [CarPlayRow] {
        let memorized = snapshots.filter { $0.status == .memorized }
        guard !memorized.isEmpty else { return [] }
        let surahNumbers = Set(memorized.compactMap { catalog.verse(globalAyah: $0.globalAyah)?.surahNumber })
        return order.arranged(catalog.surahs.filter { surahNumbers.contains($0.number) }).map { surah in
            let passages = ReviewPlanner.memorizedPassages(in: surah.range, snapshots: memorized, catalog: catalog)
            let parts = joined(passages)
            let detail = parts == [surah.range]
                ? surah.arabicName
                : parts.map { LearningPassage.ayahLabel($0, catalog: catalog) }.joined(separator: ", ")
            return CarPlayRow(title: surah.englishName, detail: detail, symbol: .memorized,
                              tap: .play(.memorized(surah: surah.number, passages: passages)))
        }
    }

    /// Back-to-back passages read as one span, so a long memorized stretch is labeled once.
    private static func joined(_ passages: [VerseRange]) -> [VerseRange] {
        passages.reduce(into: []) { spans, passage in
            if let last = spans.last, last.endGlobalAyah + 1 == passage.startGlobalAyah {
                spans[spans.count - 1] = .clamped(start: last.startGlobalAyah, end: passage.endGlobalAyah)
            } else {
                spans.append(passage)
            }
        }
    }

    // MARK: - Quran tab

    /// Recently played surahs (the latest picks up where the user stopped), then every juz to browse.
    static func quran(recentSurahs: [Int], readingAyah: Int, catalog: BundledQuranCatalog) -> [CarPlaySection] {
        let reading = catalog.verse(globalAyah: readingAyah)
        let recent = recentSurahs.compactMap(catalog.surah(number:)).map { surah in
            if let reading, reading.surahNumber == surah.number, reading.ayahInSurah > 1, reading.globalAyah < surah.endGlobalAyah {
                return CarPlayRow(title: surah.englishName, detail: String(localized: "Continue from ayah \(reading.ayahInSurah)"),
                                  symbol: .resume, tap: .play(.surah(surah.number, fromAyah: reading.globalAyah)))
            }
            return CarPlayRow(title: surah.englishName, detail: surah.arabicName, symbol: .surah,
                              tap: .play(.surah(surah.number, fromAyah: nil)))
        }
        let juzs = catalog.juzs.map { juz in
            let surahs = ProgressMap.surahs(in: juz, from: catalog.surahs)
            let names = [surahs.first, surahs.count > 1 ? surahs.last : nil].compactMap { $0?.surah.englishName }
            return CarPlayRow(title: QuranDestination.juz(juz.number).title(in: catalog), detail: names.joined(separator: " – "),
                              symbol: .juz, tap: .browseJuz(juz.number))
        }
        var sections: [CarPlaySection] = []
        if !recent.isEmpty { sections.append(CarPlaySection(header: String(localized: "Recent"), rows: recent)) }
        sections.append(CarPlaySection(header: String(localized: "Juz"), rows: juzs))
        return sections
    }

    /// One juz: play all of it, or any surah in it. A surah that began in an earlier juz starts where this juz does.
    static func juz(_ number: Int, catalog: BundledQuranCatalog) -> [CarPlaySection] {
        guard let juz = catalog.juzs.first(where: { $0.number == number }) else { return [] }
        let playAll = CarPlayRow(title: String(localized: "Play all of \(QuranDestination.juz(number).title(in: catalog))"),
                                 symbol: .resume, tap: .play(.juz(number)))
        let surahs = ProgressMap.surahs(in: juz, from: catalog.surahs).map { part in
            let firstAyah = catalog.verse(globalAyah: part.range.startGlobalAyah)?.ayahInSurah ?? 1
            return CarPlayRow(
                title: part.surah.englishName,
                detail: part.startsHere ? String(localized: "\(part.surah.arabicName) · \(part.surah.ayahCount) ayahs")
                    : String(localized: "From ayah \(firstAyah)"),
                symbol: .surah,
                tap: .play(.surah(part.surah.number, fromAyah: part.startsHere ? nil : part.range.startGlobalAyah)))
        }
        return [CarPlaySection(header: nil, rows: [playAll]), CarPlaySection(header: String(localized: "Surahs"), rows: surahs)]
    }

    // MARK: - Playing

    /// Marks the rows that play exactly what's playing now.
    static func markingPlaying(_ sections: [CarPlaySection], playing: [VerseRange]?, catalog: BundledQuranCatalog) -> [CarPlaySection] {
        sections.map { section in
            var section = section
            for index in section.rows.indices {
                guard case .play(let action) = section.rows[index].tap else { continue }
                section.rows[index].isPlaying = playing != nil && action.passages(in: catalog) == playing
            }
            return section
        }
    }

    private static func surahName(_ range: VerseRange, catalog: BundledQuranCatalog) -> String {
        catalog.verse(globalAyah: range.startGlobalAyah).flatMap { catalog.surah(number: $0.surahNumber) }?.englishName ?? ""
    }
}
