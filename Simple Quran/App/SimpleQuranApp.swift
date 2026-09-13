import SwiftData
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    var downloads: AudioDownloadManager?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        downloads?.backgroundCompletionHandler = completionHandler
    }
}

@main
struct SimpleQuranApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer
    private let environment: AppEnvironment

    init() {
        AppTheme.registerFonts()
        let container: ModelContainer
        var persistenceLoadError: UserFacingMessage?
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            // Use an in-memory container only to render a blocking recovery screen.
            // The user cannot unknowingly create data that disappears on relaunch.
            container = try! PersistenceController.makeContainer(inMemory: true)
            persistenceLoadError = UserFacingMessage.from(.persistenceFailure)
        }
        self.container = container

        let source = AlQuranCloudAudioSource()
        let files = AudioFileStore(reciter: source.reciter)
        let settings = AppSettings()
        let downloads = AudioDownloadManager(
            source: source,
            fileStore: files,
            allowCellular: !settings.wifiOnly
        )
        downloads.attach(context: container.mainContext)
        let playback = PlaybackCoordinator(source: source, fileStore: files)
        let recorder = RecitationRecordingController()
        recorder.attach(context: container.mainContext)
        let store = PracticeStore(context: container.mainContext)

        let catalog: BundledQuranCatalog
        var loadError: UserFacingMessage?
        do {
            catalog = try BundledQuranCatalog.loadFromBundle()
        } catch let error as AppError {
            loadError = UserFacingMessage.from(error)
            catalog = fallbackCatalog()
        } catch {
            loadError = UserFacingMessage.from(.missingQuranData)
            catalog = fallbackCatalog()
        }

        let environment = AppEnvironment(
            quran: catalog,
            store: store,
            audioSource: source,
            downloads: downloads,
            playback: playback,
            recorder: recorder,
            settings: settings
        )
        environment.catalogLoadError = loadError
        environment.persistenceLoadError = persistenceLoadError
        self.environment = environment
        appDelegate.downloads = downloads
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(environment)
                .modelContainer(container)
        }
    }
}

private func fallbackCatalog() -> BundledQuranCatalog {
    let ayah = #"{"g":1,"n":1,"t":"بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ","j":1,"p":1}"#
    let json = Data(#"{"surahs":[{"number":1,"arabicName":"الفاتحة","englishName":"Al-Faatiha","translation":"The Opening","revelation":"Meccan","ayahs":[\#(ayah)]}]}"#.utf8)
    // Fallback is only used so the shell can render a friendly error. Integrity will fail in tests, not here.
    return try! BundledQuranCatalog(data: json, strict: false)
}
