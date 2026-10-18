import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 24
    static let tightRadius: CGFloat = 16
    static let controlHeight: CGFloat = 50
}

extension Color {
    static let parchment = Color("ParchmentBackground")
    static let appWarmSurface = Color("WarmSurface")
    static let surfaceHighlight = Color("SurfaceHighlight")
    static let appBrownText = Color("BrownText")
    static let secondaryWarm = Color("SecondaryText")
    static let olive = Color("OliveAccent")
    static let gold = Color("GoldAccent")
    static let fadingAmber = Color("FadingAmber")
    static let goldButtonText = Color("GoldButtonText")
    static let bronze = Color("Bronze")
    static let appHighlightFill = Color("HighlightFill")
    static let appCollectedFill = Color("CollectedFill")
    static let warmBorder = Color("WarmBorder")
    static let dangerWarm = Color("DangerText")
}

extension Freshness {
    /// Green while fresh, amber while fading, and the warm danger color once it needs revision.
    var color: Color {
        switch self {
        case .fresh: .olive
        case .fading: .fadingAmber
        case .needsRevision: .dangerWarm
        }
    }
}

extension Font {
    static func quran(_ size: QuranScript.Size = .body) -> Font {
        QuranScript.font(size)
    }
}

struct WarmCard<Content: View>: View {
    var emphasized: Bool
    var content: () -> Content

    init(emphasized: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.emphasized = emphasized
        self.content = content
    }

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasized ? Color.appCollectedFill : Color.appWarmSurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .strokeBorder(Color.warmBorder.opacity(0.65), lineWidth: 0.5)
            }
    }
}

struct WarmButtonStyle: ButtonStyle {
    enum Emphasis {
        case primary
        case secondary
    }

    var emphasis: Emphasis = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(emphasis == .primary ? Color.goldButtonText : Color.bronze)
            .padding(.horizontal, 20)
            .frame(minHeight: AppTheme.controlHeight)
            .background(emphasis == .primary ? Color.gold : Color.appCollectedFill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct WarmSymbol: View {
    var systemName: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.bronze)
            .frame(width: size, height: size)
            .background(Color.appCollectedFill, in: Circle())
    }
}

struct PlayGlyph: View {
    var systemName: String = "play.fill"
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.goldButtonText)
            .offset(x: systemName.hasPrefix("play") ? size * 0.04 : 0)
            .frame(width: size, height: size)
            .background(Color.gold, in: Circle())
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
            WarmSymbol(systemName: "book.closed", size: 56)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.appBrownText)
            Text(message)
                .font(.body)
                .foregroundStyle(Color.secondaryWarm)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(WarmButtonStyle())
                .accessibilityIdentifier(actionIdentifier)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(WarmButtonStyle(emphasis: .secondary))
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
    /// Marked as slipped while testing; underlined in the danger color.
    var marked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayedText)
                .font(.quran())
                .lineSpacing(12)
                .foregroundStyle(Color.appBrownText)
                .underline(marked, color: .dangerWarm)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityLabel(hidden ? String(localized: "Arabic hidden for recall") : verse.text)
                .accessibilityValue(marked ? String(localized: "Marked as slipped") : "")
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
        .accessibilityAddTraits(isCurrent || isInPassage ? .isSelected : [])
    }

    /// The ayah followed by its number, which the font draws inside the end-of-ayah ornament.
    private var displayedText: AttributedString {
        guard !hidden else { return AttributedString(QuranScript.hiddenPlaceholder) }
        var number = AttributedString(QuranScript.ayahNumber(verse.ayahInSurah))
        number.foregroundColor = Color.bronze
        return AttributedString(verse.text) + number
    }

    private var fillColor: Color {
        if isCurrent {
            return Color.appHighlightFill
        }
        if isInPassage {
            return Color.appCollectedFill
        }
        return Color.clear
    }
}

struct ReadingLayoutMenu: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Section(String(localized: "Reading Layout")) {
            ForEach(QuranReadingLayout.allCases) { layout in
                Button {
                    environment.settings.quranReadingLayout = layout
                } label: {
                    Label(
                        layout.title,
                        systemImage: environment.settings.quranReadingLayout == layout
                            ? "checkmark"
                            : layout.systemImage
                    )
                }
            }
        }
    }
}

struct BasmalaHeader: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Text(environment.quran.basmala)
            .font(.quran(.basmala))
            .foregroundStyle(Color.appBrownText)
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
                    .buttonStyle(WarmButtonStyle(emphasis: .secondary))
            }
        }
        .padding()
        .background(Color.appWarmSurface, in: RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                .strokeBorder(Color.warmBorder.opacity(0.7), lineWidth: 0.75)
        }
    }
}

struct ReadingBanner: View {
    var title: String
    var isArabic: Bool

    var body: some View {
        VStack(spacing: 10) {
            rule
            Text(title)
                .font(isArabic ? .quran(.title) : .title3.weight(.semibold))
                .foregroundStyle(Color.appBrownText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            rule
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var rule: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Color.gold, .clear], startPoint: .leading, endPoint: .trailing))
            .frame(width: 112, height: 1)
    }
}

extension View {
    func parchmentNavigationBar() -> some View {
        toolbarBackground(.automatic, for: .navigationBar)
    }

    func warmListChrome() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.parchment.ignoresSafeArea())
            .listRowSeparatorTint(Color.warmBorder.opacity(0.8))
            .parchmentNavigationBar()
    }

    func warmListRow() -> some View {
        listRowBackground(Color.appWarmSurface)
    }
}

/// Decorative linework, drawn once by SwiftUI without image loading or animation.
struct ArchMotif: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<5 {
                let inset = CGFloat(index) * 17
                let rect = CGRect(x: inset, y: inset, width: max(0, size.width - inset * 2), height: size.height * 1.4)
                let path = Path(roundedRect: rect, cornerRadius: rect.width / 2)
                context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.appBrownText)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(Color.secondaryWarm)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
