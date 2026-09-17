import CoreText
import SwiftUI
import UIKit

enum AppTheme {
    static let cornerRadius: CGFloat = 18
    static let tightRadius: CGFloat = 12
    static let controlHeight: CGFloat = 48

    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf", subdirectory: "Resources/Fonts")
            ?? Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "AmiriQuran", withExtension: "ttf")
        else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    static let parchment = Color("ParchmentBackground")
    static let appWarmSurface = Color("WarmSurface")
    static let appBrownText = Color("BrownText")
    static let secondaryWarm = Color("SecondaryText")
    static let olive = Color("OliveAccent")
    static let gold = Color("GoldAccent")
    static let appHighlightFill = Color("HighlightFill")
    static let dangerWarm = Color("DangerText")
}

extension Font {
    static func quran(size: CGFloat = 28) -> Font {
        .custom("AmiriQuran", size: size, relativeTo: .title)
    }
}

struct WarmCard<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appWarmSurface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}

struct StatusChip: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct EmptyStateView: View {
    var title: String
    var message: String
    var actionTitle: String
    var action: () -> Void
    var actionIdentifier: String = "empty.createSet"
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var secondaryIdentifier: String = "empty.collect"

    init(
        title: String,
        message: String,
        actionTitle: String,
        actionIdentifier: String = "empty.createSet",
        secondaryTitle: String? = nil,
        secondaryIdentifier: String = "empty.collect",
        secondaryAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.actionIdentifier = actionIdentifier
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.secondaryIdentifier = secondaryIdentifier
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(Color.gold)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.appBrownText)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.secondaryWarm)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .accessibilityIdentifier(actionIdentifier)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .tint(Color.olive)
                    .accessibilityIdentifier(secondaryIdentifier)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct QuranAyahText: View {
    var verse: QuranVerse
    var isCurrent: Bool
    var isInPassage: Bool = false
    var hidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hidden ? "••••••" : verse.text)
                .font(.quran())
                .lineSpacing(8)
                .foregroundStyle(Color.appBrownText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityLabel(hidden ? String(localized: "Arabic hidden for recall") : verse.text)
            HStack {
                if verse.sajdah != .none {
                    StatusChip(title: String(localized: "Sajdah"), tint: .olive)
                }
                Spacer()
                Text(verse.reference)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondaryWarm)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                .stroke(strokeColor, lineWidth: isCurrent ? 1.5 : 1)
        )
        .accessibilityAddTraits(isCurrent || isInPassage ? .isSelected : [])
    }

    private var fillColor: Color {
        if isCurrent {
            return Color.appHighlightFill.opacity(0.55)
        }
        if isInPassage {
            return Color.olive.opacity(0.14)
        }
        return Color.clear
    }

    private var strokeColor: Color {
        if isCurrent {
            return Color.gold
        }
        if isInPassage {
            return Color.olive.opacity(0.45)
        }
        return Color.clear
    }
}

struct MushafFlowView: UIViewRepresentable {
    var verses: [QuranVerse]
    var currentGlobalAyah: Int?
    var hidesCurrentAyah: Bool
    var selectionEnabled: Bool
    var onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 20, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: UIColor(named: "BrownText") ?? UIColor.label,
            .underlineStyle: 0
        ]
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        textView.isSelectable = selectionEnabled

        let verseIDs = verses.map(\.globalAyah)
        let needsRender = context.coordinator.renderedVerseIDs != verseIDs
            || context.coordinator.renderedCurrentAyah != currentGlobalAyah
            || context.coordinator.renderedHiddenState != hidesCurrentAyah

        guard needsRender else { return }
        let rendered = makeAttributedText()
        context.coordinator.renderedVerseIDs = verseIDs
        context.coordinator.renderedCurrentAyah = currentGlobalAyah
        context.coordinator.renderedHiddenState = hidesCurrentAyah
        textView.attributedText = rendered.text

        guard let currentGlobalAyah,
              let range = rendered.ayahRanges[currentGlobalAyah]
        else { return }
        textView.layoutIfNeeded()
        textView.scrollRangeToVisible(range)
    }

    private func makeAttributedText() -> (text: NSAttributedString, ayahRanges: [Int: NSRange]) {
        let result = NSMutableAttributedString()
        var ayahRanges: [Int: NSRange] = [:]
        let bodyFont = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: UIFont(name: "AmiriQuran", size: 28) ?? .systemFont(ofSize: 28)
        )
        let basmalaFont = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: UIFont(name: "AmiriQuran", size: 25) ?? .systemFont(ofSize: 25)
        )
        let bodyColor = UIColor(named: "BrownText") ?? .label
        let basmalaColor = UIColor(named: "OliveAccent") ?? .secondaryLabel
        let highlightColor = (UIColor(named: "HighlightFill") ?? .systemYellow).withAlphaComponent(0.45)

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .justified
        bodyParagraph.baseWritingDirection = .rightToLeft
        bodyParagraph.lineSpacing = 8
        bodyParagraph.paragraphSpacing = 10

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
                        .foregroundColor: basmalaColor,
                        .paragraphStyle: basmalaParagraph
                    ]
                ))
            }

            let visibleText = hidesCurrentAyah && verse.globalAyah == currentGlobalAyah
                ? "••••••"
                : verse.text
            let sajdahMarker = verse.sajdah == .none ? "" : " ۩"
            let segmentText = "\(visibleText)\(sajdahMarker) ﴿\(Self.arabicIndicNumber(verse.ayahInSurah))﴾ "
            let location = result.length
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: bodyColor,
                .paragraphStyle: bodyParagraph
            ]
            if let link = URL(string: "simplequran://ayah/\(verse.globalAyah)") {
                attributes[.link] = link
            }
            if verse.globalAyah == currentGlobalAyah {
                attributes[.backgroundColor] = highlightColor
            }
            result.append(NSAttributedString(string: segmentText, attributes: attributes))
            ayahRanges[verse.globalAyah] = NSRange(location: location, length: segmentText.utf16.count)
        }

        return (result, ayahRanges)
    }

    private static func arabicIndicNumber(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { character in
            character.wholeNumberValue.map { digits[$0] }
        })
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MushafFlowView
        var renderedVerseIDs: [Int] = []
        var renderedCurrentAyah: Int?
        var renderedHiddenState = false

        init(parent: MushafFlowView) {
            self.parent = parent
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            let range = textItem.range
            guard parent.selectionEnabled,
                  range.location < textView.attributedText.length,
                  let URL = textView.attributedText.attribute(
                    .link,
                    at: range.location,
                    effectiveRange: nil
                  ) as? URL,
                  URL.scheme == "simplequran",
                  URL.host == "ayah",
                  let globalAyah = Int(URL.lastPathComponent)
            else { return nil }
            return UIAction { [weak self] _ in
                self?.parent.onSelect(globalAyah)
            }
        }
    }
}

struct BasmalaHeader: View {
    var body: some View {
        Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
            .font(.quran(size: 25))
            .foregroundStyle(Color.olive)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityLabel(String(localized: "Bismillah ir-Rahman ir-Raheem"))
    }
}

struct FriendlyErrorView: View {
    var message: UserFacingMessage
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.title)
                .font(.headline)
                .foregroundStyle(Color.appBrownText)
            Text(message.message)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryWarm)
            if let recovery = message.recovery {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(Color.olive)
            }
            if let retry {
                Button(String(localized: "Try again"), action: retry)
                    .buttonStyle(.bordered)
                    .tint(Color.gold)
            }
        }
        .padding()
        .background(Color.appWarmSurface, in: RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous))
    }
}
