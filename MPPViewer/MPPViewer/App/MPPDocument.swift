import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mpp = UTType(importedAs: "com.microsoft.project", conformingTo: .data)
    static let mppplan = UTType(exportedAs: "com.mppviewer.plan", conformingTo: .json)
}

struct PlanningDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mppplan, .mpp] }
    static var writableContentTypes: [UTType] { [.mppplan] }

    var editablePortfolioID: UUID?
    var editablePlanData: Data?
    var editablePlanSeed: NativeProjectPlan?
    let importedMPPData: Data?
    let fileURL: URL?

    init() {
        let emptyPlan = NativeProjectPlan.empty()
        editablePortfolioID = emptyPlan.portfolioID
        editablePlanData = try? emptyPlan.encodedData()
        editablePlanSeed = emptyPlan
        importedMPPData = nil
        fileURL = nil
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents
            ?? configuration.file.serializedRepresentation

        guard let data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.fileURL = nil
        let nativePlan = try PlanningDocument.decodeNativePlanIfPossible(from: data)

        if let nativePlan {
            editablePortfolioID = nativePlan.portfolioID
            editablePlanData = data
            editablePlanSeed = nativePlan
            importedMPPData = nil
        } else {
            editablePortfolioID = nil
            editablePlanData = nil
            editablePlanSeed = nil
            importedMPPData = data
        }
    }

    private static func decodeNativePlanIfPossible(from data: Data) throws -> NativeProjectPlan? {
        guard !data.isEmpty else { return nil }
        let trimmed = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
        do {
            return try NativeProjectPlan.decode(from: Data(trimmed))
        } catch let error as NativePlanFormatError {
            // A plan from a newer app version must fail loudly, not fall through
            // to the binary .mpp import path with a confusing converter error.
            throw error
        } catch {
            return nil
        }
    }

    var isEditablePlan: Bool {
        editablePortfolioID != nil
    }

    var projectModel: ProjectModel? {
        nativePlan?.asProjectModel()
    }

    var nativePlan: NativeProjectPlan? {
        get {
            // The seed is kept in sync by the setter and nilled by callers
            // that write raw data directly, so prefer it and avoid a full
            // JSON decode on every access.
            if let editablePlanSeed {
                return editablePlanSeed
            }
            if let editablePlanData,
               let decoded = try? NativeProjectPlan.decode(from: editablePlanData) {
                return decoded
            }
            return nil
        }
        set {
            editablePortfolioID = newValue?.portfolioID
            editablePlanSeed = newValue
            editablePlanData = try? newValue?.encodedData()
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let editablePlanData else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return .init(regularFileWithContents: editablePlanData)
    }
}
