import Foundation

struct VoxCPMPluginRuntime: Sendable {
    static let bridgeVersion = "1.0"
    static let healthCheckTimeout: TimeInterval = 10

    enum RuntimeError: LocalizedError {
        case bridgeScriptNotFound
        case invalidResponse
        case processFailed(message: String)
        case timedOut(seconds: TimeInterval)

        var errorDescription: String? {
            switch self {
            case .bridgeScriptNotFound:
                return "未找到 VoxCPM Python bridge 脚本。"
            case .invalidResponse:
                return "VoxCPM bridge 返回了无法解析的响应。"
            case .processFailed(let message):
                return message
            case .timedOut(let seconds):
                return "VoxCPM bridge 在 \(Int(seconds)) 秒内未完成响应。"
            }
        }
    }

    struct HealthCheckArguments: Equatable {
        var voxcpmRoot: String
    }

    private final class ProcessIOBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var outputData = Data()
        private var errorData = Data()
        private var didResume = false
        private var timeoutWorkItem: DispatchWorkItem?

        func appendOutput(from fileHandle: FileHandle) {
            lock.lock()
            defer { lock.unlock() }
            drain(handle: fileHandle, into: &outputData)
        }

        func appendError(from fileHandle: FileHandle) {
            lock.lock()
            defer { lock.unlock() }
            drain(handle: fileHandle, into: &errorData)
        }

        func snapshot(
            outputHandle: FileHandle,
            errorHandle: FileHandle
        ) -> (output: Data, error: Data) {
            lock.lock()
            defer { lock.unlock() }
            drain(handle: outputHandle, into: &outputData)
            drain(handle: errorHandle, into: &errorData)
            return (outputData, errorData)
        }

        func markResumed() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return false }
            didResume = true
            return true
        }

        func setTimeoutWorkItem(_ workItem: DispatchWorkItem?) {
            lock.lock()
            defer { lock.unlock() }
            timeoutWorkItem = workItem
        }

        func clearTimeoutWorkItem() {
            lock.lock()
            defer { lock.unlock() }
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
        }

        private func drain(handle: FileHandle, into buffer: inout Data) {
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
        }
    }

    func healthCheck(configuration: VoxCPMPluginConfiguration) async throws -> VoxCPMHealthCheckResult {
        let response = try await invoke(
            command: .healthCheck,
            arguments: HealthCheckArguments(voxcpmRoot: configuration.voxcpmRootPath),
            preferredPythonCommand: configuration.pythonCommand,
            timeout: Self.healthCheckTimeout
        )

        let details = response.details
        let voxcpmRoot = details["voxcpm_root"]?.stringValue ?? configuration.voxcpmRootPath
        let rootExists = details["exists"]?.boolValue ?? false
        let requiredFiles = try decodeRequiredFiles(from: details["required_files"])

        return VoxCPMHealthCheckResult(
            response: response,
            voxcpmRoot: voxcpmRoot,
            rootExists: rootExists,
            requiredFiles: requiredFiles
        )
    }

    func invoke(
        command: VoxCPMBridgeCommand,
        arguments: HealthCheckArguments,
        preferredPythonCommand: String?,
        timeout: TimeInterval? = nil
    ) async throws -> VoxCPMBridgeResponseEnvelope {
        let request = VoxCPMBridgeRequestEnvelope(
            version: Self.bridgeVersion,
            requestID: UUID().uuidString,
            command: command,
            arguments: [
                "voxcpm_root": .string(arguments.voxcpmRoot)
            ]
        )
        return try await invoke(
            request: request,
            preferredPythonCommand: preferredPythonCommand,
            timeout: timeout
        )
    }

    func invoke(
        request: VoxCPMBridgeRequestEnvelope,
        preferredPythonCommand: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> VoxCPMBridgeResponseEnvelope {
        let bridgeScriptURL = try resolveBridgeScriptURL()
        let pythonExecutable = try resolvePythonExecutable(preferredCommand: preferredPythonCommand)
        let requestData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = pythonExecutable
            process.arguments = [bridgeScriptURL.path]

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            ].joined(separator: ":")
            process.environment = environment

            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            let ioBuffer = ProcessIOBuffer()

            let cleanupHandlers: @Sendable () -> Void = {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                ioBuffer.clearTimeoutWorkItem()
            }

            let finish: @Sendable (Result<VoxCPMBridgeResponseEnvelope, Error>) -> Void = { result in
                guard ioBuffer.markResumed() else { return }
                cleanupHandlers()
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                ioBuffer.appendOutput(from: fileHandle)
            }

            errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                ioBuffer.appendError(from: fileHandle)
            }

            process.terminationHandler = { process in
                let snapshot = ioBuffer.snapshot(
                    outputHandle: outputPipe.fileHandleForReading,
                    errorHandle: errorPipe.fileHandleForReading
                )
                let outputData = snapshot.output
                let errorData = snapshot.error

                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard process.terminationStatus == 0 else {
                    finish(
                        .failure(
                            RuntimeError.processFailed(
                                message: errorText?.isEmpty == false
                                    ? errorText!
                                    : "VoxCPM bridge 进程退出码为 \(process.terminationStatus)。"
                            )
                        )
                    )
                    return
                }

                do {
                    let response = try JSONDecoder().decode(VoxCPMBridgeResponseEnvelope.self, from: outputData)
                    guard response.version == Self.bridgeVersion else {
                        throw RuntimeError.invalidResponse
                    }
                    finish(.success(response))
                } catch {
                    finish(.failure(error))
                }
            }

            do {
                try process.run()
                inputPipe.fileHandleForWriting.write(requestData)
                inputPipe.fileHandleForWriting.closeFile()

                if let timeout, timeout > 0 {
                    let workItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                        }
                        finish(.failure(RuntimeError.timedOut(seconds: timeout)))
                    }
                    ioBuffer.setTimeoutWorkItem(workItem)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(
                        deadline: .now() + timeout,
                        execute: workItem
                    )
                }
            } catch {
                finish(
                    .failure(
                        RuntimeError.processFailed(
                            message: "无法启动 VoxCPM bridge：\(error.localizedDescription)"
                        )
                    )
                )
            }
        }
    }

    private func decodeRequiredFiles(
        from value: VoxCPMBridgeValue?
    ) throws -> [String: VoxCPMBridgeRequiredFileStatus] {
        guard let objectValue = value?.objectValue else {
            return [:]
        }

        let data = try JSONEncoder().encode(objectValue)
        return try JSONDecoder().decode([String: VoxCPMBridgeRequiredFileStatus].self, from: data)
    }

    private func resolveBridgeScriptURL() throws -> URL {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let bundleResources = Bundle.main.resourceURL

        let candidates = [
            sourceRoot
                .appendingPathComponent("Support", isDirectory: true)
                .appendingPathComponent("VoxCPM", isDirectory: true)
                .appendingPathComponent("voxcpm_bridge.py"),
            bundleResources?
                .appendingPathComponent("VoxCPM", isDirectory: true)
                .appendingPathComponent("voxcpm_bridge.py"),
            bundleResources?.appendingPathComponent("voxcpm_bridge.py")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        throw RuntimeError.bridgeScriptNotFound
    }

    private func resolvePythonExecutable(preferredCommand: String?) throws -> URL {
        let candidates = [
            preferredCommand,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ].compactMap { $0 }

        for candidate in candidates {
            if candidate.hasPrefix("/") {
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            } else if let resolvedPath = resolveCommandPath(candidate) {
                return URL(fileURLWithPath: resolvedPath)
            }
        }

        throw RuntimeError.processFailed(message: "未找到可用的 Python 解释器。")
    }

    private func resolveCommandPath(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }
}
