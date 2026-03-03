import Foundation

enum MPPConverterError: LocalizedError {
    case jreNotFound
    case jarNotFound
    case conversionFailed(String)
    case processError(Int32, String)
    case outputFileNotFound

    var errorDescription: String? {
        switch self {
        case .jreNotFound:
            return "Bundled Java runtime not found. The app may be damaged."
        case .jarNotFound:
            return "MPXJ converter JAR not found. The app may be damaged."
        case .conversionFailed(let msg):
            return "MPP conversion failed: \(msg)"
        case .processError(let code, let stderr):
            return "Java process exited with code \(code): \(stderr)"
        case .outputFileNotFound:
            return "Converter produced no output file."
        }
    }
}

final class MPPConverterService {

    func convert(mppFileURL: URL) async throws -> Data {
        let javaPath = locateJava()
        let jarPath = locateJAR()

        guard FileManager.default.fileExists(atPath: javaPath) else {
            throw MPPConverterError.jreNotFound
        }
        guard FileManager.default.fileExists(atPath: jarPath) else {
            throw MPPConverterError.jarNotFound
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
            throw MPPConverterError.outputFileNotFound
        }

        return try Data(contentsOf: outputURL)
    }

    private func locateJava() -> String {
        // Check bundled JRE first
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

        // Fall back to common system Java locations
        let candidates = [
            "/usr/local/opt/openjdk@21/bin/java",
            "/usr/local/opt/openjdk/bin/java",
            "/opt/homebrew/opt/openjdk@21/bin/java",
            "/opt/homebrew/opt/openjdk/bin/java",
            "/usr/bin/java",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return "/usr/bin/java"
    }

    private func locateJAR() -> String {
        // Check bundle Resources
        if let jarURL = Bundle.main.url(forResource: "mpxj-converter", withExtension: "jar") {
            return jarURL.path
        }

        // Fall back: look relative to the Xcode project source root
        // The project source is at the same level as MPPConverter/
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services/
            .deletingLastPathComponent() // MPPViewer/
            .deletingLastPathComponent() // MPPViewer/ (project)
            .deletingLastPathComponent() // MPPViewer/ (workspace root)
        let devPath = sourceRoot
            .appendingPathComponent("MPPConverter")
            .appendingPathComponent("target")
            .appendingPathComponent("mpxj-converter.jar")
            .path
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }

        // Hardcoded fallback for development
        let hardcoded = "/Users/engagendy/RiderProjects/mpp/MPPConverter/target/mpxj-converter.jar"
        return hardcoded
    }

    private func runProcess(
        javaPath: String,
        jarPath: String,
        inputPath: String,
        outputPath: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: javaPath)
            process.arguments = ["-jar", jarPath, inputPath, outputPath]

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
                    continuation.resume(throwing: MPPConverterError.processError(proc.terminationStatus, stderr))
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
