# Simple Quran

Simple Quran is an iOS app for reading the Quran and practicing passages you want to memorize. The full Uthmani text is bundled on the device. Collections, recall progress, downloaded audio, and personal recordings stay local. No account is required.

The reciter is Abdul Rahman Al-Sudais. Audio can be streamed or downloaded for offline practice.

## Requirements

- Xcode 26 or later, with the iOS 26.2 SDK
- Swift 6
- An iPhone or iPad running iOS 26.2 or later, or the matching simulator

## Run

Open `Simple Quran.xcodeproj` and run the **Simple Quran** scheme.

## Features

**Today** shows whether you practiced today, your streak, the last session you can resume, and collections that have ayahs due for review.

**Quran** browses by surah, juz, or the 604-page Madani Hafs layout. Search accepts a surah name, a juz or page number, or a reference such as `18:1-10`. Reading can switch between ayah-by-ayah and a flowing Mushaf layout. You can listen to a range, or collect ayahs — including passages from different surahs — and save them as a collection.

**Collections** holds saved passages. A collection can be practiced, edited, archived, or downloaded for offline use. Practice options include how many times to repeat each ayah, how many times to repeat the collection, a pause of up to five seconds after an ayah, hiding the Arabic for recall, and advancing manually.

**Practice** plays the collection with a mini player that stays available across tabs, including lock screen and background audio. You can mark an ayah for review, hide the current ayah, record your own recitation, and play that recording back beside the reciter. Recordings stay on the device. When you finish, you can rate recall as Again, Needs work, Comfortable, or Solid. That rating schedules the next review.

**Progress** summarizes ayahs you know, completed surahs, Juz 30, and ayahs that still need work.

**Settings** (from Today) covers light, night, or system appearance, Wi-Fi-only downloads, streaming when an ayah is not downloaded, and deleting downloaded audio or all recordings.

## Tests

Unit tests live in `Simple QuranTests` and use the Swift Testing framework. They cover the bundled text integrity (114 surahs, 6,236 ayahs, 604 pages), search, practice playback, and progress scheduling. UI tests live in `Simple QuranUITests`.

From the repository root:

```sh
xcodebuild test \
  -project "Simple Quran.xcodeproj" \
  -scheme "Simple Quran" \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use an installed simulator name if `iPhone 17` is not available.

## Project layout

```
Simple Quran.xcodeproj
Simple Quran/
  App/                 entry point, environment, root tabs
  Core/
    Audio/             playback, session, lock screen
    DesignSystem/      parchment theme and fonts
    Domain/            ranges, recall scheduling, progress
    Downloads/         background audio downloads
    Persistence/       SwiftData models
    QuranContent/      bundled text, search
    Recording/         on-device recitation recordings
  Features/            Today, Quran, Collections, Practice, Progress, Settings
  Resources/
    Fonts/             KFGQPC HAFS Uthmanic Script
    Quran/             quran-hafs.json (built by Scripts/BuildQuranText.swift)
Simple QuranTests/
Simple QuranUITests/
Scripts/RenderAppIcon.swift
Scripts/BuildQuranText.swift
```

## Sources and licenses

- **Quran text.** Uthmani Hafs text (QPC Hafs) from the King Fahd Glorious Quran Printing Complex, distributed by the [Quranic Universal Library](https://qul.tarteel.ai). To rebuild it, download "QPC Hafs script, Ayah by Ayah" (JSON) from QUL into `Scripts/QuranSources/` and run `swift Scripts/BuildQuranText.swift <qul.json> "Simple Quran/Resources/Quran/quran-hafs.json" "Simple Quran/Resources/Fonts/UthmanicHafs_V22.ttf" "Simple Quran/Resources/Quran/quran-hafs.json"`. The only change to the text is moving each ayah's number out of it. Do not modify the verse text. See `Simple Quran/Resources/Quran/ATTRIBUTION.txt`.
- **Page, juz, and sajdah metadata.** Standard 604-page Madani Hafs layout, used for navigation. Verse display is flowing text, not a pixel-identical Mushaf page.
- **Audio.** Abdul Rahman Al-Sudais recitations are streamed or downloaded from the Al Quran Cloud / islamic.network CDN for personal and educational use. Copyright remains with the reciter.
- **Font.** KFGQPC HAFS Uthmanic Script (V22) © King Fahd Glorious Quran Printing Complex, free to use and distribute but not to sell or modify. Ship `UthmanicHafs_V22.ttf` byte-for-byte. See `Simple Quran/Resources/Fonts/KFGQPC-LICENSE.txt`.

## Privacy

Collections, progress, downloads, and recordings are stored on the device. The microphone is used only when you record a collection. The app includes no account and no analytics SDK. Downloaded recitation and recordings can be removed from Settings.
