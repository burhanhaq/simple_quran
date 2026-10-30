# Simple Quran

Simple Quran is an iPhone app for memorizing the Quran a piece at a time, and for reading and listening to it. The full Uthmani text and an English translation are bundled on the device. Progress, recordings, and downloaded recitation stay on the device. There is no account, no analytics, and no tracking.

- Bundle ID: `com.dumblemon.SimpleQuran`, published by Dumb Lemon
- iPhone only, free
- Website: <https://dumblemon.com/apps/simple-quran/>, with the [privacy policy](https://dumblemon.com/apps/simple-quran/privacy/) and [support](https://dumblemon.com/apps/simple-quran/support/) pages. Settings → Privacy in the app summarizes the policy, so keep the two in step.

## Requirements

- Xcode 26 or later, with the iOS 26.2 SDK
- Swift 6
- An iPhone running iOS 26.2 or later, or the matching simulator

## Run

Open `Simple Quran.xcodeproj` and run the **Simple Quran** scheme.

## Features

The app has two tabs.

**Memorize** opens on today's checklist: the next piece to learn, and what to revise. Pieces follow the Madani mushaf page (a quarter, half, or full page; a short surah is always one piece). A session moves from Listen, to Recite with the Arabic hidden, to Check, where you say whether you have it memorized. Ayahs only count as memorized when you say so. Below the checklist, **Your journey** maps every surah by juz and shows how fresh each memorized one is. Memorized surahs fade when they go longer than your revision cycle without being heard, recited, or marked "Revised today".

**Quran** browses by surah, juz, or the 604-page Madani layout. Read ayah by ayah, with the Saheeh International translation if you like, or as continuous text. Search accepts a surah name, a juz or page number, or a reference such as `18:1-10`. Swipe between surahs while reading. During playback the text follows the reciter.

**Listening** works everywhere, with lock screen and background playback and a mini player across tabs. There are six reciters, and Mahmoud Khalil Al-Husary is the default. The reciter list is bundled in `Resources/Audio/reciters.json`. The same file can later be published remotely (`RemoteCatalog.url`) to change reciters without an app update. Audio streams from cdn.islamic.network, and is kept for offline listening as it plays unless you turn that off.

**Recording** saves your recitation of a passage on the device so you can play it back beside the reciter.

**Settings** covers the start tab, appearance, reading layout, translation, reciter, download preferences, piece size, repeats, the revision cycle, and removing downloads or recordings. It also links to Privacy, Acknowledgements, support, and the website.

The app asks for an App Store rating once: after five listening sessions of at least a minute, or five revisions. It asks when a reader or session closes (`ReviewPrompt`).

## Data

User data is stored in SwiftData (`Core/Persistence/AppSchema.swift`). Memorization targets and preferences are stored in `UserDefaults` (`AppSettings`).

**`AppSchemaV1` is the schema that shipped in 1.0. Never change its models.** To change the data model, add `AppSchemaV2` and a migration stage in `AppMigrationPlan`.

The schema follows CloudKit's rules, so iCloud sync can be turned on later without a migration:

- no unique attributes, so every insert looks for an existing record first
- a default value for every stored property
- optional relationships

Turning sync on later also means moving memorization targets out of `UserDefaults`.

Recordings and downloaded audio live in Application Support and are excluded from backups.

## Tests

Unit tests live in `Simple QuranTests` and use the Swift Testing framework. They cover:

- bundled text integrity (114 surahs, 6,236 ayahs, 604 pages)
- search, pieces, and passage labels
- memorization status, freshness, and the reciter catalog
- the rating prompt

UI tests live in `Simple QuranUITests`. `AccessibilityAuditTests` runs Xcode's accessibility audit on every main screen.

Boot the simulator once and leave it running. If `xcodebuild` has to boot it, it shuts it down again afterwards, so every run pays a ~35s cold boot:

```sh
xcrun simctl boot "iPhone Air"
```

To run the unit tests only (about 20s on a booted simulator), from the repository root:

```sh
xcodebuild test \
  -project "Simple Quran.xcodeproj" \
  -scheme "Simple Quran" \
  -destination 'platform=iOS Simulator,name=iPhone Air' \
  -only-testing:"Simple QuranTests" \
  -collect-test-diagnostics never
```

Drop `-only-testing` to include the UI tests, which launch the app for every test and take several minutes. `-collect-test-diagnostics never` stops `xcodebuild` from running a sysdiagnose (up to 10 minutes) when the playback tests log an AVAudioSession hang-risk warning, even though every test passed.

If `iPhone Air` isn't available, use the name of an installed simulator.

## Release checklist

1. **Translation.** Check that QuranEnc's Saheeh International is still current: `https://quranenc.com/check/english_saheeh/v<version>` (the version is in `Resources/Translations/english_saheeh.json`). If a newer version exists, rebuild it with `swift Scripts/BuildTranslation.swift <quranenc.csv> "Simple Quran/Resources/Translations/english_saheeh.json"`.
2. **Reciters.** Check every reciter's audio: `swift Scripts/CheckReciterAudio.swift "Simple Quran/Resources/Audio/reciters.json"`.
3. **Tests.** Run the unit and UI tests, including the accessibility audit.
4. **Version.** Bump `CURRENT_PROJECT_VERSION` for every upload, and `MARKETING_VERSION` for every release.
5. **Privacy.** If what the app sends or stores changes, update Settings → Privacy (`PrivacyView`), the website's policy, and its effective date (`AppLinks.privacyEffectiveDate`) together. The App Store privacy label stays "Data Not Collected".

## Project layout

```
Simple Quran.xcodeproj
Simple Quran/
  App/                 entry point, environment, root tabs
  Core/
    AppIdentity.swift  bundle ID, version, the one logging subsystem
    AppLinks.swift     website, support, privacy, and source links
    Audio/             playback, session, lock screen, reciter catalog
    DesignSystem/      theme and Quran script
    Domain/            ranges, pieces, recall, freshness, progress
    Downloads/         background audio downloads
    Feedback/          the App Store rating prompt
    Persistence/       SwiftData schema and store
    QuranContent/      bundled text, translation, search
    Recording/         on-device recitation recordings
  Features/            Memorize, Quran, Surah (reader and sessions), Onboarding, Settings
  Resources/
    Audio/             reciters.json
    Fonts/             KFGQPC HAFS Uthmanic Script and its license
    Quran/             quran-hafs.json and ATTRIBUTION.txt
    Translations/      english_saheeh.json
Simple QuranTests/
Simple QuranUITests/
Scripts/               BuildQuranText, BuildTranslation, CheckReciterAudio, RenderAppIcon
```

## Sources and licenses

- **Quran text.** Uthmani Hafs text (QPC Hafs) from the King Fahd Glorious Quran Printing Complex, distributed by the [Quranic Universal Library](https://qul.tarteel.ai). To rebuild it:
  1. Download "QPC Hafs script, Ayah by Ayah" (JSON) from QUL into `Scripts/QuranSources/`.
  2. Run `swift Scripts/BuildQuranText.swift <qul.json> "Simple Quran/Resources/Quran/quran-hafs.json" "Simple Quran/Resources/Fonts/UthmanicHafs_V22.ttf" "Simple Quran/Resources/Quran/quran-hafs.json"`.

  The only change to the text is moving each ayah's number out of it. Do not modify the verse text.
- **Page, juz, and sajdah metadata.** Standard 604-page Madani Hafs layout, used for navigation and pieces. Verse display is flowing text, not a pixel-identical mushaf page.
- **Translation.** Saheeh International, issued by Noor International Center, from [QuranEnc](https://quranenc.com/en/browse/english_saheeh). It is bundled unchanged. The app hides footnote markers because it doesn't show footnotes yet.
- **Audio.** Recitations are streamed and downloaded from the Al Quran Cloud / islamic.network CDN for personal and educational use. Copyright remains with each reciter.
- **Font.** KFGQPC HAFS Uthmanic Script (V22) © King Fahd Glorious Quran Printing Complex. It is free to use and distribute, but not to sell or modify. Ship `UthmanicHafs_V22.ttf` byte-for-byte.

See `Simple Quran/Resources/Quran/ATTRIBUTION.txt` and Settings → Acknowledgements.
