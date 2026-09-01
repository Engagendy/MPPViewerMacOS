import Foundation
import AppKit
import SwiftUI

/// iCloud Drive support for .mppplan documents.
///
/// Everything here is capability-gated: it only activates when the app is
/// signed with the iCloud Documents entitlement
/// (`com.apple.developer.icloud-container-identifiers` +
/// `com.apple.developer.ubiquity-container-identifiers`). The Info.plist
/// already declares `NSUbiquitousContainers` for
/// `iCloud.com.mppviewer.MPPViewer`, so once the capability is enabled the
/// app's Documents folder appears in iCloud Drive automatically.
///
/// ENABLING THE CAPABILITY (one-step toggle, requires a provisioning profile
/// with iCloud): in Xcode, select the MPPViewer target > Signing &
/// Capabilities > "+ Capability" > iCloud > check "iCloud Documents" and add
/// the container `iCloud.com.mppviewer.MPPViewer`. Xcode registers the
/// container with the developer account and regenerates the profile. No code
/// changes are needed — `CloudDocuments.isAvailable` flips to true at runtime.
enum CloudDocuments {
    /// The default ubiquity container (`nil` resolves the first identifier in
    /// the entitlement; ours is `iCloud.com.mppviewer.MPPViewer`).
    static let containerIdentifier: String? = nil

    /// True when the app has the iCloud entitlement AND the user is signed
    /// into iCloud. `ubiquityIdentityToken` is cheap and safe to call from
    /// the main thread, unlike `url(forUbiquityContainerIdentifier:)`.
    static var isSignedIntoICloud: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Resolves the container's Documents directory, creating it on first
    /// use. Must be called off the main thread (the first call can block
    /// while the container is provisioned). Returns nil when the entitlement
    /// is absent or the user is signed out of iCloud.
    static func documentsDirectory() -> URL? {
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) else { return nil }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: documents.path) {
            try? FileManager.default.createDirectory(
                at: documents, withIntermediateDirectories: true
            )
        }
        return documents
    }

    /// True when `url` already lives in iCloud (any ubiquitous location,
    /// including the shared iCloud Drive tree).
    static func isUbiquitous(_ url: URL) -> Bool {
        FileManager.default.isUbiquitousItem(at: url)
    }

    /// Moves a saved document into the app's iCloud Drive folder. Runs the
    /// blocking `setUbiquitous` call on a utility queue and reports back on
    /// the main queue. If a file with the same name already exists in the
    /// container a numbered suffix is appended, matching Finder behavior.
    static func moveToICloud(
        fileAt sourceURL: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                guard let documents = documentsDirectory() else {
                    throw CloudDocumentsError.containerUnavailable
                }
                let destination = availableDestination(
                    for: sourceURL.lastPathComponent, in: documents
                )
                try FileManager.default.setUbiquitous(
                    true, itemAt: sourceURL, destinationURL: destination
                )
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// First non-colliding URL for `filename` inside `directory`
    /// ("Plan.mppplan", "Plan 2.mppplan", ...).
    private static func availableDestination(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
}

enum CloudDocumentsError: LocalizedError {
    case containerUnavailable
    case documentNotSaved

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return String(localized: "iCloud Drive is not available. Sign in to iCloud and enable iCloud Drive in System Settings, or check that Planroom has iCloud enabled.")
        case .documentNotSaved:
            return String(localized: "Save the document before moving it to iCloud Drive.")
        }
    }
}

/// File > Move to iCloud Drive. Uses the AppKit document backing SwiftUI's
/// DocumentGroup so we can save first and let NSDocument's file coordination
/// track the move.
struct CloudDocumentCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button(String(localized: "Move to iCloud Drive")) {
                Self.moveFrontDocumentToICloud()
            }
            .disabled(!CloudDocuments.isSignedIntoICloud)
        }
    }

    /// The NSDocument behind the frontmost document window, if any.
    private static var frontDocument: NSDocument? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController?.document as? NSDocument
            ?? NSDocumentController.shared.currentDocument
    }

    static func moveFrontDocumentToICloud() {
        guard let document = frontDocument else { return }
        guard let fileURL = document.fileURL else {
            presentError(CloudDocumentsError.documentNotSaved)
            return
        }
        guard !CloudDocuments.isUbiquitous(fileURL) else { return }
        // Flush edits so the moved file is current.
        document.save(nil)
        CloudDocuments.moveToICloud(fileAt: fileURL) { result in
            switch result {
            case .success(let destination):
                // Keep NSDocument pointed at the new location; file
                // coordination usually handles this, but be explicit.
                document.fileURL = destination
            case .failure(let error):
                presentError(error)
            }
        }
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn't Move to iCloud Drive")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
