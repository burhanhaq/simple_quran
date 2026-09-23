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
}

struct MushafHighlightState: Equatable {
    var highlightedAyah: Int?
    var collectedAyahs: Set<Int> = []

    static let empty = MushafHighlightState()
}

struct MushafAttributedPage {
    var text: NSAttributedString
    var ayahRanges: [Int: NSRange]
}

enum MushafTextBuilder {
    static let hiddenPlaceholder = "••••••"
    static let highlightColor = (UIColor(named: "HighlightFill") ?? .systemYellow).withAlphaComponent(0.45)
    static let collectedColor = (UIColor(named: "Bronze") ?? .label).withAlphaComponent(0.14)

    static func make(
        verses: [QuranVerse],
        hiddenAyah: Int?,
        contentSizeCategory: UIContentSizeCategory
    ) -> MushafAttributedPage {
        let result = NSMutableAttributedString()
        var ayahRanges: [Int: NSRange] = [:]
        let bodyFont = scaledFont(name: "AmiriQuran", size: 28, textStyle: .title2, category: contentSizeCategory)
        let basmalaFont = scaledFont(name: "AmiriQuran", size: 25, textStyle: .title3, category: contentSizeCategory)
        let bodyColor = UIColor(named: "BrownText") ?? .label
        let bronzeColor = UIColor(named: "Bronze") ?? bodyColor

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .justified
        bodyParagraph.baseWritingDirection = .rightToLeft
        bodyParagraph.lineSpacing = 12
        bodyParagraph.paragraphSpacing = 14

        let basmalaParagraph = NSMutableParagraphStyle()
        basmalaParagraph.alignment = .center
        basmalaParagraph.baseWritingDirection = .rightToLeft
        basmalaParagraph.paragraphSpacingBefore = 8
        basmalaParagraph.paragraphSpacing = 12

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
                    string: "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ\n",
                    attributes: [
                        .font: basmalaFont,
                        .foregroundColor: bodyColor,
                        .paragraphStyle: basmalaParagraph
                    ]
                ))
            }

            let visibleText = verse.globalAyah == hiddenAyah ? hiddenPlaceholder : verse.text
            let sajdahMarker = verse.sajdah == .none ? "" : " ۩"
            let bodyText = "\(visibleText)\(sajdahMarker) "
            let markerText = "﴿\(arabicIndicNumber(verse.ayahInSurah))﴾ "
            let location = result.length
            var bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: bodyParagraph
            ]
            if let link = URL(string: "simplequran://ayah/\(verse.globalAyah)") {
                bodyAttributes[.link] = link
            }
            let markerAttributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: bronzeColor,
                .paragraphStyle: bodyParagraph
            ]
            result.append(NSAttributedString(string: bodyText, attributes: bodyAttributes))
            result.append(NSAttributedString(string: markerText, attributes: markerAttributes))
            let segmentLength = (bodyText as NSString).length + (markerText as NSString).length
            ayahRanges[verse.globalAyah] = NSRange(location: location, length: segmentLength)
        }

        return MushafAttributedPage(text: result, ayahRanges: ayahRanges)
    }

    /// Updates only background colors. Character data, and therefore line breaks, stay put.
    static func applyHighlightChange(
        to text: NSMutableAttributedString,
        ayahRanges: [Int: NSRange],
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

        let storage = text as? NSTextStorage
        storage?.beginEditing()
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

    private static func scaledFont(
        name: String,
        size: CGFloat,
        textStyle: UIFont.TextStyle,
        category: UIContentSizeCategory
    ) -> UIFont {
        let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
    }

    private static func arabicIndicNumber(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { character in
            character.wholeNumberValue.map { digits[$0] }
        })
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
    var hidesCurrentAyah: Bool
    var selectionEnabled: Bool
    var collectedAyahs: Set<Int> = []
    var focusedAyah: Int? = nil
    var onSelect: (Int) -> Void

    @State private var glyphScrolledAyah: Int?
    @State private var followedPlacement: MushafAnchorPlacement?
    @State private var placedAnchor: MushafAnchorPlacement?

    private var blocks: [MushafPageBlock] {
        MushafPageBlocks.make(from: verses)
    }

    private var passageID: String {
        guard let first = verses.first?.globalAyah, let last = verses.last?.globalAyah else { return "empty" }
        return "\(first)-\(last)-\(verses.count)"
    }

    /// Playback wins over the ayah that opened the page, matching the previous text view.
    private var scrollTarget: Int? {
        if let currentGlobalAyah, blocks.contains(where: { $0.contains(currentGlobalAyah) }) {
            return currentGlobalAyah
        }
        if let focusedAyah, blocks.contains(where: { $0.contains(focusedAyah) }) {
            return focusedAyah
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(blocks) { block in
                        MushafPageContainer(
                            verses: block.verses,
                            highlightedAyah: highlightedAyah(in: block),
                            hiddenAyah: hiddenAyah(in: block),
                            collectedAyahs: collectedAyahs(in: block),
                            anchorAyah: anchorAyah(in: block),
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
            .onChange(of: scrollTarget, initial: true) { _, target in
                scrollToPageIfNeeded(target, proxy: proxy)
            }
            .onChange(of: placedAnchor) { _, placement in
                scrollToAyahIfNeeded(placement, proxy: proxy)
            }
        }
    }

    private func highlightedAyah(in block: MushafPageBlock) -> Int? {
        guard let currentGlobalAyah, block.contains(currentGlobalAyah) else { return nil }
        return currentGlobalAyah
    }

    private func hiddenAyah(in block: MushafPageBlock) -> Int? {
        guard hidesCurrentAyah, let currentGlobalAyah, block.contains(currentGlobalAyah) else { return nil }
        return currentGlobalAyah
    }

    private func collectedAyahs(in block: MushafPageBlock) -> Set<Int> {
        Set(block.verses.lazy.map(\.globalAyah).filter { collectedAyahs.contains($0) })
    }

    private func anchorAyah(in block: MushafPageBlock) -> Int? {
        guard let scrollTarget, block.contains(scrollTarget) else { return nil }
        return scrollTarget
    }

    private func scrollToPageIfNeeded(_ target: Int?, proxy: ScrollViewProxy) {
        guard let target, glyphScrolledAyah != target else { return }
        let targetBlock = blocks.first { $0.contains(target) }?.id
        let followedBlock = glyphScrolledAyah.flatMap { ayah in blocks.first { $0.contains(ayah) }?.id }
        guard targetBlock != followedBlock, let targetBlock else { return }
        proxy.scrollTo(MushafScrollTarget.page(targetBlock), anchor: .center)
    }

    private func scrollToAyahIfNeeded(_ placement: MushafAnchorPlacement?, proxy: ScrollViewProxy) {
        guard let placement,
              placement.passageID == passageID,
              placement.ayah == scrollTarget,
              followedPlacement != placement
        else { return }
        proxy.scrollTo(MushafScrollTarget.ayah(placement.ayah), anchor: .center)
        followedPlacement = placement
        glyphScrolledAyah = placement.ayah
    }
}

private struct MushafPageContainer: View {
    var verses: [QuranVerse]
    var highlightedAyah: Int?
    var hiddenAyah: Int?
    var collectedAyahs: Set<Int>
    var anchorAyah: Int?
    var passageID: String
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void

    @State private var anchorRect: CGRect?
    @State private var measuredAyah: Int?

    var body: some View {
        MushafPageView(
            verses: verses,
            highlightedAyah: highlightedAyah,
            hiddenAyah: hiddenAyah,
            collectedAyahs: collectedAyahs,
            anchorAyah: anchorAyah,
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
    var hiddenAyah: Int?
    var collectedAyahs: Set<Int>
    var anchorAyah: Int?
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void
    var onAnchorRect: @MainActor (CGRect) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onAnchorRect: onAnchorRect)
    }

    func makeUIView(context: Context) -> MushafPageTextView {
        let textView = MushafPageTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = selectionEnabled
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(named: "BrownText") ?? UIColor.label,
            .underlineStyle: 0
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.onAnchorRect = { [weak coordinator = context.coordinator] rect in
            coordinator?.onAnchorRect(rect)
        }
        return textView
    }

    func updateUIView(_ textView: MushafPageTextView, context: Context) {
        context.coordinator.selectionEnabled = selectionEnabled
        context.coordinator.onSelect = onSelect
        context.coordinator.onAnchorRect = onAnchorRect
        textView.isSelectable = selectionEnabled
        textView.anchorAyah = anchorAyah
        textView.configure(
            verses: verses,
            hiddenAyah: hiddenAyah,
            highlight: MushafHighlightState(
                highlightedAyah: highlightedAyah,
                collectedAyahs: collectedAyahs
            ),
            contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MushafPageTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else {
            return CGSize(width: 0, height: 1)
        }
        updateUIView(uiView, context: context)
        return CGSize(width: width, height: uiView.measuredHeight(for: width))
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

    private var pendingVerses: [QuranVerse] = []
    private var pendingHiddenAyah: Int?
    private var pendingHighlight = MushafHighlightState.empty
    private var pendingCategory: UIContentSizeCategory = .large
    private var renderKey: RenderKey?
    private var appliedHighlight = MushafHighlightState.empty
    private var ayahRanges: [Int: NSRange] = [:]
    private var lastReportedAnchor: CGRect?
    private var isApplying = false

    func configure(
        verses: [QuranVerse],
        hiddenAyah: Int?,
        highlight: MushafHighlightState,
        contentSizeCategory: UIContentSizeCategory
    ) {
        pendingVerses = verses
        pendingHiddenAyah = hiddenAyah
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
        let key = RenderKey(
            verseIDs: pendingVerses.map(\.globalAyah),
            hiddenAyah: pendingHiddenAyah,
            category: pendingCategory
        )
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        if renderKey != key {
            let document = MushafTextBuilder.make(
                verses: pendingVerses,
                hiddenAyah: pendingHiddenAyah,
                contentSizeCategory: pendingCategory
            )
            let mutable = NSMutableAttributedString(attributedString: document.text)
            MushafTextBuilder.applyHighlightChange(
                to: mutable,
                ayahRanges: document.ayahRanges,
                from: .empty,
                to: pendingHighlight
            )
            ayahRanges = document.ayahRanges
            appliedHighlight = pendingHighlight
            renderKey = key
            attributedText = mutable
            lastReportedAnchor = nil
            return
        }

        guard appliedHighlight != pendingHighlight else { return }
        MushafTextBuilder.applyHighlightChange(
            to: textStorage,
            ayahRanges: ayahRanges,
            from: appliedHighlight,
            to: pendingHighlight
        )
        appliedHighlight = pendingHighlight
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
        var hiddenAyah: Int?
        var category: UIContentSizeCategory
    }
}
