import AppKit
import UniformTypeIdentifiers

enum CSVExporter {

    @MainActor
    static func exportTasksToCSV(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        resources: [ProjectResource],
        assignments: [ResourceAssignment],
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "ID,WBS,Name,Duration,Start,Finish,% Complete,Cost,Predecessors,Resource Names\n"
        appendRows(tasks: tasks, allTasks: allTasks, resources: resources, assignments: assignments, to: &csv)

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func appendRows(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        resources: [ProjectResource],
        assignments: [ResourceAssignment],
        to csv: inout String
    ) {
        for task in tasks {
            let id = task.id.map(String.init) ?? ""
            let wbs = task.wbs ?? ""
            let name = task.displayName
            let duration = task.durationDisplay
            let start = DateFormatting.shortDate(task.start)
            let finish = DateFormatting.shortDate(task.finish)
            let pctComplete = task.percentComplete.map { "\(Int($0))" } ?? ""
            let cost = task.cost.map { String(format: "%.2f", $0) } ?? ""

            let predText: String = {
                guard let preds = task.predecessors, !preds.isEmpty else { return "" }
                return preds.compactMap { rel -> String? in
                    guard let predTask = allTasks[rel.targetTaskUniqueID] else { return nil }
                    let taskID = predTask.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
                    let suffix = rel.type == "FS" ? "" : (rel.type ?? "")
                    return taskID + suffix
                }.joined(separator: "; ")
            }()

            let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
            let resourceNames = taskAssignments.compactMap { a in
                resources.first(where: { $0.uniqueID == a.resourceUniqueID })?.name
            }.joined(separator: "; ")

            let row = [id, wbs, name, duration, start, finish, pctComplete, cost, predText, resourceNames]
                .map { escapeCSV($0) }
                .joined(separator: ",")
            csv += row + "\n"

            if !task.children.isEmpty {
                appendRows(tasks: task.children, allTasks: allTasks, resources: resources, assignments: assignments, to: &csv)
            }
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
