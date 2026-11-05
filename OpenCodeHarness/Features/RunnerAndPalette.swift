import AppKit
import SwiftUI

struct RunnerPanelView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ocTeal)
                Text("SHELL")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
                Text(model.runnerTitle == "Shell" ? "project shell" : model.runnerTitle)
                    .font(.ocMono(9.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .lineLimit(1)
                if model.runnerRunning {
                    Spinner(size: 9, tint: .ocTeal)
                }
                Spacer()
                Menu {
                    if model.runnerHistory.isEmpty {
                        Text("No history yet")
                    }
                    ForEach(model.runnerHistory.prefix(15), id: \.self) { command in
                        Button(command) {
                            model.runnerCommand = command
                            Task { await model.runRunnerCommand() }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(Color.ocTextTertiary)
                IconButton(systemImage: "trash", help: "Clear output", size: 22) {
                    model.clearRunner()
                }
                if model.runnerRunning {
                    IconButton(systemImage: "stop.fill", help: "Stop command", size: 22, tint: .ocDanger) {
                        model.stopRunner()
                    }
                }
                IconButton(systemImage: "xmark", help: "Close shell", size: 22) {
                    withAnimation(Motion.smooth) { model.showTerminal = false }
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.ocSurface.opacity(0.8))

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(cleanedOutput.isEmpty ? "Run a command in the project. Output streams here." : cleanedOutput)
                        .font(.ocMono(10.5))
                        .foregroundStyle(cleanedOutput.isEmpty ? Color.ocTextTertiary : Color.ocTextSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("output")
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.runnerOutput) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("output", anchor: .bottom)
                    }
                }
            }
            .frame(height: 196)
            .background(Color.ocCodeBackground)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            HStack(spacing: 8) {
                Text("$")
                    .font(.ocMono(12, weight: .bold))
                    .foregroundStyle(Color.ocTeal)
                TextField("Run a command…", text: $model.runnerCommand)
                    .textFieldStyle(.plain)
                    .font(.ocMono(11))
                    .focused($focused)
                    .onSubmit {
                        Task { await model.runRunnerCommand() }
                    }
                if model.runnerRunning {
                    Spinner(size: 10, tint: .ocTeal)
                } else {
                    Button {
                        Task { await model.runRunnerCommand() }
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.ocTextTertiary)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.ocHover))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.runnerCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.ocSurface.opacity(0.8))
        }
        .background(Color.ocSurface.opacity(0.3))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.ocBorder).frame(height: 1)
        }
        .onAppear { focused = true }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var cleanedOutput: String {
        model.runnerOutput
            .replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

// MARK: - Command palette

struct PaletteAction: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var icon: String
    var section: String
    var keywords: String = ""
    var destructive: Bool = false
    var action: () -> Void
}

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var allActions: [PaletteAction] { buildActions() }

    private var filtered: [PaletteAction] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return allActions }
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return allActions.filter { action in
            let haystack = (action.title + " " + action.subtitle + " " + action.keywords + " " + action.section).lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private var sections: [(String, [PaletteAction])] {
        var order: [String] = []
        var map: [String: [PaletteAction]] = [:]
        for action in filtered {
            if map[action.section] == nil {
                order.append(action.section)
                map[action.section] = []
            }
            map[action.section]?.append(action)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ocAccent)
                TextField("Type a command or search…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { runSelected() }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ocTextTertiary)
                }
                KeyCap(text: "ESC")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections, id: \.0) { section, actions in
                            Section {
                                ForEach(actions) { action in
                                    actionRow(action)
                                        .id(action.id)
                                }
                            } header: {
                                Text(section.uppercased())
                                    .font(.ocMono(8.5, weight: .semibold))
                                    .tracking(1.1)
                                    .foregroundStyle(Color.ocTextTertiary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 9)
                                    .padding(.bottom, 3)
                            }
                        }
                        if filtered.isEmpty {
                            Text("No matching commands")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ocTextTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 50)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: selected) { _, value in
                    if let action = filtered[safe: value] {
                        withAnimation(Motion.quick) { proxy.scrollTo(action.id, anchor: .center) }
                    }
                }
            }
            .frame(maxHeight: 440)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
            HStack(spacing: 12) {
                Text("↑↓ navigate")
                Text("↩ run")
                Text("⌘K toggle")
                Spacer()
                Text("\(filtered.count) results")
            }
            .font(.ocMono(8.5))
            .foregroundStyle(Color.ocTextTertiary)
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .frame(width: 650, height: 540)
        .background(.regularMaterial)
        .background(Color.ocCanvas.opacity(0.92))
        .onAppear {
            focused = true
            selected = 0
        }
        .onChange(of: query) { _, _ in selected = 0 }
        .onKeyPress(.downArrow) {
            if selected < filtered.count - 1 { selected += 1 }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selected > 0 { selected -= 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    private func actionRow(_ action: PaletteAction) -> some View {
        let isSelected = filtered[safe: selected]?.id == action.id
        return Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                action.action()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(action.destructive ? Color.ocDanger : Color.ocAccent)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill((action.destructive ? Color.ocDanger : Color.ocAccent).opacity(0.09))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(action.destructive ? Color.ocDanger : Color.ocTextPrimary)
                    Text(action.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ocTextTertiary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.ocTextTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.ocAccent.opacity(0.11) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            if hovering, let index = filtered.firstIndex(where: { $0.id == action.id }) {
                selected = index
            }
        }
    }

    private func runSelected() {
        guard let action = filtered[safe: selected] else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            action.action()
        }
    }

    private func buildActions() -> [PaletteAction] {
        var actions: [PaletteAction] = [
            PaletteAction(id: "new-session", title: "New Session", subtitle: "Start a fresh conversation in this project", icon: "plus.bubble", section: "Session") {
                Task { await model.newSession() }
            },
            PaletteAction(id: "open-project", title: "Open Project…", subtitle: "Switch the OpenCode location", icon: "folder.badge.plus", section: "Workspace") {
                model.chooseWorkspace()
            },
            PaletteAction(id: "all-projects", title: "Browse Projects", subtitle: "Choose from recent OpenCode projects", icon: "square.grid.2x2", section: "Workspace") {
                model.showWorkspacePicker = true
            },
            PaletteAction(id: "toggle-inspector", title: "Toggle Inspector", subtitle: "Files, changes, and session details", icon: "sidebar.right", section: "View", keywords: "sidebar panel") {
                withAnimation(Motion.smooth) { model.prefs.showInspector.toggle() }
            },
            PaletteAction(id: "toggle-shell", title: "Toggle Shell", subtitle: "Run commands against the project", icon: "terminal", section: "View") {
                withAnimation(Motion.smooth) { model.showTerminal.toggle() }
            },
            PaletteAction(id: "stats", title: "Usage Statistics", subtitle: "Tokens, sessions, and tool activity", icon: "chart.bar.xaxis", section: "View") {
                model.showStats = true
                Task { await model.loadStats() }
            },
            PaletteAction(id: "reload", title: "Reload Configuration", subtitle: "Re-read opencode.json and plugins", icon: "arrow.clockwise.circle", section: "Engine") {
                Task { await model.reloadConfiguration() }
            },
            PaletteAction(id: "restart", title: "Reconnect Engine", subtitle: "Reconnect to the local OpenCode server", icon: "power", section: "Engine") {
                Task { await model.restartServer() }
            },
            PaletteAction(id: "settings", title: "Open Settings", subtitle: "Connection, providers, MCP, plugins", icon: "gearshape", section: "Engine") {
                openSettings()
            },
            PaletteAction(id: "shortcuts", title: "Keyboard Shortcuts", subtitle: "See every shortcut", icon: "keyboard", section: "Help") {
                model.showShortcuts = true
            },
            PaletteAction(id: "docs", title: "OpenCode Documentation", subtitle: "opencode.ai/docs", icon: "book", section: "Help") {
                if let url = URL(string: "https://opencode.ai/docs") { NSWorkspace.shared.open(url) }
            }
        ]

        if let session = model.selectedSession {
            actions.insert(PaletteAction(id: "stop", title: "Stop Generating", subtitle: "Interrupt the active agent run", icon: "stop.circle", section: "Session", destructive: true) {
                Task { await model.stopGeneration() }
            }, at: 1)
            actions.insert(PaletteAction(id: "compact", title: "Compact Context", subtitle: "Summarize the active context window", icon: "arrow.down.right.and.arrow.up.left", section: "Session") {
                Task { await model.compactSession() }
            }, at: 2)
            actions.append(PaletteAction(id: "fork", title: "Fork Session", subtitle: session.displayTitle, icon: "arrow.triangle.branch", section: "Session") {
                Task { await model.forkSession(session) }
            })
            actions.append(PaletteAction(id: "export", title: "Export Session", subtitle: session.displayTitle, icon: "square.and.arrow.up", section: "Session") {
                model.exportCurrentSession()
            })
            actions.append(PaletteAction(id: "archive", title: "Archive Session", subtitle: session.displayTitle, icon: "archivebox", section: "Session") {
                Task { await model.archiveSession(session) }
            })
            actions.append(PaletteAction(id: "delete", title: "Delete Session…", subtitle: session.displayTitle, icon: "trash", section: "Session", destructive: true) {
                model.pendingDeleteSession = session
            })
        }

        for session in model.sessions.prefix(8) where session.id != model.selectedSessionID {
            actions.append(PaletteAction(
                id: "session-\(session.id)",
                title: session.displayTitle,
                subtitle: "\(session.model?.shortName ?? "session") · \(Format.relative(session.time.updatedDate))",
                icon: "bubble.left",
                section: "Recent Sessions",
                keywords: session.id
            ) {
                model.selectSession(session)
            })
        }

        for agent in model.primaryAgents {
            actions.append(PaletteAction(
                id: "agent-\(agent.id)",
                title: "Agent: \(agent.name)",
                subtitle: agent.description ?? agent.id,
                icon: "person.crop.circle",
                section: "Agents"
            ) {
                Task { await model.selectAgent(agent) }
            })
        }

        for item in model.availableModels.prefix(16) {
            actions.append(PaletteAction(
                id: "model-\(item.providerID)-\(item.modelID)",
                title: item.displayName,
                subtitle: "\(item.providerID) · \(item.modelID)",
                icon: "cpu",
                section: "Models"
            ) {
                Task { await model.selectModel(item, variant: item.variants?.first?.id) }
            })
        }

        for project in model.recentProjects.prefix(6) where project.canonical != model.workspace?.directory {
            actions.append(PaletteAction(
                id: "project-\(project.id)",
                title: "Open \(project.displayName)",
                subtitle: project.canonical,
                icon: "folder",
                section: "Projects"
            ) {
                Task { await model.openWorkspace(path: project.canonical) }
            })
        }
        return actions
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Quick open

struct QuickOpenView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FileSystemEntry] = []
    @State private var selected = 0
    @State private var loading = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ocAccent)
                TextField("Search files…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit { openSelected() }
                if loading { Spinner(size: 11) }
                KeyCap(text: "⌘P")
            }
            .padding(.horizontal, 15)
            .frame(height: 50)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(results.enumerated()), id: \.offset) { index, file in
                            Button {
                                open(file)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 11))
                                        .foregroundStyle(file.isDirectory ? Color.ocAccent : Color.ocTextTertiary)
                                        .frame(width: 17)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color.ocTextPrimary)
                                        Text(file.path)
                                            .font(.ocMono(9))
                                            .foregroundStyle(Color.ocTextTertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if index == selected {
                                        Image(systemName: "return")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.ocTextTertiary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(index == selected ? Color.ocAccent.opacity(0.10) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(file.id)
                            .onHover { hovering in
                                if hovering { selected = index }
                            }
                        }
                        if results.isEmpty, !loading {
                            Text(query.isEmpty ? "Start typing to find files" : "No files found")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.ocTextTertiary)
                                .padding(.top, 40)
                        }
                    }
                    .padding(7)
                }
                .onChange(of: selected) { _, index in
                    if let file = results[safe: index] {
                        withAnimation(Motion.quick) { proxy.scrollTo(file.id, anchor: .center) }
                    }
                }
            }
            .frame(maxHeight: 390)

            HStack {
                Text("↑↓ navigate · ↩ open")
                Spacer()
                Text("\(results.count) files")
            }
            .font(.ocMono(8.5))
            .foregroundStyle(Color.ocTextTertiary)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(Color.ocSurfaceSunken.opacity(0.5))
        }
        .frame(width: 620, height: 500)
        .background(.regularMaterial)
        .background(Color.ocCanvas.opacity(0.92))
        .task(id: query) {
            await search()
        }
        .onAppear { focused = true }
        .onKeyPress(.downArrow) {
            if selected < results.count - 1 { selected += 1 }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selected > 0 { selected -= 1 }
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    private func search() async {
        loading = true
        defer { loading = false }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = await model.listWorkspaceFiles(".")
        } else {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            results = await model.searchFiles(query)
        }
        selected = 0
    }

    private func openSelected() {
        guard let file = results[safe: selected] else { return }
        open(file)
    }

    private func open(_ file: FileSystemEntry) {
        guard !file.isDirectory else { return }
        Task {
            prefs.inspectorSection = .files
            prefs.showInspector = true
            await model.loadFile(file.path)
        }
        dismiss()
    }
}
