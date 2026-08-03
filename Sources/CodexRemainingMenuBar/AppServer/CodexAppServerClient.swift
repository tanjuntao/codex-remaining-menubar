import Foundation

@MainActor
final class CodexAppServerClient {
    enum ClientError: LocalizedError {
        case executableNotFound
        case serverNotRunning
        case serverExited(Int32, String?)
        case invalidResponse
        case rpc(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "没有找到 Codex CLI。请先安装 Codex，或通过 CODEX_EXECUTABLE 指定路径。"
            case .serverNotRunning:
                return "Codex App Server 尚未运行。"
            case let .serverExited(status, details):
                let summary = "Codex App Server 已退出（状态码 \(status)）。"
                guard let details, !details.isEmpty else { return summary }
                return summary + "\n" + details
            case .invalidResponse:
                return "Codex App Server 返回了无效响应。"
            case let .rpc(_, message):
                return message
            }
        }
    }

    typealias NotificationHandler = @MainActor (_ method: String, _ params: JSONValue?) -> Void

    var notificationHandler: NotificationHandler?

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private(set) var executableURL: URL?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func startIfNeeded() async throws {
        if isRunning { return }

        guard let executable = CodexExecutableLocator.locate() else {
            throw ClientError.executableNotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        errorBuffer.removeAll(keepingCapacity: true)

        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = CodexExecutableLocator.launchEnvironment(for: executable)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeError(data)
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { @MainActor in
                self?.handleTermination(status: status)
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        executableURL = executable

        do {
            _ = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codex_remaining_menubar"),
                        "title": .string("Codex Remaining"),
                        "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                    ])
                ])
            )
            try sendNotification(method: "initialized", params: .object([:]))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        process?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        process?.standardError.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        executableURL = nil
        failPending(with: ClientError.serverNotRunning)
    }

    func readAccount() async throws -> JSONValue {
        try await request(
            method: "account/read",
            params: .object(["refreshToken": .bool(false)])
        )
    }

    func readRateLimits() async throws -> JSONValue {
        try await request(method: "account/rateLimits/read", params: nil)
    }

    func startChatGPTLogin() async throws -> URL {
        let result = try await request(
            method: "account/login/start",
            params: .object([
                "type": .string("chatgpt"),
                "useHostedLoginSuccessPage": .bool(true),
                "appBrand": .string("chatgpt")
            ])
        )
        guard let urlString = result.objectValue?["authUrl"]?.stringValue,
              let url = URL(string: urlString) else {
            throw ClientError.invalidResponse
        }
        return url
    }

    private func request(method: String, params: JSONValue?) async throws -> JSONValue {
        guard isRunning else { throw ClientError.serverNotRunning }

        let id = nextRequestID
        nextRequestID += 1

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try writeMessage(id: id, method: method, params: params)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) throws {
        try writeMessage(id: nil, method: method, params: params)
    }

    private func writeMessage(id: Int?, method: String, params: JSONValue?) throws {
        guard let inputHandle else { throw ClientError.serverNotRunning }

        var message: [String: JSONValue] = ["method": .string(method)]
        if let id { message["id"] = .number(Double(id)) }
        if let params { message["params"] = params }

        var data = try JSONEncoder().encode(JSONValue.object(message))
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard let envelope = try? JSONDecoder().decode(RPCEnvelope.self, from: data) else {
            return
        }

        if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
            if let error = envelope.error {
                continuation.resume(throwing: ClientError.rpc(code: error.code, message: error.message))
            } else if let result = envelope.result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: ClientError.invalidResponse)
            }
            return
        }

        if let method = envelope.method {
            notificationHandler?(method, envelope.params)
        }
    }

    private func consumeError(_ data: Data) {
        let maximumBytes = 16_384
        errorBuffer.append(data)
        if errorBuffer.count > maximumBytes {
            errorBuffer.removeFirst(errorBuffer.count - maximumBytes)
        }
    }

    private func handleTermination(status: Int32) {
        let details = String(data: errorBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process = nil
        inputHandle = nil
        executableURL = nil
        errorBuffer.removeAll(keepingCapacity: true)
        failPending(with: ClientError.serverExited(status, details))
    }

    private func failPending(with error: Error) {
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }
}
