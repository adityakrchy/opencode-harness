import Foundation

enum Diagnostics {
    static let logURL = URL(fileURLWithPath: "/tmp/opencode-harness-app.log")
    private static let lock = NSLock()

    static let enabled = ProcessInfo.processInfo.environment["OC_HARNESS_DEBUG"] == "1"

    static func log(_ message: String) {
        guard enabled else { return }
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
