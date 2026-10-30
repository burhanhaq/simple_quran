import Foundation
import Testing
@testable import Simple_Quran

struct ReviewPromptTests {
    private func isolatedDefaults() throws -> (defaults: UserDefaults, name: String) {
        let name = "ReviewPromptTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test @MainActor func fiveListensMakeItDue() throws {
        let isolated = try isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.name) }
        let prompt = ReviewPrompt(defaults: isolated.defaults)
        for _ in 1..<ReviewPrompt.threshold { prompt.recordListen() }
        #expect(!prompt.isDue)
        prompt.recordListen()
        #expect(prompt.isDue)
    }

    @Test @MainActor func fiveRevisionsMakeItDueOnTheirOwn() throws {
        let isolated = try isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.name) }
        let prompt = ReviewPrompt(defaults: isolated.defaults)
        prompt.recordListen()
        for _ in 1..<ReviewPrompt.threshold { prompt.recordRevision() }
        #expect(!prompt.isDue)
        prompt.recordRevision()
        #expect(prompt.isDue)
    }

    @Test @MainActor func asksOnlyOnceAcrossLaunches() throws {
        let isolated = try isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.name) }
        let prompt = ReviewPrompt(defaults: isolated.defaults)
        for _ in 0..<ReviewPrompt.threshold { prompt.recordRevision() }
        let relaunched = ReviewPrompt(defaults: isolated.defaults)
        #expect(relaunched.isDue)
        relaunched.markRequested()
        relaunched.recordListen()
        #expect(!relaunched.isDue)
        #expect(!ReviewPrompt(defaults: isolated.defaults).isDue)
    }

    @Test @MainActor func neverDueWhenDisabled() throws {
        let isolated = try isolatedDefaults()
        defer { isolated.defaults.removePersistentDomain(forName: isolated.name) }
        let prompt = ReviewPrompt(defaults: isolated.defaults, isEnabled: false)
        for _ in 0..<ReviewPrompt.threshold { prompt.recordListen() }
        #expect(!prompt.isDue)
    }
}
