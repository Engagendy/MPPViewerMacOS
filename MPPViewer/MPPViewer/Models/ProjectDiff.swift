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
    let finishDeltaDays: Int?
    let costDelta: Double?
    let criticalityDelta: CriticalityDelta
}

struct TaskDiffImpact {
    let taskName: String
    let deltaDays: Int
}

enum CriticalityDelta {
    case none
    case entered
    case exited
}

struct ProjectDiffSummary {
    let projectFinishDeltaDays: Int?
    let finishMovedLaterCount: Int
    let finishMovedEarlierCount: Int
    let largestFinishSlip: TaskDiffImpact?
    let totalCostDelta: Double
    let changedCostTaskCount: Int
    let criticalAddedCount: Int
    let criticalRemovedCount: Int
    let currentCriticalCount: Int
    let enteredCriticalTasks: [String]
    let exitedCriticalTasks: [String]
}

struct ProjectDiffAnalysis {
    let diffs: [TaskDiff]
    let summary: ProjectDiffSummary
}

enum ProjectDiffCalculator {

    static func diff(baseline: ProjectModel, current: ProjectModel) -> [TaskDiff] {
        analyze(baseline: baseline, current: current).diffs
    }

    static func analyze(baseline: ProjectModel, current: ProjectModel) -> ProjectDiffAnalysis {
        let baselineByUID = Dictionary(nonThrowingUniquePairs: baseline.tasks.map { ($0.uniqueID, $0) })
        let currentByUID = Dictionary(nonThrowingUniquePairs: current.tasks.map { ($0.uniqueID, $0) })

        var diffs: [TaskDiff] = []
        var finishMovedLaterCount = 0
        var finishMovedEarlierCount = 0
        var largestFinishSlip: TaskDiffImpact?
        var changedCostTaskCount = 0

        // Added tasks (in current but not in baseline)
        for task in current.tasks {
            if baselineByUID[task.uniqueID] == nil {
                diffs.append(TaskDiff(
                    id: task.uniqueID,
                    changeType: .added,
                    taskName: task.displayName,
                    changes: [],
                    finishDeltaDays: nil,
                    costDelta: task.cost,
                    criticalityDelta: task.critical == true ? .entered : .none
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
                    changes: [],
                    finishDeltaDays: nil,
                    costDelta: task.cost.map { -$0 },
                    criticalityDelta: task.critical == true ? .exited : .none
                ))
            }
        }

        // Modified tasks
        for task in current.tasks {
            guard let baseTask = baselineByUID[task.uniqueID] else { continue }
            var changes: [FieldChange] = []
            let finishDeltaDays: Int? = {
                guard let baseFinish = baseTask.finishDate, let currentFinish = task.finishDate else { return nil }
                let deltaDays = Calendar.current.dateComponents([.day], from: baseFinish, to: currentFinish).day ?? 0
                return deltaDays == 0 ? nil : deltaDays
            }()
            let costDelta: Double? = {
                guard task.cost != baseTask.cost else { return nil }
                return (task.cost ?? 0) - (baseTask.cost ?? 0)
            }()
            let criticalityDelta: CriticalityDelta = {
                let wasCritical = baseTask.critical == true
                let isCritical = task.critical == true
                if !wasCritical && isCritical { return .entered }
                if wasCritical && !isCritical { return .exited }
                return .none
            }()

            if task.name != baseTask.name {
                changes.append(FieldChange(field: "Name", oldValue: baseTask.name ?? "", newValue: task.name ?? ""))
            }
            if task.start != baseTask.start {
                changes.append(FieldChange(field: "Start", oldValue: DateFormatting.shortDate(baseTask.start), newValue: DateFormatting.shortDate(task.start)))
            }
            if task.finish != baseTask.finish {
                changes.append(FieldChange(field: "Finish", oldValue: DateFormatting.shortDate(baseTask.finish), newValue: DateFormatting.shortDate(task.finish)))
                if let deltaDays = finishDeltaDays {
                    if deltaDays > 0 {
                        finishMovedLaterCount += 1
                        if largestFinishSlip == nil || deltaDays > largestFinishSlip!.deltaDays {
                            largestFinishSlip = TaskDiffImpact(taskName: task.displayName, deltaDays: deltaDays)
                        }
                    } else {
                        finishMovedEarlierCount += 1
                    }
                }
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
                changedCostTaskCount += 1
            }
            if criticalityDelta == .entered {
                changes.append(FieldChange(field: "Critical", oldValue: "No", newValue: "Yes"))
            } else if criticalityDelta == .exited {
                changes.append(FieldChange(field: "Critical", oldValue: "Yes", newValue: "No"))
            }

            if !changes.isEmpty {
                diffs.append(TaskDiff(
                    id: task.uniqueID,
                    changeType: .modified,
                    taskName: task.displayName,
                    changes: changes,
                    finishDeltaDays: finishDeltaDays,
                    costDelta: costDelta,
                    criticalityDelta: criticalityDelta
                ))
            }
        }

        let baselineCritical = Dictionary(nonThrowingUniquePairs: baseline.tasks.compactMap { task -> (Int, ProjectTask)? in
            guard task.critical == true else { return nil }
            return (task.uniqueID, task)
        })
        let currentCritical = Dictionary(nonThrowingUniquePairs: current.tasks.compactMap { task -> (Int, ProjectTask)? in
            guard task.critical == true else { return nil }
            return (task.uniqueID, task)
        })
        let enteredCriticalIDs = Set(currentCritical.keys).subtracting(baselineCritical.keys)
        let exitedCriticalIDs = Set(baselineCritical.keys).subtracting(currentCritical.keys)

        let summary = ProjectDiffSummary(
            projectFinishDeltaDays: projectFinishDeltaDays(baseline: baseline, current: current),
            finishMovedLaterCount: finishMovedLaterCount,
            finishMovedEarlierCount: finishMovedEarlierCount,
            largestFinishSlip: largestFinishSlip,
            totalCostDelta: totalCost(for: current) - totalCost(for: baseline),
            changedCostTaskCount: changedCostTaskCount,
            criticalAddedCount: enteredCriticalIDs.count,
            criticalRemovedCount: exitedCriticalIDs.count,
            currentCriticalCount: currentCritical.count,
            enteredCriticalTasks: enteredCriticalIDs.compactMap { currentCritical[$0]?.displayName }.sorted(),
            exitedCriticalTasks: exitedCriticalIDs.compactMap { baselineCritical[$0]?.displayName }.sorted()
        )

        return ProjectDiffAnalysis(
            diffs: diffs.sorted { $0.id < $1.id },
            summary: summary
        )
    }

    private static func totalCost(for project: ProjectModel) -> Double {
        project.tasks.compactMap(\.cost).reduce(0, +)
    }

    private static func projectFinishDeltaDays(baseline: ProjectModel, current: ProjectModel) -> Int? {
        let baselineFinish = projectFinishDate(for: baseline)
        let currentFinish = projectFinishDate(for: current)
        guard let baselineFinish, let currentFinish else { return nil }
        return Calendar.current.dateComponents([.day], from: baselineFinish, to: currentFinish).day
    }

    private static func projectFinishDate(for project: ProjectModel) -> Date? {
        if let finish = project.properties.finishDate, let parsed = DateFormatting.parseMPXJDate(finish) {
            return parsed
        }
        return project.tasks.compactMap(\.finishDate).max()
    }
}
