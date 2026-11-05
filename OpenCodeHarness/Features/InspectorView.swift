import AppKit
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(InspectorSection.allCases) { section in
                    Button {
                        withAnimation(Motion.snappy) { prefs.inspectorSection = section }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: section.icon)
                                .font(.system(size: 9, weight: .medium))
                            Text(section.title)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(prefs.inspectorSection == section ? Color.ocTextPrimary : Color.ocTextTertiary)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(prefs.inspectorSection == section ? Color.ocSurfaceRaised : .clear)
                                .shadow(color: .black.opacity(prefs.inspectorSection == section ? 0.08 : 0), radius: 3, y: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                IconButton(systemImage: "xmark", help: "Hide inspector", size: 24) {
                    withAnimation(Motion.smooth) { prefs.showInspector = false }
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 44)
            .background(Color.ocSidebar.opacity(0.28))

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            switch prefs.inspectorSection {
            case .files:
                FilesInspectorView()
            case .changes:
                ChangesInspectorView()
            case .details:
                DetailsInspectorView()
            }
        }
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blending: .withinWindow)
                Color.ocSurface.opacity(0.35)
            }
        )
    }
}

// MARK: - Files

struct FilesInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var currentPath = "."
    @State private var entries: [FileSystemEntry] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if model.selectedFilePath != nil {
                filePreview
            } else {
                browser
            }
        }
        .task(id: "\(model.workspace?.directory ?? "")::\(currentPath)") {
            await load()
        }
        .onChange(of: model.workspace?.directory) { _, _ in
            currentPath = "."
            model.selectedFilePath = nil
            model.selectedFileText = nil
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Button {
                    goUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(currentPath == "." ? Color.ocTextTertiary.opacity(0.4) : Color.ocTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.ocHover.opacity(currentPath == "." ? 0.3 : 1)))
                }
                .buttonStyle(.plain)
                .disabled(currentPath == ".")

                Text(pathLabel)
                    .font(.ocMono(9.5, weight: .medium))
                    .foregroundStyle(Color.ocTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if loading {
                    Spinner(size: 10)
                }
                IconButton(systemImage: "arrow.clockwise", help: "Refresh files", size: 22) {
                    Task { await load() }
                }
                IconButton(systemImage: "magnifyingglass", help: "Quick open (⌘P)", size: 22) {
                    model.showQuickOpen = true
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollView {
                LazyVStack(spacing: 1) {
                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.ocTextTertiary)
                            .padding(14)
                    }
                    ForEach(entries) { entry in
                        Button {
                            if entry.isDirectory {
                                currentPath = entry.path
                            } else {
                                Task { await model.loadFile(entry.path) }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.path))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(entry.isDirectory ? Color.ocAccent : color(for: entry.path))
                                    .frame(width: 16)
                                Text(entry.name)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.ocTextPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if entry.isDirectory {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 7.5, weight: .semibold))
                                        .foregroundStyle(Color.ocTextTertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if entries.isEmpty, loadError == nil, !loading {
                        VStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(Color.ocTextTertiary)
                            Text("This folder is empty")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.ocTextTertiary)
                        }
                        .padding(.top, 30)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
            HStack {
                Text("\(entries.filter { !$0.isDirectory }.count) files")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Button("Open Folder") {
                    model.revealWorkspaceInFinder()
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
        }
    }

    private var filePreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    model.selectedFilePath = nil
                    model.selectedFileText = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.ocTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.ocHover))
                }
                .buttonStyle(.plain)
                Image(systemName: icon(for: model.selectedFilePath ?? ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color(for: model.selectedFilePath ?? ""))
                Text(model.selectedFilePath ?? "")
                    .font(.ocMono(9.5, weight: .medium))
                    .foregroundStyle(Color.ocTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                IconButton(systemImage: "arrow.up.forward.app", help: "Open in default editor", size: 22) {
                    model.openSelectedFileExternally()
                }
                IconButton(systemImage: "finder", help: "Reveal in Finder", size: 22) {
                    model.revealSelectedFile()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 38)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            if model.filePreviewLoading {
                Spacer()
                Spinner()
                Spacer()
            } else if let text = model.selectedFileText {
                ScrollView {
                    if model.selectedFileIsBinary {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(Color.ocTextTertiary)
                            Text(text)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ocTextTertiary)
                        }
                        .padding(.top, 60)
                    } else {
                        CodeBlockView(
                            code: text,
                            language: language(for: model.selectedFilePath ?? ""),
                            compact: true
                        )
                        .padding(8)
                    }
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
            HStack {
                Text(Format.bytes(model.selectedFileSize))
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Text("\(model.selectedFileText?.components(separatedBy: "\n").count ?? 0) lines")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.ocSurfaceSunken.opacity(0.5))
        }
    }

    private var pathLabel: String {
        if currentPath == "." { return model.workspace?.name ?? "Project" }
        return URL(fileURLWithPath: currentPath).lastPathComponent
    }

    private func goUp() {
        guard currentPath != "." else { return }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        currentPath = parent.isEmpty || parent == "." ? "." : parent
    }

    private func load() async {
        loading = true
        loadError = nil
        entries = await model.listWorkspaceFiles(currentPath)
        loading = false
    }

    private func icon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "curlybraces.square"
        case "md", "markdown", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "sh", "zsh", "bash": return "terminal"
        case "lock": return "lock"
        default: return "doc"
        }
    }

    private func color(for path: String) -> Color {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .ocAccent
        case "js", "jsx", "ts", "tsx": return .ocWarning
        case "json", "yaml", "yml", "toml": return .ocViolet
        case "md", "markdown": return .ocInfo
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return .ocTeal
        default: return .ocTextTertiary
        }
    }

    private func language(for path: String) -> String {
        (path as NSString).pathExtension.lowercased()
    }
}

// MARK: - Changes

struct ChangesInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expanded: Set<String> = []
    @State private var loading = false

    private var files: [FileDiff] {
        model.diffMode == "session" ? model.sessionDiffs : model.vcsDiffs
    }

    private var additions: Int { files.reduce(0) { $0 + $1.additions } }
    private var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                segment("Session", value: "session")
                segment("Working tree", value: "working")
                Spacer()
                if loading { Spinner(size: 10) }
                IconButton(systemImage: "arrow.clockwise", help: "Refresh changes", size: 22) {
                    Task {
                        loading = true
                        await model.refreshChanges()
                        loading = false
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)

            HStack(spacing: 8) {
                Text("\(files.count) files")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
                if additions > 0 {
                    Text("+\(additions)").font(.ocMono(8.5)).foregroundStyle(Color.ocSuccess)
                }
                if deletions > 0 {
                    Text("-\(deletions)").font(.ocMono(8.5)).foregroundStyle(Color.ocDanger)
                }
                Spacer()
                if let branch = model.vcsInfo?.branch?.current {
                    Tag(text: branch, icon: "arrow.triangle.branch", tint: .ocViolet)
                }
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 7)

            Rectangle().fill(Color.ocBorder).frame(height: 0.5)

            ScrollView {
                LazyVStack(spacing: 6) {
                    if files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(Color.ocSuccess.opacity(0.7))
                            Text(model.diffMode == "session" ? "No file changes in this turn" : "Working tree is clean")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.ocTextTertiary)
                            if model.vcsInfo == nil {
                                Button("Initialize Git") {
                                    Task { await model.initGit() }
                                }
                                .buttonStyle(QuietButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                    }
                    ForEach(files) { diff in
                        diffCard(diff)
                    }
                }
                .padding(9)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            loading = true
            await model.refreshChanges()
            loading = false
        }
    }

    private func segment(_ title: String, value: String) -> some View {
        Button {
            withAnimation(Motion.quick) { model.diffMode = value }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(model.diffMode == value ? Color.ocTextPrimary : Color.ocTextTertiary)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.diffMode == value ? Color.ocSurfaceRaised : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func diffCard(_ diff: FileDiff) -> some View {
        let isOpen = expanded.contains(diff.file)
        return VStack(spacing: 0) {
            Button {
                withAnimation(Motion.smooth) {
                    if isOpen { expanded.remove(diff.file) } else { expanded.insert(diff.file) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: diff.status == "added" ? "plus.circle.fill" : diff.status == "deleted" ? "minus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(diff.status == "added" ? Color.ocSuccess : diff.status == "deleted" ? Color.ocDanger : Color.ocWarning)
                    Text(diff.file)
                        .font(.ocMono(9.5, weight: .medium))
                        .foregroundStyle(Color.ocTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text("+\(diff.additions)")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocSuccess)
                    Text("-\(diff.deletions)")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocDanger)
                    Chevron(open: isOpen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen, !diff.patch.isEmpty {
                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
                DiffPatchView(patch: diff.patch, maxHeight: 280)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.ocSurface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ocBorder, lineWidth: 0.5))
    }
}

// MARK: - Details

struct DetailsInspectorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let session = model.selectedSession {
                    contextCard(session)
                    metadata(session)
                    actions(session)
                } else {
                    EmptyStateView(
                        icon: "sidebar.right",
                        title: "No session selected",
                        message: "Choose a session to see its model, context, and controls."
                    )
                }
                worktrees
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private func contextCard(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("CONTEXT")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Tag(text: "\(Int(model.contextFraction * 100))%", tint: model.contextFraction > 0.85 ? .ocWarning : .ocTeal)
            }
            HStack(spacing: 12) {
                ZStack {
                    ProgressRing(progress: model.contextFraction, lineWidth: 5, size: 54, tint: model.contextFraction > 0.85 ? .ocWarning : .ocTeal)
                    Image(systemName: "brain")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Color.ocTextSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.contextLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("\(Format.cost(session.cost ?? 0)) this session")
                        .font(.ocMono(9))
                        .foregroundStyle(Color.ocTextTertiary)
                    if let tokens = session.tokens {
                        Text("in \(Format.tokens(tokens.input)) · out \(Format.tokens(tokens.output)) · cached \(Format.tokens(tokens.cache.read))")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }
            }
            Button {
                Task { await model.compactSession() }
            } label: {
                Label("Compact context", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocHover))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ocTextSecondary)
        }
        .padding(11)
        .cardSurface(radius: 10)
    }

    private func metadata(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION")
                .font(.ocMono(8.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.ocTextTertiary)
            infoRow("Model", session.model?.shortName ?? "—")
            infoRow("Agent", session.agent ?? "—")
            infoRow("Directory", session.location?.directory ?? "—", mono: true, truncate: true)
            infoRow("Branch", model.vcsInfo?.branch?.current ?? "—")
            infoRow("Updated", Format.relative(session.time.updatedDate))
            infoRow("Messages", "\(model.messages.count)")
            infoRow("ID", session.id, mono: true, truncate: true)
            if let outcome = session.outcome {
                infoRow("Outcome", outcome.capitalized)
            }
            Button {
                model.copyText(session.id)
            } label: {
                Label("Copy session ID", systemImage: "doc.on.doc")
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocHover))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ocTextSecondary)
        }
        .padding(11)
        .cardSurface(radius: 10)
    }

    private func actions(_ session: SessionInfo) -> some View {
        VStack(spacing: 5) {
            actionButton("Fork session", icon: "arrow.triangle.branch") {
                Task { await model.forkSession(session) }
            }
            actionButton("Export session", icon: "square.and.arrow.up") {
                model.exportCurrentSession()
            }
            actionButton("Archive session", icon: "archivebox") {
                Task { await model.archiveSession(session) }
            }
            actionButton("Delete session", icon: "trash", dangerous: true) {
                model.pendingDeleteSession = session
            }
        }
    }

    private func actionButton(_ title: String, icon: String, dangerous: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
            }
            .foregroundStyle(dangerous ? Color.ocDanger : Color.ocTextSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(dangerous ? Color.ocDanger.opacity(0.06) : Color.ocSurface.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false, truncate: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.ocTextTertiary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(mono ? .ocMono(9) : .system(size: 10))
                .foregroundStyle(Color.ocTextSecondary)
                .lineLimit(truncate ? 1 : 3)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var worktrees: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("WORKTREES")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                if model.workspace?.project?.id != nil {
                    Button {
                        Task { await model.loadWorktrees() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ocTextTertiary)
                    .help("Refresh worktrees")
                    Button {
                        model.showWorktreeSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ocTextTertiary)
                    .help("Create a worktree")
                }
            }
            if model.worktrees.isEmpty {
                Text("No linked worktrees.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ocTextTertiary)
            } else {
                ForEach(model.worktrees) { tree in
                    Button {
                        Task { await model.openWorkspace(path: tree.directory) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.ocViolet)
                            Text(URL(fileURLWithPath: tree.directory).lastPathComponent)
                                .font(.ocMono(9))
                                .foregroundStyle(Color.ocTextSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(11)
        .cardSurface(radius: 10)
    }
}
