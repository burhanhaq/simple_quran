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
                .accessibilityIdentifier("empty.createSet")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct QuranAyahText: View {
    var verse: QuranVerse
    var isCurrent: Bool
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
                .fill(isCurrent ? Color.appHighlightFill.opacity(0.55) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.tightRadius, style: .continuous)
                .stroke(isCurrent ? Color.gold : Color.clear, lineWidth: 1.5)
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
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
