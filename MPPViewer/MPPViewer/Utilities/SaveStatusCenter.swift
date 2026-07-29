import Foundation
import SwiftData
import SwiftUI
import OSLog

/// Central reporter for persistence failures so saves never fail silently.
@MainActor
final class SaveStatusCenter: ObservableObject {
    static let shared = SaveStatusCenter()

    private static let logger = Logger(subsystem: "com.mppviewer", category: "Persistence")

    @Published var failureMessage: String?
    @Published var isShowingFailure = false

    func reportFailure(_ error: Error, operation: String) {
        Self.logger.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        failureMessage = "\(operation) failed: \(error.localizedDescription)\n\nYour latest changes may not be stored. Try again, and if the problem persists restart the app before continuing to edit."
        isShowingFailure = true
    }
}

extension ModelContext {
    /// Saves the context and routes any failure to `SaveStatusCenter` instead of dropping it.
    @MainActor
    func saveReportingFailures(operation: String = "Saving changes") {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            SaveStatusCenter.shared.reportFailure(error, operation: operation)
        }
    }
}

/// Attaches a user-visible alert for persistence failures.
struct SaveFailureAlertModifier: ViewModifier {
    @ObservedObject private var center = SaveStatusCenter.shared

    func body(content: Content) -> some View {
        content.alert("Save Failed", isPresented: $center.isShowingFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(center.failureMessage ?? "Your latest changes could not be stored.")
        }
    }
}

extension View {
    func saveFailureAlerts() -> some View {
        modifier(SaveFailureAlertModifier())
    }
}
