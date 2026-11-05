import Foundation

struct OpenCodeEvent: Sendable {
    var id: String?
    var type: String
    var created: Double?
    var data: JSONValue
    var metadata: JSONValue?
    var location: LocationRef?

    static func parse(_ payload: String) -> OpenCodeEvent? {
        guard let data = payload.data(using: .utf8),
              let value = try? JSONValue.fromData(data),
              let type = value["type"]?.string else { return nil }
        return OpenCodeEvent(
            id: value["id"]?.string,
            type: type,
            created: value["created"]?.double,
            data: value["data"] ?? .object([:]),
            metadata: value["metadata"],
            location: value["location"]?.decoded(LocationRef.self)
        )
    }
}

enum EventStreamState: Sendable, Equatable {
    case connecting
    case connected
    case reconnecting(String)
    case stopped
}

/// URLSession's `bytes(for:)` can buffer SSE responses in some process contexts.
/// A delegate-backed data task gives us the chunks as they arrive.
final class SSEClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let auth: String
    private let onOpen: @Sendable () -> Void

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: AsyncThrowingStream<OpenCodeEvent, Error>.Continuation?
    private var buffer = ""
    private var dataLines: [String] = []
    private var finished = false
    private let lock = NSLock()

    init(url: URL, auth: String, onOpen: @escaping @Sendable () -> Void) {
        self.url = url
        self.auth = auth
        self.onOpen = onOpen
    }

    func events() -> AsyncThrowingStream<OpenCodeEvent, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.cancel()
            }
            start()
        }
    }

    private func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60 * 60 * 24
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60 * 60 * 24

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.finish()
        continuation = nil
    }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
        task = nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(OpenCodeAPIError.transport("OpenCode event stream returned no HTTP response"))
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            completionHandler(.cancel)
            finish(OpenCodeAPIError.http(status: http.statusCode, message: "Event stream refused the connection"))
            return
        }
        Diagnostics.log("SSE response \(http.statusCode)")
        completionHandler(.allow)
        onOpen()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Diagnostics.log("SSE data chunk \(data.count)")
        buffer += String(decoding: data, as: UTF8.self)
        while let newline = buffer.firstIndex(of: "\n") {
            var line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty {
                guard !dataLines.isEmpty else { continue }
                let payload = dataLines.joined(separator: "\n")
                dataLines.removeAll(keepingCapacity: true)
                if let event = OpenCodeEvent.parse(payload) {
                    Diagnostics.log("SSE event yield \(event.type)")
                    continuation?.yield(event)
                } else {
                    Diagnostics.log("SSE parse failed: \(payload.prefix(80))")
                }
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                dataLines.append(value)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Diagnostics.log("SSE completed error=\(error?.localizedDescription ?? "nil")")
        if let error, (error as NSError).code != NSURLErrorCancelled {
            finish(error)
        } else {
            finish(nil)
        }
    }
}

final class OpenCodeEventStream {
    private let baseURL: URL
    private let password: String
    private var task: Task<Void, Never>?

    init(baseURL: URL, password: String) {
        self.baseURL = baseURL
        self.password = password
    }

    func start(
        onEvent: @escaping @Sendable (OpenCodeEvent) -> Void,
        onState: @escaping @Sendable (EventStreamState) -> Void
    ) {
        stop()
        let auth = "Basic " + Data("opencode:\(password)".utf8).base64EncodedString()
        task = Task { [baseURL] in
            var attempt = 0
            while !Task.isCancelled {
                onState(attempt == 0 ? .connecting : .reconnecting("Reconnecting…"))
                guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { break }
                components.percentEncodedPath += "/api/event"
                guard let url = components.url else { break }

                let client = SSEClient(url: url, auth: auth, onOpen: {
                    onState(.connected)
                })

                do {
                    for try await event in client.events() {
                        if Task.isCancelled { break }
                        Diagnostics.log("SSE consumer got \(event.type)")
                        onEvent(event)
                    }
                } catch {
                    if Task.isCancelled { break }
                    attempt += 1
                    onState(.reconnecting(error.localizedDescription))
                }

                if Task.isCancelled { break }
                attempt += 1
                let delay = min(12.0, 0.8 * pow(1.7, Double(min(attempt, 6))))
                if attempt > 1 { onState(.reconnecting("Reconnecting…")) }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            onState(.stopped)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
