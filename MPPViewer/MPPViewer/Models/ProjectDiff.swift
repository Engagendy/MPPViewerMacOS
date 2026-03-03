import Foundation

enum DiffChangeType: String {
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}

struct FieldChange: Identifiable {
    let id = UUID()
    let field: String
    let oldValue: String
    let newValue: String
}

struct TaskDiff: Identifiable {
    let id: Int
    let changeType: DiffChangeType
    let taskName: String
    let changes: [FieldChange]
}

enum ProjectDiffCalculator {

    static func diff(baseline: ProjectModel, current: ProjectModel) -> [TaskDiff] {
        let baselineByUID = Dictionary(uniqueKeysWithValues: baseline.tasks.map { ($0.uniqueID, $0) })
        let currentByUID = Dictionary(uniqueKeysWithValues: current.tasks.map { ($0.uniqueID, $0) })

        var diffs: [TaskDiff] = []

        // Added tasks (in current but not in baseline)
        for task in current.tasks {
            if baselineByUID[task.uniqueID] == nil {
                diffs.append(TaskDiff(
                    id: task.uniqueID,
                    changeType: .added,
                    taskName: task.displayName,
                    changes: []
                ))
            }
        }

        // Removed tasks (in baseline but not in current)
        for task in baseline.tasks {
            if currentByUID[task.uniqueID] == nil {
                diffs.append(TaskDiff(
                    id: task.uniqueID,
                    changeType: .removed,
                    taskName: task.displayName,
                    changes: []
                ))
            }
        }

        // Modified tasks
        for task in current.tasks {
            guard let baseTask = baselineByUID[task.uniqueID] else { continue }
            var changes: [FieldChange] = []

            if task.name != baseTask.name {
                changes.append(FieldChange(field: "Name", oldValue: baseTask.name ?? "", newValue: task.name ?? ""))
            }
            if task.start != baseTask.start {
                changes.append(FieldChange(field: "Start", oldValue: DateFormatting.shortDate(baseTask.start), newValue: DateFormatting.shortDate(task.start)))
            }
            if task.finish != baseTask.finish {
                changes.append(FieldChange(field: "Finish", oldValue: DateFormatting.shortDate(baseTask.finish), newValue: DateFormatting.shortDate(task.finish)))
            }
            if task.duration != baseTask.duration {
                changes.append(FieldChange(field: "Duration", oldValue: baseTask.durationDisplay, newValue: task.durationDisplay))
            }
            if task.percentComplete != baseTask.percentComplete {
                changes.append(FieldChange(field: "% Complete", oldValue: baseTask.percentCompleteDisplay, newValue: task.percentCompleteDisplay))
            }
            if task.cost != baseTask.cost {
                let fmt: (Double?) -> String = { v in v.map { String(format: "%.2f", $0) } ?? "" }
                changes.append(FieldChange(field: "Cost", oldValue: fmt(baseTask.cost), newValue: fmt(task.cost)))
            }

            if !changes.isEmpty {
                diffs.append(TaskDiff(
                    id: task.uniqueID,
                    changeType: .modified,
                    taskName: task.displayName,
                    changes: changes
                ))
            }
        }

        return diffs.sorted { $0.id < $1.id }
    }
}
