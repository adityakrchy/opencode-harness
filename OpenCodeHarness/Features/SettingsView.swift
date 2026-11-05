import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case providers
    case mcp
    case plugins
    case configuration
    case about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .mcp: "MCP"
        case .plugins: "Plugins"
        case .configuration: "Configuration"
        case .about: "About"
        }
    }
    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .providers: "key.horizontal"
        case .mcp: "server.rack"
        case .plugins: "puzzlepiece.extension"
        case .configuration: "doc.text"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.ocBorder).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .general: GeneralSettingsView()
                    case .providers: ProvidersSettingsView()
                    case .mcp: McpSettingsView()
                    case .plugins: PluginsSettingsView()
                    case .configuration: ConfigurationSettingsView()
                    case .about: AboutSettingsView()
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ocCanvas)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color.ocCanvas)
        .task { await model.refreshSettingsData() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.ocRounded(15, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("OpenCode Harness")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            ForEach(SettingsSection.allCases) { item in
                Button {
                    withAnimation(Motion.quick) { section = item }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 17)
                        Text(item.title)
                            .font(.system(size: 12, weight: section == item ? .semibold : .regular))
                        Spacer()
                        if section == item {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.ocAccent)
                                .frame(width: 2.5, height: 15)
                        }
                    }
                    .foregroundStyle(section == item ? Color.ocTextPrimary : Color.ocTextSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 31)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(section == item ? Color.ocAccent.opacity(0.10) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            HStack(spacing: 6) {
                StatusDot(color: model.eventConnection == .connected ? .ocSuccess : .ocWarning)
                Text(model.serverInfo.map { "v\($0.version)" } ?? "offline")
                    .font(.ocMono(9))
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Button("Restart") {
                    Task { await model.restartServer() }
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(14)
        }
        .frame(width: 190)
        .background(
            ZStack {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Color.ocSidebar.opacity(0.5)
            }
        )
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.ocTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 12)
    }
}

private struct FieldLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.ocMono(9, weight: .medium))
            .foregroundStyle(Color.ocTextTertiary)
            .frame(width: 104, alignment: .leading)
    }
}

private struct SettingsTextField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 11.5))
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ocBorder, lineWidth: 0.5))
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "General", subtitle: "Connection, appearance, and behavior")

            SettingsCard(title: "OpenCode engine", subtitle: "How the harness reaches the OpenCode runtime") {
                HStack(spacing: 10) {
                    Picker("", selection: $prefs.connectionMode) {
                        ForEach(ServerMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 300)

                    Spacer()

                    HStack(spacing: 6) {
                        StatusDot(color: model.server.state == .ready ? .ocSuccess : .ocWarning, pulsing: model.server.state != .ready)
                        Text(serverStatus)
                            .font(.ocMono(9))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }

                if prefs.connectionMode == .local {
                    HStack(spacing: 10) {
                        FieldLabel(text: "Binary path")
                        SettingsTextField(placeholder: "Auto-detect opencode on PATH", text: $prefs.binaryPath)
                        Button("Detect") {
                            prefs.binaryPath = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(model.server.binaryPath ?? "The app will look in ~/.opencode/bin, Homebrew, and PATH.")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    HStack(spacing: 10) {
                        FieldLabel(text: "Server URL")
                        SettingsTextField(placeholder: "http://127.0.0.1:4096", text: $prefs.remoteURL)
                    }
                    HStack(spacing: 10) {
                        FieldLabel(text: "Password")
                        SettingsTextField(placeholder: "Server password", text: $prefs.remotePassword, secure: true)
                    }
                }

                HStack(spacing: 8) {
                    Button("Reconnect Engine") {
                        Task { await model.restartServer() }
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))

                    Button(showLogs ? "Hide Logs" : "Show Logs") {
                        withAnimation(Motion.smooth) { showLogs.toggle() }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if let info = model.serverInfo {
                        Text("PID \(info.pid) · \(info.capabilities?.persistentPty == true ? "PTY ready" : "core")")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }

                if showLogs {
                    ScrollView {
                        Text(model.server.logs.suffix(80).joined(separator: "\n"))
                            .font(.ocMono(9.5))
                            .foregroundStyle(Color.ocTextTertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                    }
                    .frame(height: 130)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.ocCodeBackground))
                }
            }

            SettingsCard(title: "Appearance", subtitle: "The harness follows native macOS materials") {
                HStack(spacing: 10) {
                    FieldLabel(text: "Theme")
                    Picker("", selection: $prefs.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    Spacer()
                }
                Toggle("Play a sound when the agent finishes", isOn: $prefs.completionSound)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                Toggle("Bounce the Dock icon when the app is in the background", isOn: $prefs.notificationsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                Toggle("Expand tool output by default", isOn: $prefs.showToolDetails)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                    .onChange(of: prefs.showToolDetails) { _, value in
                        model.showToolDetails = value
                    }
            }

            SettingsCard(title: "Workspace", subtitle: "OpenCode runs with the selected folder as its working directory") {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.ocAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.workspace?.name ?? "No project")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.ocTextPrimary)
                        Text(model.workspace?.directory ?? "—")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Switch…") { model.chooseWorkspace() }
                        .buttonStyle(.bordered)
                    Button("Reveal") { model.revealWorkspaceInFinder() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var serverStatus: String {
        switch model.server.state {
        case .ready: "ready"
        case .starting: "starting"
        case .connecting: "connecting"
        case .locating: "locating binary"
        case .failed: "failed"
        case .stopped: "stopped"
        case .idle: "idle"
        }
    }
}

// MARK: - Providers

struct ProvidersSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var connectIntegration: IntegrationInfo?
    @State private var method: IntegrationMethod?
    @State private var integrationQuery = ""

    private var visibleIntegrations: [IntegrationInfo] {
        let sorted = model.integrations.sorted { lhs, rhs in
            let lhsConnected = lhs.connections?.isEmpty == false
            let rhsConnected = rhs.connections?.isEmpty == false
            if lhsConnected != rhsConnected { return lhsConnected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        guard !integrationQuery.isEmpty else { return Array(sorted.prefix(18)) }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(integrationQuery) ||
            $0.id.localizedCaseInsensitiveContains(integrationQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Providers", subtitle: "Credentials stay in the local OpenCode runtime")

            SettingsCard(title: "Model providers", subtitle: "\(model.providers.count) providers available in this workspace") {
                if model.providers.isEmpty {
                    Text("No providers reported yet. Add a credential below or configure a provider in opencode.json.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ocTextTertiary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(model.providers) { provider in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(ModelCatalog.providerTint(provider.id))
                                    .frame(width: 5, height: 5)
                                Text(provider.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.ocTextSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.ocHover))
                            .overlay(Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.5))
                        }
                    }
                }
            }

            SettingsCard(title: "Integrations", subtitle: "Connect API keys or OAuth accounts") {
                if model.integrations.isEmpty {
                    Text("Loading integrations…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ocTextTertiary)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.ocTextTertiary)
                        TextField("Search providers", text: $integrationQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                        Text("\(model.integrations.count)")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ocBorder, lineWidth: 0.5))

                    VStack(spacing: 0) {
                        ForEach(visibleIntegrations) { integration in
                            integrationRow(integration)
                            if integration.id != visibleIntegrations.last?.id {
                                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
                            }
                        }
                    }
                    if integrationQuery.isEmpty, model.integrations.count > 18 {
                        Text("Showing connected and 18 providers · search to find all \(model.integrations.count)")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }
            }

            SettingsCard(title: "Stored credentials", subtitle: "Managed by the OpenCode server") {
                if model.credentials.isEmpty {
                    Text("No stored credentials.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ocTextTertiary)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.credentials) { credential in
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(credential.active ? Color.ocSuccess : Color.ocTextTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(credential.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color.ocTextPrimary)
                                    Text("\(credential.integrationID) · \(credential.kind)")
                                        .font(.ocMono(8.5))
                                        .foregroundStyle(Color.ocTextTertiary)
                                }
                                Spacer()
                                if credential.active {
                                    Tag(text: "ACTIVE", tint: .ocSuccess)
                                }
                                Button(role: .destructive) {
                                    Task { await model.removeCredential(credential) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9.5))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.ocTextTertiary)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken.opacity(0.6)))
                        }
                    }
                }
            }
        }
        .sheet(item: $connectIntegration) { integration in
            ConnectIntegrationSheet(integration: integration)
                .environmentObject(model)
        }
    }

    private func integrationRow(_ integration: IntegrationInfo) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ModelCatalog.providerSymbol(integration.id))
                .font(.system(size: 11))
                .foregroundStyle(ModelCatalog.providerTint(integration.id))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(integration.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(integration.methods.map(\.displayLabel).joined(separator: " · "))
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if let connection = integration.connections?.first {
                Tag(text: connection.label ?? connection.name ?? "CONNECTED", tint: .ocSuccess)
            }
            Button(integration.connections?.isEmpty == false ? "Add" : "Connect") {
                connectIntegration = integration
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 7)
    }
}

struct ConnectIntegrationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var integration: IntegrationInfo

    @State private var selectedMethod: IntegrationMethod?
    @State private var key = ""
    @State private var label = ""
    @State private var answerText: [String: String] = [:]
    @State private var answerBool: [String: Bool] = [:]
    @State private var multi: [String: Set<String>] = [:]
    @State private var submitting = false
    @State private var oauthAttemptID: String?
    @State private var oauthURL: String?
    @State private var oauthInstructions: String?
    @State private var oauthCode = ""
    @State private var oauthStatus = ""
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: ModelCatalog.providerSymbol(integration.id))
                    .font(.system(size: 16))
                    .foregroundStyle(ModelCatalog.providerTint(integration.id))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ModelCatalog.providerTint(integration.id).opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect \(integration.name)")
                        .font(.ocRounded(17, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("Credentials are stored by the local OpenCode server.")
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

            if integration.methods.count > 1 {
                Picker("Method", selection: Binding(
                    get: { selectedMethod?.stableID ?? integration.methods.first?.stableID ?? "" },
                    set: { id in selectedMethod = integration.methods.first { $0.stableID == id } }
                )) {
                    ForEach(integration.methods) { method in
                        Text(method.displayLabel).tag(method.stableID)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let method = selectedMethod ?? integration.methods.first {
                methodForm(method)
            } else {
                Text("This integration does not expose a connection method.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextTertiary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                if (selectedMethod ?? integration.methods.first)?.type == "oauth" {
                    Button(oauthAttemptID == nil ? "Start sign-in" : "I've finished") {
                        if oauthAttemptID == nil {
                            startOAuth()
                        } else {
                            pollOAuth()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(submitting)
                } else {
                    Button("Connect") {
                        connect()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(submitting || ((selectedMethod ?? integration.methods.first)?.type == "key" && key.isEmpty))
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .background(Color.ocCanvas)
        .onAppear { selectedMethod = integration.methods.first }
        .onDisappear { pollingTask?.cancel() }
    }

    @ViewBuilder
    private func methodForm(_ method: IntegrationMethod) -> some View {
        switch method.type {
        case "key":
            VStack(alignment: .leading, spacing: 9) {
                labeledField("API key") {
                    SettingsTextField(placeholder: "Paste key", text: $key, secure: true)
                }
                labeledField("Label") {
                    SettingsTextField(placeholder: "Optional label", text: $label)
                }
                answerFields(method.form ?? [])
            }
        case "oauth":
            VStack(alignment: .leading, spacing: 9) {
                Text("This provider uses an OAuth browser flow.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextSecondary)
                if let oauthInstructions, !oauthInstructions.isEmpty {
                    Text(oauthInstructions)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.ocTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let oauthURL, let url = URL(string: oauthURL) {
                    Link(destination: url) {
                        Label("Open authorization page", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }
                if !oauthStatus.isEmpty {
                    HStack(spacing: 6) {
                        if oauthAttemptID != nil { Spinner(size: 10) }
                        Text(oauthStatus)
                            .font(.ocMono(9.5))
                            .foregroundStyle(Color.ocTextSecondary)
                    }
                }
                labeledField("Authorization code") {
                    SettingsTextField(placeholder: "Paste code if prompted", text: $oauthCode)
                }
                if oauthAttemptID != nil {
                    Button("Submit code") {
                        completeOAuth()
                    }
                    .buttonStyle(.bordered)
                    .disabled(oauthCode.isEmpty)
                }
                answerFields(method.form ?? [])
            }
        case "external":
            VStack(alignment: .leading, spacing: 8) {
                Text("This provider uses an external sign-in flow.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextSecondary)
                answerFields(method.form ?? [])
            }
        case "command":
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this command in a terminal to connect:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextSecondary)
                HStack {
                    Text((method.command ?? []).joined(separator: " "))
                        .font(.ocMono(10))
                        .foregroundStyle(Color.ocTextPrimary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString((method.command ?? []).joined(separator: " "), forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocSurfaceSunken))
            }
        case "env":
            VStack(alignment: .leading, spacing: 8) {
                Text("Set one of these environment variables before launching OpenCode:")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextSecondary)
                ForEach(method.names ?? [], id: \.self) { name in
                    Text(name)
                        .font(.ocMono(10))
                        .foregroundStyle(Color.ocTextPrimary)
                        .textSelection(.enabled)
                }
            }
        default:
            Text("Unsupported method: \(method.type)")
                .font(.system(size: 11))
                .foregroundStyle(Color.ocTextTertiary)
        }
    }

    @ViewBuilder
    private func answerFields(_ fields: [FormField]) -> some View {
        ForEach(fields.filter { $0.hidden != true }) { field in
            if let options = field.options, !options.isEmpty {
                labeledField(field.label) {
                    Picker("", selection: Binding(
                        get: { answerText[field.key] ?? "" },
                        set: { answerText[field.key] = $0 }
                    )) {
                        Text("Select…").tag("")
                        ForEach(options) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } else if field.type == "boolean" {
                Toggle(field.label, isOn: Binding(
                    get: { answerBool[field.key] ?? false },
                    set: { answerBool[field.key] = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11))
            } else if field.type == "multiselect" {
                VStack(alignment: .leading, spacing: 5) {
                    Text(field.label)
                        .font(.ocMono(9, weight: .medium))
                        .foregroundStyle(Color.ocTextTertiary)
                    FlowLayout(spacing: 5) {
                        ForEach(field.options ?? []) { option in
                            let selected = multi[field.key]?.contains(option.value) ?? false
                            Button {
                                var set = multi[field.key] ?? []
                                if selected { set.remove(option.value) } else { set.insert(option.value) }
                                multi[field.key] = set
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(selected ? Color.ocAccent : Color.ocTextSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(selected ? Color.ocAccent.opacity(0.10) : Color.ocHover))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                labeledField(field.label) {
                    SettingsTextField(placeholder: field.placeholder ?? "", text: Binding(
                        get: { answerText[field.key] ?? "" },
                        set: { answerText[field.key] = $0 }
                    ))
                }
            }
        }
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            FieldLabel(text: label)
            content()
        }
    }

    private func buildAnswer() -> [String: JSONValue] {
        var answer: [String: JSONValue] = [:]
        for (key, value) in answerText where !value.isEmpty { answer[key] = .string(value) }
        for (key, value) in answerBool { answer[key] = .bool(value) }
        for (key, value) in multi { answer[key] = .array(value.sorted().map(JSONValue.string)) }
        return answer
    }

    private func connect() {
        guard let method = selectedMethod ?? integration.methods.first else { return }
        submitting = true
        Task {
            await model.connectIntegration(integration, method: method, key: key, answer: buildAnswer())
            submitting = false
            dismiss()
        }
    }

    private func startOAuth() {
        guard let method = selectedMethod ?? integration.methods.first, let api = model.api else { return }
        submitting = true
        Task {
            do {
                let attempt = try await api.startIntegrationOAuth(integration.id, methodID: method.id ?? method.type, answer: buildAnswer().isEmpty ? nil : buildAnswer())
                oauthAttemptID = attempt["attemptID"]?.string
                oauthURL = attempt["url"]?.string
                oauthInstructions = attempt["instructions"]?.string
                oauthStatus = "Waiting for authorization…"
                if let urlString = oauthURL, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
                submitting = false
                startPolling()
            } catch {
                model.presentError(error)
                submitting = false
            }
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                pollOAuth()
            }
        }
    }

    private func pollOAuth() {
        guard let attempt = oauthAttemptID, let api = model.api else { return }
        Task {
            do {
                let status = try await api.integrationOAuthStatus(integration.id, attemptID: attempt)
                let value = status["status"]?.string ?? ""
                if value == "complete" {
                    oauthStatus = "Connected"
                    pollingTask?.cancel()
                    await model.refreshSettingsData()
                    await model.loadCatalog()
                    dismiss()
                } else if value == "failed" {
                    oauthStatus = status["message"]?.string ?? "Authorization failed"
                    pollingTask?.cancel()
                } else if value == "expired" {
                    oauthStatus = "Authorization expired. Start again."
                    pollingTask?.cancel()
                } else {
                    oauthStatus = "Waiting for authorization in your browser…"
                }
            } catch {
                oauthStatus = error.localizedDescription
            }
        }
    }

    private func completeOAuth() {
        guard let attempt = oauthAttemptID, let api = model.api else { return }
        Task {
            do {
                try await api.completeIntegrationOAuth(integration.id, attemptID: attempt, code: oauthCode.isEmpty ? nil : oauthCode)
                oauthStatus = "Code submitted"
            } catch { model.presentError(error) }
        }
    }
}

// MARK: - MCP

struct McpSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Model Context Protocol", subtitle: "Connect tools, resources, and prompts")

            SettingsCard(title: "MCP servers", subtitle: "\(model.mcpServers.filter { $0.statusName == "connected" }.count) connected") {
                if model.mcpServers.isEmpty {
                    VStack(spacing: 8) {
                        Text("No MCP servers configured.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.ocTextTertiary)
                        Button("Add Server") { showAdd = true }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.mcpServers) { server in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(mcpColor(server.statusName))
                                    .frame(width: 6, height: 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(server.name)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Color.ocTextPrimary)
                                    Text(server.statusName.replacingOccurrences(of: "_", with: " "))
                                        .font(.ocMono(8.5))
                                        .foregroundStyle(Color.ocTextTertiary)
                                }
                                Spacer()
                                Button {
                                    Task { await model.toggleMcp(server) }
                                } label: {
                                    Text(server.statusName == "connected" ? "Disconnect" : "Connect")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                Button(role: .destructive) {
                                    Task { await model.removeMcp(server) }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9.5))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.ocTextTertiary)
                            }
                            .padding(.vertical, 7)
                            if server.id != model.mcpServers.last?.id {
                                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
                            }
                        }
                    }
                }
                Button {
                    showAdd = true
                } label: {
                    Label("Add MCP server", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            SettingsCard(title: "About MCP", subtitle: "OpenCode exposes MCP tools directly to the agent") {
                Text("Servers are loaded from your OpenCode configuration. Changes are applied to the running engine and persisted by the OpenCode server.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddMcpSheet()
                .environmentObject(model)
        }
    }

    private func mcpColor(_ status: String) -> Color {
        switch status {
        case "connected": .ocSuccess
        case "failed", "needs_auth": .ocDanger
        case "pending": .ocWarning
        default: .ocTextTertiary
        }
    }
}

struct AddMcpSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "local"
    @State private var command = ""
    @State private var url = ""
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add MCP server")
                    .font(.ocRounded(18, weight: .bold))
                    .foregroundStyle(Color.ocTextPrimary)
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

            Picker("", selection: $type) {
                Text("Local command").tag("local")
                Text("Remote URL").tag("remote")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                FieldLabel(text: "Name")
                SettingsTextField(placeholder: "my-server", text: $name)
            }

            if type == "local" {
                HStack(spacing: 10) {
                    FieldLabel(text: "Command")
                    SettingsTextField(placeholder: "npx -y @modelcontextprotocol/server-filesystem .", text: $command)
                }
            } else {
                HStack(spacing: 10) {
                    FieldLabel(text: "URL")
                    SettingsTextField(placeholder: "https://mcp.example.com/sse", text: $url)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add server") {
                    submitting = true
                    Task {
                        await model.addMcp(name: name, type: type, command: command, url: url)
                        submitting = false
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (type == "local" ? command.isEmpty : url.isEmpty) || submitting)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Color.ocCanvas)
    }
}

// MARK: - Plugins

struct PluginsSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Plugins", subtitle: "Extensions loaded by the OpenCode engine")

            SettingsCard(title: "Installed plugins", subtitle: "\(model.plugins.count) loaded") {
                if model.plugins.isEmpty {
                    Text("No plugins loaded for this workspace.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ocTextTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.plugins) { plugin in
                            HStack(spacing: 8) {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(plugin.status == "active" ? Color.ocTeal : Color.ocDanger)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(plugin.sourceLabel)
                                        .font(.ocMono(10))
                                        .foregroundStyle(Color.ocTextPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 5) {
                                        Text(plugin.source["type"]?.string ?? "plugin")
                                        if plugin.isOutdated { Text("· update available").foregroundStyle(Color.ocWarning) }
                                    }
                                    .font(.ocMono(8.5))
                                    .foregroundStyle(Color.ocTextTertiary)
                                }
                                Spacer()
                                Tag(text: plugin.status.uppercased(), tint: plugin.status == "active" ? .ocSuccess : .ocDanger)
                            }
                            .padding(.vertical, 7)
                            if plugin.id != model.plugins.last?.id {
                                Rectangle().fill(Color.ocBorder).frame(height: 0.5)
                            }
                        }
                    }
                }
                HStack {
                    Button("Check for updates") {
                        Task { await model.checkPluginUpdates() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("Plugins come from opencode.json and npm packages.")
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
            }
        }
    }
}

// MARK: - Configuration

struct ConfigurationSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Configuration", subtitle: "Inspect and reload the running engine")

            SettingsCard(title: "Configuration files", subtitle: "Read-only paths reported by OpenCode") {
                if model.configEntries.isEmpty {
                    Text("No configuration documents found.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ocTextTertiary)
                } else {
                    ForEach(Array(model.configEntries.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry["type"]?.string == "directory" ? "folder" : "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(entry["type"]?.string == "directory" ? Color.ocTeal : Color.ocTextTertiary)
                            Text(entry["path"]?.string ?? "")
                                .font(.ocMono(9.5))
                                .foregroundStyle(Color.ocTextSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if let path = entry["path"]?.string,
                               let url = URL(string: "file://\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)") {
                                Button("Open") { NSWorkspace.shared.open(url) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                HStack {
                    Button("Open Config") { model.openConfigFile() }
                        .buttonStyle(.bordered)
                    Button("Reload Configuration") {
                        Task { await model.reloadConfiguration() }
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    Spacer()
                }
            }

            SettingsCard(title: "Shell", subtitle: "The shell OpenCode uses for shell commands") {
                let current = currentShell
                HStack(spacing: 10) {
                    FieldLabel(text: "Shell")
                    Picker("", selection: Binding(
                        get: { current },
                        set: { value in Task { await model.setShell(value) } }
                    )) {
                        ForEach(model.shellOptions, id: \.self) { option in
                            let path = option["path"]?.string ?? ""
                            Text("\(option["name"]?.string ?? path)\(option["acceptable"]?.bool == false ? " (unsupported)" : "")")
                                .tag(path)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 360)
                    Spacer()
                }
                if !current.isEmpty {
                    Text(current)
                        .font(.ocMono(8.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
            }

            SettingsCard(title: "Runtime", subtitle: "Local engine details") {
                infoRow("Version", model.serverInfo?.version ?? "—")
                infoRow("PID", model.serverInfo.map { String($0.pid) } ?? "—")
                infoRow("Temp path", model.serverInfo?.paths?.tmp ?? "—")
                infoRow("Worktrees", "\(model.worktrees.count)")
                HStack {
                    Button(showLogs ? "Hide logs" : "Show logs") {
                        withAnimation(Motion.smooth) { showLogs.toggle() }
                    }
                    .buttonStyle(.bordered)
                    Button("Reconnect engine") {
                        Task { await model.restartServer() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                if showLogs {
                    ScrollView {
                        Text(model.server.logs.suffix(100).joined(separator: "\n"))
                            .font(.ocMono(9))
                            .foregroundStyle(Color.ocTextTertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.ocCodeBackground))
                }
            }
        }
    }

    private var currentShell: String {
        if let document = model.configEntries.first(where: { $0["type"]?.string == "document" }),
           let shell = document["info"]?["shell"]?.string {
            return shell
        }
        return model.shellOptions.first { $0["acceptable"]?.bool == true }?["path"]?.string ?? "/bin/zsh"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.ocTextTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.ocMono(9))
                .foregroundStyle(Color.ocTextSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "About", subtitle: "A native harness for the OpenCode agent")

            VStack(spacing: 16) {
                BrandMark(size: 78, glow: true)
                VStack(spacing: 4) {
                    Text("OpenCode Harness")
                        .font(.ocRounded(24, weight: .bold))
                        .foregroundStyle(Color.ocTextPrimary)
                    Text("Version 1.0 · SwiftUI for macOS")
                        .font(.ocMono(9.5))
                        .foregroundStyle(Color.ocTextTertiary)
                }
                Text("A first-class desktop surface for the OpenCode engine. Sessions, tools, diffs, approvals, providers, MCP, and usage — all native, all local.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.ocTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .lineSpacing(3)
                HStack(spacing: 9) {
                    if let url = URL(string: "https://opencode.ai") {
                        Link("opencode.ai", destination: url)
                            .buttonStyle(.bordered)
                    }
                    if let url = URL(string: "https://opencode.ai/docs") {
                        Link("Documentation", destination: url)
                            .buttonStyle(.bordered)
                    }
                    if let url = URL(string: "https://github.com/sst/opencode") {
                        Link("GitHub", destination: url)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .cardSurface(radius: 14)

            SettingsCard(title: "Engine", subtitle: "The harness launches a private OpenCode server") {
                HStack(spacing: 10) {
                    StatusDot(color: model.server.state == .ready ? .ocSuccess : .ocWarning)
                    Text(model.serverInfo.map { "OpenCode \($0.version) · PID \($0.pid)" } ?? "Engine offline")
                        .font(.ocMono(9.5))
                        .foregroundStyle(Color.ocTextSecondary)
                    Spacer()
                    if let info = model.serverInfo, let url = info.urls.first {
                        Button("Copy URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

// MARK: - Shared

struct SettingsHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.ocRounded(22, weight: .bold))
                .foregroundStyle(Color.ocTextPrimary)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.ocTextTertiary)
        }
    }
}
