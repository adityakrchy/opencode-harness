import SwiftUI

@main
struct OpenCodeHarnessApp: App {
    @StateObject private var prefs: AppPreferences
    @StateObject private var model: AppModel

    init() {
        Diagnostics.log("App init")
        let preferences = AppPreferences()
        _prefs = StateObject(wrappedValue: preferences)
        _model = StateObject(wrappedValue: AppModel(prefs: preferences))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(prefs)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(prefs.theme.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1380, height: 900)
        .commands {
            AppCommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(prefs)
                .frame(minWidth: 820, minHeight: 560)
                .preferredColorScheme(prefs.theme.colorScheme)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                Task { await model.newSession() }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Project…") {
                model.chooseWorkspace()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Import Session…") {
                model.importSession()
            }
            Button("Export Session…") {
                model.exportCurrentSession()
            }
            .disabled(model.selectedSessionID == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Quick Open…") {
                model.showQuickOpen = true
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Command Palette…") {
                model.showCommandPalette = true
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("Session") {
            Button("Stop Generating") {
                Task { await model.stopGeneration() }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.isBusy)

            Button("Compact Context") {
                Task { await model.compactSession() }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(model.selectedSessionID == nil)

            Button("Fork Session") {
                if let session = model.selectedSession {
                    Task { await model.forkSession(session) }
                }
            }
            .disabled(model.selectedSession == nil)

            Button("Copy Session ID") {
                model.copySessionID()
            }
            .disabled(model.selectedSessionID == nil)

            Divider()

            Button("Archive Session") {
                if let session = model.selectedSession {
                    Task { await model.archiveSession(session) }
                }
            }
            .disabled(model.selectedSession == nil)

            Button("Delete Session…") {
                model.pendingDeleteSession = model.selectedSession
            }
            .disabled(model.selectedSession == nil)

            Divider()

            Button("Refresh") {
                Task { await model.refreshEverything() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button(model.prefs.showInspector ? "Hide Inspector" : "Show Inspector") {
                withAnimation(Motion.smooth) { model.prefs.showInspector.toggle() }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button(model.showTerminal ? "Hide Shell" : "Show Shell") {
                withAnimation(Motion.smooth) { model.showTerminal.toggle() }
            }
            .keyboardShortcut("j", modifiers: .command)

            Button("Usage Statistics…") {
                model.showStats = true
                Task { await model.loadStats() }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Reload Configuration") {
                Task { await model.reloadConfiguration() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Open Config File") {
                model.openConfigFile()
            }

            Button("Reveal Project in Finder") {
                model.revealWorkspaceInFinder()
            }
        }

        CommandGroup(after: .sidebar) {
            Button("Show Archived Sessions") {
                Task { await model.toggleArchived() }
            }
        }
    }
}
