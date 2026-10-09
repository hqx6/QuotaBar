import Foundation
import SQLite3
import Darwin

enum CodexProvider {
    static func fetch() async throws -> UsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try read()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func read() throws -> UsageSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [ProcessInfo.processInfo.environment["CODEX_BINARY"],
                          "/Applications/Codex.app/Contents/Resources/codex",
                          "\(home)/Applications/Codex.app/Contents/Resources/codex",
                          "\(home)/.npm-global/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].compactMap { $0 }
        guard let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageError.message("未找到 Codex。请安装 Codex 桌面版或 CLI。")
        }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageError.message("无法启动 Codex 用量服务。") }
        defer {
            if process.isRunning { process.terminate() }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            // A terminated server must never accumulate in the background.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "quota_bar", "version": "1.0.0"]]])
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        var buffer = Data()
        var bytes = [UInt8](repeating: 0, count: 65536)
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard poll(&descriptor, 1, 250) > 0 else { continue }
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw UsageError.message("Codex 用量服务已退出，请确认 Codex 能正常启动。") }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 4_000_000 else { throw UsageError.message("Codex 返回的数据过大。") }
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end)
                buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int else { continue }
                if object["error"] != nil {
                    throw UsageError.message("Codex 额度读取失败，请打开 Codex 确认 ChatGPT 登录状态后重试。")
                }
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = object["result"] as? [String: Any] {
                    return try UsageParser.codex(result)
                }
            }
        }
        throw UsageError.message("Codex 用量读取超时，请检查网络后刷新。")
    }
}

// Refuse redirects so the locally loaded credential is only ever sent to Cursor.
private final class CursorSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum CursorProvider {
    static func accessToken() throws -> String {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(database, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw UsageError.message("未找到 Cursor 登录状态，请先打开 Cursor 并登录。")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'", -1, &statement, nil) == SQLITE_OK else {
            throw UsageError.message("无法读取 Cursor 登录状态。")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw UsageError.message("Cursor 尚未登录，请先在 Cursor 中登录。")
        }
        let token = String(cString: text)
        guard !token.isEmpty else { throw UsageError.message("Cursor 登录状态为空，请重新登录。") }
        return token
    }

    static func fetch() async throws -> UsageSnapshot {
        let token = try accessToken()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: CursorSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        @Sendable func request(_ method: String) async throws -> [String: Any] {
            let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch { throw UsageError.message("Cursor 用量连接失败，请检查网络后刷新。") }
            guard let http = response as? HTTPURLResponse else { throw UsageError.message("Cursor 返回了无效响应。") }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageError.message("Cursor 登录已失效，请在 Cursor 重新登录后刷新。")
            }
            guard http.statusCode == 200 else { throw UsageError.message("Cursor 用量服务返回 HTTP \(http.statusCode)。") }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UsageError.message("Cursor 用量格式已改变，请更新程序。")
            }
            return object
        }
        async let usage = request("GetCurrentPeriodUsage")
        async let info = try? request("GetPlanInfo")
        let (root, planInfo) = try await (usage, info)
        let plan = (planInfo?["planInfo"] as? [String: Any])?["planName"] as? String
        return try UsageParser.cursor(root, plan: plan)
    }
}
