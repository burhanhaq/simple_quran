import CoreText
import SwiftUI

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
    static let surfaceHighlight = Color("SurfaceHighlight")
    static let appBrownText = Color("BrownText")
    static let secondaryWarm = Color("SecondaryText")
    static let olive = Color("OliveAccent")
    static let gold = Color("GoldAccent")
    static let goldButtonText = Color("GoldButtonText")
    static let bronze = Color("Bronze")
    static let appHighlightFill = Color("HighlightFill")
    static let appCollectedFill = Color("CollectedFill")
    static let warmBorder = Color("WarmBorder")
    static let dangerWarm = Color("DangerText")
}

extension Font {
    static func quran(size: CGFloat = 28) -> Font {
        .custom("AmiriQuran", size: size, relativeTo: .title)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.surfaceHighlight, Color.appWarmSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.warmBorder.opacity(0.72), lineWidth: 0.75)
            }
            .shadow(color: emphasized ? Color.gold.opacity(0.15) : .black.opacity(0.045), radius: emphasized ? 18 : 10, y: emphasized ? 7 : 3)
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
            .padding(.horizontal, 18)
            .frame(minHeight: AppTheme.controlHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: emphasis == .primary
                            ? [Color(red: 0.94, green: 0.79, blue: 0.51), Color.gold]
                            : [Color.surfaceHighlight, Color.appWarmSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                    .strokeBorder(
                        emphasis == .primary ? Color.gold.opacity(0.75) : Color.warmBorder,
                        lineWidth: 0.75
                    )
            }
            .shadow(color: emphasis == .primary ? Color.gold.opacity(0.18) : .clear, radius: 10, y: 4)
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
            .background {
                Circle().fill(LinearGradient(
                    colors: [Color(red: 0.96, green: 0.83, blue: 0.57), Color.gold],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            }
            .overlay {
                Circle().strokeBorder(Color.gold.opacity(0.8), lineWidth: 0.75)
            }
            .shadow(color: Color.gold.opacity(0.22), radius: 8, y: 3)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hidden ? "••••••" : verse.text)
                .font(.quran())
                .lineSpacing(12)
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
        .accessibilityAddTraits(isCurrent || isInPassage ? .isSelected : [])
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
    var body: some View {
        Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
            .font(.quran(size: 25))
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
                .font(isArabic ? .quran(size: 28) : .title3.weight(.semibold))
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
        toolbarBackground(Color.parchment, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
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
