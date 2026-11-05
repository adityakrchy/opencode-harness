import AppKit
import SwiftUI

struct ChatHeaderView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    var session: SessionInfo

    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var showModelPicker = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if editingTitle {
                    TextField("Session title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .focused($titleFocused)
                        .onSubmit { commitTitle() }
                        .onExitCommand { editingTitle = false }
                        .frame(maxWidth: 360)
                } else {
                    Text(session.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ocTextPrimary)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { beginEditing() }
                        .help("Double-click to rename")
                }

                HStack(spacing: 7) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.isBusy ? Color.ocSuccess : Color.ocTextTertiary.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(model.isBusy ? "working" : "idle")
                    }
                    Text("·")
                    Text(session.agent ?? model.selectedAgent)
                    Text("·")
                    Text(session.model?.shortName ?? model.selectedModel?.shortName ?? "no model")
                    if let cost = session.cost, cost > 0 {
                        Text("·")
                        Text(Format.cost(cost))
                    }
                }
                .font(.ocMono(9.5))
                .foregroundStyle(Color.ocTextTertiary)
            }

            Spacer(minLength: 8)

            if let tokens = session.tokens {
                HStack(spacing: 6) {
                    ProgressRing(progress: model.contextFraction, lineWidth: 2.2, size: 22, tint: model.contextFraction > 0.85 ? .ocWarning : .ocTeal)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Format.tokens(tokens.total) + " tok")
                            .font(.ocMono(9.5, weight: .medium))
                            .foregroundStyle(Color.ocTextSecondary)
                        Text(Format.cost(session.cost ?? 0))
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.ocHover))
                .overlay(Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.5))
                .help(model.contextLabel)
            }

            Button {
                showModelPicker.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                    Text(model.selectedModelInfo?.displayName ?? model.selectedModel?.shortName ?? "Model")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Color.ocTextSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.ocHover))
                .overlay(Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                ModelPickerView()
                    .environmentObject(model)
                    .environmentObject(prefs)
            }

            HStack(spacing: 1) {
                IconButton(systemImage: "plus.forwardslash.minus", help: "Changes (⇧⌘I)", size: 27) {
                    prefs.inspectorSection = .changes
                    withAnimation(Motion.smooth) { prefs.showInspector = true }
                    Task { await model.refreshChanges() }
                }
                IconButton(systemImage: "arrow.triangle.branch", help: "Fork session", size: 27) {
                    Task { await model.forkSession(session) }
                }
                Menu {
                    Button("Rename…") { beginEditing() }
                    Button("Compact Context") { Task { await model.compactSession() } }
                    Divider()
                    Button("Fork Session") { Task { await model.forkSession(session) } }
                    Button("Export Session…") { model.exportCurrentSession() }
                    Button("Copy Session ID") { model.copySessionID() }
                    Divider()
                    Button("Archive") { Task { await model.archiveSession(session) } }
                    Button("Delete…", role: .destructive) { model.pendingDeleteSession = session }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ocTextSecondary)
                        .frame(width: 28, height: 27)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(Color.ocCanvas.opacity(0.5))
    }

    private func beginEditing() {
        titleDraft = session.displayTitle
        editingTitle = true
        titleFocused = true
    }

    private func commitTitle() {
        let value = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTitle = false
        guard !value.isEmpty, value != session.displayTitle else { return }
        Task { await model.renameSession(session, title: value) }
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel

    @State private var autoScroll = true
    @State private var showJump = false
    @State private var lastSignature = ""

    private var displayMessages: [ChatMessage] {
        model.messages.filter { message in
            switch message.kind {
            case .system, .synthetic, .skill, .agentSwitched, .modelSwitched, .locationSwitched:
                return false
            case .idle:
                return message.errorText != nil
            default:
                return true
            }
        }
    }

    private var signature: String {
        guard let last = displayMessages.last else { return "empty" }
        let textLength = last.blocks.reduce(0) { $0 + $1.text.count }
        let toolStatus = last.blocks.compactMap { $0.tool?.status }.joined()
        return "\(displayMessages.count)-\(last.id)-\(textLength)-\(toolStatus)-\(last.isStreaming)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if displayMessages.isEmpty {
                        emptyChat
                    } else {
                        ForEach(displayMessages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                        if model.isBusy {
                            WorkingIndicator()
                                .padding(.top, 2)
                                .id("working")
                        }
                    }
                    Color.clear
                        .frame(height: 8)
                        .id("bottom")
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "chat-scroll")
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        if autoScroll {
                            autoScroll = false
                            withAnimation(Motion.gentle) { showJump = true }
                        }
                    }
            )
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: signature) { _, _ in
                if autoScroll {
                    scrollToBottom(proxy, animated: true)
                } else if showJump == false {
                    withAnimation(Motion.gentle) { showJump = true }
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                if autoScroll {
                    settleAtBottom(proxy)
                } else {
                    withAnimation(Motion.gentle) { showJump = true }
                }
            }
            .onChange(of: model.selectedSessionID) { _, _ in
                autoScroll = true
                showJump = false
                settleAtBottom(proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if showJump {
                    Button {
                        autoScroll = true
                        showJump = false
                        scrollToBottom(proxy, animated: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down")
                            Text("Latest")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.ocTextPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.regularMaterial))
                        .overlay(Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(Motion.smooth, value: displayMessages.count)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        lastSignature = signature
    }

    private func settleAtBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var emptyChat: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                BrandMark(size: 42, glow: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready when you are")
                        .font(.ocRounded(21, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("The agent can read, edit, run, and search inside this project.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ocTextSecondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                suggestion("What should I know about this codebase?", "sparkles")
                suggestion("Run the test suite and fix any failures.", "checkmark.seal")
                suggestion("Find a bug and propose a patch.", "ladybug")
            }
        }
        .padding(.top, 30)
        .frame(maxWidth: 580, alignment: .leading)
    }

    private func suggestion(_ text: String, _ icon: String) -> some View {
        Button {
            Task { await model.sendMessage(text) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.ocAccent)
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ocTextSecondary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.ocSurface.opacity(0.55))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.ocBorder, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WorkingIndicator: View {
    /// Playful gerunds, in the spirit of Claude Code's "Noodling…", "Pondering…" etc.
    private static let verbs = [
        "Thinking",
        "Pondering",
        "Noodling",
        "Brewing",
        "Cooking",
        "Scheming",
        "Conjuring",
        "Vibing",
        "Riffing",
        "Simmering",
        "Ideating",
        "Wandering",
        "Hustling",
        "Percolating",
        "Daydreaming",
        "Narrowing in",
        "Unravelling",
        "Assembling",
        "Wielding",
        "Venturing",
    ]

    @State private var phase = false
    @State private var verb: String = Self.verbs.randomElement()!

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.ocAccent)
                        .frame(width: 4, height: 4)
                        .opacity(phase ? 0.9 : 0.25)
                        .scaleEffect(phase ? 1 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                            value: phase
                        )
                }
            }
            ShimmerText(text: "\(verb)…")
        }
        .padding(.horizontal, 4)
        .onAppear {
            phase = true
            verb = Self.verbs.randomElement() ?? "Thinking"
        }
    }
}

struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    var message: ChatMessage

    var body: some View {
        switch message.kind {
        case .user:
            UserMessageView(message: message)
        case .assistant:
            AssistantMessageView(message: message)
        case .shell:
            ShellMessageView(message: message)
        case .compaction:
            CompactionMessageView(message: message)
        case .idle:
            ErrorMessageView(message: message)
        default:
            EmptyView()
        }
    }
}

struct UserMessageView: View {
    @EnvironmentObject private var model: AppModel
    var message: ChatMessage
    @State private var hovering = false

    var body: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 7) {
                if !message.attachments.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(message.attachments) { attachment in
                            HStack(spacing: 4) {
                                Image(systemName: attachment.isImage ? "photo" : "doc")
                                    .font(.system(size: 8.5))
                                Text(attachment.displayName)
                                    .font(.ocMono(9))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.ocTextSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.ocHover))
                        }
                    }
                }
                Text(message.userText ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.ocTextPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.ocAccent.opacity(0.18),
                                        Color.ocAccent.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.ocAccent.opacity(0.18), lineWidth: 0.6)
                    }
                HStack(spacing: 8) {
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                    if hovering {
                        Button {
                            model.copyText(message.userText ?? "")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.ocTextTertiary)
                        .transition(.opacity)
                    }
                }
            }
            .onHover { hovering = $0 }
        }
    }
}

struct AssistantMessageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    var message: ChatMessage
    @State private var hovering = false
    @State private var confirmRevert = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            BrandMark(size: 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Text(model.agents.first(where: { $0.id == message.agent })?.name ?? "OpenCode")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text(message.model?.shortName ?? "")
                        .font(.ocMono(9))
                        .foregroundStyle(Color.ocTextTertiary)
                    if message.isStreaming {
                        ShimmerText(text: "streaming")
                    } else if let completedAt = message.completedAt {
                        Text(completedAt.formatted(date: .omitted, time: .shortened))
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                    if let duration = duration {
                        Text("· \(Format.duration(duration))")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }

                if message.isEmptyAssistant && message.isStreaming {
                    HStack(spacing: 7) {
                        StreamingCaret()
                        Text("Thinking…")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                    .padding(.vertical, 3)
                }

                ForEach(message.blocks) { block in
                    switch block.kind {
                    case .text:
                        VStack(alignment: .leading, spacing: 3) {
                            MarkdownView(markdown: block.text)
                            if message.isStreaming, block.id == message.blocks.last?.id {
                                StreamingCaret()
                            }
                        }
                    case .reasoning:
                        ReasoningView(block: block, streaming: message.isStreaming && block.id == message.blocks.last?.id)
                    case .tool:
                        if let tool = block.tool {
                            ToolCallView(tool: tool)
                        }
                    }
                }

                if let error = message.errorText {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .textSelection(.enabled)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ocDanger)
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.ocDanger.opacity(0.08)))
                }

                if !message.isStreaming {
                    messageFooter
                        .opacity(hovering ? 1 : 0.55)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy response") { model.copyText(message.copyableText) }
            Button("Fork from here") {
                if let session = model.selectedSession {
                    Task { await model.forkSession(session, before: message.id) }
                }
            }
            Divider()
            Button("Revert to here…", role: .destructive) {
                confirmRevert = true
            }
        }
        .confirmationDialog("Revert to this point?", isPresented: $confirmRevert, titleVisibility: .visible) {
            Button("Revert session and files", role: .destructive) {
                Task { await model.revert(to: message) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the conversation and the files changed after this assistant turn.")
        }
    }

    private var duration: Double? {
        guard let completed = message.completedAt else { return nil }
        return completed.timeIntervalSince(message.createdAt)
    }

    private var messageFooter: some View {
        HStack(spacing: 9) {
            if let tokens = message.tokens {
                Label("\(Format.tokens(tokens.total)) tokens", systemImage: "text.word.spacing")
            }
            if let cost = message.cost, cost > 0 {
                Text(Format.cost(cost))
            }
            Button {
                model.copyText(message.copyableText)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            Button {
                if let session = model.selectedSession {
                    Task { await model.forkSession(session, before: message.id) }
                }
            } label: {
                Label("Fork", systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.plain)
        }
        .font(.ocMono(8.5))
        .foregroundStyle(Color.ocTextTertiary)
        .padding(.top, 1)
    }
}

struct ReasoningView: View {
    @EnvironmentObject private var prefs: AppPreferences
    var block: MessageBlock
    var streaming: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .medium))
                    if streaming {
                        ShimmerText(text: "Thinking…")
                    } else if let duration = block.reasoningDuration {
                        Text("Thought for \(Format.duration(duration))")
                            .font(.system(size: 10.5, weight: .medium))
                    } else {
                        Text("Reasoning")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    Spacer()
                    Chevron(open: expanded)
                }
                .foregroundStyle(Color.ocTextTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(block.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if streaming, !block.text.isEmpty {
                Text(String(block.text.suffix(120)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.ocSurfaceSunken.opacity(0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.ocBorder, lineWidth: 0.5)
        }
    }
}

struct ToolCallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    var tool: ToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(statusTint.opacity(0.11))
                        Image(systemName: tool.iconName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(statusTint)
                    }
                    .frame(width: 23, height: 23)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(tool.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Color.ocTextPrimary)
                            if tool.isRunning {
                                Spinner(size: 9, tint: statusTint)
                            }
                            if let duration = tool.duration {
                                Text(Format.duration(duration))
                                    .font(.ocMono(8.5))
                                    .foregroundStyle(Color.ocTextTertiary)
                            }
                        }
                        if let summary = tool.summary {
                            Text(summary)
                                .font(.ocMono(9.5))
                                .foregroundStyle(Color.ocTextTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if !tool.isRunning {
                        Text(statusLabel)
                            .font(.ocMono(8.5, weight: .medium))
                            .foregroundStyle(statusTint)
                    }
                    Chevron(open: expanded)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    if let input = tool.input, !input.displayText.isEmpty, input != .null {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("INPUT")
                                .font(.ocMono(8, weight: .semibold))
                                .tracking(1)
                                .foregroundStyle(Color.ocTextTertiary)
                            CodeBlockView(code: input.prettyString, language: "json", compact: true)
                        }
                    }
                    if !tool.content.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("OUTPUT")
                                    .font(.ocMono(8, weight: .semibold))
                                    .tracking(1)
                                    .foregroundStyle(Color.ocTextTertiary)
                                Spacer()
                                Button {
                                    model.copyText(tool.content)
                                } label: {
                                    Text("Copy")
                                        .font(.ocMono(8.5))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.ocTextTertiary)
                            }
                            CodeBlockView(code: tool.content, language: languageForOutput, compact: true)
                        }
                    }
                    if let error = tool.errorText {
                        Text(error)
                            .font(.ocMono(10))
                            .foregroundStyle(Color.ocDanger)
                            .textSelection(.enabled)
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.ocDanger.opacity(0.07)))
                    }
                    if !tool.files.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(tool.files) { file in
                                Tag(text: file.name ?? URL(string: file.uri)?.lastPathComponent ?? "file", icon: "doc", tint: .ocTeal)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.ocSurface.opacity(0.52))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(tool.isRunning ? statusTint.opacity(0.28) : Color.ocBorder, lineWidth: 0.6)
        }
        .onAppear {
            if prefs.showToolDetails { expanded = true }
        }
    }

    private var statusTint: Color {
        if tool.isError { return .ocDanger }
        if tool.isRunning { return .ocWarning }
        return .ocTeal
    }

    private var statusLabel: String {
        if tool.isError { return "FAILED" }
        switch tool.status {
        case "completed": return "DONE"
        default: return tool.status.uppercased()
        }
    }

    private var languageForOutput: String {
        if tool.name == "shell" || tool.name == "bash" { return "shell" }
        if tool.name == "read" { return "" }
        if let path = tool.input?["path"]?.string ?? tool.input?["filePath"]?.string {
            return (path as NSString).pathExtension
        }
        return ""
    }
}

struct ShellMessageView: View {
    @EnvironmentObject private var model: AppModel
    var message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ocTeal)
                Text("SHELL")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
                Text(message.command ?? "")
                    .font(.ocMono(10.5, weight: .medium))
                    .foregroundStyle(Color.ocTextPrimary)
                    .lineLimit(1)
                Spacer()
                if let status = message.shellStatus {
                    Text(status.uppercased())
                        .font(.ocMono(8.5))
                        .foregroundStyle(status == "running" ? Color.ocWarning : Color.ocTextTertiary)
                }
                Button {
                    model.copyText(message.command ?? "")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            if let output = message.shellOutput, !output.isEmpty {
                ScrollView(.horizontal) {
                    Text(output.trimmingCharacters(in: .newlines))
                        .font(.ocMono(10.5))
                        .foregroundStyle(Color.ocTextSecondary)
                        .textSelection(.enabled)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .background(Color.ocCodeBackground)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.ocSurface.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ocBorder, lineWidth: 0.6))
    }
}

struct CompactionMessageView: View {
    var message: ChatMessage
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                Text("CONTEXT COMPACTED")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1)
            }
            .foregroundStyle(Color.ocViolet.opacity(0.85))
            .fixedSize()
            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }
}

struct ErrorMessageView: View {
    var message: ChatMessage
    var body: some View {
        if let error = message.errorText {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session error")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(error)
                        .font(.system(size: 11.5))
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .foregroundStyle(Color.ocDanger)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.ocDanger.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.ocDanger.opacity(0.16), lineWidth: 0.6))
        }
    }
}
