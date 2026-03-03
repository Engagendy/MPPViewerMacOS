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
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            reply(nil, "Java process exited with code \(process.terminationStatus): \(stderr)")
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

    private func locateJava() -> String {
        // Check bundled JRE in the XPC service's own bundle
        let xpcBundle = Bundle.main
        if let pluginsURL = xpcBundle.builtInPlugInsURL {
            let bundledPath = pluginsURL
                .appendingPathComponent("jre")
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // Check the parent app bundle's PlugIns directory
        // XPC service is at: AppBundle/Contents/XPCServices/MPPConverterXPC.xpc
        // JRE is at: AppBundle/Contents/PlugIns/jre/bin/java
        let xpcBundlePath = xpcBundle.bundlePath
        if let appContentsURL = URL(string: xpcBundlePath)?
            .deletingLastPathComponent()  // XPCServices/
            .deletingLastPathComponent()  // Contents/
        {
            let jrePath = appContentsURL
                .appendingPathComponent("PlugIns")
                .appendingPathComponent("jre")
                .appendingPathComponent("bin")
                .appendingPathComponent("java")
                .path
            if FileManager.default.fileExists(atPath: jrePath) {
                return jrePath
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
        // Check XPC service bundle resources
        if let jarURL = Bundle.main.url(forResource: "mpxj-converter", withExtension: "jar") {
            return jarURL.path
        }

        // Check parent app bundle resources
        let xpcBundlePath = Bundle.main.bundlePath
        if let appContentsURL = URL(string: xpcBundlePath)?
            .deletingLastPathComponent()  // XPCServices/
            .deletingLastPathComponent()  // Contents/
        {
            let jarPath = appContentsURL
                .appendingPathComponent("Resources")
                .appendingPathComponent("mpxj-converter.jar")
                .path
            if FileManager.default.fileExists(atPath: jarPath) {
                return jarPath
            }
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

        return "/Users/engagendy/RiderProjects/mpp/MPPConverter/target/mpxj-converter.jar"
    }
}

