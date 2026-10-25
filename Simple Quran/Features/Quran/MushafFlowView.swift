import OSLog
import SwiftUI
import UIKit

struct MushafPageBlock: Identifiable, Equatable {
    var verses: [QuranVerse]
    var id: Int { verses[0].globalAyah }

    func contains(_ globalAyah: Int) -> Bool {
        verses.contains { $0.globalAyah == globalAyah }
    }
}

enum MushafPageBlocks {
    /// Groups a passage into consecutive runs of the same Madani page.
    /// Input order is preserved, so a later return to an earlier page stays its own block.
    static func make(from verses: [QuranVerse]) -> [MushafPageBlock] {
        var blocks: [MushafPageBlock] = []
        var current: [QuranVerse] = []

        for verse in verses {
            if let last = current.last, last.page != verse.page {
                blocks.append(MushafPageBlock(verses: current))
                current = [verse]
            } else {
                current.append(verse)
            }
        }

        if !current.isEmpty {
            blocks.append(MushafPageBlock(verses: current))
        }
        return blocks
    }
    /// Which block each ayah sits in, keyed by global ayah.
    static func blockIDs(for blocks: [MushafPageBlock]) -> [Int: Int] {
        var ids: [Int: Int] = [:]
        for block in blocks {
            for verse in block.verses { ids[verse.globalAyah] = block.id }
        }
        return ids
    }
}

struct MushafHighlightState: Equatable {
    var highlightedAyah: Int?
    var collectedAyahs: Set<Int> = []
    /// Ayahs faded back while the user memorizes a piece around them.
    var dimmedAyahs: Set<Int> = []
    /// Ayahs the user marked as slipped while testing themselves, underlined in the danger color.
    var markedAyahs: Set<Int> = []
    /// Ayahs hidden for recall. Their words stay laid out but undrawn, so hiding never moves a line.
    var hiddenAyahs: Set<Int> = []

    static let empty = MushafHighlightState()
}

struct MushafAttributedPage {
    var text: NSAttributedString
    var ayahRanges: [Int: NSRange]
    /// Each ayah's words without its number, so dimming can restore both colors.
    var bodyRanges: [Int: NSRange] = [:]
}

enum MushafTextBuilder {
    static let highlightColor = UIColor(named: "HighlightFill") ?? .systemYellow
    static let collectedColor = UIColor(named: "CollectedFill") ?? .secondarySystemBackground
    private static let bodyColor = UIColor(named: "BrownText") ?? .label
    private static let numberColor = UIColor(named: "Bronze") ?? bodyColor
    static let dimmedAlpha: CGFloat = 0.3
    static let hiddenBarColor = bodyColor.withAlphaComponent(HiddenAyahStyle.barOpacity)
    private static let markedColor = UIColor(named: "DangerText") ?? .systemRed

    private static let bodyParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .justified
        style.baseWritingDirection = .rightToLeft
        style.lineSpacing = 12
        style.paragraphSpacing = 14
        return style
    }()

    private static let basmalaParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.baseWritingDirection = .rightToLeft
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 12
        return style
    }()

    static func make(
        verses: [QuranVerse],
        basmala: String,
        contentSizeCategory: UIContentSizeCategory
    ) -> MushafAttributedPage {
        let result = NSMutableAttributedString()
        var ayahRanges: [Int: NSRange] = [:]
        var bodyRanges: [Int: NSRange] = [:]
        let bodyFont = QuranScript.uiFont(.body, category: contentSizeCategory)
        let basmalaFont = QuranScript.uiFont(.basmala, category: contentSizeCategory)
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: numberColor,
            .paragraphStyle: bodyParagraph
        ]

        for (index, verse) in verses.enumerated() {
            let previous = index > 0 ? verses[index - 1] : nil
            let startsNewPassage = previous.map {
                $0.globalAyah + 1 != verse.globalAyah || $0.surahNumber != verse.surahNumber
            } ?? false

            if startsNewPassage, !verse.showsBasmalaBefore {
                result.append(NSAttributedString(string: "\n\n", attributes: [.paragraphStyle: bodyParagraph]))
            }
            if verse.showsBasmalaBefore {
                if result.length > 0 {
                    result.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: bodyParagraph]))
                }
                result.append(NSAttributedString(
                    string: basmala + "\n",
                    attributes: [
                        .font: basmalaFont,
                        .foregroundColor: bodyColor,
                        .paragraphStyle: basmalaParagraph
                    ]
                ))
            }

            // The text already carries the sajdah sign where one belongs.
            let bodyText = verse.text
            let numberText = QuranScript.ayahNumber(verse.ayahInSurah) + " "
            let location = result.length
            var bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: bodyParagraph
            ]
            if let link = URL(string: "simplequran://ayah/\(verse.globalAyah)") {
                bodyAttributes[.link] = link
            }
            result.append(NSAttributedString(string: bodyText, attributes: bodyAttributes))
            result.append(NSAttributedString(string: numberText, attributes: numberAttributes))
            let segmentLength = (bodyText as NSString).length + (numberText as NSString).length
            ayahRanges[verse.globalAyah] = NSRange(location: location, length: segmentLength)
            bodyRanges[verse.globalAyah] = NSRange(location: location, length: (bodyText as NSString).length)
        }

        return MushafAttributedPage(text: result, ayahRanges: ayahRanges, bodyRanges: bodyRanges)
    }

    /// Updates only colors and underlines. Character data, and therefore line breaks, stay put.
    static func applyHighlightChange(
        to text: NSMutableAttributedString,
        ayahRanges: [Int: NSRange],
        bodyRanges: [Int: NSRange] = [:],
        from previous: MushafHighlightState,
        to next: MushafHighlightState
    ) {
        guard previous != next else { return }

        var affected: Set<Int> = []
        if previous.highlightedAyah != next.highlightedAyah {
            if let ayah = previous.highlightedAyah { affected.insert(ayah) }
            if let ayah = next.highlightedAyah { affected.insert(ayah) }
        }
        affected.formUnion(previous.collectedAyahs.symmetricDifference(next.collectedAyahs))

        let recolored = previous.dimmedAyahs.symmetricDifference(next.dimmedAyahs)
            .union(previous.hiddenAyahs.symmetricDifference(next.hiddenAyahs))

        let storage = text as? NSTextStorage
        storage?.beginEditing()
        for ayah in recolored {
            guard let range = ayahRanges[ayah], range.location + range.length <= text.length else { continue }
            let dimmed = next.dimmedAyahs.contains(ayah)
            let body = bodyRanges[ayah] ?? range
            let words: UIColor = next.hiddenAyahs.contains(ayah) ? .clear
                : dimmed ? bodyColor.withAlphaComponent(dimmedAlpha) : bodyColor
            text.addAttribute(.foregroundColor, value: words, range: body)
            // The number stays in view while the words are hidden, so the user knows which ayah to recite.
            let number = NSRange(location: NSMaxRange(body), length: NSMaxRange(range) - NSMaxRange(body))
            if number.length > 0 {
                text.addAttribute(.foregroundColor, value: dimmed ? numberColor.withAlphaComponent(dimmedAlpha) : numberColor, range: number)
            }
        }
        for ayah in previous.markedAyahs.symmetricDifference(next.markedAyahs) {
            guard let range = ayahRanges[ayah], range.location + range.length <= text.length else { continue }
            let body = bodyRanges[ayah] ?? range
            if next.markedAyahs.contains(ayah) {
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: body)
                text.addAttribute(.underlineColor, value: markedColor, range: body)
            } else {
                text.removeAttribute(.underlineStyle, range: body)
                text.removeAttribute(.underlineColor, range: body)
            }
        }
        for ayah in affected {
            guard let range = ayahRanges[ayah], range.location + range.length <= text.length else { continue }
            if ayah == next.highlightedAyah {
                text.addAttribute(.backgroundColor, value: highlightColor, range: range)
            } else if next.collectedAyahs.contains(ayah) {
                text.addAttribute(.backgroundColor, value: collectedColor, range: range)
            } else {
                text.removeAttribute(.backgroundColor, range: range)
            }
        }
        storage?.endEditing()
    }
}

private enum MushafScrollTarget: Hashable {
    case page(Int)
    case ayah(Int)
}

private struct MushafAnchorPlacement: Equatable {
    var passageID: String
    var ayah: Int
    /// Glyph position in 4-point steps, so a corrected layout can scroll again
    /// without chasing sub-point noise.
    var midY: Int
}

private struct MushafPlacedAnchorKey: PreferenceKey {
    static var defaultValue: MushafAnchorPlacement?
    static func reduce(value: inout MushafAnchorPlacement?, nextValue: () -> MushafAnchorPlacement?) {
        value = nextValue() ?? value
    }
}

struct MushafFlowView: View {
    var verses: [QuranVerse]
    var currentGlobalAyah: Int?
    var hiddenAyahs: Set<Int> = []
    var basmala: String
    var selectionEnabled: Bool
    var collectedAyahs: Set<Int> = []
    var focusedAyah: Int? = nil
    /// The piece being memorized; everything else fades back.
    var focusRange: VerseRange? = nil
    var markedAyahs: Set<Int> = []
    /// False while the user has scrolled away during playback; the text then stays where they put it.
    var isFollowing = true
    var onSelect: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glyphScrolledAyah: Int?
    /// Whether the scroll under way glides: a move to the same or the next page does, a longer jump doesn't.
    @State private var animatesFollow = false
    @State private var followedPlacement: MushafAnchorPlacement?
    @State private var placedAnchor: MushafAnchorPlacement?

    /// Built once per value so the per-block helpers below are dictionary lookups,
    /// not a regrouping of the whole passage for every page on every render.
    private let blocks: [MushafPageBlock]
    private let blockIDByAyah: [Int: Int]
    private let blockOrder: [Int: Int]

    init(
        verses: [QuranVerse],
        currentGlobalAyah: Int?,
        hiddenAyahs: Set<Int> = [],
        basmala: String,
        selectionEnabled: Bool,
        collectedAyahs: Set<Int> = [],
        focusedAyah: Int? = nil,
        focusRange: VerseRange? = nil,
        markedAyahs: Set<Int> = [],
        isFollowing: Bool = true,
        onSelect: @escaping (Int) -> Void
    ) {
        self.verses = verses
        self.currentGlobalAyah = currentGlobalAyah
        self.hiddenAyahs = hiddenAyahs
        self.basmala = basmala
        self.selectionEnabled = selectionEnabled
        self.collectedAyahs = collectedAyahs
        self.focusedAyah = focusedAyah
        self.focusRange = focusRange
        self.markedAyahs = markedAyahs
        self.isFollowing = isFollowing
        self.onSelect = onSelect
        let blocks = MushafPageBlocks.make(from: verses)
        self.blocks = blocks
        self.blockIDByAyah = MushafPageBlocks.blockIDs(for: blocks)
        self.blockOrder = Dictionary(uniqueKeysWithValues: blocks.enumerated().map { ($1.id, $0) })
    }

    private var passageID: String {
        guard let first = verses.first?.globalAyah, let last = verses.last?.globalAyah else { return "empty" }
        return "\(first)-\(last)-\(verses.count)"
    }

    /// Playback wins over the ayah that opened the page, matching the previous text view.
    private var scrollTarget: Int? {
        if let currentGlobalAyah, blockIDByAyah[currentGlobalAyah] != nil {
            return currentGlobalAyah
        }
        if let focusedAyah, blockIDByAyah[focusedAyah] != nil {
            return focusedAyah
        }
        return nil
    }

    var body: some View {
        let target = scrollTarget
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(blocks) { block in
                        MushafPageContainer(
                            verses: block.verses,
                            highlightedAyah: ayah(currentGlobalAyah, in: block),
                            hiddenAyahs: ayahs(hiddenAyahs, in: block),
                            collectedAyahs: ayahs(collectedAyahs, in: block),
                            dimmedAyahs: dimmedAyahs(in: block),
                            markedAyahs: ayahs(markedAyahs, in: block),
                            anchorAyah: ayah(target, in: block),
                            basmala: basmala,
                            passageID: passageID,
                            selectionEnabled: selectionEnabled,
                            onSelect: onSelect
                        )
                        .id(MushafScrollTarget.page(block.id))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .id(passageID)
            .onPreferenceChange(MushafPlacedAnchorKey.self) { placedAnchor = $0 }
            .onChange(of: passageID) { _, _ in
                glyphScrolledAyah = nil
                followedPlacement = nil
            }
            .onChange(of: target, initial: true) { _, target in
                guard isFollowing else { return }
                animatesFollow = !reduceMotion && isNearby(target, from: glyphScrolledAyah)
                scrollToPageIfNeeded(target, proxy: proxy)
            }
            .onChange(of: placedAnchor) { _, placement in
                guard isFollowing else { return }
                scrollToAyahIfNeeded(placement, proxy: proxy)
            }
            .onChange(of: isFollowing) { _, following in
                guard following else { return }
                resumeFollowing(proxy: proxy)
            }
        }
    }

    private func ayah(_ ayah: Int?, in block: MushafPageBlock) -> Int? {
        guard let ayah, blockIDByAyah[ayah] == block.id else { return nil }
        return ayah
    }

    /// This page's ayahs outside the piece being memorized.
    private func dimmedAyahs(in block: MushafPageBlock) -> Set<Int> {
        guard let focusRange else { return [] }
        return Set(block.verses.lazy.map(\.globalAyah).filter { !focusRange.contains($0) })
    }

    /// Only the members on this page, so a change elsewhere leaves this page's inputs equal.
    private func ayahs(_ ayahs: Set<Int>, in block: MushafPageBlock) -> Set<Int> {
        guard !ayahs.isEmpty else { return [] }
        return ayahs.filter { blockIDByAyah[$0] == block.id }
    }

    /// Same page or the next one over, so the scroll can glide instead of jump.
    private func isNearby(_ target: Int?, from followed: Int?) -> Bool {
        guard let target, let followed,
              let to = blockIDByAyah[target].flatMap({ blockOrder[$0] }),
              let from = blockIDByAyah[followed].flatMap({ blockOrder[$0] }) else { return false }
        return abs(to - from) <= 1
    }

    private func scroll(to target: MushafScrollTarget, proxy: ScrollViewProxy) {
        if animatesFollow {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func scrollToPageIfNeeded(_ target: Int?, proxy: ScrollViewProxy) {
        guard let target, glyphScrolledAyah != target else { return }
        let targetBlock = blockIDByAyah[target]
        let followedBlock = glyphScrolledAyah.flatMap { blockIDByAyah[$0] }
        guard targetBlock != followedBlock, let targetBlock else { return }
        scroll(to: .page(targetBlock), proxy: proxy)
    }

    /// Back from the user's own scrolling: straight to the ayah when its page has placed it,
    /// otherwise to its page first, which then places it.
    private func resumeFollowing(proxy: ScrollViewProxy) {
        let target = scrollTarget
        animatesFollow = !reduceMotion
        followedPlacement = nil
        if let placedAnchor, placedAnchor.ayah == target {
            scrollToAyahIfNeeded(placedAnchor, proxy: proxy)
        } else if let target, let block = blockIDByAyah[target] {
            glyphScrolledAyah = nil
            scroll(to: .page(block), proxy: proxy)
        }
    }

    private func scrollToAyahIfNeeded(_ placement: MushafAnchorPlacement?, proxy: ScrollViewProxy) {
        guard let placement,
              placement.passageID == passageID,
              placement.ayah == scrollTarget,
              followedPlacement != placement
        else { return }
        scroll(to: .ayah(placement.ayah), proxy: proxy)
        followedPlacement = placement
        glyphScrolledAyah = placement.ayah
    }
}

private struct MushafPageContainer: View {
    var verses: [QuranVerse]
    var highlightedAyah: Int?
    var hiddenAyahs: Set<Int>
    var collectedAyahs: Set<Int>
    var dimmedAyahs: Set<Int>
    var markedAyahs: Set<Int>
    var anchorAyah: Int?
    var basmala: String
    var passageID: String
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void

    @State private var anchorRect: CGRect?
    @State private var measuredAyah: Int?

    var body: some View {
        MushafPageView(
            verses: verses,
            highlightedAyah: highlightedAyah,
            hiddenAyahs: hiddenAyahs,
            collectedAyahs: collectedAyahs,
            dimmedAyahs: dimmedAyahs,
            markedAyahs: markedAyahs,
            anchorAyah: anchorAyah,
            basmala: basmala,
            selectionEnabled: selectionEnabled,
            onSelect: onSelect,
            onAnchorRect: { rect in
                guard measuredAyah != anchorAyah || anchorRect != rect else { return }
                measuredAyah = anchorAyah
                anchorRect = rect
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: anchorAyah) { _, _ in
            measuredAyah = nil
            anchorRect = nil
        }
        .overlay(alignment: .topLeading) {
            if let anchorAyah, measuredAyah == anchorAyah, let anchorRect {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(anchorRect.midY - 0.5, 0))
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id(MushafScrollTarget.ayah(anchorAyah))
                        .preference(
                            key: MushafPlacedAnchorKey.self,
                            value: MushafAnchorPlacement(
                                passageID: passageID,
                                ayah: anchorAyah,
                                midY: Int((anchorRect.midY / 4).rounded())
                            )
                        )
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct MushafPageView: UIViewRepresentable {
    var verses: [QuranVerse]
    var highlightedAyah: Int?
    var hiddenAyahs: Set<Int>
    var collectedAyahs: Set<Int>
    var dimmedAyahs: Set<Int>
    var markedAyahs: Set<Int>
    var anchorAyah: Int?
    var basmala: String
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void
    var onAnchorRect: @MainActor (CGRect) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onAnchorRect: onAnchorRect)
    }

    func makeUIView(context: Context) -> MushafPageHostView {
        let host = MushafPageHostView()
        let textView = host.textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = selectionEnabled
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // Ayahs are links for tapping, but their color comes from the text so a piece can dim its surroundings.
        textView.linkTextAttributes = [:]
        textView.onAnchorRect = { [weak coordinator = context.coordinator] rect in
            coordinator?.onAnchorRect(rect)
        }
        return host
    }

    func updateUIView(_ host: MushafPageHostView, context: Context) {
        context.coordinator.selectionEnabled = selectionEnabled
        context.coordinator.onSelect = onSelect
        context.coordinator.onAnchorRect = onAnchorRect
        let textView = host.textView
        textView.isSelectable = selectionEnabled
        textView.anchorAyah = anchorAyah
        textView.configure(
            verses: verses,
            basmala: basmala,
            highlight: MushafHighlightState(
                highlightedAyah: highlightedAyah,
                collectedAyahs: collectedAyahs,
                dimmedAyahs: dimmedAyahs,
                markedAyahs: markedAyahs,
                hiddenAyahs: hiddenAyahs
            ),
            contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MushafPageHostView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else {
            return CGSize(width: 0, height: 1)
        }
        updateUIView(uiView, context: context)
        return CGSize(width: width, height: uiView.textView.measuredHeight(for: width))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var selectionEnabled: Bool
        var onSelect: (Int) -> Void
        var onAnchorRect: @MainActor (CGRect) -> Void

        init(onSelect: @escaping (Int) -> Void, onAnchorRect: @escaping @MainActor (CGRect) -> Void) {
            self.selectionEnabled = true
            self.onSelect = onSelect
            self.onAnchorRect = onAnchorRect
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            let range = textItem.range
            guard selectionEnabled,
                  let attributedText = textView.attributedText,
                  range.location < attributedText.length,
                  let url = attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                  url.scheme == "simplequran",
                  url.host == "ayah",
                  let globalAyah = Int(url.lastPathComponent)
            else { return nil }
            return UIAction { [weak self] _ in
                self?.onSelect(globalAyah)
            }
        }

        /// Hidden words stay in the text for layout, so the menu mustn't offer to copy or look them up.
        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let page = textView as? MushafPageTextView, page.hidesWords(in: range) else { return nil }
            return UIMenu(children: [])
        }
    }
}

private extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

private final class MushafPageTextView: UITextView {
    var onAnchorRect: (@MainActor (CGRect) -> Void)?
    var anchorAyah: Int? {
        didSet {
            guard anchorAyah != oldValue else { return }
            lastReportedAnchor = nil
        }
    }

    /// The text was built anew, so anything drawn over it must be placed again.
    var onRebuild: (() -> Void)?
    /// Ayahs opened or hidden on text that kept its layout, so the change can animate in place.
    var onHidingChange: ((_ revealed: Set<Int>, _ covered: Set<Int>) -> Void)?

    private var pendingVerses: [QuranVerse] = []
    private var pendingBasmala = ""
    private var pendingHighlight = MushafHighlightState.empty
    private var pendingCategory: UIContentSizeCategory = .large
    private var renderKey: RenderKey?
    private var appliedHighlight = MushafHighlightState.empty
    private var ayahRanges: [Int: NSRange] = [:]
    private var bodyRanges: [Int: NSRange] = [:]
    private var lastReportedAnchor: CGRect?
    private var isApplying = false

    var hiddenAyahs: Set<Int> { appliedHighlight.hiddenAyahs }

    func configure(
        verses: [QuranVerse],
        basmala: String,
        highlight: MushafHighlightState,
        contentSizeCategory: UIContentSizeCategory
    ) {
        pendingVerses = verses
        pendingBasmala = basmala
        pendingHighlight = highlight
        pendingCategory = contentSizeCategory
        if bounds.width > 0 {
            apply(width: bounds.width)
        }
        reportAnchor()
    }

    func measuredHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        if abs(bounds.width - width) > 0.5 {
            bounds.size.width = width
        }
        apply(width: width)
        let height = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return max(ceil(height), 1)
    }

    override func layoutSubviews() {
        guard !isApplying else {
            super.layoutSubviews()
            return
        }
        super.layoutSubviews()
        if bounds.width > 0 {
            apply(width: bounds.width)
        }
        reportAnchor()
    }

    private func apply(width: CGFloat) {
        guard width > 0, !pendingVerses.isEmpty else { return }
        let key = RenderKey(verseIDs: pendingVerses.map(\.globalAyah), category: pendingCategory)
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        if renderKey != key {
            let ayahCount = pendingVerses.count
            let signpost = QuranLog.rendering.beginInterval("Page build", "\(ayahCount) ayahs")
            defer { QuranLog.rendering.endInterval("Page build", signpost) }
            let document = MushafTextBuilder.make(
                verses: pendingVerses,
                basmala: pendingBasmala,
                contentSizeCategory: pendingCategory
            )
            let mutable = NSMutableAttributedString(attributedString: document.text)
            MushafTextBuilder.applyHighlightChange(
                to: mutable,
                ayahRanges: document.ayahRanges,
                bodyRanges: document.bodyRanges,
                from: .empty,
                to: pendingHighlight
            )
            ayahRanges = document.ayahRanges
            bodyRanges = document.bodyRanges
            appliedHighlight = pendingHighlight
            renderKey = key
            attributedText = mutable
            lastReportedAnchor = nil
            onRebuild?()
            return
        }

        guard appliedHighlight != pendingHighlight else { return }
        let previous = appliedHighlight
        MushafTextBuilder.applyHighlightChange(
            to: textStorage,
            ayahRanges: ayahRanges,
            bodyRanges: bodyRanges,
            from: previous,
            to: pendingHighlight
        )
        appliedHighlight = pendingHighlight
        let revealed = previous.hiddenAyahs.subtracting(pendingHighlight.hiddenAyahs)
        let covered = pendingHighlight.hiddenAyahs.subtracting(previous.hiddenAyahs)
        if !revealed.isEmpty || !covered.isEmpty {
            onHidingChange?(revealed, covered)
        }
    }

    /// Where an ayah's words sit, one rect per line, in this view's coordinates. Standard segments
    /// measure every line alike; selection rects stretch a line that continues an ayah up into the
    /// line spacing above it.
    func bodyRects(for globalAyah: Int) -> [CGRect] {
        guard let range = bodyRanges[globalAyah],
              let manager = textLayoutManager,
              let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return [] }
        manager.ensureLayout(for: textRange)
        var lines: [CGRect] = []
        manager.enumerateTextSegments(in: textRange, type: .standard, options: .rangeNotRequired) { _, frame, _, _ in
            guard let segment = usableRect(frame.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)) else { return true }
            // Runs of one line can come back as separate segments; a line gets one bar.
            if let index = lines.firstIndex(where: { abs($0.midY - segment.midY) < 1 }) {
                lines[index] = lines[index].union(segment)
            } else {
                lines.append(segment)
            }
            return true
        }
        return lines
    }

    func hidesWords(in range: NSRange) -> Bool {
        hiddenAyahs.contains { ayah in
            bodyRanges[ayah].map { NSIntersectionRange($0, range).length > 0 } ?? false
        }
    }

    /// VoiceOver says a hidden ayah is hidden instead of reading out the words being recited.
    override var accessibilityValue: String? {
        get {
            guard !hiddenAyahs.isEmpty, let text = attributedText?.string else { return super.accessibilityValue }
            let spoken = NSMutableString(string: text)
            let ranges = hiddenAyahs.compactMap { bodyRanges[$0] }.sorted { $0.location > $1.location }
            for range in ranges where NSMaxRange(range) <= spoken.length {
                spoken.replaceCharacters(in: range, with: String(localized: "Arabic hidden for recall"))
            }
            return spoken as String
        }
        set { super.accessibilityValue = newValue }
    }

    private func reportAnchor() {
        guard let ayah = anchorAyah,
              let rect = rectForAyah(ayah).flatMap(usableRect(_:)),
              !rectsMatch(rect, lastReportedAnchor)
        else { return }
        lastReportedAnchor = rect
        Task { @MainActor [weak self] in
            guard let self, self.anchorAyah == ayah else { return }
            self.onAnchorRect?(rect)
        }
    }

    private func rectForAyah(_ globalAyah: Int) -> CGRect? {
        guard let range = ayahRanges[globalAyah],
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end)
        else { return nil }
        return firstRect(for: textRange)
    }

    private func usableRect(_ rect: CGRect) -> CGRect? {
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private func rectsMatch(_ lhs: CGRect, _ rhs: CGRect?) -> Bool {
        guard let rhs else { return false }
        return abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private struct RenderKey: Equatable {
        var verseIDs: [Int]
        var category: UIContentSizeCategory
    }
}

/// A page's text with the bars that stand in for its hidden ayahs laid over it, above any highlight
/// behind the words. The bars sit beside the text, not inside it, so the mask that sweeps an opening
/// ayah's ink in never cuts them, and they let touches through to the ayah underneath.
private final class MushafPageHostView: UIView {
    let textView = MushafPageTextView()
    private let barsView = UIView()
    /// Bars over the ayahs hidden now. A bar fading out has already left.
    private var bars: [Int: CAShapeLayer] = [:]
    private var fadingBars: [CALayer] = []
    private var barsSize: CGSize?
    private var sweepMask: CALayer?

    private static let textFadeKey = "hiding"
    private static let sweepKey = "sweep"

    override init(frame: CGRect) {
        super.init(frame: frame)
        barsView.isUserInteractionEnabled = false
        addSubview(textView)
        addSubview(barsView)
        textView.onRebuild = { [weak self] in
            self?.finishAnimations()
            self?.barsSize = nil
            self?.setNeedsLayout()
        }
        textView.onHidingChange = { [weak self] revealed, covered in
            self?.animateHiding(revealed: revealed, covered: covered)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
            let color = self.barColor
            for bar in self.bars.values { bar.fillColor = color }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        barsView.frame = bounds
        guard bounds.width > 0, barsSize != bounds.size else { return }
        // A new width moves the lines, so anything mid-flight finishes where it was headed.
        finishAnimations()
        textView.layoutIfNeeded()
        placeBars()
        barsSize = bounds.size
    }

    // MARK: Bars

    private var barColor: CGColor {
        MushafTextBuilder.hiddenBarColor.resolvedColor(with: traitCollection).cgColor
    }

    /// One bar per line the ayah's words take, so the page keeps its shape while they're hidden.
    private func barPath(for ayah: Int) -> CGPath {
        let path = CGMutablePath()
        for line in textView.bodyRects(for: ayah) {
            let height = line.height * HiddenAyahStyle.barHeight
            let bar = CGRect(x: line.minX, y: line.midY - height / 2, width: line.width, height: height)
            let radius = min(height, line.width) / 2
            path.addRoundedRect(in: bar, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    private func makeBar(for ayah: Int) -> CAShapeLayer {
        let bar = CAShapeLayer()
        bar.fillColor = barColor
        bar.path = barPath(for: ayah)
        barsView.layer.addSublayer(bar)
        bars[ayah] = bar
        return bar
    }

    /// Bars for exactly the ayahs hidden now, placed on the current lines.
    private func placeBars() {
        let hidden = textView.hiddenAyahs
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (ayah, bar) in bars where !hidden.contains(ayah) {
            bar.removeFromSuperlayer()
            bars[ayah] = nil
        }
        for ayah in hidden {
            if let bar = bars[ayah] { bar.path = barPath(for: ayah) } else { _ = makeBar(for: ayah) }
        }
        CATransaction.commit()
    }

    // MARK: Animation

    /// Hiding fades the words out as their bars fade in. Opening sweeps each ayah's ink in from the
    /// right as its bar fades, one ayah after another; with Reduce Motion it fades instead.
    private func animateHiding(revealed: Set<Int>, covered: Set<Int>) {
        finishAnimations()
        let sweeps = !revealed.isEmpty && !UIAccessibility.isReduceMotionEnabled
        let delays = sweeps ? HiddenAyahStyle.revealDelays(for: revealed) : [:]
        let now = CACurrentMediaTime()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !covered.isEmpty || (!revealed.isEmpty && !sweeps) {
            fadeText(duration: covered.isEmpty ? HiddenAyahStyle.revealDuration : HiddenAyahStyle.hideDuration)
        }
        for ayah in covered {
            fade(makeBar(for: ayah), from: 0, to: 1, duration: HiddenAyahStyle.hideDuration, beginTime: now)
        }
        for ayah in revealed {
            guard let bar = bars.removeValue(forKey: ayah) else { continue }
            fadingBars.append(bar)
            fade(bar, from: 1, to: 0, duration: HiddenAyahStyle.revealDuration, beginTime: now + (delays[ayah] ?? 0))
        }
        if sweeps { sweepIn(delays, at: now) }

        let mask = sweepMask
        let fading = fadingBars
        CATransaction.setCompletionBlock { [weak self] in
            fading.forEach { $0.removeFromSuperlayer() }
            guard let self else { return }
            self.fadingBars.removeAll { layer in fading.contains { $0 === layer } }
            if let mask, self.sweepMask === mask { self.clearSweep() }
        }
        CATransaction.commit()
    }

    private func fadeText(duration: TimeInterval) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        textView.layer.add(fade, forKey: Self.textFadeKey)
    }

    private func fade(_ layer: CALayer, from: Float, to: Float, duration: TimeInterval, beginTime: CFTimeInterval) {
        layer.opacity = to
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = duration
        fade.beginTime = beginTime
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: nil)
    }

    /// Masks the text so the opening ayahs' words start undrawn, then sweeps each one's ink in
    /// right to left behind a soft edge. Everything else on the page shows as usual throughout.
    private func sweepIn(_ delays: [Int: TimeInterval], at now: CFTimeInterval) {
        let mask = CALayer()
        mask.frame = textView.bounds
        let rest = CAShapeLayer()
        rest.frame = mask.bounds
        rest.fillRule = .evenOdd
        let restPath = CGMutablePath()
        restPath.addRect(mask.bounds)
        mask.addSublayer(rest)

        for (ayah, delay) in delays {
            let lines = textView.bodyRects(for: ayah)
            guard !lines.isEmpty else { continue }
            restPath.addRects(lines)
            mask.addSublayer(sweep(over: lines, beginTime: now + delay))
        }
        rest.path = restPath
        textView.layer.mask = mask
        sweepMask = mask
    }

    private func sweep(over lines: [CGRect], beginTime: CFTimeInterval) -> CALayer {
        let box = lines.reduce(CGRect.null) { $0.union($1) }
        let area = CALayer()
        area.frame = box
        let shape = CAShapeLayer()
        shape.frame = area.bounds
        let linesPath = CGMutablePath()
        linesPath.addRects(lines, transform: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        shape.path = linesPath
        area.mask = shape

        // Clear on the left, opaque from the soft edge on. It starts just past the ayah's right
        // side and ends with the opaque part covering it.
        let edge = box.width * HiddenAyahStyle.sweepSoftness
        let ink = CAGradientLayer()
        ink.colors = [UIColor.clear.cgColor, UIColor.black.cgColor]
        ink.locations = [0, NSNumber(value: Double(edge / (box.width + edge)))]
        ink.startPoint = CGPoint(x: 0, y: 0.5)
        ink.endPoint = CGPoint(x: 1, y: 0.5)
        ink.frame = CGRect(x: -edge, y: 0, width: box.width + edge, height: box.height)
        area.addSublayer(ink)

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = ink.position.x + box.width + edge
        move.toValue = ink.position.x
        move.duration = HiddenAyahStyle.revealDuration
        move.beginTime = beginTime
        move.fillMode = .backwards
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ink.add(move, forKey: Self.sweepKey)
        return area
    }

    private func clearSweep() {
        textView.layer.mask = nil
        sweepMask = nil
    }

    /// Jumps whatever is animating to where it was headed.
    private func finishAnimations() {
        clearSweep()
        textView.layer.removeAnimation(forKey: Self.textFadeKey)
        fadingBars.forEach { $0.removeFromSuperlayer() }
        fadingBars.removeAll()
        bars.values.forEach { $0.removeAllAnimations() }
    }
}
