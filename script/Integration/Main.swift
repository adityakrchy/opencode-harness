import AppKit
import Foundation

@main
struct HarnessIntegration {
    @MainActor
    static func main() async {
        let suite = UserDefaults(suiteName: "ai.opencode.harness.integration")!
        suite.removePersistentDomain(forName: "ai.opencode.harness.integration")
        let prefs = AppPreferences(defaults: suite)
        prefs.lastWorkspace = "/Users/aditya/Developer/opencode-harnes"
        prefs.completionSound = false

        let model = AppModel(prefs: prefs)
        print("Booting harness…")
        await model.boot(force: true)
        guard model.phase == .ready else {
            print("FAILED boot: \(model.phase)")
            exit(1)
        }
        print("READY models=\(model.models.count) sessions=\(model.sessions.count)")

        await model.newSession()
        guard let sessionID = model.selectedSessionID else {
            print("FAILED no session")
            exit(1)
        }
        print("CREATED \(sessionID)")

        await model.sendMessage("Reply with exactly HARNESS_APP_OK and nothing else.")
        var assistantText = ""
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let text = model.messages
                .filter { $0.kind == .assistant }
                .flatMap(\.blocks)
                .filter { $0.kind == .text }
                .map(\.text)
                .joined(separator: "\n")
            if text.contains("HARNESS_APP_OK") {
                assistantText = text
                break
            }
        }
        print("ASSISTANT: \(assistantText)")
        print("MESSAGES: \(model.messages.count) BUSY: \(model.isBusy)")

        if let session = model.sessions.first(where: { $0.id == sessionID }) {
            await model.deleteSession(session)
        }
        model.shutdown()
        exit(assistantText.contains("HARNESS_APP_OK") ? 0 : 2)
    }
}
