import CoreText
import OSLog
import SwiftUI
import UIKit

/// The one place that knows which font and conventions draw Quran text.
/// The KFGQPC HAFS font is paired with the King Fahd (QPC Hafs) text in quran-hafs.json;
/// changing one without the other misplaces marks.
enum QuranScript {
    nonisolated static let fontFile = "UthmanicHafs_V22"
    nonisolated static let fontExtension = "ttf"
    /// Truncated like this inside the font itself. Any other spelling silently falls back to the system font.
    nonisolated static let postScriptName = "KFGQPCHAFSUthmanicScript-Regula"
    /// Shown in place of an ayah hidden for recall. The font has no bullet, so iOS draws it in the system font.
    static let hiddenPlaceholder = "••••••"

    nonisolated enum Size: Hashable, Sendable {
        case body
        case basmala
        case title
        case listName

        var points: CGFloat {
            switch self {
            case .body, .title: 28
            case .basmala: 25
            case .listName: 23
            }
        }

        var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .body, .title: .title2
            case .basmala, .listName: .title3
            }
        }

        var textStyle: Font.TextStyle {
            switch self {
            case .body, .title: .title2
            case .basmala, .listName: .title3
            }
        }
    }

    private static let logger = Logger(subsystem: "com.simpleAzaan.Simple-Quran1", category: "quran-script")
    private static var fontCache: [FontKey: UIFont] = [:]

    private struct FontKey: Hashable {
        var size: Size
        var category: UIContentSizeCategory
    }

    @discardableResult
    static func registerFont(in bundle: Bundle = .main) -> Bool {
        if UIFont(name: postScriptName, size: Size.body.points) != nil { return true }
        let candidates = [
            bundle.url(forResource: fontFile, withExtension: fontExtension, subdirectory: "Resources/Fonts"),
            bundle.url(forResource: fontFile, withExtension: fontExtension, subdirectory: "Fonts"),
            bundle.url(forResource: fontFile, withExtension: fontExtension)
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            logger.fault("Quran font \(fontFile, privacy: .public) is missing from the bundle")
            assertionFailure("Quran font is missing from the bundle")
            return false
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        guard registered || UIFont(name: postScriptName, size: Size.body.points) != nil else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            logger.fault("Quran font failed to register: \(reason, privacy: .public)")
            assertionFailure("Quran font failed to register")
            return false
        }
        return true
    }

    /// Scaled for Dynamic Type and cached, since every continuous-flow page asks for the same fonts.
    static func uiFont(_ size: Size, category: UIContentSizeCategory) -> UIFont {
        let key = FontKey(size: size, category: category)
        if let cached = fontCache[key] { return cached }
        let base = UIFont(name: postScriptName, size: size.points) ?? .systemFont(ofSize: size.points)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let font = UIFontMetrics(forTextStyle: size.uiTextStyle).scaledFont(for: base, compatibleWith: traits)
        fontCache[key] = font
        return font
    }

    static func font(_ size: Size) -> Font {
        .custom(postScriptName, size: size.points, relativeTo: size.textStyle)
    }

    /// A no-break space keeps the number on the ayah's last line, and the font draws the
    /// end-of-ayah ornament around Arabic-Indic digits.
    static func ayahNumber(_ number: Int) -> String {
        "\u{00A0}" + String(number).map { digit in
            digit.wholeNumberValue.map { arabicIndicDigits[$0] } ?? digit
        }
    }

    private static let arabicIndicDigits = Array("٠١٢٣٤٥٦٧٨٩")

    /// Loads the font's shaping tables once, off the main thread, so opening the first
    /// surah doesn't pay for it.
    nonisolated static func warmUp() {
        let font = CTFontCreateWithName(postScriptName as CFString, Size.body.points, nil)
        let sample = "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ\u{00A0}١٢٣"
        let attributed = NSAttributedString(string: sample, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        _ = CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}
