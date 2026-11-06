import Foundation

enum OpenCodeAPIError: LocalizedError {
    case invalidURL(String)
    case http(status: Int, message: String)
    case decoding(String)
    case transport(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path):
            return "Invalid OpenCode URL: \(path)"
        case .http(let status, let message):
            return message.isEmpty ? "OpenCode returned HTTP \(status)" : message
        case .decoding(let message):
            return "Could not read OpenCode response: \(message)"
        case .transport(let message):
            return message
        case .emptyResponse:
            return "OpenCode returned an empty response"
        }
    }
}

private struct APIEnvelope<T: Decodable>: Decodable {
    var data: T
}

private struct APILocationEnvelope<T: Decodable>: Decodable {
    var data: T
    var location: LocationRef?
}

private struct MessagePage: Decodable {
    var data: [JSONValue]
    var cursor: PageCursor?

    struct PageCursor: Decodable {
        var previous: String?
        var next: String?
    }
}

private struct SessionJSONPage: Decodable {
    var data: [JSONValue]
    var cursor: PageCursor?

    struct PageCursor: Decodable {
        var previous: String?
        var next: String?
    }
}

private struct EmptyBody: Codable {}

final class APIClient {
    var baseURL: URL
    var password: String
    /// The OpenCode location used for instance-scoped routes.
    var directory: String?

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseURL: URL, password: String, directory: String? = nil) {
        self.baseURL = baseURL
        self.password = password
        self.directory = directory

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    var authHeader: String {
        "Basic " + Data("opencode:\(password)".utf8).base64EncodedString()
    }

    // MARK: - Transport

    private func makeURL(path: String, query: [(String, String?)] = []) throws -> URL {
        let suffix = path.hasPrefix("/") ? path : "/" + path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenCodeAPIError.invalidURL(path)
        }
        components.percentEncodedPath = components.percentEncodedPath + suffix
        if !query.isEmpty {
            components.queryItems = query.compactMap { name, value in
                value.map { URLQueryItem(name: name, value: $0) }
            }
        }
        guard let url = components.url else { throw OpenCodeAPIError.invalidURL(path) }
        return url
    }

    @discardableResult
    func requestData(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: Data? = nil,
        contentType: String = "application/json",
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout ?? 90
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let directory, !directory.isEmpty {
            request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenCodeAPIError.transport("OpenCode did not return an HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw OpenCodeAPIError.http(
                    status: http.statusCode,
                    message: Self.serverMessage(from: data, status: http.statusCode)
                )
            }
            return data
        } catch let error as OpenCodeAPIError {
            throw error
        } catch let error as URLError {
            throw OpenCodeAPIError.transport(error.localizedDescription)
        } catch {
            throw OpenCodeAPIError.transport(error.localizedDescription)
        }
    }

    private static func serverMessage(from data: Data, status: Int) -> String {
        if let value = try? JSONValue.fromData(data) {
            if let message = value["message"]?.string, !message.isEmpty { return message }
            if let error = value["error"]?["message"]?.string, !error.isEmpty { return error }
            if let tag = value["_tag"]?.string, !tag.isEmpty { return tag }
            let text = value.displayText
            if !text.isEmpty { return text }
        }
        if let string = String(data: data, encoding: .utf8), !string.isEmpty {
            return String(string.prefix(600))
        }
        return "HTTP \(status)"
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpenCodeAPIError.decoding(error.localizedDescription)
        }
    }

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: [String: JSONValue]? = nil,
        as type: T.Type
    ) async throws -> T {
        let data = try await requestData(method, path, query: query, body: try body?.jsonData())
        return try decode(type, from: data)
    }

    private func sendVoid(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: [String: JSONValue]? = nil
    ) async throws {
        _ = try await requestData(method, path, query: query, body: try body?.jsonData())
    }

    // MARK: - Server & project

    func serverInfo() async throws -> ServerInfo {
        let data = try await requestData("GET", "/api/info", timeout: 8)
        return try decode(ServerInfo.self, from: data)
    }

    func location() async throws -> JSONValue {
        try await send("GET", "/api/location", as: JSONValue.self)
    }

    func reloadLocation() async throws {
        try await sendVoid("POST", "/api/location/reload")
    }

    func projects() async throws -> [ProjectInfo] {
        let data = try await requestData("GET", "/api/project")
        return try decode([ProjectInfo].self, from: data)
    }

    // MARK: - Sessions

    func sessions(archived: Bool? = false, topLevel: Bool = true) async throws -> [SessionInfo] {
        var all: [SessionInfo] = []
        var cursor: String?
        var pageCount = 0
        repeat {
            var query: [(String, String?)] = []
            if let directory { query.append(("directory", directory)) }
            if let archived { query.append(("archived", archived ? "true" : "false")) }
            // The API reads "parentID"; "parent" is silently ignored.
            if topLevel { query.append(("parentID", "null")) }
            if let cursor { query.append(("cursor", cursor)) }
            let data = try await requestData("GET", "/api/session", query: query)
            let page = try decode(SessionJSONPage.self, from: data)
            all.append(contentsOf: page.data.compactMap { $0.decoded(SessionInfo.self) })
            cursor = page.cursor?.next
            pageCount += 1
        } while (cursor?.isEmpty == false) && pageCount < 8
        return all
    }

    func session(_ id: String) async throws -> SessionInfo {
        let envelope = try await send("GET", "/api/session/\(id)", as: APIEnvelope<SessionInfo>.self)
        return envelope.data
    }

    func createSession(title: String? = nil, model: ModelRef?, agent: String?) async throws -> SessionInfo {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let agent { body["agent"] = .string(agent) }
        if let model { body["model"] = encoded(model) }
        if let directory { body["location"] = .object(["directory": .string(directory)]) }
        let envelope = try await send("POST", "/api/session", body: body, as: APIEnvelope<SessionInfo>.self)
        return envelope.data
    }

    func updateSession(_ id: String, title: String? = nil, archived: Bool? = nil) async throws -> SessionInfo {
        var body: [String: JSONValue] = [:]
        if let title { body["title"] = .string(title) }
        if let archived { body["archived"] = .bool(archived) }
        let envelope = try await send("PATCH", "/api/session/\(id)", body: body, as: APIEnvelope<SessionInfo>.self)
        return envelope.data
    }

    func deleteSession(_ id: String) async throws {
        try await sendVoid("DELETE", "/api/session/\(id)")
    }

    func forkSession(_ id: String, before messageID: String? = nil) async throws -> SessionInfo {
        var body: [String: JSONValue] = [:]
        if let messageID { body["before"] = .string(messageID) }
        let envelope = try await send("POST", "/api/session/\(id)/fork", body: body, as: APIEnvelope<SessionInfo>.self)
        return envelope.data
    }

    func switchModel(sessionID: String, model: ModelRef) async throws {
        try await sendVoid("POST", "/api/session/\(sessionID)/model", body: ["model": encoded(model)])
    }

    func switchAgent(sessionID: String, agent: String) async throws {
        try await sendVoid("POST", "/api/session/\(sessionID)/agent", body: ["agent": .string(agent)])
    }

    func messages(sessionID: String) async throws -> [ChatMessage] {
        var all: [JSONValue] = []
        var cursor: String?
        var pageCount = 0
        repeat {
            var query: [(String, String?)] = [("limit", "200")]
            if let cursor {
                query.append(("cursor", cursor))
            } else {
                query.append(("order", "asc"))
            }
            let data = try await requestData("GET", "/api/session/\(sessionID)/message", query: query)
            let page = try decode(MessagePage.self, from: data)
            all.append(contentsOf: page.data)
            cursor = page.cursor?.next
            pageCount += 1
        } while (cursor?.isEmpty == false) && pageCount < 12
        return all.compactMap(ChatMessage.parse)
    }

    func prompt(
        sessionID: String,
        text: String,
        files: [PromptAttachment] = [],
        delivery: String = "steer",
        resume: Bool? = nil
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = [
            "text": .string(text),
            "delivery": .string(delivery)
        ]
        if !files.isEmpty {
            // The API's string fields don't accept null — omit them instead.
            body["files"] = .array(files.map { attachment in
                var file: [String: JSONValue] = ["uri": .string(attachment.uri)]
                if let name = attachment.name { file["name"] = .string(name) }
                if let description = attachment.description { file["description"] = .string(description) }
                return .object(file)
            })
        }
        if let resume { body["resume"] = .bool(resume) }
        return try await send("POST", "/api/session/\(sessionID)/prompt", body: body, as: JSONValue.self)
    }

    func runCommand(sessionID: String, name: String, text: String, files: [PromptAttachment] = []) async throws -> JSONValue {
        var body: [String: JSONValue] = [
            "name": .string(name),
            "text": .string(text)
        ]
        if !files.isEmpty {
            // Omit optional string fields rather than sending null.
            body["files"] = .array(files.map { attachment in
                var file: [String: JSONValue] = ["uri": .string(attachment.uri)]
                if let name = attachment.name { file["name"] = .string(name) }
                return .object(file)
            })
        }
        return try await send("POST", "/api/session/\(sessionID)/command", body: body, as: JSONValue.self)
    }

    func runShell(sessionID: String, command: String) async throws -> JSONValue {
        try await send("POST", "/api/session/\(sessionID)/shell", body: ["command": .string(command)], as: JSONValue.self)
    }

    func interrupt(sessionID: String, resume: Bool = false) async throws -> Bool {
        let value = try await send(
            "POST",
            "/api/session/\(sessionID)/interrupt",
            query: [("resume", resume ? "true" : "false")],
            as: JSONValue.self
        )
        return value["interrupted"]?.bool ?? false
    }

    func compact(sessionID: String) async throws {
        try await sendVoid("POST", "/api/session/\(sessionID)/compact", body: [:])
    }

    func sessionDiff(sessionID: String) async throws -> [FileDiff] {
        let envelope = try await send("GET", "/api/session/\(sessionID)/diff", as: APILocationEnvelope<[FileDiff]>.self)
        return envelope.data
    }

    func sessionContext(sessionID: String) async throws -> [JSONValue] {
        let envelope = try await send("GET", "/api/session/\(sessionID)/context", as: APIEnvelope<[JSONValue]>.self)
        return envelope.data
    }

    func stageRevert(sessionID: String, messageID: String, files: Bool = true) async throws -> RevertInfo {
        let envelope = try await send(
            "POST",
            "/api/session/\(sessionID)/revert/stage",
            body: ["messageID": .string(messageID), "files": .bool(files)],
            as: APIEnvelope<RevertInfo>.self
        )
        return envelope.data
    }

    func commitRevert(sessionID: String) async throws {
        try await sendVoid("POST", "/api/session/\(sessionID)/revert/commit")
    }

    func clearRevert(sessionID: String) async throws {
        try await sendVoid("DELETE", "/api/session/\(sessionID)/revert")
    }

    func exportSession(_ id: String) async throws -> JSONValue {
        let envelope = try await send(
            "GET",
            "/api/experimental/session/\(id)/export",
            query: [("sanitize", "false")],
            as: APIEnvelope<JSONValue>.self
        )
        return envelope.data
    }

    func importSession(_ value: JSONValue) async throws -> SessionInfo {
        let data = try JSONEncoder().encode(value)
        let response = try await requestData("POST", "/api/experimental/session/import", body: data)
        let envelope = try decode(APIEnvelope<SessionInfo>.self, from: response)
        return envelope.data
    }

    func activeSessions() async throws -> [String: SessionActiveInfo] {
        let envelope = try await send("GET", "/api/session/active", as: APIEnvelope<[String: SessionActiveInfo]>.self)
        return envelope.data
    }

    // MARK: - Catalog

    func models() async throws -> [ModelInfo] {
        let envelope = try await send("GET", "/api/model", as: APILocationEnvelope<[ModelInfo]>.self)
        return envelope.data
    }

    func defaultModel() async throws -> ModelInfo? {
        let envelope = try await send("GET", "/api/model/default", as: APILocationEnvelope<ModelInfo?>.self)
        return envelope.data
    }

    func providers() async throws -> [ProviderInfo] {
        let envelope = try await send("GET", "/api/provider", as: APILocationEnvelope<[ProviderInfo]>.self)
        return envelope.data
    }

    func agents() async throws -> [AgentInfo] {
        let envelope = try await send("GET", "/api/agent", as: APILocationEnvelope<[AgentInfo]>.self)
        return envelope.data
    }

    func commands() async throws -> [CommandInfo] {
        let envelope = try await send("GET", "/api/command", as: APILocationEnvelope<[CommandInfo]>.self)
        return envelope.data
    }

    func skills() async throws -> [SkillInfo] {
        let envelope = try await send("GET", "/api/skill", as: APILocationEnvelope<[SkillInfo]>.self)
        return envelope.data
    }

    // MARK: - Permissions & forms

    func permissions(sessionID: String) async throws -> [PermissionRequest] {
        let envelope = try await send("GET", "/api/session/\(sessionID)/permission", as: APIEnvelope<[PermissionRequest]>.self)
        return envelope.data
    }

    func replyPermission(sessionID: String, requestID: String, decision: String) async throws {
        try await sendVoid(
            "POST",
            "/api/session/\(sessionID)/permission/\(requestID)/reply",
            body: ["decision": .string(decision)]
        )
    }

    func forms(sessionID: String) async throws -> [FormInfo] {
        let envelope = try await send("GET", "/api/session/\(sessionID)/form", as: APIEnvelope<[FormInfo]>.self)
        return envelope.data
    }

    func replyForm(sessionID: String, formID: String, answer: [String: JSONValue]) async throws {
        try await sendVoid(
            "POST",
            "/api/session/\(sessionID)/form/\(formID)/reply",
            body: ["answer": .object(answer)]
        )
    }

    func cancelForm(sessionID: String, formID: String) async throws {
        try await sendVoid("DELETE", "/api/session/\(sessionID)/form/\(formID)")
    }

    // MARK: - Filesystem & VCS

    func listFiles(path: String = ".") async throws -> [FileSystemEntry] {
        let envelope = try await send(
            "GET",
            "/api/fs/list",
            query: [("path", path)],
            as: APILocationEnvelope<[FileSystemEntry]>.self
        )
        return envelope.data
    }

    func findFiles(_ query: String, limit: Int = 40, type: String? = nil) async throws -> [FileSystemEntry] {
        var items: [(String, String?)] = [("query", query), ("limit", String(limit))]
        if let type { items.append(("type", type)) }
        let envelope = try await send("GET", "/api/fs/find", query: items, as: APILocationEnvelope<[FileSystemEntry]>.self)
        return envelope.data
    }

    func readFile(path: String) async throws -> Data {
        let encoded = path
            .addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?#"))) ?? path
        return try await requestData("GET", "/api/fs/read/\(encoded)")
    }

    func vcsStatus() async throws -> [VcsFileStatus] {
        let envelope = try await send("GET", "/api/vcs/status", as: APILocationEnvelope<[VcsFileStatus]>.self)
        return envelope.data
    }

    func vcsInfo() async throws -> VcsInfo {
        let envelope = try await send("GET", "/api/vcs", as: APILocationEnvelope<VcsInfo>.self)
        return envelope.data
    }

    func vcsDiff(mode: String = "working") async throws -> [FileDiff] {
        let envelope = try await send(
            "GET",
            "/api/vcs/diff",
            query: [("mode", mode)],
            as: APILocationEnvelope<[FileDiff]>.self
        )
        return envelope.data
    }

    func initVcs() async throws {
        try await sendVoid("POST", "/api/vcs/init")
    }

    // MARK: - Shell runner

    func createShell(command: String, cwd: String? = nil, timeout: Int? = nil) async throws -> ShellInfo {
        var body: [String: JSONValue] = ["command": .string(command)]
        if let cwd { body["cwd"] = .string(cwd) }
        if let timeout { body["timeout"] = .number(Double(timeout)) }
        let envelope = try await send("POST", "/api/shell", body: body, as: APILocationEnvelope<ShellInfo>.self)
        return envelope.data
    }

    func shellOutput(id: String, cursor: Int? = nil) async throws -> ShellOutput {
        var query: [(String, String?)] = []
        if let cursor { query.append(("cursor", String(cursor))) }
        let envelope = try await send("GET", "/api/shell/\(id)/output", query: query, as: APILocationEnvelope<ShellOutput>.self)
        return envelope.data
    }

    func shells() async throws -> [ShellInfo] {
        let envelope = try await send("GET", "/api/shell", as: APILocationEnvelope<[ShellInfo]>.self)
        return envelope.data
    }

    func shell(id: String) async throws -> ShellInfo {
        let envelope = try await send("GET", "/api/shell/\(id)", as: APILocationEnvelope<ShellInfo>.self)
        return envelope.data
    }

    func removeShell(id: String) async throws {
        try await sendVoid("DELETE", "/api/shell/\(id)")
    }

    // MARK: - Worktrees

    func worktrees(projectID: String) async throws -> [WorktreeInfo] {
        let data = try await requestData("GET", "/api/worktree", query: [("projectID", projectID)])
        return try decode([WorktreeInfo].self, from: data)
    }

    func createWorktree(projectID: String, name: String? = nil, branch: String? = nil) async throws -> WorktreeInfo {
        var body: [String: JSONValue] = ["projectID": .string(projectID)]
        if let name { body["name"] = .string(name) }
        if let branch { body["branch"] = .string(branch) }
        let data = try await requestData("POST", "/api/worktree", body: try body.jsonData())
        return try decode(WorktreeInfo.self, from: data)
    }

    func removeWorktree(projectID: String, directory: String) async throws {
        let body: [String: JSONValue] = ["projectID": .string(projectID), "directory": .string(directory)]
        _ = try await requestData("DELETE", "/api/worktree", body: try body.jsonData())
    }

    // MARK: - Stats

    func stats(projectID: String? = nil) async throws -> SessionStatsInfo {
        var query: [(String, String?)] = [("tools", "detail")]
        if let projectID { query.append(("project", projectID)) }
        let envelope = try await send("GET", "/api/experimental/session/stats", query: query, as: APIEnvelope<SessionStatsInfo>.self)
        return envelope.data
    }

    // MARK: - Integrations, MCP, plugins, config

    func mcpServers() async throws -> [McpServer] {
        let envelope = try await send("GET", "/api/mcp", as: APILocationEnvelope<[McpServer]>.self)
        return envelope.data
    }

    func connectMcp(_ name: String) async throws {
        try await sendVoid("POST", "/api/experimental/mcp/\(name)/connect")
    }

    func disconnectMcp(_ name: String) async throws {
        try await sendVoid("POST", "/api/experimental/mcp/\(name)/disconnect")
    }

    func addMcp(name: String, config: JSONValue) async throws {
        try await sendVoid("PUT", "/api/experimental/mcp/\(name)", body: ["config": config])
    }

    func removeMcp(_ name: String) async throws {
        try await sendVoid("DELETE", "/api/experimental/mcp/\(name)")
    }

    func plugins() async throws -> [PluginInfo] {
        let envelope = try await send("GET", "/api/plugin", as: APILocationEnvelope<[PluginInfo]>.self)
        return envelope.data
    }

    func checkPlugins() async throws -> [PluginInfo] {
        let envelope = try await send("POST", "/api/plugin/check", body: [:], as: APILocationEnvelope<[PluginInfo]>.self)
        return envelope.data
    }

    func updatePlugins(targets: [String]) async throws {
        try await sendVoid("POST", "/api/plugin/update", body: ["targets": .array(targets.map(JSONValue.string))])
    }

    func integrations() async throws -> [IntegrationInfo] {
        let envelope = try await send("GET", "/api/integration", as: APILocationEnvelope<[IntegrationInfo]>.self)
        return envelope.data
    }

    func connectIntegrationKey(_ id: String, key: String, answer: [String: JSONValue]? = nil, label: String? = nil) async throws {
        var body: [String: JSONValue] = ["key": .string(key)]
        if let answer { body["answer"] = .object(answer) }
        if let label { body["label"] = .string(label) }
        try await sendVoid("POST", "/api/integration/\(id)/connect/key", body: body)
    }

    func connectIntegrationExternal(_ id: String, methodID: String, answer: [String: JSONValue]? = nil) async throws {
        var body: [String: JSONValue] = ["methodID": .string(methodID)]
        if let answer { body["answer"] = .object(answer) }
        try await sendVoid("POST", "/api/integration/\(id)/connect/external", body: body)
    }

    func startIntegrationOAuth(_ id: String, methodID: String, answer: [String: JSONValue]? = nil) async throws -> JSONValue {
        var body: [String: JSONValue] = ["methodID": .string(methodID)]
        if let answer { body["answer"] = .object(answer) }
        let envelope = try await send(
            "POST",
            "/api/integration/\(id)/connect/oauth",
            body: body,
            as: APILocationEnvelope<JSONValue>.self
        )
        return envelope.data
    }

    func integrationOAuthStatus(_ id: String, attemptID: String) async throws -> JSONValue {
        let envelope = try await send(
            "GET",
            "/api/integration/\(id)/connect/oauth/\(attemptID)",
            as: APILocationEnvelope<JSONValue>.self
        )
        return envelope.data
    }

    func completeIntegrationOAuth(_ id: String, attemptID: String, code: String?) async throws {
        var body: [String: JSONValue] = [:]
        if let code { body["code"] = .string(code) }
        try await sendVoid(
            "POST",
            "/api/integration/\(id)/connect/oauth/\(attemptID)/complete",
            body: body
        )
    }

    func cancelIntegrationOAuth(_ id: String, attemptID: String) async throws {
        try await sendVoid("DELETE", "/api/integration/\(id)/connect/oauth/\(attemptID)")
    }

    func credentials() async throws -> [CredentialEntry] {
        let envelope = try await send("GET", "/api/credential", as: APIEnvelope<[CredentialEntry]>.self)
        return envelope.data
    }

    func removeCredential(_ id: String) async throws {
        try await sendVoid("DELETE", "/api/credential/\(id)")
    }

    func activateCredential(_ id: String) async throws {
        try await sendVoid("POST", "/api/credential/\(id)/activate")
    }

    func configEntries() async throws -> [JSONValue] {
        let data = try await requestData("GET", "/api/config")
        return try decode([JSONValue].self, from: data)
    }

    func shellOptions() async throws -> [JSONValue] {
        let data = try await requestData("GET", "/api/config/shell")
        return try decode([JSONValue].self, from: data)
    }

    func setShell(_ path: String) async throws {
        try await sendVoid("PATCH", "/api/experimental/config", body: ["shell": .string(path)])
    }

    // MARK: - Encoding

    private func encoded<T: Encodable>(_ value: T) -> JSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONValue.fromData(data) else { return .null }
        return json
    }
}

// MARK: - Filesystem model

struct FileSystemEntry: Codable, Identifiable, Hashable, Sendable {
    var path: String
    var type: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var isDirectory: Bool { type == "directory" }
}
