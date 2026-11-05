import UIKit

/// Colors the Quran text is drawn in, shared by continuous text and mushaf pages.
enum MushafPalette {
    static let body = UIColor(named: "BrownText") ?? .label
    static let number = UIColor(named: "Bronze") ?? body
    static let highlight = UIColor(named: "HighlightFill") ?? .systemYellow
    static let collected = UIColor(named: "CollectedFill") ?? .secondarySystemBackground
    static let marked = UIColor(named: "DangerText") ?? .systemRed
    static let frame = UIColor(named: "Bronze") ?? .separator
    static let hiddenBar = body.withAlphaComponent(HiddenAyahStyle.barOpacity)
    /// Ayahs outside the piece being memorized fade to this.
    static let dimmedAlpha: CGFloat = 0.3
}
