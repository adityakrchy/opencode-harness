import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences

    @State private var text = ""
    @State private var attachments: [PromptAttachment] = []
    @State private var shellMode = false
    @State private var showModelPicker = false
    @State private var showFileImporter = false
    @State private var mentionResults: [FileSystemEntry] = []
    @State private var mentionTask: Task<Void, Never>?
    @State private var selectedSuggestion = 0
    @FocusState private var focused: Bool

    private var commandQuery: String? {
        guard let last = text.components(separatedBy: "\n").last else { return nil }
        guard last.hasPrefix("/"), !last.dropFirst().contains(" ") else { return nil }
        return String(last.dropFirst())
    }

    private var fileQuery: String? {
        guard let last = text.components(separatedBy: "\n").last,
              let at = last.lastIndex(of: "@") else { return nil }
        let suffix = last[last.index(after: at)...]
        guard !suffix.contains(" ") else { return nil }
        return String(suffix)
    }

    private var filteredCommands: [CommandInfo] {
        guard let query = commandQuery else { return [] }
        if query.isEmpty { return Array(model.commands.prefix(8)) }
        return model.commands.filter { $0.name.localizedCaseInsensitiveContains(query) }.prefix(8).map { $0 }
    }

    private var editorHeight: CGFloat {
        let lines = max(1, text.components(separatedBy: "\n").count)
        let wrapped = max(0, text.count / 78)
        return min(178, CGFloat(lines + wrapped) * 18 + 34)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let permission = model.pendingPermissions.first {
                ApprovalBanner(permission: permission, count: model.pendingPermissions.count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer
        }
        .frame(maxWidth: 880)
        .frame(maxWidth: .infinity)
        .animation(Motion.smooth, value: model.pendingPermissions.count)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls.prefix(8) {
                    let attachment = PromptAttachment(
                        uri: url.absoluteString,
                        name: url.lastPathComponent,
                        mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    )
                    if !attachments.contains(where: { $0.uri == attachment.uri }) {
                        attachments.append(attachment)
                    }
                }
            }
        }
        .onChange(of: text) { _, _ in
            scheduleMentionSearch()
        }
        .onAppear {
            focused = true
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(attachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
                }
                .scrollIndicators(.hidden)
            }

            if !filteredCommands.isEmpty {
                suggestionPanel(title: "COMMANDS") {
                    ForEach(filteredCommands) { command in
                        suggestionRow(
                            icon: "slash.circle",
                            title: "/\(command.name)",
                            subtitle: command.description ?? "Run command",
                            selected: false
                        ) {
                            text = "/\(command.name) "
                            focused = true
                        }
                    }
                }
            } else if !mentionResults.isEmpty, fileQuery != nil {
                suggestionPanel(title: "MENTION FILE") {
                    ForEach(mentionResults.prefix(7)) { file in
                        suggestionRow(
                            icon: file.isDirectory ? "folder" : "doc.text",
                            title: file.path,
                            subtitle: file.isDirectory ? "Folder" : "File",
                            selected: false
                        ) {
                            insert(filePath: file.path)
                        }
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ocTextTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ocTextPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($focused)
                    .frame(height: editorHeight)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 10)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            return .ignored
                        }
                        if commandQuery != nil, let command = filteredCommands.first {
                            text = "/\(command.name) "
                            return .handled
                        }
                        if fileQuery != nil, let file = mentionResults.first {
                            insert(filePath: file.path)
                            return .handled
                        }
                        submit()
                        return .handled
                    }
            }

            HStack(spacing: 5) {
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.ocTextTertiary)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help("Attach files")

                Button {
                    if !text.hasPrefix("/") { text = "/" }
                    focused = true
                } label: {
                    Image(systemName: "command")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(commandQuery != nil ? Color.ocAccent : Color.ocTextTertiary)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help("Commands")

                Button {
                    withAnimation(Motion.quick) { shellMode.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                        if shellMode { Text("SHELL") }
                    }
                    .font(.ocMono(9, weight: .semibold))
                    .foregroundStyle(shellMode ? Color.ocTeal : Color.ocTextTertiary)
                    .padding(.horizontal, shellMode ? 6 : 2)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(shellMode ? Color.ocTeal.opacity(0.10) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .help("Run a shell command instead of prompting the agent")

                Divider().frame(height: 14).opacity(0.5)

                agentMenu
                modelButton

                if model.isBusy {
                    deliveryMenu
                }

                Spacer()

                if let usage = model.selectedSession?.tokens, usage.total > 0 {
                    Text("\(Format.tokens(usage.total)) tok")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                        .padding(.trailing, 2)
                }

                if model.isBusy {
                    Button {
                        Task { await model.stopGeneration() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.ocDanger)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.ocDanger.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating (⌘.)")
                }

                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 29, height: 29)
                        .background(
                            Circle()
                                .fill(canSubmit ? AnyShapeStyle(LinearGradient(colors: [Color.ocAccent, Color.ocAccent.opacity(0.78)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.ocTextTertiary.opacity(0.2)))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help("Send (↩)")
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 8)
            .padding(.top, 2)

            HStack(spacing: 8) {
                if shellMode {
                    Tag(text: "SHELL MODE", icon: "terminal", tint: .ocTeal)
                } else {
                    Text("↩ send · ⇧↩ newline · @ files · / commands")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary.opacity(0.8))
                }
                Spacer()
                if !model.isBusy {
                    Text(model.delivery == "queue" ? "queue" : "steer")
                        .font(.ocMono(8))
                        .foregroundStyle(Color.ocTextTertiary.opacity(0.65))
                }
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 7)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.ocSurface.opacity(0.78))
                }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? Color.ocAccent.opacity(0.35) : Color.ocBorder, lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .animation(Motion.quick, value: focused)
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls.prefix(8) {
                if !attachments.contains(where: { $0.uri == url.absoluteString }) {
                    attachments.append(PromptAttachment(uri: url.absoluteString, name: url.lastPathComponent))
                }
            }
            return true
        }
    }

    private var agentMenu: some View {
        Menu {
            ForEach(model.primaryAgents) { agent in
                Button {
                    Task { await model.selectAgent(agent) }
                } label: {
                    if agent.id == model.selectedAgent {
                        Label(agent.name, systemImage: "checkmark")
                    } else {
                        Label(agent.name, systemImage: "person")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 9.5))
                Text(model.selectedAgentInfo?.name ?? model.selectedAgent.capitalized)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
            }
            .foregroundStyle(Color.ocTextSecondary)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.ocHover))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Agent")
    }

    private var modelButton: some View {
        Button {
            showModelPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(ModelCatalog.providerTint(model.selectedModel?.providerID ?? "opencode"))
                    .frame(width: 5, height: 5)
                Text(model.selectedModelInfo?.displayName ?? model.selectedModel?.shortName ?? "Model")
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.ocTextSecondary)
                if let variant = model.selectedModel?.variant, !variant.isEmpty, variant != "default" {
                    Text(variant.uppercased())
                        .font(.ocMono(7.5, weight: .semibold))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.ocHover))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
            ModelPickerView()
                .environmentObject(model)
                .environmentObject(prefs)
        }
    }

    private var deliveryMenu: some View {
        Menu {
            Button {
                model.delivery = "steer"
            } label: {
                if model.delivery == "steer" { Label("Steer", systemImage: "checkmark") } else { Text("Steer") }
            }
            Button {
                model.delivery = "queue"
            } label: {
                if model.delivery == "queue" { Label("Queue", systemImage: "checkmark") } else { Text("Queue") }
            }
        } label: {
            Image(systemName: model.delivery == "queue" ? "text.badge.plus" : "arrow.turn.down.right")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.ocTextTertiary)
                .frame(width: 22, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("How to deliver while busy")
    }

    private var placeholder: String {
        if shellMode { return "Run a shell command in this project…" }
        return "Ask the agent to build, fix, explain, or explore…"
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.canChat
    }

    private func submit() {
        guard canSubmit else { return }
        let value = text
        let files = attachments
        let useShell = shellMode
        text = ""
        attachments = []
        mentionResults = []
        showModelPicker = false

        var command = value
        if useShell && command.hasPrefix("$") {
            command.removeFirst()
        }
        Task {
            await model.sendMessage(command, files: files, shellMode: useShell)
        }
    }

    private func scheduleMentionSearch() {
        mentionTask?.cancel()
        guard let query = fileQuery else {
            mentionResults = []
            return
        }
        mentionTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            let results = await model.searchFiles(query.isEmpty ? "." : query)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                fileQuery != nil ? (mentionResults = results) : (mentionResults = [])
            }
        }
    }

    private func insert(filePath path: String) {
        guard let at = text.lastIndex(of: "@") else { return }
        let prefix = String(text[..<at])
        text = prefix + "@" + path + " "
        mentionResults = []
        focused = true
    }

    private func attachmentChip(_ attachment: PromptAttachment) -> some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.isImage ? "photo" : "doc")
                .font(.system(size: 8.5))
                .foregroundStyle(Color.ocTeal)
            Text(attachment.displayName)
                .font(.ocMono(9))
                .lineLimit(1)
                .frame(maxWidth: 160)
            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.ocTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.ocHover))
        .overlay(Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.5))
    }

    private func suggestionPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.ocMono(8, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.ocTextTertiary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            content()
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
        }
    }

    private func suggestionRow(
        icon: String,
        title: String,
        subtitle: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ocAccent)
                    .frame(width: 16)
                Text(title)
                    .font(.ocMono(10.5, weight: .medium))
                    .foregroundStyle(Color.ocTextPrimary)
                    .lineLimit(1)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 210, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(selected ? Color.ocHover : .clear)
        }
        .buttonStyle(.plain)
    }
}

struct ApprovalBanner: View {
    @EnvironmentObject private var model: AppModel
    var permission: PermissionRequest
    var count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ocWarning.opacity(0.12))
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ocWarning)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Permission required")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(permission.message ?? "\(permission.action) · \(permission.resources.prefix(2).joined(separator: ", "))")
                    .font(.ocMono(9.5))
                    .foregroundStyle(Color.ocTextSecondary)
                    .lineLimit(1)
                if count > 1 {
                    Text("+ \(count - 1) more request\(count > 2 ? "s" : "")")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Reject") {
                Task { await model.replyPermission(permission, decision: "reject") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.ocDanger)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.ocDanger.opacity(0.08)))

            Button("Always") {
                Task { await model.replyPermission(permission, decision: "always") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.ocTextSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.ocHover))

            Button("Allow once") {
                Task { await model.replyPermission(permission, decision: "once") }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 13).fill(Color.ocWarning.opacity(0.045)))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Color.ocWarning.opacity(0.22), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}

struct ModelPickerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ModelInfo] {
        let source = model.availableModels
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.modelID.localizedCaseInsensitiveContains(query) ||
            $0.providerID.localizedCaseInsensitiveContains(query)
        }
    }

    private var grouped: [(String, [ModelInfo])] {
        Dictionary(grouping: filtered) { $0.providerID }
            .map { ($0.key, $0.value.sorted { $0.displayName < $1.displayName }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ocTextTertiary)
                TextField("Search models", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                Text("\(filtered.count)")
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.ocSurfaceSunken)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(grouped, id: \.0) { provider, models in
                        Section {
                            ForEach(models) { item in
                                modelRow(item)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: ModelCatalog.providerSymbol(provider))
                                    .font(.system(size: 8.5))
                                Text(provider.uppercased())
                                    .font(.ocMono(8, weight: .semibold))
                                    .tracking(0.8)
                                Spacer()
                                Text("\(models.count)")
                                    .font(.ocMono(8))
                            }
                            .foregroundStyle(Color.ocTextTertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.ocSurface)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 430)
        }
        .frame(width: 370)
        .background(Color.ocSurface)
    }

    private func modelRow(_ item: ModelInfo) -> some View {
        let selected = model.selectedModel?.providerID == item.providerID && model.selectedModel?.id == item.modelID
        return HStack(spacing: 8) {
            Circle()
                .fill(ModelCatalog.providerTint(item.providerID))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color.ocTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.modelID)
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                    if let context = item.contextWindow {
                        Text("\(Format.tokens(Double(context))) ctx")
                            .font(.ocMono(8))
                            .foregroundStyle(Color.ocTextTertiary.opacity(0.7))
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.ocAccent)
            }
            if let variants = item.variants, !variants.isEmpty {
                Menu {
                    Button("Default") {
                        Task { await model.selectModel(item, variant: nil) }
                        dismiss()
                    }
                    ForEach(variants) { variant in
                        Button(variant.id.capitalized) {
                            Task { await model.selectModel(item, variant: variant.id) }
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(selected ? Color.ocAccent.opacity(0.08) : .clear)
        .onTapGesture {
            Task { await model.selectModel(item, variant: item.variants?.first?.id) }
            dismiss()
        }
    }
}
