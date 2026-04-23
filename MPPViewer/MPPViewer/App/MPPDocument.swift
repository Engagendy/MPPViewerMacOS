import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mpp = UTType(importedAs: "com.microsoft.project", conformingTo: .data)
    static let mppplan = UTType(exportedAs: "com.mppviewer.plan", conformingTo: .json)
}

struct PlanningDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mppplan, .mpp] }
    static var writableContentTypes: [UTType] { [.mppplan] }

    var nativePlan: NativeProjectPlan?
    let importedMPPData: Data?
    let fileURL: URL?

    init() {
        nativePlan = .empty()
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

        if configuration.contentType == .mppplan {
            nativePlan = try NativeProjectPlan.decode(from: data)
            importedMPPData = nil
        } else {
            nativePlan = nil
            importedMPPData = data
        }
    }

    var isEditablePlan: Bool {
        nativePlan != nil
    }

    var projectModel: ProjectModel? {
        nativePlan?.asProjectModel()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let nativePlan else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return .init(regularFileWithContents: try nativePlan.encodedData())
    }
}
