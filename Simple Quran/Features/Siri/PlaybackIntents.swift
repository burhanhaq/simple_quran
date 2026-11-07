import AppIntents

/// "Play Al-Mulk", optionally from a given ayah.
struct PlaySurahIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Surah"
    static let description = IntentDescription("Plays a surah with your chosen reciter.")

    @Parameter(title: "Surah", requestValueDialog: "Which surah?")
    var surah: SurahEntity

    @Parameter(title: "Starting Ayah", inclusiveRange: (1, 286))
    var startAyah: Int?

    @Dependency private var environment: AppEnvironment

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$surah)") { \.$startAyah }
    }

    init() {}

    init(surah: SurahEntity) { self.surah = surah }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let surah = environment.quran.surah(number: self.surah.id) else { throw SiriListeningError.unknownPassage }
        let fromAyah = try startAyah.map { ayah in
            try SiriListeningError.checking(surah) { () throws(SiriListening.Problem) in try SiriListening.globalAyah(of: surah, ayah: ayah) }
        }
        let title = QuranDestination.surah(number: surah.number).title(in: environment.quran)
        try await environment.listenForSiri(title: title, passages: [surah.range], fromAyah: fromAyah)
        let dialog: IntentDialog = if let startAyah, startAyah > 1 {
            "Playing \(title) from ayah \(startAyah)."
        } else {
            "Playing \(title)."
        }
        return .result(dialog: dialog)
    }
}

/// "Play 10 ayahs of Al-Baqara", optionally from a given ayah.
struct PlayAyahsIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Ayahs"
    static let description = IntentDescription("Plays a number of ayahs from a surah, starting at the ayah you choose.")

    @Parameter(title: "Surah", requestValueDialog: "Which surah?")
    var surah: SurahEntity

    @Parameter(title: "Number of Ayahs", inclusiveRange: (1, 286), requestValueDialog: "How many ayahs?")
    var count: Int

    @Parameter(title: "Starting Ayah", default: 1, inclusiveRange: (1, 286))
    var startAyah: Int

    @Dependency private var environment: AppEnvironment

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$count) ayahs of \(\.$surah) from ayah \(\.$startAyah)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let quran = environment.quran
        guard let surah = quran.surah(number: self.surah.id) else { throw SiriListeningError.unknownPassage }
        let range = try SiriListeningError.checking(surah) { () throws(SiriListening.Problem) in try SiriListening.ayahs(of: surah, from: startAyah, count: count) }
        let title = PassageLabel.passage(range, catalog: quran)
        try await environment.listenForSiri(title: title, passages: [range])
        let dialog: IntentDialog = range.count < count
            ? "\(surah.englishName) ends at ayah \(surah.ayahCount), so playing \(title)."
            : "Playing \(title)."
        return .result(dialog: dialog)
    }
}

/// "Play Juz 18".
struct PlayJuzIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Juz"
    static let description = IntentDescription("Plays a whole juz with your chosen reciter.")

    @Parameter(title: "Juz", requestValueDialog: "Which juz?")
    var juz: JuzEntity

    @Dependency private var environment: AppEnvironment

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$juz)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let quran = environment.quran
        guard let section = quran.juzs.first(where: { $0.number == juz.id }) else { throw SiriListeningError.unknownPassage }
        let title = QuranDestination.juz(section.number).title(in: quran)
        try await environment.listenForSiri(title: title, passages: [section.range])
        return .result(dialog: "Playing Juz \(section.number).")
    }
}

/// "Continue listening": picks up whatever was playing, or the last ayah listened to.
struct ContinueListeningIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Continue Listening"
    static let description = IntentDescription("Carries on from the last ayah you listened to.")

    @Dependency private var environment: AppEnvironment

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let playback = environment.playback
        if playback.snapshot.currentGlobalAyah != nil {
            playback.resume()
            try await environment.awaitPlaybackStart()
            return .result(dialog: "Continuing \(playback.snapshot.setTitle).")
        }
        let quran = environment.quran
        guard let verse = quran.verse(globalAyah: environment.settings.readingAyah),
              let surah = quran.surah(number: verse.surahNumber) else { throw SiriListeningError.nothingToContinue }
        let title = QuranDestination.surah(number: surah.number).title(in: quran)
        try await environment.listenForSiri(title: title, passages: [surah.range], fromAyah: verse.globalAyah)
        return .result(dialog: "Continuing \(title) from ayah \(verse.ayahInSurah).")
    }
}

nonisolated enum SiriListeningError: Error, CustomLocalizedStringResourceConvertible {
    case unknownPassage
    case ayahOutOfRange(surah: String, ayahCount: Int, asked: Int)
    case noAyahs
    case nothingToContinue
    case playbackFailed(UserFacingMessage)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unknownPassage:
            "That part of the Quran couldn’t be found."
        case .ayahOutOfRange(let surah, let ayahCount, let asked):
            "\(surah) has \(ayahCount) ayahs, so there is no ayah \(asked)."
        case .noAyahs:
            "Ask for at least one ayah."
        case .nothingToContinue:
            "There’s nothing to continue yet. Ask to play a surah or juz first."
        case .playbackFailed(let message):
            "\(message.title). \(message.message)"
        }
    }

    /// Runs a `SiriListening` step on `surah`, turning its problem into something Siri can say.
    static func checking<T>(_ surah: Surah, _ body: () throws(SiriListening.Problem) -> T) throws(SiriListeningError) -> T {
        do {
            return try body()
        } catch {
            switch error {
            case .ayahOutOfRange(_, let ayahCount, let asked):
                throw .ayahOutOfRange(surah: surah.englishName, ayahCount: ayahCount, asked: asked)
            case .countNotPositive:
                throw .noAyahs
            }
        }
    }
}

extension AppEnvironment {
    /// How long Siri waits for audio before answering anyway; streaming can take a moment to begin.
    private static let siriStartLimit: Duration = .seconds(4)
    private static let siriStartPoll: Duration = .milliseconds(100)

    /// Plays what Siri was asked for from its start, even when the same passage is paused part way.
    func listenForSiri(title: String, passages: [VerseRange], fromAyah: Int? = nil) async throws {
        listen(title: title, passages: passages, fromAyah: fromAyah, restart: true)
        try await awaitPlaybackStart()
    }

    /// Waits until audio plays or fails, so Siri says the problem rather than "Playing" over silence.
    func awaitPlaybackStart() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.siriStartLimit)
        while clock.now < deadline {
            if let message = playback.userMessage { throw SiriListeningError.playbackFailed(message) }
            if playback.snapshot.isPlaying || !playback.snapshot.isLoading { return }
            try await Task.sleep(for: Self.siriStartPoll)
        }
    }
}
