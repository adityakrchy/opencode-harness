import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.openSettings) private var openSettings
    @State private var renameSession: SessionInfo?
    @State private var renameText = ""
    @State private var showSwitcher = false

    private var searchActive: Bool {
        !model.sessionSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Root sessions normally; when searching, a flat pool including
    /// nested subagent sessions is searched so every match is visible.
    private var sidebarSessions: [SessionInfo] {
        guard searchActive else { return model.workspaceRecentSessions }
        var pool: [SessionInfo] = model.showArchived
            ? model.archivedSessions
            : model.sessions + model.sessionChildren.values.flatMap { $0 }
        let query = model.sessionSearch.lowercased()
        return pool.filter {
            $0.displayTitle.lowercased().contains(query) ||
            ($0.agent?.lowercased().contains(query) ?? false) ||
            ($0.model?.id.lowercased().contains(query) ?? false)
        }
    }

    private var groups: [(String, [SessionInfo])] {
        let calendar = Calendar.current
        var today: [SessionInfo] = []
        var yesterday: [SessionInfo] = []
        var week: [SessionInfo] = []
        var older: [SessionInfo] = []

        for session in sidebarSessions {
            let date = session.time.updatedDate
            if calendar.isDateInToday(date) {
                today.append(session)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(session)
            } else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
                week.append(session)
            } else {
                older.append(session)
            }
        }
        return [
            ("Today", today),
            ("Yesterday", yesterday),
            ("Previous 7 days", week),
            ("Older", older)
        ].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            newSessionButton
            searchField
            sessionList
            footer
        }
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Color.ocSidebar.opacity(0.58)
            }
        )
        .alert("Rename session", isPresented: renameBinding) {
            TextField("Session title", text: $renameText)
            Button("Save") {
                if let session = renameSession, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Task { await model.renameSession(session, title: renameText) }
                }
                renameSession = nil
            }
            Button("Cancel", role: .cancel) { renameSession = nil }
        } message: {
            Text("Give this session a memorable title.")
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameSession != nil },
            set: { if !$0 { renameSession = nil } }
        )
    }

    // MARK: - Header

    private var workspaceHeader: some View {
        Button {
            showSwitcher.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [Color.ocAccent.opacity(0.22), Color.ocAccent.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(String(model.workspace?.name.prefix(1).uppercased() ?? "?"))
                        .font(.ocRounded(15, weight: .bold))
                        .foregroundStyle(Color.ocAccent)
                }
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.ocAccent.opacity(0.18), lineWidth: 0.6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.workspace?.name ?? "Choose a project")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.ocTextPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let branch = model.vcsInfo?.branch?.current {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 7.5, weight: .semibold))
                            Text(branch)
                                .lineLimit(1)
                        } else {
                            Text(model.workspace?.directory ?? "No workspace")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.ocMono(9))
                    .foregroundStyle(Color.ocTextTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.ocSurface.opacity(0.45))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(Color.ocBorder, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showSwitcher, arrowEdge: .bottom) {
            workspaceSwitcher
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var workspaceSwitcher: some View {
        VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PROJECTS")
                    .font(.ocMono(8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.ocTextTertiary)
                if let workspace = model.workspace {
                    Text(workspace.directory)
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ForEach(model.recentProjects.prefix(7)) { project in
                Button {
                    showSwitcher = false
                    Task { await model.openWorkspace(path: project.canonical) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(project.id == model.workspace?.project?.id ? Color.ocAccent : Color.ocTextTertiary)
                        Text(project.displayName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.ocTextPrimary)
                        Spacer()
                        if project.id == model.workspace?.project?.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.ocAccent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Rectangle().fill(Color.ocBorder).frame(height: 0.5).padding(.vertical, 4)

            Button {
                showSwitcher = false
                model.chooseWorkspace()
            } label: {
                Label("Open Folder…", systemImage: "folder.badge.plus")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showSwitcher = false
                model.showWorkspacePicker = true
            } label: {
                Label("Browse All Projects", systemImage: "square.grid.2x2")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !model.worktrees.isEmpty {
                Rectangle().fill(Color.ocBorder).frame(height: 0.5).padding(.vertical, 4)
                Text("WORKTREES")
                    .font(.ocMono(8, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.ocTextTertiary)
                    .padding(.horizontal, 9)
                ForEach(model.worktrees) { tree in
                    Button {
                        showSwitcher = false
                        Task { await model.openWorkspace(path: tree.directory) }
                    } label: {
                        Label(URL(fileURLWithPath: tree.directory).lastPathComponent, systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ocTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Rectangle().fill(Color.ocBorder).frame(height: 0.5).padding(.vertical, 4)

            HStack(spacing: 8) {
                Button {
                    showSwitcher = false
                    model.revealWorkspaceInFinder()
                } label: {
                    Label("Reveal", systemImage: "finder")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Text("\(model.projects.count) projects")
                    .font(.ocMono(8))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
        .padding(7)
        .frame(width: 300)
    }

    private var newSessionButton: some View {
        Button {
            Task { await model.newSession() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New session")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                KeyCap(text: "⌘N")
            }
            .foregroundStyle(Color.ocTextPrimary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.ocAccent.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.ocAccent.opacity(0.16), lineWidth: 0.6)
                    }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canChat)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.ocTextTertiary)
            TextField("Search sessions", text: $model.sessionSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !model.sessionSearch.isEmpty {
                Button {
                    model.sessionSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ocSurfaceSunken.opacity(0.8))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.ocBorder, lineWidth: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Sessions

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3, pinnedViews: [.sectionHeaders]) {
                if model.showArchived && !model.archivedSessions.isEmpty {
                    section("Archived", sessions: model.archivedSessions)
                }
                ForEach(groups, id: \.0) { group in
                    Section {
                        ForEach(group.1) { session in
                            SessionListRow(
                                session: session,
                                depth: 0,
                                showChildren: !searchActive,
                                onRename: { target in
                                    renameText = target.displayTitle
                                    renameSession = target
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(group.0.uppercased())
                                .font(.ocMono(8.5, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(Color.ocTextTertiary)
                            Spacer()
                            Text("\(group.1.count)")
                                .font(.ocMono(8.5))
                                .foregroundStyle(Color.ocTextTertiary.opacity(0.7))
                        }
                        .padding(.horizontal, 15)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .background(Color.ocSidebar.opacity(0.92).blur(radius: 8))
                    }
                }
                if sidebarSessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: model.sessionSearch.isEmpty ? "bubble.left" : "magnifyingglass")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color.ocTextTertiary)
                        Text(model.sessionSearch.isEmpty ? "No sessions yet" : "No matching sessions")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func section(_ title: String, sessions: [SessionInfo]) -> some View {
        Section {
            ForEach(sessions) { session in
                SessionListRow(
                    session: session,
                    depth: 0,
                    showChildren: false,
                    onRename: { target in
                        renameText = target.displayTitle
                        renameSession = target
                    }
                )
            }
        } header: {
            Text(title.uppercased())
                .font(.ocMono(8.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.ocTextTertiary)
                .padding(.horizontal, 15)
                .padding(.vertical, 5)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ocBorder).frame(height: 1)
            HStack(spacing: 2) {
                Button {
                    Task { await model.toggleArchived() }
                } label: {
                    Label("Archived", systemImage: "archivebox")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(model.showArchived ? Color.ocAccent : Color.ocTextTertiary)
                }
                .buttonStyle(QuietButtonStyle())
                .help("Show archived sessions")

                Button {
                    model.showStats = true
                    Task { await model.loadStats() }
                } label: {
                    Label("Usage", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(QuietButtonStyle())

                Spacer()

                Menu {
                    Button("Settings…") {
                        openSettings()
                    }
                    Button("Keyboard Shortcuts…") { model.showShortcuts = true }
                    Divider()
                    Button("Reload Configuration") { Task { await model.reloadConfiguration() } }
                    Button("Reconnect Engine") { Task { await model.restartServer() } }
                    Divider()
                    Button("OpenCode Docs") {
                        if let url = URL(string: "https://opencode.ai/docs") { NSWorkspace.shared.open(url) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ocTextTertiary)
                        .frame(width: 26, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)

            HStack(spacing: 6) {
                StatusDot(color: model.eventConnection == .connected ? .ocSuccess : .ocWarning)
                Text(model.serverInfo.map { "OpenCode \($0.version)" } ?? "OpenCode")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Text(model.selectedSession.map { Format.tokens($0.tokens?.total ?? 0) + " tok" } ?? "native harness")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
        .background(Color.ocSidebar.opacity(0.7))
    }
}

/// Renders one session and, recursively, its nested child sessions.
struct SessionListRow: View {
    @EnvironmentObject private var model: AppModel
    var session: SessionInfo
    var depth: Int
    var showChildren: Bool
    var onRename: (SessionInfo) -> Void

    @State private var expanded = true

    private var children: [SessionInfo] {
        showChildren ? model.children(of: session.id) : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SessionRow(
                session: session,
                selected: model.selectedSessionID == session.id,
                running: model.activeSessionIDs.contains(session.id),
                depth: depth,
                isSubagent: session.parentID != nil,
                childCount: children.count,
                expanded: expanded,
                onToggleExpand: {
                    withAnimation(Motion.quick) { expanded.toggle() }
                },
                onRename: { onRename(session) }
            )
            if expanded && !children.isEmpty {
                ForEach(children) { child in
                    SessionListRow(
                        session: child,
                        depth: depth + 1,
                        showChildren: showChildren,
                        onRename: onRename
                    )
                }
            }
        }
    }
}

struct SessionRow: View {
    @EnvironmentObject private var model: AppModel
    var session: SessionInfo
    var selected: Bool
    var running: Bool
    var depth: Int = 0
    var isSubagent: Bool = false
    var childCount: Int = 0
    var expanded: Bool = true
    var onToggleExpand: (() -> Void)? = nil
    var onRename: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.selectSession(session)
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        Circle()
                            .fill(selected ? Color.ocAccent : Color.ocHover)
                            .frame(width: 24, height: 24)
                        if running {
                            Spinner(size: 11, tint: selected ? .white : .ocAccent)
                        } else {
                            Image(systemName: isSubagent ? "person.2" : "bubble.left")
                                .font(.system(size: isSubagent ? 8.5 : 9.5, weight: .medium))
                                .foregroundStyle(selected ? Color.white : Color.ocTextTertiary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(session.displayTitle)
                            .font(.system(size: isSubagent ? 11.5 : 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(Color.ocTextPrimary)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            if isSubagent {
                                Text("subagent")
                            }
                            if let modelName = session.model?.shortName {
                                Text(modelName)
                                    .lineLimit(1)
                            }
                            if let cost = session.cost, cost > 0 {
                                Text("·")
                                Text(Format.cost(cost))
                            }
                        }
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                    }
                    Spacer(minLength: 2)
                    Text(Format.relative(session.time.updatedDate))
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary.opacity(0.8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if childCount > 0, let onToggleExpand {
                Button(action: onToggleExpand) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.ocTextTertiary)
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide nested sessions" : "Show nested sessions")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.ocAccent.opacity(0.14) : (hovering ? Color.ocHover : .clear))
                .animation(Motion.quick, value: selected)
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.ocAccent)
                    .frame(width: 2.5, height: 20)
                    .offset(x: -1)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 7)
        .padding(.leading, CGFloat(depth) * 14)
        .onHover { value in
            withAnimation(Motion.quick) { hovering = value }
        }
        .contextMenu {
            Button("Rename…", action: onRename)
            if !isSubagent {
                Button("Fork Session") {
                    Task { await model.forkSession(session) }
                }
            }
            Button("Export Session") {
                model.selectSession(session)
                model.exportCurrentSession()
            }
            Button("Copy Session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
            Divider()
            Button("Archive") {
                Task { await model.archiveSession(session) }
            }
            Button("Delete…", role: .destructive) {
                model.pendingDeleteSession = session
            }
        }
    }
}
