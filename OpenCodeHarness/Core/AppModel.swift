import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum BootPhase: Equatable {
    case idle
    case booting
    case ready
    case failed(String)
}

@MainActor
final class AppModel: ObservableObject {
    // Dependencies
    let prefs: AppPreferences
    let server = OpenCodeServer()
    private(set) var api: APIClient?
    private var eventStream: OpenCodeEventStream?

    // Boot / connection
    @Published var phase: BootPhase = .idle
    @Published var serverInfo: ServerInfo?
    @Published var eventConnection: EventStreamState = .connecting
    @Published var bootDetail = "Starting OpenCode…"

    // Workspace & sessions
    @Published var projects: [ProjectInfo] = []
    @Published var workspace: Workspace?
    @Published var sessions: [SessionInfo] = []
    @Published var archivedSessions: [SessionInfo] = []
    @Published var sessionChildren: [String: [SessionInfo]] = [:]
    @Published var selectedSessionID: String?
    @Published var activeSessionIDs: Set<String> = []
    @Published var sessionSearch = ""
    @Published var showArchived = false

    // Chat
    @Published var messages: [ChatMessage] = []
    @Published var isLoadingMessages = false
    @Published var isSending = false
    @Published var selectedModel: ModelRef?
    @Published var selectedAgent = "build"
    @Published var delivery = "steer"
    @Published var pendingPermissions: [PermissionRequest] = []
    @Published var pendingForms: [FormInfo] = []
    @Published var showToolDetails = false

    // Catalog
    @Published var models: [ModelInfo] = []
    @Published var defaultModel: ModelInfo?
    @Published var providers: [ProviderInfo] = []
    @Published var agents: [AgentInfo] = []
    @Published var commands: [CommandInfo] = []
    @Published var skills: [SkillInfo] = []

    // Settings screens
    @Published var integrations: [IntegrationInfo] = []
    @Published var credentials: [CredentialEntry] = []
    @Published var mcpServers: [McpServer] = []
    @Published var plugins: [PluginInfo] = []
    @Published var configEntries: [JSONValue] = []
    @Published var shellOptions: [JSONValue] = []
    @Published var settingsLoading = false

    // Changes & inspector
    @Published var sessionDiffs: [FileDiff] = []
    @Published var vcsDiffs: [FileDiff] = []
    @Published var vcsStatus: [VcsFileStatus] = []
    @Published var vcsInfo: VcsInfo?
    @Published var selectedFilePath: String?
    @Published var selectedFileText: String?
    @Published var selectedFileSize = 0
    @Published var selectedFileIsBinary = false
    @Published var filePreviewLoading = false
    @Published var diffMode = "session"

    // Stats & worktrees
    @Published var stats: SessionStatsInfo?
    @Published var worktrees: [WorktreeInfo] = []

    // UI
    @Published var showCommandPalette = false
    @Published var showQuickOpen = false
    @Published var showStats = false
    @Published var showSettings = false
    @Published var showWorkspacePicker = false
    @Published var showTerminal = false
    @Published var showShortcuts = false
    @Published var alert: AppAlert?
    @Published var toasts: [ToastMessage] = []
    @Published var isRefreshing = false
    @Published var pendingDeleteSession: SessionInfo?
    @Published var showWorktreeSheet = false

    // Shell runner
    @Published var runnerCommand = ""
    @Published var runnerOutput = ""
    @Published var runnerRunning = false
    @Published var runnerHistory: [String] = []
    @Published var runnerTitle = "Shell"

    // Private tasks
    private var booted = false
    private var messageLoadGeneration = 0
    private var messageTask: Task<Void, Never>?
    private var refreshMessagesTask: Task<Void, Never>?
    private var refreshSessionsTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var runnerTask: Task<Void, Never>?
    private var runnerCursor: Int?
    private var runnerShellID: String?
    private var toastTasks: [UUID: Task<Void, Never>] = [:]
    private var terminateObserver: NSObjectProtocol?
    private var recoveryTask: Task<Void, Never>?
    private var isRecoveringConnection = false

    init(prefs: AppPreferences) {
        self.prefs = prefs
        self.selectedAgent = prefs.lastAgent
        self.showToolDetails = prefs.showToolDetails
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.shutdown() }
        }
    }

    // MARK: - Computed state

    var selectedSession: SessionInfo? {
        sessions.first { $0.id == selectedSessionID } ??
        archivedSessions.first { $0.id == selectedSessionID } ??
        sessionChildren.values.flatMap { $0 }.first { $0.id == selectedSessionID }
    }

    var selectedModelInfo: ModelInfo? {
        guard let selectedModel else { return nil }
        return models.first { $0.providerID == selectedModel.providerID && $0.modelID == selectedModel.id }
    }

    var selectedAgentInfo: AgentInfo? {
        agents.first { $0.id == selectedAgent }
    }

    var primaryAgents: [AgentInfo] {
        agents.filter { ($0.mode == "primary" || $0.mode == "all") && $0.hidden != true }
    }

    var availableModels: [ModelInfo] {
        models.filter { $0.enabled != false }
    }

    var isBusy: Bool {
        guard let selectedSessionID else { return false }
        return activeSessionIDs.contains(selectedSessionID)
    }

    var canChat: Bool { workspace != nil && api != nil }

    var recentProjects: [ProjectInfo] {
        func activity(_ project: ProjectInfo) -> Double {
            project.time?.active ?? project.time?.updated ?? 0
        }
        return projects.sorted { activity($0) > activity($1) }
    }

    var contextFraction: Double {
        guard let session = selectedSession,
              let tokens = session.tokens,
              let limit = selectedModelInfo?.contextWindow, limit > 0 else { return 0 }
        return min(1, (tokens.input + tokens.cache.read + tokens.output) / Double(limit))
    }

    var contextLabel: String {
        guard let session = selectedSession, let tokens = session.tokens else { return "No context usage yet" }
        let used = tokens.input + tokens.cache.read + tokens.cache.write
        if let limit = selectedModelInfo?.contextWindow {
            return "\(Format.tokens(used)) / \(Format.tokens(Double(limit))) context"
        }
        return "\(Format.tokens(used)) context tokens"
    }

    var workspaceRecentSessions: [SessionInfo] {
        let source = showArchived ? archivedSessions : sessions
        guard !sessionSearch.trimmingCharacters(in: .whitespaces).isEmpty else { return source }
        let query = sessionSearch.lowercased()
        return source.filter {
            $0.displayTitle.lowercased().contains(query) ||
            ($0.agent?.lowercased().contains(query) ?? false) ||
            ($0.model?.id.lowercased().contains(query) ?? false)
        }
    }

    var runnerIsVisible: Bool { showTerminal }

    // MARK: - Boot

    func boot(force: Bool = false) async {
        if booted && !force { return }
        if case .booting = phase { return }
        booted = true
        Diagnostics.log("AppModel boot mode=\(prefs.connectionMode.rawValue)")
        phase = .booting
        bootDetail = prefs.connectionMode == .local ? "Starting the local OpenCode engine…" : "Connecting to OpenCode…"
        stopEventStream()

        do {
            let connection = try await server.start(
                mode: prefs.connectionMode,
                binaryPath: prefs.binaryPath,
                remoteURL: prefs.remoteURL,
                remotePassword: prefs.remotePassword
            )
            Diagnostics.log("Server connection ready \(connection.baseURL)")
            serverInfo = connection.info
            let client = APIClient(
                baseURL: connection.baseURL,
                password: connection.password,
                directory: effectiveInitialDirectory()
            )
            api = client
            startEventStream(connection)
            bootDetail = "Loading workspace…"
            await loadProjects()
            Diagnostics.log("Projects loaded: \(projects.count)")
            phase = .ready
            await openInitialWorkspace()
            Diagnostics.log("Boot complete workspace=\(workspace?.directory ?? "nil") sessions=\(sessions.count) messages=\(messages.count)")
        } catch {
            Diagnostics.log("Boot failed: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            bootDetail = error.localizedDescription
        }
    }

    func restartServer() async {
        shutdown(keepModel: true)
        booted = false
        selectedSessionID = nil
        messages = []
        sessions = []
        archivedSessions = []
        phase = .idle
        await boot(force: true)
    }

    private func effectiveInitialDirectory() -> String? {
        if !prefs.lastWorkspace.isEmpty { return prefs.lastWorkspace }
        if let first = recentProjects.first?.canonical { return first }
        return workspace?.directory
    }

    private func openInitialWorkspace() async {
        var path = prefs.lastWorkspace
        if path.isEmpty || !FileManager.default.fileExists(atPath: path) {
            path = recentProjects.first?.canonical ?? NSHomeDirectory()
        }
        guard !path.isEmpty else { return }
        await openWorkspace(path: path, selectMostRecent: true)
    }

    func loadProjects() async {
        guard let api else { return }
        Diagnostics.log("Loading projects")
        do {
            projects = try await api.projects()
            Diagnostics.log("Projects request success")
        } catch {
            Diagnostics.log("Projects request failed: \(error.localizedDescription)")
            // Project listing can fail on a fresh install; workspace selection still works.
            projects = []
        }
    }

    // MARK: - Event stream

    private func startEventStream(_ connection: ServerConnection) {
        stopEventStream()
        let stream = OpenCodeEventStream(baseURL: connection.baseURL, password: connection.password)
        eventStream = stream
        eventConnection = .connecting
        stream.start(
            onEvent: { [weak self] event in
                Diagnostics.log("Event callback \(event.type)")
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            },
            onState: { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    Diagnostics.log("Event stream state: \(state)")
                    self.eventConnection = state
                    if case .reconnecting = state {
                        self.scheduleConnectionRecovery()
                    }
                }
            }
        )
    }

    private func stopEventStream() {
        eventStream?.stop()
        eventStream = nil
    }

    private func handle(_ event: OpenCodeEvent) {
        Diagnostics.log("AppModel handle \(event.type)")
        let sessionID = event.data["sessionID"]?.string
            ?? event.data["session"]?["id"]?.string
            ?? (event.data["id"]?.string?.hasPrefix("ses_") == true ? event.data["id"]?.string : nil)

        switch event.type {
        case "server.connected":
            eventConnection = .connected

        case "session.created", "session.updated", "session.deleted",
             "session.archived", "session.unarchived", "session.title.updated",
             "session.title.pending", "session.inbox.delivery.changed":
            scheduleSessionsRefresh()

        case "session.execution.started":
            if let sessionID {
                activeSessionIDs.insert(sessionID)
                if sessionID == selectedSessionID { scheduleMessageRefresh(after: 80_000_000) }
            }

        case "session.execution.succeeded":
            if let sessionID {
                activeSessionIDs.remove(sessionID)
                if sessionID == selectedSessionID {
                    scheduleMessageRefresh(after: 80_000_000)
                    Task { await refreshSelectedSession() }
                    announceCompletion()
                }
            }
            scheduleSessionsRefresh()

        case "session.execution.failed":
            if let sessionID {
                activeSessionIDs.remove(sessionID)
                if sessionID == selectedSessionID {
                    scheduleMessageRefresh(after: 80_000_000)
                    if let message = event.data["error"]?["message"]?.string {
                        showToast(message, icon: "exclamationmark.triangle.fill", tint: .ocDanger)
                    }
                }
            }
            scheduleSessionsRefresh()

        case "session.execution.interrupted":
            if let sessionID { activeSessionIDs.remove(sessionID) }
            scheduleMessageRefresh(after: 100_000_000)
            scheduleSessionsRefresh()

        case "session.text.delta", "session.text.started", "session.text.ended":
            applyStreamingEvent(event, sessionID: sessionID, block: .text)

        case "session.reasoning.delta", "session.reasoning.started", "session.reasoning.ended":
            applyStreamingEvent(event, sessionID: sessionID, block: .reasoning)

        case "session.step.started", "session.step.ended", "session.step.streamed", "session.step.failed":
            scheduleMessageRefresh(after: event.type == "session.step.started" ? 50_000_000 : 120_000_000)
            if event.type == "session.step.ended" { scheduleSessionsRefresh(after: 600_000_000) }

        case "session.tool.input.started", "session.tool.input.delta", "session.tool.input.ended",
             "session.tool.called", "session.tool.progress", "session.tool.success", "session.tool.failed":
            scheduleMessageRefresh(after: 70_000_000)

        case "session.inbox.enqueued", "session.inbox.delivered", "session.inbox.cancelled":
            scheduleMessageRefresh(after: 90_000_000)
            scheduleSessionsRefresh(after: 350_000_000)

        case "session.shell.started", "session.shell.ended":
            scheduleMessageRefresh(after: 100_000_000)

        case "session.compaction.started", "session.compaction.delta",
             "session.compaction.ended", "session.compaction.failed":
            scheduleMessageRefresh(after: 150_000_000)

        case "session.usage.updated":
            if sessionID == selectedSessionID, let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                if let cost = event.data["cost"]?.double { sessions[index].cost = cost }
                if let tokens = event.data["tokens"]?.decoded(TokenUsage.self) { sessions[index].tokens = tokens }
            }
            scheduleSessionsRefresh(after: 900_000_000)

        case "permission.asked":
            loadPendingApprovals()
            showToast("A tool needs your approval", icon: "hand.raised.fill", tint: .ocWarning)

        case "permission.replied", "permission.rejected":
            loadPendingApprovals()

        case "form.created":
            loadPendingForms()

        case "form.replied", "form.cancelled":
            loadPendingForms()

        default:
            break
        }
    }

    private enum StreamBlock { case text, reasoning }

    private func applyStreamingEvent(_ event: OpenCodeEvent, sessionID: String?, block: StreamBlock) {
        guard let sessionID, sessionID == selectedSessionID,
              let messageID = event.data["assistantMessageID"]?.string else { return }
        let ordinal = event.data["ordinal"]?.int ?? 0
        let suffix = block == .text ? "text" : "reasoning"
        let blockID = "\(messageID):\(suffix):\(ordinal)"
        let delta = event.data["delta"]?.string ?? event.data["text"]?.string ?? ""
        let ended = event.type.hasSuffix(".ended")

        guard let messageIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            scheduleMessageRefresh(after: 60_000_000)
            return
        }

        if let blockIndex = messages[messageIndex].blocks.firstIndex(where: { $0.id == blockID }) {
            if ended {
                messages[messageIndex].blocks[blockIndex].text = event.data["text"]?.string ?? messages[messageIndex].blocks[blockIndex].text
            } else if !delta.isEmpty {
                messages[messageIndex].blocks[blockIndex].text += delta
            }
            if ended, block == .reasoning {
                messages[messageIndex].blocks[blockIndex].reasoningCompleted = event.created
            }
        } else {
            var newBlock = MessageBlock(id: blockID, kind: block == .text ? .text : .reasoning, text: delta)
            if block == .reasoning {
                newBlock.reasoningStarted = event.created
                if ended { newBlock.reasoningCompleted = event.created }
            }
            messages[messageIndex].blocks.append(newBlock)
        }
        messages[messageIndex].isStreaming = !ended
    }

    private func scheduleMessageRefresh(after delay: UInt64 = 90_000_000) {
        refreshMessagesTask?.cancel()
        refreshMessagesTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshMessages()
        }
    }

    private func scheduleSessionsRefresh(after delay: UInt64 = 250_000_000) {
        refreshSessionsTask?.cancel()
        refreshSessionsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.loadSessions()
        }
    }

    // MARK: - Workspace

    func openWorkspace(path: String, selectMostRecent: Bool = true) async {
        let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: standardized) else {
            presentError("That folder could not be found.", title: "Workspace unavailable")
            return
        }
        Diagnostics.log("Opening workspace \(standardized)")
        let project = projects.first {
            URL(fileURLWithPath: $0.canonical).standardizedFileURL.path == standardized
        }
        workspace = Workspace(directory: standardized, project: project)
        prefs.recordWorkspace(standardized)
        api?.directory = standardized
        showWorkspacePicker = false
        showQuickOpen = false
        selectedSessionID = nil
        messages = []
        sessionDiffs = []
        vcsDiffs = []
        vcsStatus = []
        selectedFilePath = nil
        selectedFileText = nil
        stopRunner()
        runnerOutput = ""

        Diagnostics.log("Workspace set, loading catalog")
        await loadCatalog()
        Diagnostics.log("Catalog loaded models=\(models.count) agents=\(agents.count)")
        await loadSessions()
        Diagnostics.log("Sessions loaded \(sessions.count)")
        await refreshWorkspaceMetadata()
        Diagnostics.log("Workspace metadata loaded")
        if selectMostRecent, let session = sessions.first(where: { $0.id == prefs.lastSessionID }) ?? sessions.first {
            selectSession(session)
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Open a project"
        panel.prompt = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspace?.url ?? URL(fileURLWithPath: prefs.lastWorkspace.isEmpty ? NSHomeDirectory() : prefs.lastWorkspace)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task { await self.openWorkspace(path: url.path) }
        }
    }

    func revealWorkspaceInFinder() {
        guard let workspace else { return }
        NSWorkspace.shared.activateFileViewerSelecting([workspace.url])
    }

    func openWorkspaceInTerminal() {
        guard let workspace else { return }
        NSWorkspace.shared.open(workspace.url)
    }

    // MARK: - Catalog

    func loadCatalog() async {
        guard let api else { return }
        Diagnostics.log("Catalog: models start")
        do { models = try await api.models() } catch { Diagnostics.log("models error \(error.localizedDescription)") }
        Diagnostics.log("Catalog: models done \(models.count)")
        do { defaultModel = try await api.defaultModel() } catch { }
        do { providers = try await api.providers() } catch { }
        do { agents = try await api.agents() } catch { }
        do { commands = try await api.commands() } catch { }
        do { skills = try await api.skills() } catch { }

        if selectedModel == nil {
            selectedModel = ModelRef.parse(prefs.lastModelKey)
                ?? selectedSession?.model
                ?? defaultModel?.ref
                ?? availableModels.first?.ref
        }
        if selectedModel != nil,
           let ref = selectedModel,
           !models.contains(where: { $0.providerID == ref.providerID && $0.modelID == ref.id }) {
            selectedModel = defaultModel?.ref ?? availableModels.first?.ref
        }

        let requestedAgent = prefs.lastAgent.isEmpty ? selectedAgent : prefs.lastAgent
        if agents.contains(where: { $0.id == requestedAgent }) {
            selectedAgent = requestedAgent
        } else if !agents.contains(where: { $0.id == selectedAgent }) {
            selectedAgent = primaryAgents.first?.id ?? "build"
        }
    }

    // MARK: - Sessions

    /// Child (subagent) sessions of a session, oldest first.
    func children(of sessionID: String) -> [SessionInfo] {
        (sessionChildren[sessionID] ?? []).sorted { $0.time.created < $1.time.created }
    }

    func loadSessions() async {
        guard let api, let workspace else { return }
        do {
            // Fetch every session (roots and children) and split them so
            // subagent sessions stay nested under their parent in the sidebar.
            let fresh = try await api.sessions(archived: false, topLevel: false)
            let inWorkspace = fresh.filter {
                $0.location?.directory == workspace.directory || $0.location == nil
            }
            sessions = inWorkspace.filter { $0.parentID == nil }
            sessionChildren = Dictionary(
                grouping: inWorkspace.filter { $0.parentID != nil },
                by: { $0.parentID! }
            )
        } catch {
            // Don't flash errors during transient reconnects.
            return
        }
        if showArchived {
            do {
                archivedSessions = try await api.sessions(archived: true, topLevel: true)
                    .filter { $0.location?.directory == workspace.directory || $0.location == nil }
            } catch { archivedSessions = [] }
        }
        do {
            let active = try await api.activeSessions()
            activeSessionIDs = Set(active.keys)
        } catch { }
    }

    func selectSession(_ session: SessionInfo) {
        guard selectedSessionID != session.id else { return }
        Diagnostics.log("Selecting session \(session.id)")
        selectedSessionID = session.id
        prefs.lastSessionID = session.id
        selectedModel = session.model ?? selectedModel
        if let agent = session.agent { selectedAgent = agent }
        messages = []
        pendingPermissions = []
        pendingForms = []
        sessionDiffs = []
        selectedFilePath = nil
        selectedFileText = nil
        if let model = selectedModel {
            prefs.lastModelKey = model.key
        }
        prefs.lastAgent = selectedAgent

        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshMessages()
            await self.refreshSelectedSession()
            await self.refreshChanges()
            self.loadPendingApprovals()
            self.loadPendingForms()
        }
    }

    func newSession() async {
        guard let api, workspace != nil else {
            chooseWorkspace()
            return
        }
        do {
            let session = try await api.createSession(
                title: nil,
                model: selectedModel,
                agent: selectedAgent
            )
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            prefs.lastSessionID = session.id
            messages = []
            sessionDiffs = []
            pendingPermissions = []
            pendingForms = []
            selectedFilePath = nil
            selectedFileText = nil
            if let model = session.model { selectedModel = model }
            if let agent = session.agent { selectedAgent = agent }
            showToast("New session ready", icon: "plus.bubble.fill", tint: .ocTeal)
            scheduleSessionsRefresh(after: 600_000_000)
        } catch {
            presentError(error)
        }
    }

    func refreshSelectedSession() async {
        guard let api, let id = selectedSessionID else { return }
        do {
            let session = try await api.session(id)
            if let index = sessions.firstIndex(where: { $0.id == id }) {
                sessions[index] = session
            } else if let index = archivedSessions.firstIndex(where: { $0.id == id }) {
                archivedSessions[index] = session
            }
            if let model = session.model, selectedModel == nil { selectedModel = model }
        } catch { }
    }

    func refreshMessages() async {
        guard let api, let id = selectedSessionID else {
            messages = []
            return
        }
        messageLoadGeneration += 1
        let generation = messageLoadGeneration
        if messages.isEmpty { isLoadingMessages = true }
        do {
            let loaded = try await api.messages(sessionID: id)
            Diagnostics.log("Loaded \(loaded.count) messages for \(id)")
            guard generation == messageLoadGeneration, selectedSessionID == id else { return }
            let wasAtEnd = messages.isEmpty || messages.last?.isStreaming == true
            messages = loaded
            if wasAtEnd, let last = messages.last, last.kind == .idle {
                activeSessionIDs.remove(id)
            }
            isLoadingMessages = false
        } catch {
            guard generation == messageLoadGeneration else { return }
            isLoadingMessages = false
        }
    }

    func renameSession(_ session: SessionInfo, title: String) async {
        guard let api else { return }
        do {
            let updated = try await api.updateSession(session.id, title: title)
            if let index = sessions.firstIndex(where: { $0.id == session.id }) { sessions[index] = updated }
            if let index = archivedSessions.firstIndex(where: { $0.id == session.id }) { archivedSessions[index] = updated }
            showToast("Session renamed", icon: "pencil.circle.fill", tint: .ocTeal)
        } catch { presentError(error) }
    }

    func archiveSession(_ session: SessionInfo) async {
        guard let api else { return }
        do {
            _ = try await api.updateSession(session.id, archived: true)
            sessions.removeAll { $0.id == session.id }
            archivedSessions.insert(session, at: 0)
            if selectedSessionID == session.id {
                selectedSessionID = nil
                messages = []
                sessionDiffs = []
                if let next = sessions.first { selectSession(next) }
            }
            showToast("Session archived", icon: "archivebox.fill", tint: .ocTextSecondary)
        } catch { presentError(error) }
    }

    func deleteSession(_ session: SessionInfo) async {
        guard let api else { return }
        do {
            try await api.deleteSession(session.id)
            sessions.removeAll { $0.id == session.id }
            archivedSessions.removeAll { $0.id == session.id }
            if selectedSessionID == session.id {
                selectedSessionID = nil
                messages = []
                sessionDiffs = []
                selectedFilePath = nil
                selectedFileText = nil
                if let next = sessions.first { selectSession(next) }
            }
            showToast("Session deleted", icon: "trash.fill", tint: .ocDanger)
        } catch { presentError(error) }
    }

    func forkSession(_ session: SessionInfo, before messageID: String? = nil) async {
        guard let api else { return }
        do {
            let forked = try await api.forkSession(session.id, before: messageID)
            sessions.insert(forked, at: 0)
            selectSession(forked)
            showToast("Session forked", icon: "arrow.triangle.branch", tint: .ocViolet)
        } catch { presentError(error) }
    }

    func copySessionID() {
        guard let id = selectedSessionID else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        showToast("Session ID copied", icon: "doc.on.doc.fill", tint: .ocTeal)
    }

    func toggleArchived() async {
        showArchived.toggle()
        if showArchived { await loadSessions() }
    }

    // MARK: - Sending

    func sendMessage(_ text: String, files: [PromptAttachment] = [], shellMode: Bool = false) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let api else {
            presentError("OpenCode is not connected yet.", title: "Not connected")
            return
        }
        guard let sessionID = await ensureSession() else { return }

        isSending = true
        defer { isSending = false }

        do {
            if shellMode {
                _ = try await api.runShell(sessionID: sessionID, command: trimmed)
                runnerHistory.removeAll { $0 == trimmed }
                runnerHistory.insert(trimmed, at: 0)
                activeSessionIDs.insert(sessionID)
                scheduleMessageRefresh(after: 120_000_000)
                return
            }

            if let commandName = commandName(in: trimmed), commands.contains(where: { $0.name == commandName }) {
                let arguments = String(trimmed.dropFirst(commandName.count + 1)).trimmingCharacters(in: .whitespaces)
                _ = try await api.runCommand(sessionID: sessionID, name: commandName, text: arguments, files: files)
            } else {
                let response = try await api.prompt(
                    sessionID: sessionID,
                    text: trimmed,
                    files: files,
                    delivery: delivery
                )
                appendOptimisticUserMessage(text: trimmed, files: files, response: response, sessionID: sessionID)
            }
            activeSessionIDs.insert(sessionID)
            scheduleMessageRefresh(after: 120_000_000)
            scheduleSessionsRefresh(after: 400_000_000)
        } catch {
            activeSessionIDs.remove(sessionID)
            presentError(error)
        }
    }

    private func ensureSession() async -> String? {
        if let selectedSessionID { return selectedSessionID }
        guard let api else { return nil }
        do {
            let session = try await api.createSession(title: nil, model: selectedModel, agent: selectedAgent)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            if let model = session.model { selectedModel = model }
            if let agent = session.agent { selectedAgent = agent }
            return session.id
        } catch {
            presentError(error)
            return nil
        }
    }

    private func appendOptimisticUserMessage(
        text: String,
        files: [PromptAttachment],
        response: JSONValue,
        sessionID: String
    ) {
        let data = response["data"] ?? response
        let id = data["id"]?.string ?? "local-\(UUID().uuidString)"
        guard !messages.contains(where: { $0.id == id }) else { return }
        let message = ChatMessage(
            id: id,
            kind: .user,
            createdAt: Date(),
            completedAt: nil,
            userText: text,
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
            attachments: files,
            isStreaming: false
        )
        messages.append(message)
    }

    private func commandName(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let first = text.dropFirst().split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        return first.isEmpty ? nil : first
    }

    func stopGeneration() async {
        guard let api, let id = selectedSessionID else { return }
        do {
            _ = try await api.interrupt(sessionID: id, resume: false)
            activeSessionIDs.remove(id)
            showToast("Stopped", icon: "stop.circle.fill", tint: .ocWarning)
            scheduleMessageRefresh(after: 300_000_000)
        } catch { presentError(error) }
    }

    func compactSession() async {
        guard let api, let id = selectedSessionID else { return }
        do {
            try await api.compact(sessionID: id)
            showToast("Compacting context…", icon: "arrow.down.right.and.arrow.up.left", tint: .ocViolet)
        } catch { presentError(error) }
    }

    func selectModel(_ model: ModelInfo, variant: String? = nil) async {
        let ref = ModelRef(id: model.modelID, providerID: model.providerID, variant: variant)
        selectedModel = ref
        prefs.lastModelKey = ref.key
        if let id = selectedSessionID, let api {
            do {
                try await api.switchModel(sessionID: id, model: ref)
                if let index = sessions.firstIndex(where: { $0.id == id }) {
                    sessions[index].model = ref
                }
                showToast("Using \(model.displayName)", icon: "cpu.fill", tint: .ocTeal)
            } catch { presentError(error) }
        }
    }

    func selectAgent(_ agent: AgentInfo) async {
        selectedAgent = agent.id
        prefs.lastAgent = agent.id
        if let id = selectedSessionID, let api {
            do {
                try await api.switchAgent(sessionID: id, agent: agent.id)
                if let index = sessions.firstIndex(where: { $0.id == id }) {
                    sessions[index].agent = agent.id
                }
                showToast("\(agent.name) agent active", icon: "person.crop.circle.badge.checkmark", tint: .ocTeal)
            } catch { presentError(error) }
        }
    }

    // MARK: - Approvals & forms

    func loadPendingApprovals() {
        guard let api, let id = selectedSessionID else {
            pendingPermissions = []
            return
        }
        Task {
            do {
                pendingPermissions = try await api.permissions(sessionID: id)
            } catch { }
        }
    }

    func replyPermission(_ request: PermissionRequest, decision: String) async {
        guard let api else { return }
        do {
            try await api.replyPermission(sessionID: request.sessionID, requestID: request.id, decision: decision)
            pendingPermissions.removeAll { $0.id == request.id }
            showToast(
                decision == "reject" ? "Permission rejected" : "Permission granted",
                icon: decision == "reject" ? "xmark.shield.fill" : "checkmark.shield.fill",
                tint: decision == "reject" ? .ocDanger : .ocSuccess
            )
        } catch { presentError(error) }
    }

    func loadPendingForms() {
        guard let api, let id = selectedSessionID else {
            pendingForms = []
            return
        }
        Task {
            do { pendingForms = try await api.forms(sessionID: id) } catch { }
        }
    }

    func replyForm(_ form: FormInfo, answer: [String: JSONValue]) async {
        guard let api else { return }
        do {
            try await api.replyForm(sessionID: form.sessionID, formID: form.id, answer: answer)
            pendingForms.removeAll { $0.id == form.id }
            showToast("Answer sent", icon: "checkmark.bubble.fill", tint: .ocTeal)
        } catch { presentError(error) }
    }

    func cancelForm(_ form: FormInfo) async {
        guard let api else { return }
        do {
            try await api.cancelForm(sessionID: form.sessionID, formID: form.id)
            pendingForms.removeAll { $0.id == form.id }
        } catch { presentError(error) }
    }

    // MARK: - Revert & changes

    func revert(to message: ChatMessage) async {
        guard let api, let id = selectedSessionID else { return }
        do {
            _ = try await api.stageRevert(sessionID: id, messageID: message.id, files: true)
            try await api.commitRevert(sessionID: id)
            await refreshMessages()
            await refreshChanges()
            showToast("Reverted to earlier turn", icon: "arrow.uturn.backward.circle.fill", tint: .ocWarning)
        } catch { presentError(error) }
    }

    func refreshChanges() async {
        guard let api else { return }
        if let id = selectedSessionID {
            do { sessionDiffs = try await api.sessionDiff(sessionID: id) } catch { sessionDiffs = [] }
        } else {
            sessionDiffs = []
        }
        do { vcsStatus = try await api.vcsStatus() } catch { vcsStatus = [] }
        do { vcsDiffs = try await api.vcsDiff(mode: "working") } catch { vcsDiffs = [] }
        do { vcsInfo = try await api.vcsInfo() } catch { vcsInfo = nil }
    }

    func refreshWorkspaceMetadata() async {
        guard let api else { return }
        await refreshChanges()
        do { worktrees = try await api.worktrees(projectID: workspace?.project?.id ?? "") } catch { worktrees = [] }
    }

    func initGit() async {
        guard let api else { return }
        do {
            try await api.initVcs()
            await refreshChanges()
            showToast("Git repository initialized", icon: "arrow.triangle.branch", tint: .ocTeal)
        } catch { presentError(error) }
    }

    // MARK: - Files

    func loadFile(_ path: String) async {
        guard let api else { return }
        selectedFilePath = path
        selectedFileText = nil
        selectedFileIsBinary = false
        filePreviewLoading = true
        prefs.inspectorSection = .files
        prefs.showInspector = true
        do {
            let data = try await api.readFile(path: path)
            selectedFileSize = data.count
            if let text = String(data: data, encoding: .utf8) {
                selectedFileText = text
            } else {
                selectedFileText = "Binary file · \(Format.bytes(data.count))"
                selectedFileIsBinary = true
            }
        } catch {
            selectedFileText = "Could not read file: \(error.localizedDescription)"
            selectedFileIsBinary = false
        }
        filePreviewLoading = false
    }

    func openSelectedFileExternally() {
        guard let workspace, let path = selectedFilePath else { return }
        let url = workspace.url.appendingPathComponent(path)
        NSWorkspace.shared.open(url)
    }

    func revealSelectedFile() {
        guard let workspace, let path = selectedFilePath else { return }
        let url = workspace.url.appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func searchFiles(_ query: String) async -> [FileSystemEntry] {
        guard let api, !query.isEmpty else { return [] }
        do { return try await api.findFiles(query, limit: 30) } catch { return [] }
    }

    func listWorkspaceFiles(_ path: String) async -> [FileSystemEntry] {
        guard let api else { return [] }
        do {
            let entries = try await api.listFiles(path: path)
            return entries.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }

    func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Copied to clipboard", icon: "doc.on.doc.fill", tint: .ocTeal)
    }

    // MARK: - Settings data

    func refreshSettingsData() async {
        guard let api else { return }
        settingsLoading = true
        defer { settingsLoading = false }
        do { integrations = try await api.integrations() } catch { }
        do { credentials = try await api.credentials() } catch { }
        do { mcpServers = try await api.mcpServers() } catch { }
        do { plugins = try await api.plugins() } catch { }
        do { configEntries = try await api.configEntries() } catch { }
        do { shellOptions = try await api.shellOptions() } catch { }
    }

    func connectIntegration(_ integration: IntegrationInfo, method: IntegrationMethod, key: String, answer: [String: JSONValue]) async {
        guard let api else { return }
        do {
            if method.type == "key" {
                try await api.connectIntegrationKey(integration.id, key: key, answer: answer.isEmpty ? nil : answer)
            } else {
                try await api.connectIntegrationExternal(integration.id, methodID: method.id ?? method.type, answer: answer.isEmpty ? nil : answer)
            }
            await refreshSettingsData()
            await loadCatalog()
            showToast("\(integration.name) connected", icon: "link.circle.fill", tint: .ocSuccess)
        } catch { presentError(error) }
    }

    func removeCredential(_ credential: CredentialEntry) async {
        guard let api else { return }
        do {
            try await api.removeCredential(credential.id)
            await refreshSettingsData()
            await loadCatalog()
            showToast("Credential removed", icon: "minus.circle.fill", tint: .ocTextSecondary)
        } catch { presentError(error) }
    }

    func toggleMcp(_ server: McpServer) async {
        guard let api else { return }
        do {
            if server.statusName == "connected" {
                try await api.disconnectMcp(server.name)
            } else {
                try await api.connectMcp(server.name)
            }
            await refreshSettingsData()
        } catch { presentError(error) }
    }

    func addMcp(name: String, type: String, command: String, url: String) async {
        guard let api else { return }
        let config: JSONValue
        if type == "local" {
            config = .object([
                "type": .string("local"),
                "command": .array(command.split(separator: " ").map { .string(String($0)) })
            ])
        } else {
            config = .object(["type": .string("remote"), "url": .string(url)])
        }
        do {
            try await api.addMcp(name: name, config: config)
            await refreshSettingsData()
            showToast("MCP server added", icon: "server.rack", tint: .ocTeal)
        } catch { presentError(error) }
    }

    func removeMcp(_ server: McpServer) async {
        guard let api else { return }
        do {
            try await api.removeMcp(server.name)
            await refreshSettingsData()
        } catch { presentError(error) }
    }

    func checkPluginUpdates() async {
        guard let api else { return }
        do {
            plugins = try await api.checkPlugins()
            showToast("Plugins checked", icon: "arrow.triangle.2.circlepath", tint: .ocTeal)
        } catch { presentError(error) }
    }

    func reloadConfiguration() async {
        guard let api else { return }
        do {
            try await api.reloadLocation()
            await loadCatalog()
            await refreshSettingsData()
            showToast("Configuration reloaded", icon: "arrow.clockwise.circle.fill", tint: .ocTeal)
        } catch { presentError(error) }
    }

    func openConfigFile() {
        if let document = configEntries.first(where: { $0["type"]?.string == "document" }),
           let path = document["path"]?.string {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            showToast("No config document found", icon: "doc.questionmark", tint: .ocWarning)
        }
    }

    func setShell(_ path: String) async {
        guard let api else { return }
        do {
            try await api.setShell(path)
            showToast("Shell updated", icon: "terminal.fill", tint: .ocTeal)
        } catch { presentError(error) }
    }

    // MARK: - Stats & worktrees

    func loadStats() async {
        guard let api else { return }
        do {
            stats = try await api.stats(projectID: workspace?.project?.id)
        } catch { presentError(error) }
    }

    func loadWorktrees() async {
        guard let api, let projectID = workspace?.project?.id else { return }
        do { worktrees = try await api.worktrees(projectID: projectID) } catch { worktrees = [] }
    }

    func createWorktree(name: String) async {
        guard let api, let projectID = workspace?.project?.id else { return }
        do {
            let tree = try await api.createWorktree(projectID: projectID, name: name)
            worktrees.append(tree)
            await openWorkspace(path: tree.directory)
            showToast("Worktree created", icon: "arrow.triangle.branch", tint: .ocViolet)
        } catch { presentError(error) }
    }

    // MARK: - Exports

    func exportCurrentSession() {
        guard let api, let id = selectedSessionID else { return }
        Task {
            do {
                let value = try await api.exportSession(id)
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                let safeTitle = (selectedSession?.displayTitle ?? "session")
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                panel.nameFieldStringValue = "\(safeTitle).json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(value).write(to: url)
                showToast("Session exported", icon: "square.and.arrow.up.fill", tint: .ocTeal)
            } catch { presentError(error) }
        }
    }

    func importSession() {
        guard let api else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let data = try Data(contentsOf: url)
                let value = try JSONValue.fromData(data)
                let imported = try await api.importSession(value)
                await loadSessions()
                if let session = sessions.first(where: { $0.id == imported.id }) {
                    selectSession(session)
                }
                showToast("Session imported", icon: "square.and.arrow.down.fill", tint: .ocTeal)
            } catch { presentError(error) }
        }
    }

    // MARK: - Runner

    func runRunnerCommand(_ command: String? = nil) async {
        let value = (command ?? runnerCommand).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let api, let workspace else { return }
        runnerCommand = ""
        runnerOutput = ""
        runnerRunning = true
        runnerCursor = nil
        runnerTitle = value
        runnerHistory.removeAll { $0 == value }
        runnerHistory.insert(value, at: 0)
        runnerHistory = Array(runnerHistory.prefix(30))

        do {
            let shell = try await api.createShell(command: value, cwd: workspace.directory, timeout: nil)
            runnerShellID = shell.id
            runnerTask?.cancel()
            runnerTask = Task { [weak self] in
                guard let self else { return }
                var cursor: Int?
                while !Task.isCancelled {
                    do {
                        let output = try await api.shellOutput(id: shell.id, cursor: cursor)
                        cursor = output.cursor
                        if !output.output.isEmpty {
                            self.runnerOutput += output.output
                            if self.runnerOutput.count > 400_000 {
                                self.runnerOutput = String(self.runnerOutput.suffix(300_000))
                            }
                        }
                        let info = try await api.shell(id: shell.id)
                        if !info.isRunning {
                            self.runnerRunning = false
                            if let exit = info.exit {
                                self.runnerOutput += "\n\n[process exited \(Int(exit))]"
                            } else {
                                self.runnerOutput += "\n\n[process \(info.status)]"
                            }
                            break
                        }
                    } catch {
                        self.runnerRunning = false
                        self.runnerOutput += "\n\n[\(error.localizedDescription)]"
                        break
                    }
                    try? await Task.sleep(nanoseconds: 320_000_000)
                }
            }
        } catch {
            runnerRunning = false
            presentError(error)
        }
    }

    func stopRunner() {
        runnerTask?.cancel()
        runnerTask = nil
        if let id = runnerShellID, let api {
            Task { try? await api.removeShell(id: id) }
        }
        runnerShellID = nil
        runnerRunning = false
    }

    func clearRunner() {
        runnerOutput = ""
    }

    // MARK: - UI helpers

    func showToast(_ text: String, icon: String = "checkmark.circle.fill", tint: Color = .ocSuccess) {
        _ = tint
        let toast = ToastMessage(text: text, icon: icon)
        withAnimation(Motion.smooth) { toasts.append(toast) }
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                withAnimation(Motion.gentle) { self.toasts.removeAll { $0.id == toast.id } }
                self.toastTasks[toast.id] = nil
            }
        }
        toastTasks[toast.id] = task
    }

    func presentError(_ error: Error, title: String = "OpenCode error") {
        alert = AppAlert(title: title, message: error.localizedDescription, isError: true)
    }

    func presentError(_ message: String, title: String = "OpenCode error") {
        alert = AppAlert(title: title, message: message, isError: true)
    }

    func refreshEverything() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await loadProjects()
        await loadCatalog()
        await loadSessions()
        await refreshMessages()
        await refreshSelectedSession()
        await refreshWorkspaceMetadata()
    }

    func announceCompletion() {
        guard prefs.completionSound else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
        if prefs.notificationsEnabled, !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    // MARK: - Connection recovery

    private func scheduleConnectionRecovery() {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            guard case .reconnecting = self.eventConnection else { return }
            await self.recoverConnection()
        }
    }

    private func recoverConnection() async {
        guard !isRecoveringConnection else { return }
        isRecoveringConnection = true
        defer { isRecoveringConnection = false }

        if let api {
            do {
                _ = try await api.serverInfo()
                // The server is healthy; let the event stream reconnect on its own.
                return
            } catch {
                Diagnostics.log("Existing server connection is stale: \(error.localizedDescription)")
            }
        }

        Diagnostics.log("Re-resolving OpenCode service connection")
        stopEventStream()
        do {
            let connection = try await server.start(
                mode: prefs.connectionMode,
                binaryPath: prefs.binaryPath,
                remoteURL: prefs.remoteURL,
                remotePassword: prefs.remotePassword
            )
            serverInfo = connection.info
            let client = APIClient(
                baseURL: connection.baseURL,
                password: connection.password,
                directory: workspace?.directory ?? prefs.lastWorkspace
            )
            api = client
            startEventStream(connection)
            phase = .ready
            await loadProjects()
            if let workspace {
                client.directory = workspace.directory
                await loadCatalog()
                await loadSessions()
                await refreshMessages()
                await refreshSelectedSession()
            }
            showToast("Reconnected to OpenCode", icon: "bolt.horizontal.circle.fill", tint: .ocTeal)
        } catch {
            Diagnostics.log("Connection recovery failed: \(error.localizedDescription)")
            eventConnection = .reconnecting(error.localizedDescription)
            scheduleConnectionRecovery()
        }
    }

    func shutdown(keepModel: Bool = false) {
        recoveryTask?.cancel()
        stopEventStream()
        runnerTask?.cancel()
        refreshMessagesTask?.cancel()
        refreshSessionsTask?.cancel()
        selectionTask?.cancel()
        server.stop()
    }
}
