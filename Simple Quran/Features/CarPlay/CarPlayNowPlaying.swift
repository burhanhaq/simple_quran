import CarPlay
import UIKit

/// The car's Now Playing screen: a reciter button, a repeat button while memorizing,
/// and an "Ayahs" list to jump within what's playing.
final class CarPlayNowPlaying: NSObject {
    private struct Buttons: Equatable {
        /// Nil when the playback isn't a memorize passage, so there's nothing to repeat.
        var ayahRepeat: RepeatCount?
        var hasUpNext: Bool
    }

    private static let ayahsTitle = String(localized: "Ayahs")
    private let environment: AppEnvironment
    private let interface: CPInterfaceController
    private let template = CPNowPlayingTemplate.shared
    private var shownButtons: Buttons?

    private var playback: PlaybackCoordinator { environment.playback }

    init(environment: AppEnvironment, interface: CPInterfaceController) {
        self.environment = environment
        self.interface = interface
        super.init()
    }

    func connect() {
        template.add(self)
        template.upNextTitle = Self.ayahsTitle
        refresh()
    }

    func disconnect() {
        template.remove(self)
        shownButtons = nil
    }

    /// Brings Now Playing to the front after the driver picks something to play.
    func show() {
        guard interface.topTemplate !== template else { return }
        if interface.templates.contains(where: { $0 === template }) {
            interface.pop(to: template, animated: true, completion: nil)
        } else {
            interface.pushTemplate(template, animated: true, completion: nil)
        }
    }

    func refresh() {
        let buttons = Buttons(ayahRepeat: playback.activeSet?.settings.ayahRepeatCount, hasUpNext: playback.versesInSet.count > 1)
        guard buttons != shownButtons else { return }
        shownButtons = buttons
        var shown: [CPNowPlayingButton] = [
            CPNowPlayingImageButton(image: Self.symbol(.reciter)) { [weak self] _ in self?.showReciters() }
        ]
        if let ayahRepeat = buttons.ayahRepeat {
            let button = CPNowPlayingImageButton(image: Self.repeatImage(ayahRepeat)) { [weak self] _ in self?.cycleRepeat() }
            button.isSelected = ayahRepeat != .one
            shown.append(button)
        }
        template.updateNowPlayingButtons(shown)
        template.isUpNextButtonEnabled = buttons.hasUpNext
    }

    // MARK: - Reciter

    private func showReciters() {
        let catalog = environment.reciters.catalog
        let current = environment.settings.reciter(in: catalog)
        let items = catalog.reciters.map { reciter in
            let item = CPListItem(text: reciter.englishName, detailText: reciter.arabicName)
            if reciter.id == current.id { item.setAccessoryImage(Self.symbol(.selected)) }
            item.handler = { [weak self] _, completion in
                // Playback carries on from the same ayah in the new voice.
                self?.environment.selectReciter(reciter)
                self?.interface.popTemplate(animated: true, completion: nil)
                completion()
            }
            return item
        }
        let list = CPListTemplate(title: String(localized: "Reciter"), sections: [CPListSection(items: items)])
        interface.pushTemplate(list, animated: true, completion: nil)
    }

    // MARK: - Repeat

    /// Steps through the same repeat choices as the phone. Like there, the choice becomes the memorize setting.
    private func cycleRepeat() {
        guard let practice = playback.activeSet else { return }
        let presets = RepeatCount.ayahPresets
        let position = presets.firstIndex(of: practice.settings.ayahRepeatCount) ?? 0
        var settings = practice.settings
        settings.ayahRepeatCount = presets[(position + 1) % presets.count]
        playback.applySettingsAndRestart(settings)
        environment.settings.memorizePlayback = settings.keepingHideArabic(of: environment.settings.memorizePlayback)
        do { try environment.store.save() } catch { playback.userMessage = .from(.persistenceFailure) }
        refresh()
    }

    /// The repeat symbol, with the count under it once an ayah plays more than once.
    private static func repeatImage(_ count: RepeatCount) -> UIImage {
        guard count != .one else { return symbol(.repeatAyah) }
        let size = CGSize(width: 40, height: 40)
        let icon = UIImage(systemName: CarPlaySymbol.repeatAyah.rawValue,
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        let label = count.label as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .bold)]
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            if let icon {
                icon.draw(at: CGPoint(x: (size.width - icon.size.width) / 2, y: 2))
            }
            let labelSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size.width - labelSize.width) / 2, y: size.height - labelSize.height - 1), withAttributes: attributes)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    // MARK: - Ayahs

    /// The ayahs from the one playing onward; tapping one jumps there.
    private func showAyahs() {
        let verses = playback.versesInSet
        let current = playback.snapshot.currentGlobalAyah
        let fromCurrent = verses.drop { $0.globalAyah != current }
        var seen = Set<Int>()
        // A passage that repeats lists each ayah once.
        let upcoming = (fromCurrent.isEmpty ? verses[...] : fromCurrent)
            .filter { seen.insert($0.globalAyah).inserted }
            .prefix(CPListTemplate.maximumItemCount)
        let items = upcoming.map { verse in
            let item = CPListItem(text: String(localized: "Ayah \(verse.ayahInSurah)"),
                                  detailText: environment.quran.surah(number: verse.surahNumber)?.englishName)
            item.isPlaying = verse.globalAyah == current
            item.handler = { [weak self] _, completion in
                self?.playback.move(to: verse.globalAyah)
                self?.interface.popTemplate(animated: true, completion: nil)
                completion()
            }
            return item
        }
        interface.pushTemplate(CPListTemplate(title: Self.ayahsTitle, sections: [CPListSection(items: items)]), animated: true, completion: nil)
    }

    private static func symbol(_ symbol: CarPlaySymbol) -> UIImage {
        UIImage(systemName: symbol.rawValue) ?? UIImage()
    }
}

extension CarPlayNowPlaying: CPNowPlayingTemplateObserver {
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        showAyahs()
    }
}
