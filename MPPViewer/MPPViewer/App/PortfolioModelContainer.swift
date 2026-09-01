import Foundation
import SwiftData
import OSLog
import CoreData
import SQLite3

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
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
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
        repairPersistedStoreIfNeeded(at: storeURL)
        // The iCloud Documents entitlement makes SwiftData default to CloudKit
        // integration (.automatic), which the portfolio schema does not satisfy —
        // the registry store must stay local-only.
        return ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
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

    private static func repairPersistedStoreIfNeeded(at storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(storeURL.path, &database, flags, nil) == SQLITE_OK, let database else {
            if let database {
                logger.error("Failed to open portfolio store for repair: \(sqliteMessage(database))")
                sqlite3_close(database)
            }
            return
        }
        defer { sqlite3_close(database) }

        guard tableExists("ZPORTFOLIOPROJECTPLAN", in: database) else { return }
        let shouldClearVolatileState = storeHasDetachedSnapshotRisk(in: database)

        guard executeSQL("BEGIN IMMEDIATE TRANSACTION", in: database) else { return }
        var repairedRows = 0
        let statements: [(sql: String, tables: [String])] = [
            ("""
            DELETE FROM ZPORTFOLIOPLANASSIGNMENT
            WHERE ZUNIQUEID IS NULL
               OR ZLEGACYID IS NULL
               OR ZTASKLEGACYID IS NULL
               OR ZUNITS IS NULL
               OR ZNOTES IS NULL
               OR ZTASK IS NULL
               OR ZTASK NOT IN (SELECT Z_PK FROM ZPORTFOLIOPLANTASK)
            """, ["ZPORTFOLIOPLANASSIGNMENT", "ZPORTFOLIOPLANTASK"]),
            ("""
            DELETE FROM ZPORTFOLIOSPRINTSTATUSSNAPSHOT
            WHERE ZUNIQUEID IS NULL
               OR ZSPRINTID IS NULL
               OR ZSPRINTNAME IS NULL
               OR ZCOMMITTEDPOINTS IS NULL
               OR ZCOMPLETEDPOINTS IS NULL
               OR ZSNAPSHOT IS NULL
               OR ZSNAPSHOT NOT IN (SELECT Z_PK FROM ZPORTFOLIOSTATUSSNAPSHOT)
            """, ["ZPORTFOLIOSPRINTSTATUSSNAPSHOT", "ZPORTFOLIOSTATUSSNAPSHOT"]),
            ("""
            DELETE FROM ZPORTFOLIOWORKFLOWCOLUMN
            WHERE ZUNIQUEID IS NULL
               OR ZORDERINDEX IS NULL
               OR ZNAME IS NULL
               OR ZALLOWEDTRANSITIONSPAYLOAD IS NULL
               OR (ZPLAN IS NULL AND ZTYPEWORKFLOW IS NULL)
               OR (ZPLAN IS NOT NULL AND ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN))
               OR (ZTYPEWORKFLOW IS NOT NULL AND ZTYPEWORKFLOW NOT IN (SELECT Z_PK FROM ZPORTFOLIOTYPEWORKFLOW))
            """, ["ZPORTFOLIOWORKFLOWCOLUMN", "ZPORTFOLIOPROJECTPLAN", "ZPORTFOLIOTYPEWORKFLOW"]),
            ("""
            DELETE FROM ZPORTFOLIOTYPEWORKFLOW
            WHERE ZUNIQUEID IS NULL
               OR ZITEMTYPE IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOTYPEWORKFLOW", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOSTATUSSNAPSHOT
            WHERE ZUNIQUEID IS NULL
               OR ZNAME IS NULL
               OR ZNOTES IS NULL
               OR ZCAPTUREDAT IS NULL
               OR ZSTATUSDATE IS NULL
               OR ZTASKCOUNT IS NULL
               OR ZCOMPLETEDTASKCOUNT IS NULL
               OR ZINPROGRESSTASKCOUNT IS NULL
               OR ZBAC IS NULL
               OR ZPV IS NULL
               OR ZEV IS NULL
               OR ZAC IS NULL
               OR ZCPI IS NULL
               OR ZSPI IS NULL
               OR ZEAC IS NULL
               OR ZVAC IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOSTATUSSNAPSHOT", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOPLANSPRINT
            WHERE ZUNIQUEID IS NULL
               OR ZLEGACYID IS NULL
               OR ZNAME IS NULL
               OR ZGOAL IS NULL
               OR ZSTARTDATE IS NULL
               OR ZENDDATE IS NULL
               OR ZCAPACITYPOINTS IS NULL
               OR ZTEAMNAME IS NULL
               OR ZSTATE IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOPLANSPRINT", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOPLANCALENDAR
            WHERE ZUNIQUEID IS NULL
               OR ZLEGACYID IS NULL
               OR ZPERSONAL IS NULL
               OR ZNAME IS NULL
               OR ZTYPE IS NULL
               OR ZEXCEPTIONSPAYLOAD IS NULL
               OR ZSUNDAYPAYLOAD IS NULL
               OR ZMONDAYPAYLOAD IS NULL
               OR ZTUESDAYPAYLOAD IS NULL
               OR ZWEDNESDAYPAYLOAD IS NULL
               OR ZTHURSDAYPAYLOAD IS NULL
               OR ZFRIDAYPAYLOAD IS NULL
               OR ZSATURDAYPAYLOAD IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOPLANCALENDAR", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOPLANRESOURCE
            WHERE ZUNIQUEID IS NULL
               OR ZACTIVE IS NULL
               OR ZLEGACYID IS NULL
               OR ZCOSTPERUSE IS NULL
               OR ZMAXUNITS IS NULL
               OR ZOVERTIMERATE IS NULL
               OR ZSTANDARDRATE IS NULL
               OR ZEMAILADDRESS IS NULL
               OR ZGROUP IS NULL
               OR ZINITIALS IS NULL
               OR ZNAME IS NULL
               OR ZNOTES IS NULL
               OR ZTYPE IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOPLANRESOURCE", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOPLANTASK
            WHERE ZUNIQUEID IS NULL
               OR ZLEGACYID IS NULL
               OR ZORDERINDEX IS NULL
               OR ZOUTLINELEVEL IS NULL
               OR ZNAME IS NULL
               OR ZNOTES IS NULL
               OR ZPLAN IS NULL
               OR ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN)
            """, ["ZPORTFOLIOPLANTASK", "ZPORTFOLIOPROJECTPLAN"]),
            ("""
            DELETE FROM ZPORTFOLIOPLANASSIGNMENT
            WHERE ZTASK IS NULL
               OR ZTASK NOT IN (SELECT Z_PK FROM ZPORTFOLIOPLANTASK)
            """, ["ZPORTFOLIOPLANASSIGNMENT", "ZPORTFOLIOPLANTASK"]),
            ("""
            DELETE FROM ZPORTFOLIOSPRINTSTATUSSNAPSHOT
            WHERE ZSNAPSHOT IS NULL
               OR ZSNAPSHOT NOT IN (SELECT Z_PK FROM ZPORTFOLIOSTATUSSNAPSHOT)
            """, ["ZPORTFOLIOSPRINTSTATUSSNAPSHOT", "ZPORTFOLIOSTATUSSNAPSHOT"]),
            ("""
            DELETE FROM ZPORTFOLIOWORKFLOWCOLUMN
            WHERE (ZPLAN IS NOT NULL AND ZPLAN NOT IN (SELECT Z_PK FROM ZPORTFOLIOPROJECTPLAN))
               OR (ZTYPEWORKFLOW IS NOT NULL AND ZTYPEWORKFLOW NOT IN (SELECT Z_PK FROM ZPORTFOLIOTYPEWORKFLOW))
            """, ["ZPORTFOLIOWORKFLOWCOLUMN", "ZPORTFOLIOPROJECTPLAN", "ZPORTFOLIOTYPEWORKFLOW"]),
            ("""
            UPDATE ZPORTFOLIOPROJECTPLAN
            SET ZISARCHIVED = 0
            WHERE ZISARCHIVED IS NULL
            """, ["ZPORTFOLIOPROJECTPLAN"])
        ]

        for statement in statements where statement.tables.allSatisfy({ tableExists($0, in: database) }) {
            if executeSQL(statement.sql, in: database) {
                repairedRows += Int(sqlite3_changes(database))
            }
        }

        if repairedRows > 0 || shouldClearVolatileState {
            clearVolatileStoreState(in: database)
        }

        if executeSQL("COMMIT", in: database) {
            _ = executeSQL("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
            if repairedRows > 0 {
                logger.info("Repaired \(repairedRows) invalid persisted portfolio rows before SwiftData opened the store.")
            } else if shouldClearVolatileState {
                logger.info("Cleared stale persisted portfolio cache/history before SwiftData opened the store.")
            }
        } else {
            _ = executeSQL("ROLLBACK", in: database)
        }
    }

    private static func storeHasDetachedSnapshotRisk(in database: OpaquePointer) -> Bool {
        let trackedTables = [
            ("PortfolioPlanAssignment", "ZPORTFOLIOPLANASSIGNMENT"),
            ("PortfolioPlanCalendar", "ZPORTFOLIOPLANCALENDAR"),
            ("PortfolioPlanResource", "ZPORTFOLIOPLANRESOURCE"),
            ("PortfolioPlanSprint", "ZPORTFOLIOPLANSPRINT"),
            ("PortfolioPlanTask", "ZPORTFOLIOPLANTASK"),
            ("PortfolioStatusSnapshot", "ZPORTFOLIOSTATUSSNAPSHOT"),
            ("PortfolioTypeWorkflow", "ZPORTFOLIOTYPEWORKFLOW"),
            ("PortfolioWorkflowColumn", "ZPORTFOLIOWORKFLOWCOLUMN")
        ]

        for (entityName, tableName) in trackedTables where tableExists(tableName, in: database) {
            let allocatedMax = scalarIntSQL(
                "SELECT COALESCE(Z_MAX, 0) FROM Z_PRIMARYKEY WHERE Z_NAME = '\(entityName)'",
                in: database
            ) ?? 0
            let currentMax = scalarIntSQL(
                "SELECT COALESCE(MAX(Z_PK), 0) FROM \(tableName)",
                in: database
            ) ?? 0
            if allocatedMax > currentMax + 1_000 {
                return true
            }
        }

        return false
    }

    private static func clearVolatileStoreState(in database: OpaquePointer) {
        let statements: [(sql: String, tables: [String])] = [
            ("DELETE FROM Z_MODELCACHE", ["Z_MODELCACHE"]),
            ("DELETE FROM ACHANGE", ["ACHANGE"]),
            ("DELETE FROM ATRANSACTION", ["ATRANSACTION"]),
            ("DELETE FROM ATRANSACTIONSTRING", ["ATRANSACTIONSTRING"])
        ]

        for statement in statements where statement.tables.allSatisfy({ tableExists($0, in: database) }) {
            _ = executeSQL(statement.sql, in: database)
        }
    }

    private static func tableExists(_ tableName: String, in database: OpaquePointer) -> Bool {
        let escaped = tableName.replacingOccurrences(of: "'", with: "''")
        let statement = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1"
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, statement, -1, &query, nil) == SQLITE_OK, let query else {
            return false
        }
        defer { sqlite3_finalize(query) }
        return sqlite3_step(query) == SQLITE_ROW
    }

    private static func scalarIntSQL(_ statement: String, in database: OpaquePointer) -> Int? {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, statement, -1, &query, nil) == SQLITE_OK, let query else {
            return nil
        }
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(query, 0))
    }

    @discardableResult
    private static func executeSQL(_ statement: String, in database: OpaquePointer) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, statement, nil, nil, &errorMessage)
        if result == SQLITE_OK {
            return true
        }

        let detail = errorMessage.map { String(cString: $0) } ?? sqliteMessage(database)
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        logger.error("Portfolio store repair SQL failed: \(detail)")
        return false
    }

    private static func sqliteMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
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
