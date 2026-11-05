import AppKit
import SwiftUI

struct BootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var ring = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(Color.ocAccent.opacity(0.10), lineWidth: 1)
                        .frame(width: 148, height: 148)
                        .scaleEffect(ring ? 1.14 : 0.95)
                        .opacity(ring ? 0 : 1)
                    Circle()
                        .stroke(Color.ocAccent.opacity(0.18), lineWidth: 1)
                        .frame(width: 116, height: 116)
                    Circle()
                        .trim(from: 0.08, to: 0.38)
                        .stroke(
                            AngularGradient(colors: [.clear, .ocAccent, .clear], center: .center),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 132, height: 132)
                        .rotationEffect(.degrees(ring ? 360 : 0))
                        .animation(.linear(duration: 2.2).repeatForever(autoreverses: false), value: ring)
                    BrandMark(size: 76, glow: true)
                }
                .onAppear { ring = true }

                VStack(spacing: 8) {
                    Text("OPENCODE HARNESS")
                        .font(.ocRounded(21, weight: .bold))
                        .tracking(2.6)
                        .foregroundStyle(Color.ocTextPrimary)
                    Text(model.bootDetail)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.ocTextSecondary)
                        .contentTransition(.opacity)
                        .animation(Motion.gentle, value: model.bootDetail)
                    HStack(spacing: 6) {
                        Spinner(size: 11)
                        Text("NATIVE · SWIFTUI · LOCAL")
                            .font(.ocMono(9, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                    .padding(.top, 3)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear {
                withAnimation(Motion.smooth.delay(0.1)) { appeared = true }
            }

            Spacer()

            if !model.server.logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ENGINE")
                        .font(.ocMono(8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.ocTextTertiary)
                    ForEach(Array(model.server.logs.suffix(4).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.ocMono(10))
                            .foregroundStyle(Color.ocTextTertiary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.bottom, 28)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServerFailureView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.openSettings) private var openSettings
    var message: String
    @State private var logsOpen = false

    var body: some View {
        VStack(spacing: 22) {
            BrandMark(size: 70, glow: true)
            VStack(spacing: 7) {
                Text("The engine did not start")
                    .font(.ocRounded(22, weight: .bold))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                    .textSelection(.enabled)
            }

            HStack(spacing: 9) {
                Button("Try Again") {
                    Task { await model.boot(force: true) }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)

                Button("OpenCode Docs") {
                    if let url = URL(string: "https://opencode.ai/docs") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            if !model.server.logs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(Motion.smooth) { logsOpen.toggle() }
                    } label: {
                        HStack {
                            Text("Engine output")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Chevron(open: logsOpen)
                        }
                        .foregroundStyle(Color.ocTextSecondary)
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                    if logsOpen {
                        ScrollView {
                            Text(model.server.logs.suffix(40).joined(separator: "\n"))
                                .font(.ocMono(10.5))
                                .foregroundStyle(Color.ocTextTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .textSelection(.enabled)
                        }
                        .frame(height: 150)
                    }
                }
                .frame(maxWidth: 560)
                .cardSurface(radius: 10, fill: Color.ocSurfaceSunken)
            }

            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text(prefs.binaryPath.isEmpty ? "Looking for the opencode CLI on your PATH" : prefs.binaryPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.ocMono(9.5))
            .foregroundStyle(Color.ocTextTertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkspaceHomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences

    private var suggestions: [(String, String, String)] {
        [
            ("Explain this codebase", "Map the architecture and point out the sharp edges.", "sparkles"),
            ("Find something to improve", "Review the working tree and suggest a focused change.", "magnifyingglass"),
            ("Run the tests", "Use the project's test command and fix what fails.", "checkmark.seal"),
            ("Write a README", "Document setup, architecture, and usage for this project.", "doc.text")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                hero
                if !model.sessions.isEmpty {
                    recent
                }
                suggestionsGrid
            }
            .padding(42)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Tag(text: model.workspace?.name ?? "NO PROJECT", icon: "folder.fill", tint: .ocTeal)
                if let branch = model.vcsInfo?.branch?.current {
                    Tag(text: branch, icon: "arrow.triangle.branch", tint: .ocViolet)
                }
            }
            .padding(30)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                StatusDot(color: .ocSuccess)
                Text("READY · \(model.serverInfo?.version ?? "2.x")")
                    .font(.ocMono(9.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
            }
            Text("What should we\nbuild today?")
                .font(.ocRounded(44, weight: .bold))
                .tracking(-1.3)
                .foregroundStyle(Color.ocTextPrimary)
                .lineSpacing(-3)
            Text("OpenCode Harness runs the OpenCode agent against **\(model.workspace?.directory ?? "your project")** — with live tools, diffs, and full local control.")
                .font(.system(size: 14))
                .foregroundStyle(Color.ocTextSecondary)
                .frame(maxWidth: 620, alignment: .leading)
                .lineSpacing(3)
            HStack(spacing: 10) {
                Button {
                    Task { await model.newSession() }
                } label: {
                    Label("Start a session", systemImage: "plus.bubble.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    model.chooseWorkspace()
                } label: {
                    Label("Switch project", systemImage: "folder")
                }
                .buttonStyle(QuietButtonStyle())
                .padding(.horizontal, 2)
            }
            .padding(.top, 4)
        }
        .padding(.top, 22)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Recent sessions", trailing: "\(model.sessions.count)")
            VStack(spacing: 0) {
                ForEach(model.sessions.prefix(5)) { session in
                    Button {
                        model.selectSession(session)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.ocAccent)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.ocAccent.opacity(0.09)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Color.ocTextPrimary)
                                    .lineLimit(1)
                                Text("\(session.model?.shortName ?? "agent") · \(Format.relative(session.time.updatedDate))")
                                    .font(.ocMono(9.5))
                                    .foregroundStyle(Color.ocTextTertiary)
                            }
                            Spacer()
                            if let cost = session.cost, cost > 0 {
                                Text(Format.cost(cost))
                                    .font(.ocMono(9.5))
                                    .foregroundStyle(Color.ocTextTertiary)
                            }
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.clear)
                    )
                    .hoverEffect()
                }
            }
            .padding(4)
            .cardSurface(radius: 13)
        }
    }

    private var suggestionsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "A good place to start")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.0) { suggestion in
                    Button {
                        Task {
                            await model.newSession()
                            await model.sendMessage(suggestion.0)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: suggestion.2)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.ocAccent)
                            Text(suggestion.0)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.ocTextPrimary)
                            Text(suggestion.1)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.ocTextSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .cardSurface(radius: 12)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(scale: 1.01)
                }
            }
        }
    }
}

private struct HoverEffectModifier: ViewModifier {
    var scale: CGFloat = 1.005
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hovering ? Color.ocHover : .clear)
            )
            .scaleEffect(hovering ? scale : 1)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    fileprivate func hoverEffect(scale: CGFloat = 1.005) -> some View {
        modifier(HoverEffectModifier(scale: scale))
    }
}

struct WorkspacePickerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a project")
                        .font(.ocRounded(20, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("OpenCode runs in the folder you pick.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ocTextSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.ocHover))
            }
            .padding(22)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.ocTextTertiary)
                TextField("Filter projects", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ocTextTertiary)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.ocSurfaceSunken))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.ocBorder, lineWidth: 0.5))
            .padding(.horizontal, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !filteredProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Recent projects")
                            ForEach(filteredProjects) { project in
                                projectRow(project)
                            }
                        }
                    }
                    if !filteredRecents.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Local folders")
                            ForEach(filteredRecents, id: \.self) { path in
                                recentRow(path)
                            }
                        }
                    }
                }
                .padding(22)
            }

            Rectangle().fill(Color.ocBorder).frame(height: 1)
            HStack {
                Button {
                    model.chooseWorkspace()
                    dismiss()
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("Current: \(model.workspace?.name ?? "None")")
                    .font(.ocMono(9.5))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
        .background(Color.ocCanvas)
    }

    private func projectRow(_ project: ProjectInfo) -> some View {
        Button {
            Task {
                await model.openWorkspace(path: project.canonical)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.ocAccent.opacity(0.10))
                    Text(project.displayName.prefix(1).uppercased())
                        .font(.ocRounded(16, weight: .bold))
                        .foregroundStyle(Color.ocAccent)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text(project.canonical)
                        .font(.ocMono(9.5))
                        .foregroundStyle(Color.ocTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if project.id == model.workspace?.project?.id {
                    Tag(text: "OPEN", icon: "checkmark", tint: .ocTeal)
                }
                Chevron(open: false)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.ocSurface.opacity(0.65)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ocBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func recentRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await model.openWorkspace(path: path)
                    dismiss()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.ocTeal)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.ocTextPrimary)
                    Spacer()
                    Text(path)
                        .font(.ocMono(9.5))
                        .foregroundStyle(Color.ocTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 280, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            Button {
                prefs.forgetWorkspace(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.ocSurface.opacity(0.45)))
    }

    private var filteredProjects: [ProjectInfo] {
        let filtered = model.recentProjects.filter { project in
            query.isEmpty ||
            project.displayName.localizedCaseInsensitiveContains(query) ||
            project.canonical.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(10))
    }

    private var filteredRecents: [String] {
        prefs.recentWorkspaces.filter { path in
            query.isEmpty || path.localizedCaseInsensitiveContains(query)
        }
    }
}

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    private let groups: [(String, [(String, String)])] = [
        ("Navigation", [
            ("⌘ K", "Command palette"),
            ("⌘ P", "Quick open file"),
            ("⌘ N", "New session"),
            ("⇧ ⌘ O", "Open project"),
            ("⇧ ⌘ I", "Toggle inspector"),
            ("⌘ J", "Toggle shell")
        ]),
        ("Session", [
            ("⌘ .", "Stop generating"),
            ("⇧ ⌘ K", "Compact context"),
            ("⌘ R", "Refresh"),
            ("⇧ ⌘ U", "Usage statistics"),
            ("⌘ ,", "Settings")
        ]),
        ("Composer", [
            ("↩", "Send message"),
            ("⌥ ↩", "Insert newline"),
            ("@", "Mention a file"),
            ("/", "Run a command"),
            ("$", "Shell mode")
        ])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Keyboard shortcuts")
                    .font(.ocRounded(20, weight: .bold))
                    .foregroundStyle(Color.ocTextPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.ocHover))
            }
            ForEach(groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: group.0)
                    VStack(spacing: 0) {
                        ForEach(group.1, id: \.1) { item in
                            HStack {
                                Text(item.1)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.ocTextSecondary)
                                Spacer()
                                KeyCap(text: item.0)
                            }
                            .padding(.vertical, 7)
                            if item.1 != group.1.last?.1 {
                                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color.ocCanvas)
    }
}


struct WorktreeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.ocViolet.opacity(0.11))
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ocViolet)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a worktree")
                        .font(.ocRounded(18, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("OpenCode creates an isolated checkout for a task.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .background(Circle().fill(Color.ocHover))
                .foregroundStyle(Color.ocTextSecondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Worktree name")
                    .font(.ocMono(9, weight: .medium))
                    .foregroundStyle(Color.ocTextTertiary)
                TextField("feature/faster-tests", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ocBorder, lineWidth: 0.6))
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ocTextTertiary)
                Text("The new worktree opens as a separate workspace so this session stays untouched.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ocTextTertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Create worktree") {
                    submitting = true
                    Task {
                        await model.createWorktree(name: name.trimmingCharacters(in: .whitespaces))
                        submitting = false
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || submitting)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(Color.ocCanvas)
    }
}
