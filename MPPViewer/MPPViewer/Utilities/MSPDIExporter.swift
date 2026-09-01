import Foundation
import AppKit
import UniformTypeIdentifiers

/// Exports a native plan to MSPDI (Microsoft Project XML) via the bundled
/// MPXJ converter. The plan is serialized to a small interchange JSON payload
/// that the Java side maps onto an MPXJ ProjectFile.
enum MSPDIExporter {

    private struct InterchangeTask: Encodable {
        let id: Int
        let name: String
        let outlineLevel: Int
        let start: String
        let finish: String
        let durationDays: Int
        let milestone: Bool
        let percentComplete: Double
        let notes: String
        let cost: Double
        let predecessorIDs: [Int]
        let baselineStart: String?
        let baselineFinish: String?
        let actualStart: String?
        let actualFinish: String?
        let constraintType: String?
        let constraintDate: String?
    }

    private struct InterchangeResource: Encodable {
        let id: Int
        let name: String
        let email: String
        let group: String
        let initials: String
    }

    private struct InterchangeAssignment: Encodable {
        let taskID: Int
        let resourceID: Int?
        let units: Double
    }

    private struct InterchangePlan: Encodable {
        let title: String
        let manager: String
        let company: String
        let statusDate: String
        let tasks: [InterchangeTask]
        let resources: [InterchangeResource]
        let assignments: [InterchangeAssignment]
    }

    static func interchangeJSON(for plan: NativeProjectPlan) throws -> Data {
        func dateString(_ date: Date?) -> String? {
            date.map(DateFormatting.simpleDate)
        }

        let payload = InterchangePlan(
            title: plan.title,
            manager: plan.manager,
            company: plan.company,
            statusDate: DateFormatting.simpleDate(plan.statusDate),
            tasks: plan.tasks.map { task in
                InterchangeTask(
                    id: task.id,
                    name: task.name,
                    outlineLevel: max(1, task.outlineLevel),
                    start: DateFormatting.simpleDate(task.startDate),
                    finish: DateFormatting.simpleDate(task.finishDate),
                    durationDays: max(1, task.durationDays),
                    milestone: task.isMilestone,
                    percentComplete: task.percentComplete,
                    notes: task.notes,
                    cost: task.fixedCost,
                    predecessorIDs: task.predecessorTaskIDs,
                    baselineStart: dateString(task.baselineStartDate),
                    baselineFinish: dateString(task.baselineFinishDate),
                    actualStart: dateString(task.actualStartDate),
                    actualFinish: dateString(task.actualFinishDate),
                    constraintType: task.constraintType,
                    constraintDate: dateString(task.constraintDate)
                )
            },
            resources: plan.resources.map { resource in
                InterchangeResource(
                    id: resource.id,
                    name: resource.name,
                    email: resource.emailAddress,
                    group: resource.group,
                    initials: resource.initials
                )
            },
            assignments: plan.assignments.map { assignment in
                InterchangeAssignment(
                    taskID: assignment.taskID,
                    resourceID: assignment.resourceID,
                    units: assignment.units
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    @MainActor
    static func exportWithSavePanel(plan: NativeProjectPlan) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export MS Project XML")
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(plan.title).xml"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task { @MainActor in
            do {
                let payload = try interchangeJSON(for: plan)
                let xmlData = try await MPPConverterService().exportMSPDI(planJSON: payload)
                try xmlData.write(to: destination, options: .atomic)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Export Failed")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
