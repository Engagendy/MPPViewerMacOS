import Darwin
import Foundation

enum MPPConverterError: LocalizedError {
    case xpcConnectionFailed
    case conversionFailed(String)
    case conversionTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .xpcConnectionFailed:
            return "Failed to connect to the converter service."
        case .conversionFailed(let msg):
            return "MPP conversion failed: \(msg)"
        case .conversionTimedOut(let msg):
            return "MPP conversion timed out: \(msg)"
        }
    }
}

private final class OneShotCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func complete(_ body: () -> Void) {
        lock.lock()
        guard !hasCompleted else {
            lock.unlock()
            return
        }
        hasCompleted = true
        lock.unlock()
        body()
    }
}

private final class ProcessOutputCapture: @unchecked Sendable {
    let stderrHandle: FileHandle
    let stdoutHandle: FileHandle

    private let stderrURL: URL
    private let stdoutURL: URL
    private let lock = NSLock()
    private var hasClosed = false

    init() throws {
        stderrURL = Self.temporaryLogURL(extension: "stderr")
        stdoutURL = Self.temporaryLogURL(extension: "stdout")
        stderrHandle = try Self.makeWritableFileHandle(at: stderrURL)
        stdoutHandle = try Self.makeWritableFileHandle(at: stdoutURL)
    }

    func closeAndReadOutput() -> (stderr: String, stdout: String) {
        lock.lock()
        guard !hasClosed else {
            lock.unlock()
            return ("", "")
        }
        hasClosed = true
        lock.unlock()

        try? stderrHandle.close()
        try? stdoutHandle.close()
        let stderr = Self.readLogText(at: stderrURL)
        let stdout = Self.readLogText(at: stdoutURL)
        try? FileManager.default.removeItem(at: stderrURL)
        try? FileManager.default.removeItem(at: stdoutURL)
        return (stderr, stdout)
    }

    private static func temporaryLogURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }

    private static func makeWritableFileHandle(at url: URL) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }

    private static func readLogText(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

final class MPPConverterService {

    private static let conversionTimeoutSeconds: TimeInterval = 90
    private var xpcConnection: NSXPCConnection?

    func convert(mppFileURL: URL) async throws -> Data {
        #if DEBUG
        do {
            return try await convertDirectly(mppFileURL: mppFileURL)
        } catch {
            do {
                return try await convertViaXPC(mppFileURL: mppFileURL)
            } catch {
                throw error
            }
        }
        #else
        do {
            // First try XPC service (for sandboxed/production builds).
            let data = try await convertViaXPC(mppFileURL: mppFileURL)
            return data
        } catch MPPConverterError.xpcConnectionFailed, MPPConverterError.conversionTimedOut {
            return try await convertDirectly(mppFileURL: mppFileURL)
        } catch {
            throw error
        }
        #endif
    }

    func exportMSPDI(planJSON: Data) async throws -> Data {
        #if DEBUG
        do {
            return try await exportMSPDIDirectly(planJSON: planJSON)
        } catch {
            return try await exportMSPDIViaXPC(planJSON: planJSON)
        }
        #else
        do {
            return try await exportMSPDIViaXPC(planJSON: planJSON)
        } catch MPPConverterError.xpcConnectionFailed, MPPConverterError.conversionTimedOut {
            return try await exportMSPDIDirectly(planJSON: planJSON)
        } catch {
            throw error
        }
        #endif
    }

    private func exportMSPDIDirectly(planJSON: Data) async throws -> Data {
        let javaPath = locateJava()
        let jarPath = locateJAR()

        guard FileManager.default.fileExists(atPath: javaPath) else {
            throw MPPConverterError.conversionFailed(
                "Java runtime not found. Searched bundled JRE and system paths."
            )
        }
        guard FileManager.default.fileExists(atPath: jarPath) else {
            throw MPPConverterError.conversionFailed(
                "MPXJ converter JAR not found in the app bundle. The app may be damaged."
            )
        }

        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("xml")

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try planJSON.write(to: inputURL, options: .atomic)
        try await runProcess(
            javaPath: javaPath,
            jarPath: jarPath,
            jarArguments: ["--plan-to-mspdi", inputURL.path, outputURL.path]
        )

        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else {
            throw MPPConverterError.conversionFailed("MSPDI export produced an empty output file.")
        }
        return data
    }

    private func exportMSPDIViaXPC(planJSON: Data) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let completion = OneShotCompletion()
            let connection = NSXPCConnection(serviceName: "com.mppviewer.MPPConverterXPC")
            connection.remoteObjectInterface = NSXPCInterface(with: MPPConverterXPCProtocol.self)
            connection.resume()

            let timeout = DispatchWorkItem {
                completion.complete {
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.conversionTimedOut(
                        "The converter helper did not reply within \(Int(Self.conversionTimeoutSeconds)) seconds."
                    ))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Self.conversionTimeoutSeconds,
                execute: timeout
            )

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.xpcConnectionFailed)
                }
            }) as? MPPConverterXPCProtocol else {
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.xpcConnectionFailed)
                }
                return
            }

            proxy.exportPlanToMSPDI(planJSON) { data, errorMessage in
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: MPPConverterError.conversionFailed(errorMessage ?? "Unknown error"))
                    }
                }
            }
        }
    }

    // MARK: - XPC Service Path

    private func convertViaXPC(mppFileURL: URL) async throws -> Data {
        let didStartAccessing = mppFileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                mppFileURL.stopAccessingSecurityScopedResource()
            }
        }

        let inputData: Data
        do {
            inputData = try Data(contentsOf: mppFileURL)
        } catch {
            throw MPPConverterError.conversionFailed(
                "Could not read input file before conversion: \(error.localizedDescription)"
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let completion = OneShotCompletion()
            let connection = NSXPCConnection(serviceName: "com.mppviewer.MPPConverterXPC")
            connection.remoteObjectInterface = NSXPCInterface(with: MPPConverterXPCProtocol.self)
            connection.resume()

            let timeout = DispatchWorkItem {
                completion.complete {
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.conversionTimedOut(
                        "The converter helper did not reply within \(Int(Self.conversionTimeoutSeconds)) seconds."
                    ))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Self.conversionTimeoutSeconds,
                execute: timeout
            )

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.xpcConnectionFailed)
                }
            }) as? MPPConverterXPCProtocol else {
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    continuation.resume(throwing: MPPConverterError.xpcConnectionFailed)
                }
                return
            }

            proxy.convertMPPData(inputData, fileExtension: mppFileURL.pathExtension) { data, errorMessage in
                completion.complete {
                    timeout.cancel()
                    connection.invalidate()
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: MPPConverterError.conversionFailed(errorMessage ?? "Unknown error"))
                    }
                }
            }
        }
    }

    // MARK: - Direct Process Fallback (development only)

    private func convertDirectly(mppFileURL: URL) async throws -> Data {
        let didStartAccessing = mppFileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                mppFileURL.stopAccessingSecurityScopedResource()
            }
        }

        let javaPath = locateJava()
        let jarPath = locateJAR()

        guard FileManager.default.fileExists(atPath: javaPath) else {
            throw MPPConverterError.conversionFailed(
                "Java runtime not found. Searched bundled JRE and system paths."
            )
        }
        guard FileManager.default.fileExists(atPath: jarPath) else {
            throw MPPConverterError.conversionFailed(
                "MPXJ converter JAR not found in the app bundle. The app may be damaged."
            )
        }
        guard FileManager.default.fileExists(atPath: mppFileURL.path) else {
            throw MPPConverterError.conversionFailed(
                "Input file not found at: \(mppFileURL.path)"
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await runProcess(
            javaPath: javaPath,
            jarPath: jarPath,
            inputPath: mppFileURL.path,
            outputPath: outputURL.path
        )

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MPPConverterError.conversionFailed(
                "Converter produced no output file. Java: \(javaPath)"
            )
        }

        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else {
            throw MPPConverterError.conversionFailed("Converter produced an empty output file.")
        }

        return data
    }

    private func locateJava() -> String {
        // 1. Check bundled JRE first (for production/packaged app)
        if let resourcesURL = Bundle.main.resourceURL {
            let archBundledPath = resourcesURL
                .appendingPathComponent("jre")
                .appendingPathComponent(runtimeArchitectureName())
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: archBundledPath) {
                return archBundledPath
            }

            let bundledPath = resourcesURL
                .appendingPathComponent("jre")
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // 2. Check packaged app's JRE in build output (for Xcode development runs)
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // MPPViewer/
            .deletingLastPathComponent()  // MPPViewer/
            .deletingLastPathComponent()  // MPPViewer/ (xcodeproj level)
        let devJreCandidates = [
            // From package.sh build output
            sourceRoot.appendingPathComponent("build/DerivedData/Build/Products/Release/MPPViewer.app/Contents/Resources/jre/bin/java").path,
            // Cached JRE download (arm64)
            sourceRoot.appendingPathComponent(".cache/jre/temurin-jre-21-aarch64/Contents/Home/bin/java").path,
            // Cached JRE download (x86_64)
            sourceRoot.appendingPathComponent(".cache/jre/temurin-jre-21-x64/Contents/Home/bin/java").path,
        ]
        for path in devJreCandidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 3. Check Homebrew OpenJDK 21
        let candidates = [
            "/usr/local/opt/openjdk@21/bin/java",
            "/opt/homebrew/opt/openjdk@21/bin/java",
            "/usr/local/opt/openjdk/bin/java",
            "/opt/homebrew/opt/openjdk/bin/java",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 4. Try /usr/libexec/java_home requesting Java 21+
        if let javaHome = resolveJavaHome(version: "21") {
            let javaPath = javaHome + "/bin/java"
            if FileManager.default.fileExists(atPath: javaPath) {
                return javaPath
            }
        }

        // 5. Fallback to any java_home
        if let javaHome = resolveJavaHome(version: nil) {
            let javaPath = javaHome + "/bin/java"
            if FileManager.default.fileExists(atPath: javaPath) {
                return javaPath
            }
        }

        return "/usr/bin/java"
    }

    private func resolveJavaHome(version: String?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        if let version = version {
            process.arguments = ["-v", version]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }

    private func locateJAR() -> String {
        if let jarURL = Bundle.main.url(forResource: "mpxj-converter", withExtension: "jar") {
            return jarURL.path
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let devPath = sourceRoot
            .appendingPathComponent("MPPConverter")
            .appendingPathComponent("target")
            .appendingPathComponent("mpxj-converter.jar")
            .path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        return ""
    }

    private func runtimeArchitectureName() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private func runProcess(
        javaPath: String,
        jarPath: String,
        inputPath: String,
        outputPath: String
    ) async throws {
        try await runProcess(javaPath: javaPath, jarPath: jarPath, jarArguments: [inputPath, outputPath])
    }

    private func runProcess(
        javaPath: String,
        jarPath: String,
        jarArguments: [String]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = OneShotCompletion()
            let process = Process()
            // Use /bin/sh to invoke java to avoid Gatekeeper/translocation
            // issues with directly executing bundled binaries
            process.executableURL = URL(fileURLWithPath: "/bin/sh")

            func shellQuoted(_ value: String) -> String {
                "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }
            let command = ([javaPath, "-jar", jarPath] + jarArguments)
                .map(shellQuoted)
                .joined(separator: " ")
            process.arguments = ["-c", command]

            let outputCapture: ProcessOutputCapture
            do {
                outputCapture = try ProcessOutputCapture()
            } catch {
                continuation.resume(throwing: MPPConverterError.conversionFailed(
                    "Failed to prepare converter log files: \(error.localizedDescription)"
                ))
                return
            }

            process.standardError = outputCapture.stderrHandle
            process.standardOutput = outputCapture.stdoutHandle

            process.terminationHandler = { proc in
                completion.complete {
                    let output = outputCapture.closeAndReadOutput()
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: MPPConverterError.conversionFailed(
                            "Java process exited with code \(proc.terminationStatus): \(Self.combinedProcessOutput(stderr: output.stderr, stdout: output.stdout))"
                        ))
                    }
                }
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.conversionTimeoutSeconds) {
                    completion.complete {
                        Self.terminateProcess(process)
                        let output = outputCapture.closeAndReadOutput()
                        continuation.resume(throwing: MPPConverterError.conversionTimedOut(
                            "Java did not finish within \(Int(Self.conversionTimeoutSeconds)) seconds. \(Self.combinedProcessOutput(stderr: output.stderr, stdout: output.stdout))"
                        ))
                    }
                }
            } catch {
                completion.complete {
                    let output = outputCapture.closeAndReadOutput()
                    continuation.resume(throwing: MPPConverterError.conversionFailed(
                        "\(error.localizedDescription): \(Self.combinedProcessOutput(stderr: output.stderr, stdout: output.stdout))"
                    ))
                }
            }
        }
    }

    private static func terminateProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        Thread.sleep(forTimeInterval: 0.5)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func combinedProcessOutput(stderr: String, stdout: String) -> String {
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedStderr.isEmpty && !trimmedStdout.isEmpty {
            return "\(trimmedStderr)\n\(trimmedStdout)"
        }
        if !trimmedStderr.isEmpty {
            return trimmedStderr
        }
        if !trimmedStdout.isEmpty {
            return trimmedStdout
        }
        return "No process output."
    }
}
