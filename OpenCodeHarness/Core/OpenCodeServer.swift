import AppKit
import Foundation

enum ServerMode: String, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
    var label: String { self == .local ? "Managed locally" : "Connect to server" }
}

struct ServerConnection: Sendable {
    var baseURL: URL
    var password: String
    var info: ServerInfo
}

@MainActor
final class OpenCodeServer: ObservableObject {
    enum State: Equatable {
        case idle
        case locating
        case starting
        case connecting
        case ready
        case failed(String)
        case stopped
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var connection: ServerConnection?
    @Published private(set) var logs: [String] = []
    @Published private(set) var binaryPath: String?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var discoveredURL: URL?
    private var discoveredPassword: String?
    private var startContinuation: CheckedContinuation<ServerConnection, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var stopping = false
    private var ownsProcess = false

    static let binaryCandidates = [
        "\(NSHomeDirectory())/.opencode/bin/opencode",
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
        "/usr/bin/opencode"
    ]

    func start(mode: ServerMode, binaryPath: String?, remoteURL: String, remotePassword: String) async throws -> ServerConnection {
        Diagnostics.log("OpenCodeServer.start mode=\(mode.rawValue)")
        stop()
        stopping = false
        logs.removeAll()
        state = .locating
        connection = nil

        switch mode {
        case .remote:
            state = .connecting
            guard let url = URL(string: remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  url.scheme != nil else {
                state = .failed("Enter a full server URL, for example http://127.0.0.1:4096")
                throw OpenCodeAPIError.invalidURL(remoteURL)
            }
            let api = APIClient(baseURL: url, password: remotePassword)
            let info = try await api.serverInfo()
            let result = ServerConnection(baseURL: url, password: remotePassword, info: info)
            connection = result
            state = .ready
            log("Connected to OpenCode \(info.version) at \(url.absoluteString)")
            return result

        case .local:
            let executable = await locateBinary(preferred: binaryPath)
            Diagnostics.log("Located binary: \(executable ?? "nil")")
            guard let executable else {
                state = .failed("OpenCode CLI was not found. Install it from opencode.ai or set the binary path in Settings.")
                throw OpenCodeAPIError.transport("OpenCode CLI was not found")
            }
            self.binaryPath = executable
            state = .starting
            log("Connecting to the OpenCode background service")

            do {
                let result = try await startBackgroundService(executable: executable)
                connection = result
                state = .ready
                log("OpenCode \(result.info.version) ready at \(result.baseURL.absoluteString)")
                return result
            } catch {
                Diagnostics.log("Background service failed: \(error.localizedDescription); falling back to private server")
                log("Background service unavailable — starting a private server")
                let result = try await launch(executable: executable)
                connection = result
                state = .ready
                log("OpenCode \(result.info.version) ready at \(result.baseURL.absoluteString)")
                return result
            }
        }
    }

    // MARK: - Managed background service

    private func startBackgroundService(executable: String) async throws -> ServerConnection {
        state = .connecting
        var urlString = await runCLI(executable: executable, arguments: ["service", "status"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http") {
            _ = await runCLI(executable: executable, arguments: ["service", "start"])
            for _ in 0..<25 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                urlString = await runCLI(executable: executable, arguments: ["service", "status"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if urlString.hasPrefix("http") { break }
            }
        }
        guard let url = URL(string: urlString), url.scheme != nil else {
            throw OpenCodeAPIError.transport("OpenCode background service did not report a URL")
        }
        guard let password = readServicePassword() else {
            throw OpenCodeAPIError.transport("OpenCode background service password was not found")
        }
        let connection = try await waitForHealth(url: url, password: password)
        log("Using background service at \(url.absoluteString)")
        return connection
    }

    private func runCLI(executable: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = (Self.binaryCandidates.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } + [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
            ]).joined(separator: ":")
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
            do { try process.run() } catch { continuation.resume(returning: "") }
        }
    }

    private func readServicePassword() -> String? {
        let configDirectory = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("opencode", isDirectory: true) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode", isDirectory: true)
        let candidates = [
            configDirectory.appendingPathComponent("service.json"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode/service.json")
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let value = try? JSONValue.fromData(data),
                  let password = value["password"]?.string,
                  !password.isEmpty else { continue }
            return password
        }
        return nil
    }

    func stop() {
        stopping = true
        timeoutTask?.cancel()
        timeoutTask = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if ownsProcess, let process, process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        ownsProcess = false
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        discoveredURL = nil
        discoveredPassword = nil
        connection = nil
        if state != .idle { state = .stopped }
    }

    // MARK: - Process launch

    private func launch(executable: String) async throws -> ServerConnection {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve", "--hostname", "127.0.0.1", "--port", "0"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            "\(NSHomeDirectory())/.opencode/bin",
            "\(NSHomeDirectory())/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existing = environment["PATH"] ?? ""
        environment["PATH"] = (extraPaths + [existing]).filter { !$0.isEmpty }.joined(separator: ":")
        environment["OPENCODE_DISABLE_UPDATE"] = "1"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        self.process = process
        self.ownsProcess = true
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.ingestStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.ingestStderr(data) }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let code = process.terminationStatus
                Diagnostics.log("opencode terminated code=\(code) reason=\(process.terminationReason.rawValue) state=\(self.state)")
                if !self.stopping, self.state != .ready {
                    self.state = .failed("OpenCode server exited with code \(code). \(self.logs.suffix(3).joined(separator: " · "))")
                    self.startContinuation?.resume(throwing: OpenCodeAPIError.transport("OpenCode server exited with code \(code)"))
                    self.startContinuation = nil
                } else if !self.stopping, self.state == .ready {
                    self.state = .failed("OpenCode server stopped unexpectedly (code \(code)).")
                }
            }
        }

        do {
            try process.run()
            Diagnostics.log("Spawned opencode pid \(process.processIdentifier)")
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }

        state = .connecting

        return try await withCheckedThrowingContinuation { continuation in
            self.startContinuation = continuation
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, self.state == .connecting || self.state == .starting else { return }
                let message = "OpenCode did not start in time. \(self.logs.suffix(3).joined(separator: " · "))"
                self.state = .failed(message)
                self.startContinuation?.resume(throwing: OpenCodeAPIError.transport(message))
                self.startContinuation = nil
                self.stop()
            }
        }
    }

    private func ingestStdout(_ data: Data) {
        stdoutBuffer += String(decoding: data, as: UTF8.self)
        while let newline = stdoutBuffer.firstIndex(of: "\n") {
            let line = String(stdoutBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            let visibleLine = line.hasPrefix("server password ") ? "server password ••••••••" : line
            log(visibleLine)
            Diagnostics.log("stdout: \(visibleLine)")
            if line.contains("server listening on "),
               let range = line.range(of: "server listening on ") {
                let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                discoveredURL = URL(string: value)
            }
            if line.hasPrefix("server password ") {
                discoveredPassword = String(line.dropFirst("server password ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if discoveredURL != nil, discoveredPassword != nil {
                finishLaunch()
            }
        }
    }

    private func ingestStderr(_ data: Data) {
        stderrBuffer += String(decoding: data, as: UTF8.self)
        while let newline = stderrBuffer.firstIndex(of: "\n") {
            let line = String(stderrBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            stderrBuffer.removeSubrange(...newline)
            if !line.isEmpty {
                log("stderr: \(line)")
                Diagnostics.log("stderr: \(line)")
            }
        }
    }

    private func finishLaunch() {
        guard let url = discoveredURL, let password = discoveredPassword, let continuation = startContinuation else { return }
        startContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .connecting

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let connection = try await self.waitForHealth(url: url, password: password)
                self.connection = connection
                self.state = .ready
                continuation.resume(returning: connection)
            } catch {
                self.state = .failed(error.localizedDescription)
                continuation.resume(throwing: error)
                self.stop()
            }
        }
    }

    private func waitForHealth(url: URL, password: String) async throws -> ServerConnection {
        let api = APIClient(baseURL: url, password: password)
        var lastError: Error?
        for _ in 0..<40 {
            do {
                let info = try await api.serverInfo()
                return ServerConnection(baseURL: url, password: password, info: info)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        throw lastError ?? OpenCodeAPIError.transport("OpenCode server did not become healthy")
    }

    // MARK: - Binary discovery

    private func locateBinary(preferred: String?) async -> String? {
        let fileManager = FileManager.default
        if let preferred, !preferred.trimmingCharacters(in: .whitespaces).isEmpty,
           fileManager.isExecutableFile(atPath: preferred) {
            return preferred
        }
        for candidate in Self.binaryCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "command -v opencode"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = (Self.binaryCandidates.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path } + [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
            ]).joined(separator: ":")
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: path.isEmpty ? nil : path)
            }
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }

    private func log(_ line: String) {
        logs.append(line)
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
}
