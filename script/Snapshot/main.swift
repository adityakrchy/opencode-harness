import AppKit
import SwiftUI

@MainActor
func runSnapshot() {
    let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/opencode-harness.png"
    let appearance = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "dark"
    let mode = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "main"

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let prefs = AppPreferences(defaults: UserDefaults(suiteName: "ai.opencode.harness.snapshot")!)
    prefs.showInspector = true
    prefs.inspectorSection = .changes
    prefs.completionSound = false
    prefs.theme = appearance == "light" ? .light : .dark

    let model = AppModel(prefs: prefs)
    model.phase = .ready
    model.serverInfo = ServerInfo(
        version: "2.1.4",
        pid: 4242,
        urls: ["http://127.0.0.1:4096"],
        paths: ServerInfo.ServerPaths(tmp: "/private/tmp/opencode"),
        capabilities: ServerInfo.ServerCapabilities(persistentPty: true)
    )
    model.eventConnection = .connected

    let project = ProjectInfo(
        id: "project_snapshot",
        canonical: "/Users/ada/orbit",
        name: "orbit",
        vcs: "git",
        icon: nil,
        commands: nil,
        time: ProjectTime(created: 1, updated: 2, active: 3),
        sandboxes: []
    )
    model.projects = [project]
    model.workspace = Workspace(directory: "/Users/ada/orbit", project: project)
    model.vcsInfo = VcsInfo(provider: "git", branch: VcsBranch(current: "feat/command-palette", default: "main"))
    model.worktrees = [WorktreeInfo(directory: "/Users/ada/orbit/.worktrees/faster-tests", strategy: "git")]

    let session1 = SessionInfo(
        id: "ses_snapshot_1",
        projectID: project.id,
        parentID: nil,
        fork: nil,
        agent: "build",
        model: ModelRef(id: "claude-sonnet-4-6", providerID: "anthropic", variant: "high"),
        cost: 0.0842,
        tokens: TokenUsage(input: 48211, output: 3982, reasoning: 921, cache: TokenUsage.CacheUsage(read: 118_000, write: 1300)),
        outcome: nil,
        time: SessionTime(created: 1_793_900_000_000, updated: 1_793_904_000_000, idle: nil, viewed: nil, archived: nil),
        title: "Add a command palette with keyboard navigation",
        subpath: "",
        revert: nil,
        location: LocationRef(directory: "/Users/ada/orbit")
    )
    let session2 = SessionInfo(
        id: "ses_snapshot_2",
        projectID: project.id,
        parentID: nil,
        fork: nil,
        agent: "build",
        model: ModelRef(id: "gpt-5.4-codex", providerID: "openai", variant: nil),
        cost: 0.021,
        tokens: TokenUsage(input: 12000, output: 1000, reasoning: 200, cache: TokenUsage.CacheUsage(read: 2000, write: 0)),
        outcome: "succeeded",
        time: SessionTime(created: 1_793_890_000_000, updated: 1_793_893_000_000, idle: 1_793_893_000_000, viewed: nil, archived: nil),
        title: "Fix flaky worktree cleanup",
        subpath: "",
        revert: nil,
        location: LocationRef(directory: "/Users/ada/orbit")
    )
    let session3 = SessionInfo(
        id: "ses_snapshot_3",
        projectID: project.id,
        parentID: nil,
        fork: nil,
        agent: "explore",
        model: ModelRef(id: "gemini-3-pro", providerID: "google", variant: nil),
        cost: 0.004,
        tokens: TokenUsage(input: 5000, output: 700, reasoning: 100, cache: TokenUsage.CacheUsage(read: 0, write: 0)),
        outcome: "succeeded",
        time: SessionTime(created: 1_793_800_000_000, updated: 1_793_802_000_000, idle: 1_793_802_000_000, viewed: nil, archived: nil),
        title: "Map the auth middleware",
        subpath: "",
        revert: nil,
        location: LocationRef(directory: "/Users/ada/orbit")
    )
    model.sessions = [session1, session2, session3]
    model.selectedSessionID = session1.id
    model.selectedModel = session1.model
    model.selectedAgent = "build"

    model.models = [
        ModelInfo(id: "claude-sonnet-4-6", modelID: "claude-sonnet-4-6", providerID: "anthropic", canonical: "anthropic", family: "claude", name: "Claude Sonnet 4.6", settings: nil, headers: nil, capabilities: ModelCapabilities(tools: true, input: ["text", "image"], output: ["text"], temperature: true), variants: [ModelVariant(id: "high")], time: ModelInfo.ModelTime(released: 0), cost: nil, status: "active", enabled: true, limit: ModelLimit(context: 200_000, input: 200_000, output: 64_000)),
        ModelInfo(id: "gpt-5.4-codex", modelID: "gpt-5.4-codex", providerID: "openai", canonical: "openai", family: "gpt", name: "GPT-5.4 Codex", settings: nil, headers: nil, capabilities: ModelCapabilities(tools: true, input: ["text"], output: ["text"], temperature: false), variants: nil, time: nil, cost: nil, status: "active", enabled: true, limit: ModelLimit(context: 400_000, input: nil, output: 128_000)),
        ModelInfo(id: "gemini-3-pro", modelID: "gemini-3-pro", providerID: "google", canonical: "google", family: "gemini", name: "Gemini 3 Pro", settings: nil, headers: nil, capabilities: ModelCapabilities(tools: true, input: ["text", "image"], output: ["text"], temperature: true), variants: nil, time: nil, cost: nil, status: "active", enabled: true, limit: ModelLimit(context: 1_000_000, input: nil, output: 65_000))
    ]
    model.agents = [
        AgentInfo(id: "build", name: "Build", model: nil, description: "The default agent. Executes tools based on configured permissions.", mode: "primary", hidden: false, color: "#FF6B2C", steps: nil, permissions: []),
        AgentInfo(id: "plan", name: "Plan", model: nil, description: "Research and plan without changing files.", mode: "primary", hidden: false, color: "#9B87F5", steps: nil, permissions: []),
        AgentInfo(id: "explore", name: "Explore", model: nil, description: "Fast codebase exploration.", mode: "subagent", hidden: false, color: "#3CC8B4", steps: nil, permissions: [])
    ]
    model.commands = [
        CommandInfo(name: "init", description: "guided AGENTS.md setup"),
        CommandInfo(name: "review", description: "review changes [commit|branch|pr]"),
        CommandInfo(name: "commit", description: "create a conventional commit")
    ]

    let user = ChatMessage(
        id: "msg_user",
        kind: .user,
        createdAt: Date().addingTimeInterval(-96),
        completedAt: nil,
        userText: "Add a command palette with keyboard navigation. It should fuzzy search sessions, files, and every action in the app.",
        blocks: [],
        model: nil,
        agent: nil,
        cost: nil,
        tokens: nil,
        finish: nil,
        outcome: nil,
        errorText: nil,
        command: nil,
        shellOutput: nil,
        shellStatus: nil,
        shellExit: nil,
        compactionText: nil,
        attachments: [PromptAttachment(uri: "file:///Users/ada/orbit/README.md", name: "README.md", mime: "text/markdown", description: nil)],
        isStreaming: false
    )

    let reasoning = MessageBlock(
        id: "msg_assistant:reasoning:0",
        kind: .reasoning,
        text: "I need to find the existing navigation shell first, then add a palette overlay and wire the global shortcut through the command menu. The palette should share the app model so its actions stay in sync with the current session.",
        reasoningStarted: 0,
        reasoningCompleted: 2400
    )

    let text1 = MessageBlock(
        id: "msg_assistant:text:0",
        kind: .text,
        text: """
        I found the main shell in `RootView.swift` and the command menu in `OpenCodeHarnessApp.swift`. I’ll add a palette overlay to the root and route **⌘K** through the app commands.

        - Fuzzy search across sessions, models, agents, and project actions
        - Fully keyboard driven — `↑` `↓` to move, `↩` to run, `esc` to close
        - Shares the existing `AppModel` so nothing goes stale

        Here’s the action model I’m adding:
        """
    )

    let tool = ToolCall(
        id: "tool_1",
        name: "edit",
        status: "completed",
        input: .object(["path": .string("OpenCodeHarness/Features/RunnerAndPalette.swift"), "description": .string("Add command palette action model")]),
        content: "Updated RunnerAndPalette.swift with 184 additions and 2 removals.",
        files: [],
        metadata: .object(["additions": .number(184), "deletions": .number(2)]),
        errorText: nil,
        executed: true,
        startedAt: 0,
        completedAt: 1.2
    )
    let toolBlock = MessageBlock(id: "msg_assistant:tool:tool_1", kind: .tool, text: "", tool: tool)

    let code = MessageBlock(
        id: "msg_assistant:text:1",
        kind: .text,
        text: """
        ### Palette wiring

        ```swift
        struct PaletteAction: Identifiable {
            let id: String
            let title: String
            let icon: String
            let action: () -> Void
        }

        Button("Command Palette…") {
            model.showCommandPalette = true
        }
        .keyboardShortcut("k", modifiers: .command)
        ```

        > The palette stays a sheet, so focus and key handling remain native. Escape closes it without dropping the current session.

        | Surface | Shortcut | Behavior |
        |---|---|---|
        | Palette | ⌘K | Fuzzy search every action |
        | Files | ⌘P | Quick open by path |
        | Shell | ⌘J | Toggle live command runner |
        """
    )

    let assistant = ChatMessage(
        id: "msg_assistant",
        kind: .assistant,
        createdAt: Date().addingTimeInterval(-90),
        completedAt: Date().addingTimeInterval(-6),
        userText: nil,
        blocks: [reasoning, text1, toolBlock, code],
        model: session1.model,
        agent: "build",
        cost: 0.0124,
        tokens: TokenUsage(input: 5310, output: 842, reasoning: 301, cache: TokenUsage.CacheUsage(read: 22_200, write: 0)),
        finish: "stop",
        outcome: nil,
        errorText: nil,
        command: nil,
        shellOutput: nil,
        shellStatus: nil,
        shellExit: nil,
        compactionText: nil,
        attachments: [],
        isStreaming: true
    )

    model.messages = [user, assistant]
    model.activeSessionIDs = [session1.id]
    model.pendingPermissions = [
        PermissionRequest(
            id: "perm_1",
            sessionID: session1.id,
            action: "edit",
            resources: ["OpenCodeHarness/Features/RunnerAndPalette.swift"],
            save: nil,
            metadata: nil,
            source: nil,
            message: "Allow Build to edit RunnerAndPalette.swift?"
        )
    ]

    model.sessionDiffs = [
        FileDiff(file: "OpenCodeHarness/Features/RunnerAndPalette.swift", patch: "@@ -1,3 +1,8 @@\n import SwiftUI\n \n+struct PaletteAction: Identifiable {\n+    let id: String\n+}\n+\n struct CommandPaletteView: View {", additions: 34, deletions: 2, status: "modified"),
        FileDiff(file: "OpenCodeHarness/App/OpenCodeHarnessApp.swift", patch: "@@ -10,6 +10,11 @@\n         .commands {\n             AppCommands(model: model)\n         }\n+\n+        CommandGroup(after: .saveItem) {\n+            Button(\"Command Palette…\") { }\n+        }", additions: 8, deletions: 0, status: "modified")
    ]

    model.stats = SessionStatsInfo(
        range: SessionStatsInfo.StatsRange(from: 1_793_800_000_000, to: 1_793_940_000_000),
        sessions: 18,
        subagents: 4,
        prompts: 67,
        steps: 214,
        tokens: TokenUsage(input: 1_204_000, output: 88_200, reasoning: 21_400, cache: TokenUsage.CacheUsage(read: 4_120_000, write: 12_000)),
        cost: 18.42,
        tools: .object(["mode": .string("detail"), "usage": .array([
            .object(["name": .string("edit"), "calls": .number(42), "failed": .number(1)]),
            .object(["name": .string("shell"), "calls": .number(31), "failed": .number(2)]),
            .object(["name": .string("read"), "calls": .number(88), "failed": .number(0)]),
            .object(["name": .string("grep"), "calls": .number(12), "failed": .number(0)])
        ])]),
        activeDays: 11,
        streak: 4,
        activity: (0..<28).map { day in
            StatsActivity(date: String(format: "2026-10-%02d", day + 8), steps: Int.random(in: 2...22))
        },
        models: [
            StatsModelUsage(model: ModelRef(id: "claude-sonnet-4-6", providerID: "anthropic", variant: nil), steps: 104, tokens: TokenUsage(input: 610_000, output: 43_000, reasoning: 11_000, cache: TokenUsage.CacheUsage(read: 2_100_000, write: 0)), cost: 11.42),
            StatsModelUsage(model: ModelRef(id: "gpt-5.4-codex", providerID: "openai", variant: nil), steps: 68, tokens: TokenUsage(input: 390_000, output: 30_000, reasoning: 6_000, cache: TokenUsage.CacheUsage(read: 1_200_000, write: 0)), cost: 5.31),
            StatsModelUsage(model: ModelRef(id: "gemini-3-pro", providerID: "google", variant: nil), steps: 42, tokens: TokenUsage(input: 204_000, output: 15_200, reasoning: 4_400, cache: TokenUsage.CacheUsage(read: 820_000, write: 0)), cost: 1.69)
        ]
    )

    model.integrations = [
        IntegrationInfo(id: "anthropic", name: "Anthropic", metadata: nil, methods: [
            IntegrationMethod(id: "key", type: "key", label: "API key", form: nil, command: nil, names: nil)
        ], connections: [
            IntegrationConnection(id: "cred_1", type: "credential", label: "Work key", active: true, status: "active", name: nil)
        ]),
        IntegrationInfo(id: "openai", name: "OpenAI", metadata: nil, methods: [
            IntegrationMethod(id: "oauth", type: "oauth", label: "Sign in with ChatGPT", form: nil, command: nil, names: nil),
            IntegrationMethod(id: "key", type: "key", label: "API key", form: nil, command: nil, names: nil)
        ], connections: []),
        IntegrationInfo(id: "google", name: "Google", metadata: nil, methods: [
            IntegrationMethod(id: "key", type: "key", label: "Google AI Studio key", form: nil, command: nil, names: nil)
        ], connections: [])
    ]
    model.credentials = [
        CredentialEntry(id: "cred_1", integrationID: "anthropic", label: "Work key", active: true, value: .object(["type": .string("key")])),
        CredentialEntry(id: "cred_2", integrationID: "openrouter", label: "Personal", active: false, value: .object(["type": .string("key")]))
    ]
    model.mcpServers = [
        McpServer(name: "filesystem", status: .object(["status": .string("connected")]), integrationID: nil),
        McpServer(name: "sentry", status: .object(["status": .string("needs_auth"), "error": .string("Sign in required")]), integrationID: nil),
        McpServer(name: "linear", status: .object(["status": .string("failed"), "error": .string("Command not found")]), integrationID: nil)
    ]
    model.plugins = [
        PluginInfo(id: "builtin:notify", source: .object(["type": .string("builtin")]), features: nil, state: .object(["status": .string("active")])),
        PluginInfo(id: "pkg:opencode-plugin", source: .object(["type": .string("package"), "target": .string("@acme/opencode-plugin"), "version": .string("1.2.0"), "outdated": .bool(true)]), features: nil, state: .object(["status": .string("active")])),
        PluginInfo(id: "local:script", source: .object(["type": .string("local"), "path": .string("./plugin.ts")]), features: nil, state: .object(["status": .string("failed"), "error": .string("Import failed")]))
    ]
    model.shellOptions = [
        .object(["path": .string("/bin/zsh"), "name": .string("zsh"), "acceptable": .bool(true)]),
        .object(["path": .string("/bin/bash"), "name": .string("bash"), "acceptable": .bool(true)])
    ]
    model.configEntries = [
        .object(["type": .string("document"), "path": .string("/Users/ada/.config/opencode/opencode.jsonc"), "info": .object(["$schema": .string("https://opencode.ai/config.json"), "shell": .string("/bin/zsh")])])
    ]
    model.runnerOutput = "$ swift build\nBuilding for debugging...\n[42/42] Linking OpenCodeHarness\nBuild complete! (3.42s)\n"

    var size = CGSize(width: 1380, height: 900)
    let content: AnyView
    switch mode {
    case "palette":
        size = CGSize(width: 650, height: 540)
        content = AnyView(CommandPaletteView().environmentObject(model).environmentObject(prefs))
    case "settings":
        size = CGSize(width: 900, height: 620)
        content = AnyView(SettingsView().environmentObject(model).environmentObject(prefs))
    case "providers":
        size = CGSize(width: 720, height: 680)
        content = AnyView(ZStack { Color.ocCanvas.ignoresSafeArea(); ScrollView { ProvidersSettingsView().environmentObject(model).padding(24) } })
    case "mcp":
        size = CGSize(width: 720, height: 620)
        content = AnyView(ZStack { Color.ocCanvas.ignoresSafeArea(); ScrollView { McpSettingsView().environmentObject(model).padding(24) } })
    case "composer":
        size = CGSize(width: 900, height: 260)
        content = AnyView(ZStack { Color.ocCanvas.ignoresSafeArea(); ComposerView().environmentObject(model).environmentObject(prefs).padding(24) })
    case "runner":
        size = CGSize(width: 900, height: 300)
        content = AnyView(ZStack { Color.ocCanvas.ignoresSafeArea(); RunnerPanelView().environmentObject(model) })
    case "boot":
        size = CGSize(width: 1000, height: 700)
        model.phase = .booting
        model.bootDetail = "Starting the local OpenCode engine…"
        content = AnyView(ZStack { AmbientBackground(); BootView().environmentObject(model).environmentObject(prefs) })
    case "home":
        model.selectedSessionID = nil
        model.messages = []
        content = AnyView(ZStack { AmbientBackground(); WorkspaceHomeView().environmentObject(model).environmentObject(prefs) })
    case "empty":
        model.messages = []
        model.activeSessionIDs = []
        model.pendingPermissions = []
        content = AnyView(ZStack { AmbientBackground(); ChatView().environmentObject(model).environmentObject(prefs) })
    case "stats":
        size = CGSize(width: 780, height: 640)
        content = AnyView(StatsView().environmentObject(model).environmentObject(prefs))
    case "form":
        size = CGSize(width: 560, height: 640)
        let form = FormInfo(id: "form_1", sessionID: session1.id, title: "Choose a deployment target", metadata: nil, fields: [
            FormField(key: "environment", title: "Environment", description: "Where should the change be deployed?", required: true, hidden: nil, type: "string", format: nil, minLength: nil, maxLength: nil, pattern: nil, placeholder: "Select environment", default: .string("staging"), options: [FormOption(value: "staging", label: "Staging", description: nil), FormOption(value: "production", label: "Production", description: nil)], minItems: nil, maxItems: nil, custom: nil, url: nil),
            FormField(key: "notify", title: "Notify the team", description: nil, required: false, hidden: nil, type: "boolean", format: nil, minLength: nil, maxLength: nil, pattern: nil, placeholder: nil, default: .bool(true), options: nil, minItems: nil, maxItems: nil, custom: nil, url: nil),
            FormField(key: "regions", title: "Regions", description: "Pick one or more edge regions.", required: true, hidden: nil, type: "multiselect", format: nil, minLength: nil, maxLength: nil, pattern: nil, placeholder: nil, default: .array([.string("us-east")]), options: [FormOption(value: "us-east", label: "US East", description: nil), FormOption(value: "eu-west", label: "EU West", description: nil), FormOption(value: "ap-south", label: "AP South", description: nil)], minItems: 1, maxItems: 3, custom: nil, url: nil)
        ])
        content = AnyView(FormSheetView(form: form).environmentObject(model))
    case "workspace":
        size = CGSize(width: 620, height: 560)
        content = AnyView(WorkspacePickerView().environmentObject(model).environmentObject(prefs))
    default:
        content = AnyView(RootView().environmentObject(model).environmentObject(prefs))
    }

    let root = content
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(appearance == "light" ? .light : .dark)

    let hosting = NSHostingView(rootView: root)
    hosting.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

    let window = NSWindow(
        contentRect: NSRect(x: 80, y: 80, width: size.width, height: size.height),
        styleMask: [.titled, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentView = hosting
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    RunLoop.main.run(until: Date().addingTimeInterval(1.4))

    hosting.layoutSubtreeIfNeeded()
    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { exit(2) }
    rep.size = NSSize(width: size.width, height: size.height)
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { exit(3) }
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
    exit(0)
}

MainActor.assumeIsolated {
    runSnapshot()
}
