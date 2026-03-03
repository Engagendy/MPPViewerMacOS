import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mpp = UTType(importedAs: "com.microsoft.project", conformingTo: .data)
}

struct MPPDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.mpp] }

    let fileURL: URL?
    let fileData: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.fileData = data
        self.fileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
