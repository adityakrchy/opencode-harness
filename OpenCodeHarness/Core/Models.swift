import Foundation
import SwiftUI

// MARK: - Core API models

struct LocationRef: Codable, Hashable, Sendable {
    var directory: String
}

struct ProjectTime: Codable, Hashable, Sendable {
    var created: Double?
    var updated: Double?
    var active: Double?
}

struct ProjectIcon: Codable, Hashable, Sendable {
    var url: String?
    var override: String?
    var color: String?
}

struct ProjectInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var canonical: String
    var name: String?
    var vcs: String?
    var icon: ProjectIcon?
    var commands: ProjectCommands?
    var time: ProjectTime?
    var sandboxes: [String]?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: canonical).lastPathComponent
    }

    var folderURL: URL { URL(fileURLWithPath: canonical, isDirectory: true) }
}

struct ProjectCommands: Codable, Hashable, Sendable {
    var start: String?
}

struct ModelRef: Codable, Hashable, Sendable {
    var id: String
    var providerID: String
    var variant: String?

    var key: String {
        "\(providerID)/\(id)\(variant.map { "#\($0)" } ?? "")"
    }

    var shortName: String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    static func parse(_ key: String) -> ModelRef? {
        guard !key.isEmpty else { return nil }
        let variantParts = key.split(separator: "#", maxSplits: 1).map(String.init)
        let base = variantParts[0]
        let parts = base.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return ModelRef(id: parts[1], providerID: parts[0], variant: variantParts.count > 1 ? variantParts[1] : nil)
    }
}

struct TokenUsage: Codable, Hashable, Sendable {
    var input: Double = 0
    var output: Double = 0
    var reasoning: Double = 0
    var cache: CacheUsage = CacheUsage()

    struct CacheUsage: Codable, Hashable, Sendable {
        var read: Double = 0
        var write: Double = 0
    }

    var total: Double { input + output + reasoning }
}

struct SessionTime: Codable, Hashable, Sendable {
    var created: Double
    var updated: Double
    var idle: Double?
    var viewed: Double?
    var archived: Double?

    var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
    var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
    var idleDate: Date? { idle.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct RevertInfo: Codable, Hashable, Sendable {
    var messageID: String
    var partID: String?
    var snapshot: String?
    var files: [FileDiff]?
}

struct SessionInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var projectID: String
    var parentID: String?
    var fork: SessionFork?
    var agent: String?
    var model: ModelRef?
    var cost: Double?
    var tokens: TokenUsage?
    var outcome: String?
    var time: SessionTime
    var title: String?
    var subpath: String?
    var revert: RevertInfo?
    var location: LocationRef?

    struct SessionFork: Codable, Hashable, Sendable {
        var sessionID: String
        /// The server models this as a structured boundary object.
        var boundary: JSONValue?
    }

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return "Untitled session"
    }

    var directory: String { location?.directory ?? "" }
    var isRunning: Bool { outcome == nil && time.idle == nil }
}

struct SessionsPage: Codable, Sendable {
    var data: [SessionInfo]
    var cursor: Cursor?

    struct Cursor: Codable, Sendable {
        var previous: String?
        var next: String?
    }
}

struct ModelLimit: Codable, Hashable, Sendable {
    var context: Int?
    var input: Int?
    var output: Int?
}

struct ModelCost: Codable, Hashable, Sendable {
    var input: Double?
    var output: Double?
    var cache: ModelCacheCost?
}

struct ModelCacheCost: Codable, Hashable, Sendable {
    var read: Double?
    var write: Double?
}

struct ModelCapabilities: Codable, Hashable, Sendable {
    var tools: Bool?
    var input: [String]?
    var output: [String]?
    var temperature: Bool?
}

struct ModelVariant: Codable, Identifiable, Hashable, Sendable {
    var id: String
}

struct ModelInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var modelID: String
    var providerID: String
    var canonical: String?
    var family: String?
    var name: String
    var settings: JSONValue?
    var headers: [String: String]?
    var capabilities: ModelCapabilities?
    var variants: [ModelVariant]?
    var time: ModelTime?
    var cost: [ModelCost]?
    var status: String?
    var enabled: Bool?
    var limit: ModelLimit?

    struct ModelTime: Codable, Hashable, Sendable {
        var released: Double?
    }

    var ref: ModelRef {
        ModelRef(id: modelID, providerID: providerID, variant: nil)
    }

    var displayName: String {
        name.isEmpty ? modelID : name
    }

    var isAvailable: Bool {
        enabled != false && status != "deprecated"
    }

    var contextWindow: Int? { limit?.context }
}

struct ProviderInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var canonical: String?
    var integrationID: String?
    var name: String
    var activation: String?
    var package: String?
    var settings: JSONValue?
    var headers: [String: String]?
}

struct AgentInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var model: ModelRef?
    var description: String?
    var mode: String?
    var hidden: Bool?
    var color: String?
    var steps: Int?
    var permissions: [PermissionRule]?
}

struct PermissionRule: Codable, Hashable, Sendable {
    var action: String
    var resource: String
    var effect: String?
}

struct CommandInfo: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var description: String?

    var id: String { name }
}

struct SkillInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var autoinvoke: Bool?
    var path: String?
}

struct FileDiff: Codable, Identifiable, Hashable, Sendable {
    var file: String
    var patch: String
    var additions: Int
    var deletions: Int
    var status: String

    var id: String { file }

    var changeLabel: String {
        switch status {
        case "added": "Added"
        case "deleted": "Deleted"
        default: "Modified"
        }
    }
}

struct VcsFileStatus: Codable, Identifiable, Hashable, Sendable {
    var file: String
    var additions: Int
    var deletions: Int
    var status: String

    var id: String { file }
}

struct VcsInfo: Codable, Hashable, Sendable {
    var provider: String?
    var branch: VcsBranch?
}

struct VcsBranch: Codable, Hashable, Sendable {
    var current: String?
    var `default`: String?
}

struct ServerInfo: Codable, Hashable, Sendable {
    var version: String
    var pid: Int
    var urls: [String]
    var paths: ServerPaths?
    var capabilities: ServerCapabilities?

    struct ServerPaths: Codable, Hashable, Sendable {
        var tmp: String?
    }

    struct ServerCapabilities: Codable, Hashable, Sendable {
        var persistentPty: Bool?
    }
}

struct ShellInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var status: String
    var command: String
    var cwd: String
    var shell: String
    var file: String?
    var pid: Int?
    var exit: Double?
    var signal: String?
    var metadata: JSONValue?
    var time: ShellTime

    struct ShellTime: Codable, Hashable, Sendable {
        var started: Double
        var completed: Double?
    }

    var startedDate: Date { Date(timeIntervalSince1970: time.started / 1000) }
    var isRunning: Bool { status == "running" }
}

struct ShellOutput: Codable, Hashable, Sendable {
    var output: String
    var cursor: Int
    var size: Int
    var truncated: Bool
}

struct PermissionRequest: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var sessionID: String
    var action: String
    var resources: [String]
    var save: [String]?
    var metadata: JSONValue?
    var source: JSONValue?
    var message: String?
}

struct FormInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var sessionID: String
    var title: String
    var metadata: JSONValue?
    var fields: [FormField]
}

struct FormField: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var title: String?
    var description: String?
    var required: Bool?
    var hidden: Bool?
    var type: String
    var format: String?
    var minLength: Int?
    var maxLength: Int?
    var pattern: String?
    var placeholder: String?
    var `default`: JSONValue?
    var options: [FormOption]?
    var minItems: Int?
    var maxItems: Int?
    var custom: Bool?
    var url: String?

    var id: String { key }
    var label: String { title?.isEmpty == false ? title! : key }
}

struct FormOption: Codable, Identifiable, Hashable, Sendable {
    var value: String
    var label: String
    var description: String?

    var id: String { value }
}

struct McpServer: Codable, Identifiable, Hashable, Sendable {
    var name: String
    var status: JSONValue
    var integrationID: String?

    var id: String { name }
    var statusName: String { status["status"]?.string ?? "unknown" }
}

struct IntegrationInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var metadata: JSONValue?
    var methods: [IntegrationMethod]
    var connections: [IntegrationConnection]?
}

struct IntegrationMethod: Codable, Identifiable, Hashable, Sendable {
    var id: String?
    var type: String
    var label: String?
    var form: [FormField]?
    var command: [String]?
    var names: [String]?

    var stableID: String { id ?? "\(type)-\(label ?? "")" }
    var displayLabel: String { label ?? type.capitalized }
}

struct IntegrationConnection: Codable, Identifiable, Hashable, Sendable {
    var id: String?
    var type: String?
    var label: String?
    var active: Bool?
    var status: String?
    var name: String?
}

struct CredentialEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var integrationID: String
    var label: String
    var active: Bool
    var value: JSONValue?

    var kind: String { value?["type"]?.string ?? "unknown" }
}

struct PluginInfo: Codable, Identifiable, Hashable, Sendable {
    var id: String?
    var source: JSONValue
    var features: JSONValue?
    var state: JSONValue?

    var stableID: String {
        id ?? source["target"]?.string ?? source["path"]?.string ?? "plugin-\(abs(hashValue))"
    }
    var sourceLabel: String {
        source["target"]?.string ?? source["path"]?.string ?? source["type"]?.string ?? "built-in"
    }
    var status: String { state?["status"]?.string ?? "unknown" }
    var isOutdated: Bool { source["outdated"]?.bool == true }
}

struct WorktreeInfo: Codable, Identifiable, Hashable, Sendable {
    var directory: String
    var strategy: String?
    var id: String { directory }
}

struct SessionActiveInfo: Codable, Hashable, Sendable {
    var type: String
}

struct StatsActivity: Codable, Identifiable, Hashable, Sendable {
    var date: String
    var steps: Int
    var id: String { date }
}

struct StatsModelUsage: Codable, Identifiable, Hashable, Sendable {
    var model: ModelRef
    var steps: Int
    var tokens: TokenUsage
    var cost: Double
    var id: String { model.key }
}

struct SessionStatsInfo: Codable, Hashable, Sendable {
    var range: StatsRange
    var sessions: Int
    var subagents: Int?
    var prompts: Int
    var steps: Int
    var tokens: TokenUsage
    var cost: Double
    var tools: JSONValue?
    var activeDays: Int
    var streak: Int?
    var activity: [StatsActivity]
    var models: [StatsModelUsage]

    struct StatsRange: Codable, Hashable, Sendable {
        var from: Double
        var to: Double
    }
}

struct PromptAttachment: Codable, Identifiable, Hashable, Sendable {
    var uri: String
    var name: String?
    var mime: String?
    var description: String?

    var id: String { uri }
    var displayName: String { name ?? URL(string: uri)?.lastPathComponent ?? uri }
    var isImage: Bool {
        let ext = URL(string: uri)?.pathExtension.lowercased() ?? ""
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"].contains(ext)
    }
}

// MARK: - Chat timeline

struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case user
        case assistant
        case idle
        case shell
        case system
        case synthetic
        case skill
        case compaction
        case agentSwitched
        case modelSwitched
        case locationSwitched
    }

    var id: String
    var kind: Kind
    var createdAt: Date
    var completedAt: Date?
    var userText: String?
    var blocks: [MessageBlock]
    var model: ModelRef?
    var agent: String?
    var cost: Double?
    var tokens: TokenUsage?
    var finish: String?
    var outcome: String?
    var errorText: String?
    var command: String?
    var shellOutput: String?
    var shellStatus: String?
    var shellExit: Double?
    var compactionText: String?
    var attachments: [PromptAttachment]
    var isStreaming: Bool

    var isEmptyAssistant: Bool {
        kind == .assistant && blocks.allSatisfy { block in
            switch block.kind {
            case .text, .reasoning: block.text.isEmpty
            case .tool: false
            }
        }
    }

    var copyableText: String {
        if let userText { return userText }
        if let command { return "$ \(command)" }
        return blocks.map { block in
            switch block.kind {
            case .text, .reasoning: block.text
            case .tool: block.tool?.copyableText ?? ""
            }
        }.joined(separator: "\n\n")
    }

    static func parse(_ value: JSONValue) -> ChatMessage? {
        guard let object = value.object,
              let id = object["id"]?.string,
              let type = object["type"]?.string else { return nil }

        let created = object["time"]?["created"]?.double ?? 0
        let completed = object["time"]?["completed"]?.double
        let kind: Kind
        switch type {
        case "user": kind = .user
        case "assistant": kind = .assistant
        case "idle": kind = .idle
        case "shell": kind = .shell
        case "system": kind = .system
        case "synthetic": kind = .synthetic
        case "skill": kind = .skill
        case "compaction": kind = .compaction
        case "agent-switched": kind = .agentSwitched
        case "model-switched": kind = .modelSwitched
        case "location-switched": kind = .locationSwitched
        default: return nil
        }

        var message = ChatMessage(
            id: id,
            kind: kind,
            createdAt: Date(timeIntervalSince1970: created / 1000),
            completedAt: completed.map { Date(timeIntervalSince1970: $0 / 1000) },
            userText: object["text"]?.string,
            blocks: [],
            model: nil,
            agent: object["agent"]?.string,
            cost: object["cost"]?.double,
            tokens: object["tokens"]?.decoded(TokenUsage.self),
            finish: object["finish"]?.string,
            outcome: object["outcome"]?.string,
            errorText: object["error"]?["message"]?.string,
            command: object["command"]?.string,
            shellOutput: object["output"]?["output"]?.string,
            shellStatus: object["status"]?.string,
            shellExit: object["exit"]?.double,
            compactionText: nil,
            attachments: [],
            isStreaming: completed == nil && type == "assistant"
        )

        if let model = object["model"] {
            message.model = model.decoded(ModelRef.self)
        }

        if kind == .user, let files = object["files"]?.array {
            message.attachments = files.compactMap { file in
                guard let uri = file["source"]?["uri"]?.string ?? file["uri"]?.string else { return nil }
                return PromptAttachment(
                    uri: uri,
                    name: file["name"]?.string,
                    mime: file["mime"]?.string,
                    description: file["description"]?.string
                )
            }
        }

        if kind == .compaction {
            let status = object["status"]?.string ?? object["state"]?.string ?? "compaction"
            let text = object["summary"]?.string ?? object["text"]?.string ?? object["error"]?["message"]?.string
            message.compactionText = text ?? "Context compacted · \(status)"
        }

        if kind == .assistant, let content = object["content"]?.array {
            var textOrdinal = 0
            var reasoningOrdinal = 0
            for item in content {
                guard let itemType = item["type"]?.string else { continue }
                switch itemType {
                case "text":
                    message.blocks.append(MessageBlock(
                        id: "\(id):text:\(textOrdinal)",
                        kind: .text,
                        text: item["text"]?.string ?? ""
                    ))
                    textOrdinal += 1
                case "reasoning":
                    let block = MessageBlock(
                        id: "\(id):reasoning:\(reasoningOrdinal)",
                        kind: .reasoning,
                        text: item["text"]?.string ?? "",
                        reasoningStarted: item["time"]?["created"]?.double,
                        reasoningCompleted: item["time"]?["completed"]?.double
                    )
                    message.blocks.append(block)
                    reasoningOrdinal += 1
                case "tool":
                    let tool = ToolCall.parse(item)
                    message.blocks.append(MessageBlock(
                        id: "\(id):tool:\(tool.id)",
                        kind: .tool,
                        text: "",
                        tool: tool
                    ))
                default:
                    break
                }
            }
        }

        if kind == .idle, let error = object["error"]?["message"]?.string {
            message.errorText = error
        }

        return message
    }
}

struct MessageBlock: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case text
        case reasoning
        case tool
    }

    var id: String
    var kind: Kind
    var text: String
    var reasoningStarted: Double?
    var reasoningCompleted: Double?
    var tool: ToolCall?

    init(
        id: String,
        kind: Kind,
        text: String,
        reasoningStarted: Double? = nil,
        reasoningCompleted: Double? = nil,
        tool: ToolCall? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.reasoningStarted = reasoningStarted
        self.reasoningCompleted = reasoningCompleted
        self.tool = tool
    }

    var reasoningDuration: Double? {
        guard let reasoningStarted, let reasoningCompleted else { return nil }
        return max(0, (reasoningCompleted - reasoningStarted) / 1000)
    }
}

struct ToolCall: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var status: String
    var input: JSONValue?
    var content: String
    var files: [ToolFile]
    var metadata: JSONValue?
    var errorText: String?
    var executed: Bool
    var startedAt: Double?
    var completedAt: Double?

    struct ToolFile: Identifiable, Hashable, Sendable {
        var uri: String
        var mime: String?
        var name: String?
        var id: String { uri }
    }

    var isRunning: Bool { status == "running" || status == "streaming" }
    var isError: Bool { status == "error" }

    var displayName: String {
        switch name.lowercased() {
        case "shell", "bash": "Shell"
        case "read": "Read file"
        case "write": "Write file"
        case "edit", "multiedit", "apply_patch", "patch": "Edit"
        case "glob": "Find files"
        case "grep": "Search"
        case "list": "List"
        case "webfetch", "websearch": "Web"
        case "task": "Subagent"
        case "todowrite", "todoread", "todo": "Tasks"
        case "question": "Question"
        default: name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var iconName: String {
        switch name.lowercased() {
        case "shell", "bash": "terminal"
        case "read": "doc.text"
        case "write": "doc.badge.plus"
        case "edit", "multiedit", "apply_patch", "patch": "pencil.line"
        case "glob": "folder"
        case "grep": "magnifyingglass"
        case "list": "list.bullet"
        case "webfetch", "websearch": "globe"
        case "task": "person.2"
        case "todowrite", "todoread", "todo": "checklist"
        case "question": "questionmark.bubble"
        default: "wrench.and.screwdriver"
        }
    }

    var summary: String? {
        guard let input else { return nil }
        if let command = input["command"]?.string { return command }
        if let path = input["path"]?.string { return path }
        if let filePath = input["filePath"]?.string { return filePath }
        if let pattern = input["pattern"]?.string { return pattern }
        if let query = input["query"]?.string { return query }
        if let description = input["description"]?.string { return description }
        return nil
    }

    var copyableText: String {
        var parts: [String] = [displayName]
        if let summary { parts.append(summary) }
        if !content.isEmpty { parts.append(content) }
        if let errorText { parts.append(errorText) }
        return parts.joined(separator: "\n")
    }

    var duration: Double? {
        guard let startedAt, let completedAt else { return nil }
        return max(0, (completedAt - startedAt) / 1000)
    }

    static func parse(_ value: JSONValue) -> ToolCall {
        let id = value["id"]?.string ?? UUID().uuidString
        let name = value["name"]?.string ?? "tool"
        let state = value["state"] ?? .null
        let status = state["status"]?.string ?? "running"
        let input = state["input"]
        let metadata = state["metadata"]
        let error = state["error"]?["message"]?.string
        var output = ""
        var files: [ToolFile] = []

        if let content = state["content"]?.array {
            for item in content {
                switch item["type"]?.string {
                case "text":
                    if !output.isEmpty { output += "\n" }
                    output += item["text"]?.string ?? ""
                case "file":
                    if let uri = item["uri"]?.string {
                        files.append(ToolFile(uri: uri, mime: item["mime"]?.string, name: item["name"]?.string))
                    }
                default:
                    if let text = item["text"]?.string { output += text }
                }
            }
        }

        return ToolCall(
            id: id,
            name: name,
            status: status,
            input: input,
            content: output,
            files: files,
            metadata: metadata,
            errorText: error,
            executed: value["executed"]?.bool ?? false,
            startedAt: value["time"]?["created"]?.double,
            completedAt: value["time"]?["completed"]?.double
        )
    }
}

// MARK: - UI-facing helpers

struct Workspace: Identifiable, Hashable, Sendable {
    var directory: String
    var project: ProjectInfo?

    var id: String { directory }
    var url: URL { URL(fileURLWithPath: directory, isDirectory: true) }
    var name: String {
        if let project { return project.displayName }
        return url.lastPathComponent.isEmpty ? directory : url.lastPathComponent
    }
}

struct AppAlert: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var message: String
    var isError: Bool = false
}

struct ToastMessage: Identifiable, Sendable {
    var id = UUID()
    var text: String
    var icon: String = "checkmark.circle.fill"
}

enum ModelCatalog {
    static func providerTint(_ id: String) -> Color {
        switch id.lowercased() {
        case "anthropic": Color(red: 0.85, green: 0.55, blue: 0.36)
        case "openai": Color(red: 0.36, green: 0.78, blue: 0.66)
        case "google": Color(red: 0.36, green: 0.55, blue: 0.95)
        case "openrouter": Color(red: 0.62, green: 0.48, blue: 0.95)
        case "opencode", "opencode-go": Color(red: 1.0, green: 0.45, blue: 0.18)
        case "deepseek": Color(red: 0.28, green: 0.58, blue: 0.95)
        case "meta", "groq": Color(red: 0.3, green: 0.72, blue: 0.9)
        case "mistral": Color(red: 1.0, green: 0.62, blue: 0.25)
        default: Color.ocAccent
        }
    }

    static func providerSymbol(_ id: String) -> String {
        switch id.lowercased() {
        case "anthropic": "a.circle.fill"
        case "openai": "circle.hexagongrid.fill"
        case "google": "g.circle.fill"
        case "openrouter": "arrow.triangle.branch"
        case "opencode", "opencode-go": "chevron.left.forwardslash.chevron.right"
        default: "cpu"
        }
    }
}
