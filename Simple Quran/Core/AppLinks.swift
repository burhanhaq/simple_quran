import Foundation

/// Where the app sends people for help, the full privacy policy, and its sources.
/// Kept in step with the app's pages at dumblemon.com/apps/simple-quran.
nonisolated enum AppLinks {
    static let email = "hello@dumblemon.com"
    static let website = URL(string: "https://dumblemon.com/apps/simple-quran/")!
    static let privacyPolicy = URL(string: "https://dumblemon.com/apps/simple-quran/privacy/")!
    static let support = URL(string: "https://dumblemon.com/apps/simple-quran/support/")!

    /// Matches the effective date of the website's policy, which this app's Privacy page summarizes.
    static let privacyEffectiveDate = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 25).date!

    enum MailSubject: String {
        case support = "Simple Quran support"
        case privacy = "Simple Quran privacy"
    }

    static func mail(_ subject: MailSubject) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: subject.rawValue)]
        return components.url!
    }
}

/// The sources Acknowledgements and Privacy credit, beyond the translation's own `TranslationEdition`.
nonisolated enum SourceLinks {
    static let quranicUniversalLibrary = URL(string: "https://qul.tarteel.ai")!
    static let qurancomplex = URL(string: "https://qurancomplex.gov.sa")!
    static let qurancomplexFonts = URL(string: "https://fonts.qurancomplex.gov.sa")!

    /// The service that streams and serves recitation downloads.
    static let audioServiceName = "Al Quran Cloud (islamic.network)"
    static let audioService = URL(string: "https://alquran.cloud")!
    static let audioServiceTerms = URL(string: "https://alquran.cloud/terms-and-conditions")!
}
