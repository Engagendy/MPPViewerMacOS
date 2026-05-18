import Foundation

/// The XPC service delegate that handles incoming connections.
class MPPConverterXPCDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exportedInterface = NSXPCInterface(with: MPPConverterXPCProtocol.self)
        newConnection.exportedInterface = exportedInterface
        newConnection.exportedObject = MPPConverterXPCHandler()
        newConnection.resume()
        return true
    }
}


/// The handler that performs the actual MPP → JSON conversion using the bundled Java runtime.
class MPPConverterXPCHandler: NSObject, MPPConverterXPCProtocol {
    func convertMPP(atPath inputPath: String, reply: @escaping (Data?, String?) -> Void) {
        performConversion(inputPath: inputPath, reply: reply)
    }

    func convertMPPData(_ inputData: Data, fileExtension: String, reply: @escaping (Data?, String?) -> Void) {
        let tempExtension = sanitizedExtension(fileExtension)
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(tempExtension)

        do {
            try inputData.write(to: inputURL, options: .atomic)
        } catch {
            reply(nil, "Failed to stage input file for conversion: \(error.localizedDescription)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: inputURL)
        }

        performConversion(inputPath: inputURL.path, reply: reply)
    }

    private func performConversion(inputPath: String, reply: @escaping (Data?, String?) -> Void) {
        let javaPath = locateJava()
        let jarPath = locateJAR()

        guard FileManager.default.fileExists(atPath: javaPath) else {
            reply(nil, "Bundled Java runtime not found. The app may be damaged.")
            return
        }
        guard FileManager.default.fileExists(atPath: jarPath) else {
            reply(nil, "MPXJ converter JAR not found. The app may be damaged.")
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = ["-jar", jarPath, inputPath, outputURL.path]

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(nil, "Failed to launch Java process: \(error.localizedDescription)")
            return
        }

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            reply(nil, "Java process exited with code \(process.terminationStatus): \(combinedProcessOutput(stderr: stderr, stdout: stdout))")
            return
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            reply(nil, "Converter produced no output file.")
            return
        }

        do {
            let data = try Data(contentsOf: outputURL)
            reply(data, nil)
        } catch {
            reply(nil, "Failed to read output: \(error.localizedDescription)")
        }
    }

    private func sanitizedExtension(_ fileExtension: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let sanitized = String(fileExtension.lowercased().filter { allowed.contains($0) })
        return sanitized.isEmpty ? "mpp" : sanitized
    }

    private func combinedProcessOutput(stderr: String, stdout: String) -> String {
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

    private func locateJava() -> String {
        // Check bundled JRE in the XPC service's own bundle
        let xpcBundle = Bundle.main
        if let pluginsURL = xpcBundle.builtInPlugInsURL {
            let archBundledPath = pluginsURL
                .appendingPathComponent("jre")
                .appendingPathComponent(runtimeArchitectureName())
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: archBundledPath) {
                return archBundledPath
            }

            let bundledPath = pluginsURL
                .appendingPathComponent("jre")
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Check the parent app bundle's Resources directory
        // XPC service is at: AppBundle/Contents/XPCServices/MPPConverterXPC.xpc
        // JRE is at: AppBundle/Contents/Resources/jre/bin/java
        let xpcBundlePath = xpcBundle.bundlePath
        let appContentsURL = URL(fileURLWithPath: xpcBundlePath)
            .deletingLastPathComponent()  // XPCServices/
            .deletingLastPathComponent()  // Contents/
        let archJrePath = appContentsURL
            .appendingPathComponent("Resources")
            .appendingPathComponent("jre")
            .appendingPathComponent(runtimeArchitectureName())
            .appendingPathComponent("bin")
            .appendingPathComponent("java")
            .path
        if FileManager.default.fileExists(atPath: archJrePath) {
            return archJrePath
        }

        let jrePath = appContentsURL
            .appendingPathComponent("Resources")
            .appendingPathComponent("jre")
            .appendingPathComponent("bin")
            .appendingPathComponent("java")
            .path
        if FileManager.default.fileExists(atPath: jrePath) {
            return jrePath
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
        // Check XPC service bundle resources
        if let jarURL = Bundle.main.url(forResource: "mpxj-converter", withExtension: "jar") {
            return jarURL.path
        }

        // Check parent app bundle resources
        let xpcBundlePath = Bundle.main.bundlePath
        let appContentsURL = URL(fileURLWithPath: xpcBundlePath)
            .deletingLastPathComponent()  // XPCServices/
            .deletingLastPathComponent()  // Contents/
        let jarPath = appContentsURL
            .appendingPathComponent("Resources")
            .appendingPathComponent("mpxj-converter.jar")
            .path
        if FileManager.default.fileExists(atPath: jarPath) {
            return jarPath
        }

        // Dev fallback
        let sourceRoot = URL(fileURLWithPath: #filePath)
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
}
