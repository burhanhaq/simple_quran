import AppIntents

/// What people can say to Siri without setting anything up. Each phrase must name the app;
/// both "surah" and "sura" are listed because Siri hears either.
nonisolated struct SimpleQuranShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySurahIntent(),
            phrases: [
                "Play \(\.$surah) in \(.applicationName)",
                "Play \(\.$surah) on \(.applicationName)",
                "Play surah \(\.$surah) in \(.applicationName)",
                "Play surah \(\.$surah) on \(.applicationName)",
                "Play sura \(\.$surah) in \(.applicationName)",
                "Play sura \(\.$surah) on \(.applicationName)",
                "Listen to \(\.$surah) in \(.applicationName)",
                "Listen to surah \(\.$surah) in \(.applicationName)",
                "Recite \(\.$surah) in \(.applicationName)",
                "Recite surah \(\.$surah) in \(.applicationName)",
                "\(.applicationName) play \(\.$surah)",
                "\(.applicationName) play surah \(\.$surah)",
                "Play a surah in \(.applicationName)",
                "Play a surah on \(.applicationName)"
            ],
            shortTitle: "Play Surah",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayJuzIntent(),
            phrases: [
                "Play \(\.$juz) in \(.applicationName)",
                "Play \(\.$juz) on \(.applicationName)",
                "Play juz \(\.$juz) in \(.applicationName)",
                "Play juz \(\.$juz) on \(.applicationName)",
                "Play para \(\.$juz) in \(.applicationName)",
                "Listen to \(\.$juz) in \(.applicationName)",
                "\(.applicationName) play \(\.$juz)",
                "\(.applicationName) play juz \(\.$juz)",
                "Play a juz in \(.applicationName)",
                "Play a juz on \(.applicationName)"
            ],
            shortTitle: "Play Juz",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: PlayAyahsIntent(),
            phrases: [
                "Play ayahs of \(\.$surah) in \(.applicationName)",
                "Play ayahs of \(\.$surah) on \(.applicationName)",
                "Play ayahs from \(\.$surah) in \(.applicationName)",
                "Play ayahs from surah \(\.$surah) in \(.applicationName)",
                "Play ayahs of surah \(\.$surah) in \(.applicationName)",
                "Play ayahs of sura \(\.$surah) in \(.applicationName)",
                "Play verses of \(\.$surah) in \(.applicationName)",
                "Play verses from \(\.$surah) in \(.applicationName)",
                "\(.applicationName) play ayahs of \(\.$surah)",
                "Play ayahs in \(.applicationName)",
                "Play ayahs on \(.applicationName)"
            ],
            shortTitle: "Play Ayahs",
            systemImageName: "text.line.first.and.arrowtriangle.forward"
        )
        AppShortcut(
            intent: ContinueListeningIntent(),
            phrases: [
                "Continue listening in \(.applicationName)",
                "Continue listening on \(.applicationName)",
                "Continue the Quran in \(.applicationName)",
                "Resume \(.applicationName)",
                "Resume listening in \(.applicationName)"
            ],
            shortTitle: "Continue Listening",
            systemImageName: "playpause"
        )
    }
}
