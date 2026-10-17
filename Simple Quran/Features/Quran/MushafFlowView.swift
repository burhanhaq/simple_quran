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

    static let empty = MushafHighlightState()
}

struct MushafAttributedPage {
    var text: NSAttributedString
    var ayahRanges: [Int: NSRange]
}

enum MushafTextBuilder {
    static let highlightColor = UIColor(named: "HighlightFill") ?? .systemYellow
    static let collectedColor = UIColor(named: "CollectedFill") ?? .secondarySystemBackground
    private static let bodyColor = UIColor(named: "BrownText") ?? .label
    private static let numberColor = UIColor(named: "Bronze") ?? bodyColor

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
        hiddenAyahs: Set<Int>,
        basmala: String,
        contentSizeCategory: UIContentSizeCategory
    ) -> MushafAttributedPage {
        let result = NSMutableAttributedString()
        var ayahRanges: [Int: NSRange] = [:]
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
            let bodyText = hiddenAyahs.contains(verse.globalAyah) ? QuranScript.hiddenPlaceholder : verse.text
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
    var onSelect: (Int) -> Void

    @State private var glyphScrolledAyah: Int?
    @State private var followedPlacement: MushafAnchorPlacement?
    @State private var placedAnchor: MushafAnchorPlacement?

    /// Built once per value so the per-block helpers below are dictionary lookups,
    /// not a regrouping of the whole passage for every page on every render.
    private let blocks: [MushafPageBlock]
    private let blockIDByAyah: [Int: Int]

    init(
        verses: [QuranVerse],
        currentGlobalAyah: Int?,
        hiddenAyahs: Set<Int> = [],
        basmala: String,
        selectionEnabled: Bool,
        collectedAyahs: Set<Int> = [],
        focusedAyah: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.verses = verses
        self.currentGlobalAyah = currentGlobalAyah
        self.hiddenAyahs = hiddenAyahs
        self.basmala = basmala
        self.selectionEnabled = selectionEnabled
        self.collectedAyahs = collectedAyahs
        self.focusedAyah = focusedAyah
        self.onSelect = onSelect
        let blocks = MushafPageBlocks.make(from: verses)
        self.blocks = blocks
        self.blockIDByAyah = MushafPageBlocks.blockIDs(for: blocks)
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
                scrollToPageIfNeeded(target, proxy: proxy)
            }
            .onChange(of: placedAnchor) { _, placement in
                scrollToAyahIfNeeded(placement, proxy: proxy)
            }
        }
    }

    private func ayah(_ ayah: Int?, in block: MushafPageBlock) -> Int? {
        guard let ayah, blockIDByAyah[ayah] == block.id else { return nil }
        return ayah
    }

    /// Only the members on this page, so a change elsewhere leaves this page's inputs equal.
    private func ayahs(_ ayahs: Set<Int>, in block: MushafPageBlock) -> Set<Int> {
        guard !ayahs.isEmpty else { return [] }
        return ayahs.filter { blockIDByAyah[$0] == block.id }
    }

    private func scrollToPageIfNeeded(_ target: Int?, proxy: ScrollViewProxy) {
        guard let target, glyphScrolledAyah != target else { return }
        let targetBlock = blockIDByAyah[target]
        let followedBlock = glyphScrolledAyah.flatMap { blockIDByAyah[$0] }
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
    var hiddenAyahs: Set<Int>
    var collectedAyahs: Set<Int>
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
    var anchorAyah: Int?
    var basmala: String
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
            hiddenAyahs: hiddenAyahs,
            basmala: basmala,
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
    private var pendingHiddenAyahs: Set<Int> = []
    private var pendingBasmala = ""
    private var pendingHighlight = MushafHighlightState.empty
    private var pendingCategory: UIContentSizeCategory = .large
    private var renderKey: RenderKey?
    private var appliedHighlight = MushafHighlightState.empty
    private var ayahRanges: [Int: NSRange] = [:]
    private var lastReportedAnchor: CGRect?
    private var isApplying = false

    func configure(
        verses: [QuranVerse],
        hiddenAyahs: Set<Int>,
        basmala: String,
        highlight: MushafHighlightState,
        contentSizeCategory: UIContentSizeCategory
    ) {
        pendingVerses = verses
        pendingHiddenAyahs = hiddenAyahs
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
        let key = RenderKey(
            verseIDs: pendingVerses.map(\.globalAyah),
            hiddenAyahs: pendingHiddenAyahs,
            category: pendingCategory
        )
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        if renderKey != key {
            let ayahCount = pendingVerses.count
            let signpost = QuranLog.rendering.beginInterval("Page build", "\(ayahCount) ayahs")
            defer { QuranLog.rendering.endInterval("Page build", signpost) }
            let document = MushafTextBuilder.make(
                verses: pendingVerses,
                hiddenAyahs: pendingHiddenAyahs,
                basmala: pendingBasmala,
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
        var hiddenAyahs: Set<Int>
        var category: UIContentSizeCategory
    }
}
