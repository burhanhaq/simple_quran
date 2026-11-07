import AppIntents

/// A surah as Siri and Shortcuts see it. Its spoken names let "Mulk" or "Tabarak" find Al-Mulk.
nonisolated struct SurahEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Surah") }
    static var defaultQuery: SurahQuery { SurahQuery() }

    let id: Int
    let name: String
    let meaning: String
    let ayahCount: Int
    let spokenNames: [String]

    init(_ surah: Surah) {
        id = surah.number
        name = surah.englishName
        meaning = surah.translation
        ayahCount = surah.ayahCount
        spokenNames = SpokenNames.surah(surah)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(id). \(meaning) · \(ayahCount) ayahs",
            synonyms: spokenNames.map { "\($0)" }
        )
    }
}

struct SurahQuery: EnumerableEntityQuery, EntityStringQuery {
    @Dependency private var environment: AppEnvironment

    @MainActor
    func entities(for identifiers: [Int]) async throws -> [SurahEntity] {
        identifiers.compactMap { environment.quran.surah(number: $0) }.map(SurahEntity.init)
    }

    /// Uses the app's own search, which forgives spelling ("Fatiha", "Yaseen") and accepts numbers.
    @MainActor
    func entities(matching string: String) async throws -> [SurahEntity] {
        environment.quran.surahs(matching: string).map(SurahEntity.init)
    }

    /// Every surah, so Siri learns all of their names for the spoken phrases.
    @MainActor
    func allEntities() async throws -> [SurahEntity] {
        environment.quran.surahs.map(SurahEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SurahEntity] {
        try await allEntities()
    }
}

/// One of the 30 juz, by number or traditional name ("Juz 18", "Para 18", "Amma").
nonisolated struct JuzEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Juz") }
    static var defaultQuery: JuzQuery { JuzQuery() }

    let id: Int
    /// The surah and ayah the juz opens with, e.g. "Al-Mulk 1".
    let opening: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "Juz \(id)",
            subtitle: "Begins at \(opening)",
            synonyms: SpokenNames.juz(id).map { "\($0)" }
        )
    }
}

struct JuzQuery: EnumerableEntityQuery, EntityStringQuery {
    @Dependency private var environment: AppEnvironment

    @MainActor
    func entities(for identifiers: [Int]) async throws -> [JuzEntity] {
        identifiers.compactMap(entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [JuzEntity] {
        environment.quran.juzs(matching: string).compactMap { entity($0.number) }
    }

    @MainActor
    func allEntities() async throws -> [JuzEntity] {
        environment.quran.juzs.compactMap { entity($0.number) }
    }

    @MainActor
    func suggestedEntities() async throws -> [JuzEntity] {
        try await allEntities()
    }

    @MainActor
    private func entity(_ number: Int) -> JuzEntity? {
        let quran = environment.quran
        guard let juz = quran.juzs.first(where: { $0.number == number }) else { return nil }
        let opening = quran.verse(globalAyah: juz.startGlobalAyah).map {
            PassageLabel.passage(.clamped(start: $0.globalAyah, end: $0.globalAyah), catalog: quran)
        } ?? ""
        return JuzEntity(id: number, opening: opening)
    }
}
