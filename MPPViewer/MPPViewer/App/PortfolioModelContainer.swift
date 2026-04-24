import Foundation
import SwiftData
import OSLog
import CoreData

enum PortfolioModelContainer {
    private static let logger = Logger(subsystem: "com.mppviewer", category: "DataStore")
    private static let schema = Schema([
        PortfolioProjectPlan.self,
        PortfolioPlanTask.self,
        PortfolioPlanResource.self,
        PortfolioPlanAssignment.self,
        PortfolioCrossProjectDependency.self,
        PortfolioReviewPreset.self,
        PortfolioReviewSnapshot.self,
        PortfolioPlanCalendar.self,
        PortfolioPlanSprint.self,
        PortfolioWorkflowColumn.self,
        PortfolioTypeWorkflow.self,
        PortfolioStatusSnapshot.self,
        PortfolioSprintStatusSnapshot.self
    ])

    private static let storeDirectoryName = "MPPViewer"
    private static let storeFileName = "portfolio.store"

    static func make() -> ModelContainer {
        do {
            return try makePersistentContainer()
        } catch {
            if isRecoverableStoreError(error) {
                logger.error("SwiftData store recovery triggered: \(error.localizedDescription)")
                if let storeURL = defaultStoreURL() {
                    recoverStore(at: storeURL)
                }

                do {
                    return try makePersistentContainer()
                } catch {
                    logger.error("Recovered store still failed to open: \(error.localizedDescription)")
                }
            } else {
                logger.error("SwiftData store initialization failed without recoverable condition: \(error.localizedDescription)")
            }
        }

        logger.info("Falling back to in-memory container.")
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        } catch {
            logger.critical("In-memory container initialization failed: \(error.localizedDescription)")
            // Last-resort fail-fast to preserve existing behavior.
            fatalError("Unable to initialize model container: \(error.localizedDescription)")
        }
    }

    private static func makePersistentContainer() throws -> ModelContainer {
        let configuration = try makePersistentConfiguration()
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func makePersistentConfiguration() throws -> ModelConfiguration {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let supportDirectory = appSupport.appendingPathComponent(storeDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: supportDirectory.path) {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        }
        guard let storeURL = defaultStoreURL(baseDirectory: supportDirectory) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return ModelConfiguration(url: storeURL)
    }

    private static func defaultStoreURL(baseDirectory: URL? = nil) -> URL? {
        let base = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(storeDirectoryName, isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(storeFileName)
    }

    private static func isRecoverableStoreError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134110 {
            return true
        }
        if let message = nsError.localizedDescription.lowercased() as String?,
           message.contains("cannot migrate store") || message.contains("validation") || message.contains("missing attribute values") || message.contains("constraint") || message.contains("duplicate") {
            return true
        }
        if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [NSError],
           detailed.contains(where: isRecoverableStoreError) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           isRecoverableStoreError(underlying) {
            return true
        }

        return false
    }

    private static func recoverStore(at storeURL: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let backupRoot = storeURL.deletingLastPathComponent().appendingPathComponent("MPPViewerStoreBackups", isDirectory: true)
        let backupStamp = ISO8601DateFormatter().string(from: Date())
        let backupDirectory = backupRoot.appendingPathComponent("backup-\(backupStamp)", isDirectory: true)

        do {
            let storeFiles = matchingStoreFiles(for: storeURL)
            guard !storeFiles.isEmpty else { return }

            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            for file in storeFiles {
                let backupFile = backupDirectory.appendingPathComponent(file.lastPathComponent)
                try? fileManager.removeItem(at: backupFile)
                try fileManager.copyItem(at: file, to: backupFile)
            }

            for file in storeFiles {
                try? fileManager.removeItem(at: file)
            }
        } catch {
            logger.error("Failed to backup and remove corrupt store files: \(error.localizedDescription)")
        }
    }

    private static func matchingStoreFiles(for storeURL: URL) -> [URL] {
        let parent = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent
        guard let fileNames = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else {
            return []
        }
        return fileNames
            .filter { $0 == baseName || $0.hasPrefix("\(baseName)-") }
            .map { parent.appendingPathComponent($0) }
    }
}
