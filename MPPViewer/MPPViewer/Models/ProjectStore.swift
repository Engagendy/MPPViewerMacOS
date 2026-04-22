import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published var project: ProjectModel?
    @Published var isLoading = false
    @Published var error: String?

    private let converter = MPPConverterService()
    private let parser = JSONProjectParser()

    func loadFromDocument(_ document: PlanningDocument) async {
        guard let importedMPPData = document.importedMPPData else {
            project = nil
            error = nil
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            // Write document data to a temp file since we receive raw data
            let tempInput = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mpp")
            try importedMPPData.write(to: tempInput)
            defer { try? FileManager.default.removeItem(at: tempInput) }

            let jsonData = try await converter.convert(mppFileURL: tempInput)
            let model = try parser.parse(jsonData: jsonData)
            self.project = model
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func reset() {
        project = nil
        isLoading = false
        error = nil
    }

    func loadProject(from url: URL) async throws -> ProjectModel {
        let jsonData = try await converter.convert(mppFileURL: url)
        return try parser.parse(jsonData: jsonData)
    }

    func loadFromURL(_ url: URL) async {
        isLoading = true
        error = nil

        do {
            let jsonData = try await converter.convert(mppFileURL: url)
            let model = try parser.parse(jsonData: jsonData)
            self.project = model
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
