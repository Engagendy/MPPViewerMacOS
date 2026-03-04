import Foundation

enum MPPConverterError: LocalizedError {
    case xpcConnectionFailed
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .xpcConnectionFailed:
            return "Failed to connect to the converter service."
        case .conversionFailed(let msg):
            return "MPP conversion failed: \(msg)"
        }
    }
}

final class MPPConverterService {

    private var xpcConnection: NSXPCConnection?

    func convert(mppFileURL: URL) async throws -> Data {
        // First try XPC service (for sandboxed/production builds)
        if let data = try? await convertViaXPC(inputPath: mppFileURL.path) {
            return data
        }

        // Fallback to direct process execution (for development)
        return try await convertDirectly(mppFileURL: mppFileURL)
    }

    // MARK: - XPC Service Path

    private func convertViaXPC(inputPath: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(serviceName: "com.mppviewer.MPPConverterXPC")
            connection.remoteObjectInterface = NSXPCInterface(with: MPPConverterXPCProtocol.self)
            connection.resume()

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                connection.invalidate()
                continuation.resume(throwing: MPPConverterError.xpcConnectionFailed)
            } as! MPPConverterXPCProtocol

            proxy.convertMPP(atPath: inputPath) { data, errorMessage in
                connection.invalidate()
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MPPConverterError.conversionFailed(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    // MARK: - Direct Process Fallback (development only)

    private func convertDirectly(mppFileURL: URL) async throws -> Data {
        let javaPath = locateJava()
        let jarPath = locateJAR()

        guard FileManager.default.fileExists(atPath: javaPath) else {
            throw MPPConverterError.conversionFailed(
                "Java runtime not found. Searched bundled JRE and system paths."
            )
        }
        guard FileManager.default.fileExists(atPath: jarPath) else {
            throw MPPConverterError.conversionFailed(
                "MPXJ converter JAR not found at: \(jarPath)"
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
        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let bundledPath = pluginsURL
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
            sourceRoot.appendingPathComponent("build/DerivedData/Build/Products/Release/MPPViewer.app/Contents/PlugIns/jre/bin/java").path,
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

        return "/Users/engagendy/RiderProjects/mpp/MPPConverter/target/mpxj-converter.jar"
    }

    private func runProcess(
        javaPath: String,
        jarPath: String,
        inputPath: String,
        outputPath: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            // Use /bin/sh to invoke java to avoid Gatekeeper/translocation
            // issues with directly executing bundled binaries
            process.executableURL = URL(fileURLWithPath: "/bin/sh")

            let escapedJava = javaPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedJar = jarPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedInput = inputPath.replacingOccurrences(of: "'", with: "'\\''")
            let escapedOutput = outputPath.replacingOccurrences(of: "'", with: "'\\''")
            process.arguments = ["-c", "'\(escapedJava)' -jar '\(escapedJar)' '\(escapedInput)' '\(escapedOutput)'"]

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            process.terminationHandler = { proc in
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: MPPConverterError.conversionFailed(
                        "Java process exited with code \(proc.terminationStatus): \(stderr)"
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: MPPConverterError.conversionFailed(error.localizedDescription))
            }
        }
    }
}
