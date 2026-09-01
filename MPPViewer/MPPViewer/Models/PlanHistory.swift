import Foundation

// MARK: - History models stored inside the .mppplan file

enum PlanHistoryEntityKind: String, Codable, Hashable {
    case plan = "Plan"
    case task = "Task"
    case resource = "Resource"
    case assignment = "Assignment"
    case dependency = "Dependency"
}

enum PlanHistoryChangeKind: String, Codable, Hashable {
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}

/// One recorded field-level change on a plan entity.
struct PlanHistoryFieldChange: Codable, Hashable, Identifiable {
    var id: UUID
    var field: String
    var oldValue: String
    var newValue: String

    init(id: UUID = UUID(), field: String, oldValue: String, newValue: String) {
        self.id = id
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

/// One added/removed/modified entity inside a saved change-log entry.
struct PlanHistoryItemChange: Codable, Hashable, Identifiable {
    var id: UUID
    var entity: PlanHistoryEntityKind
    var changeKind: PlanHistoryChangeKind
    var name: String
    var fieldChanges: [PlanHistoryFieldChange]

    init(
        id: UUID = UUID(),
        entity: PlanHistoryEntityKind,
        changeKind: PlanHistoryChangeKind,
        name: String,
        fieldChanges: [PlanHistoryFieldChange] = []
    ) {
        self.id = id
        self.entity = entity
        self.changeKind = changeKind
        self.name = name
        self.fieldChanges = fieldChanges
    }
}

/// One compact change-log entry appended each time the plan file is saved
/// with content changes versus the previously saved state.
struct PlanHistoryEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var timestamp: Date
    var summary: String
    var changes: [PlanHistoryItemChange]

    init(id: UUID = UUID(), timestamp: Date, summary: String, changes: [PlanHistoryItemChange]) {
        self.id = id
        self.timestamp = timestamp
        self.summary = summary
        self.changes = changes
    }
}

// MARK: - Builder

/// Computes the compact change log written into `NativeProjectPlan.changeHistory`
/// on save. Task-level date/duration/%/cost/criticality changes come from the
/// existing `ProjectDiffCalculator` engine; resource, dependency, and assignment
/// changes are diffed directly on the native plan models.
enum PlanHistoryBuilder {
    /// Bounded history so the .mppplan file size stays sane.
    static let maxEntries = 200
    /// Cap per-entry detail so one giant paste/import doesn't bloat the file.
    static let maxChangesPerEntry = 400

    /// True when the two plans have identical content ignoring the history itself.
    /// Compared through the file encoding so that an in-memory plan and its
    /// decoded round-trip (e.g. sub-second date truncation) read as equal.
    static func contentEqual(_ lhs: NativeProjectPlan, _ rhs: NativeProjectPlan) -> Bool {
        var normalizedLHS = lhs
        var normalizedRHS = rhs
        normalizedLHS.changeHistory = []
        normalizedRHS.changeHistory = []
        guard let lhsData = try? normalizedLHS.encodedData(),
              let rhsData = try? normalizedRHS.encodedData() else {
            return normalizedLHS == normalizedRHS
        }
        return lhsData == rhsData
    }

    /// Appends `entry` and enforces the entry cap (oldest entries drop first).
    static func capped(_ history: [PlanHistoryEntry]) -> [PlanHistoryEntry] {
        history.count > maxEntries ? Array(history.suffix(maxEntries)) : history
    }

    /// Builds a change-log entry for `previous` -> `current`, or nil when nothing
    /// content-relevant changed.
    static func entry(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan,
        timestamp: Date = Date()
    ) -> PlanHistoryEntry? {
        guard !contentEqual(previous, current) else { return nil }

        var changes: [PlanHistoryItemChange] = []
        changes += planFieldChanges(from: previous, to: current)
        changes += taskChanges(from: previous, to: current)
        changes += resourceChanges(from: previous, to: current)
        changes += dependencyChanges(from: previous, to: current)
        changes += assignmentChanges(from: previous, to: current)

        if changes.isEmpty {
            // Something changed (board columns, sprints, calendars, ...) that the
            // compact diff doesn't itemize; still record that a save happened.
            changes.append(PlanHistoryItemChange(
                entity: .plan,
                changeKind: .modified,
                name: "Plan settings"
            ))
        }
        if changes.count > maxChangesPerEntry {
            let overflow = changes.count - maxChangesPerEntry
            changes = Array(changes.prefix(maxChangesPerEntry))
            changes.append(PlanHistoryItemChange(
                entity: .plan,
                changeKind: .modified,
                name: "\(overflow) more changes not itemized"
            ))
        }

        return PlanHistoryEntry(
            timestamp: timestamp,
            summary: summaryText(for: changes),
            changes: changes
        )
    }

    // MARK: Plan-level fields

    private static func planFieldChanges(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan
    ) -> [PlanHistoryItemChange] {
        var fieldChanges: [PlanHistoryFieldChange] = []
        if previous.title != current.title {
            fieldChanges.append(PlanHistoryFieldChange(field: "Title", oldValue: previous.title, newValue: current.title))
        }
        if previous.manager != current.manager {
            fieldChanges.append(PlanHistoryFieldChange(field: "Manager", oldValue: previous.manager, newValue: current.manager))
        }
        if previous.company != current.company {
            fieldChanges.append(PlanHistoryFieldChange(field: "Company", oldValue: previous.company, newValue: current.company))
        }
        let previousStatusDate = DateFormatting.simpleDate(previous.statusDate)
        let currentStatusDate = DateFormatting.simpleDate(current.statusDate)
        if previousStatusDate != currentStatusDate {
            fieldChanges.append(PlanHistoryFieldChange(
                field: "Status Date",
                oldValue: previousStatusDate,
                newValue: currentStatusDate
            ))
        }
        guard !fieldChanges.isEmpty else { return [] }
        return [PlanHistoryItemChange(
            entity: .plan,
            changeKind: .modified,
            name: current.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Plan" : current.title,
            fieldChanges: fieldChanges
        )]
    }

    // MARK: Tasks (existing diff engine)

    private static func taskChanges(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan
    ) -> [PlanHistoryItemChange] {
        let analysis = ProjectDiffCalculator.analyze(
            baseline: previous.asProjectModel(),
            current: current.asProjectModel()
        )
        return analysis.diffs.map { diff in
            PlanHistoryItemChange(
                entity: .task,
                changeKind: changeKind(for: diff.changeType),
                name: diff.taskName,
                fieldChanges: diff.changes.map { change in
                    PlanHistoryFieldChange(field: change.field, oldValue: change.oldValue, newValue: change.newValue)
                }
            )
        }
    }

    private static func changeKind(for diffType: DiffChangeType) -> PlanHistoryChangeKind {
        switch diffType {
        case .added: return .added
        case .removed: return .removed
        case .modified: return .modified
        }
    }

    // MARK: Resources

    private static func resourceChanges(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan
    ) -> [PlanHistoryItemChange] {
        let previousByID = Dictionary(nonThrowingUniquePairs: previous.resources.map { ($0.id, $0) })
        let currentByID = Dictionary(nonThrowingUniquePairs: current.resources.map { ($0.id, $0) })
        var changes: [PlanHistoryItemChange] = []

        for resource in current.resources where previousByID[resource.id] == nil {
            changes.append(PlanHistoryItemChange(entity: .resource, changeKind: .added, name: resource.name))
        }
        for resource in previous.resources where currentByID[resource.id] == nil {
            changes.append(PlanHistoryItemChange(entity: .resource, changeKind: .removed, name: resource.name))
        }

        for resource in current.resources {
            guard let baseResource = previousByID[resource.id] else { continue }
            var fieldChanges: [PlanHistoryFieldChange] = []
            if resource.name != baseResource.name {
                fieldChanges.append(PlanHistoryFieldChange(field: "Name", oldValue: baseResource.name, newValue: resource.name))
            }
            if resource.maxUnits != baseResource.maxUnits {
                fieldChanges.append(PlanHistoryFieldChange(
                    field: "Max Units",
                    oldValue: formattedPercent(baseResource.maxUnits),
                    newValue: formattedPercent(resource.maxUnits)
                ))
            }
            if resource.standardRate != baseResource.standardRate {
                fieldChanges.append(PlanHistoryFieldChange(
                    field: "Standard Rate",
                    oldValue: formattedCurrency(baseResource.standardRate),
                    newValue: formattedCurrency(resource.standardRate)
                ))
            }
            if resource.overtimeRate != baseResource.overtimeRate {
                fieldChanges.append(PlanHistoryFieldChange(
                    field: "Overtime Rate",
                    oldValue: formattedCurrency(baseResource.overtimeRate),
                    newValue: formattedCurrency(resource.overtimeRate)
                ))
            }
            if resource.active != baseResource.active {
                fieldChanges.append(PlanHistoryFieldChange(
                    field: "Active",
                    oldValue: baseResource.active ? "Yes" : "No",
                    newValue: resource.active ? "Yes" : "No"
                ))
            }
            if !fieldChanges.isEmpty {
                changes.append(PlanHistoryItemChange(
                    entity: .resource,
                    changeKind: .modified,
                    name: resource.name,
                    fieldChanges: fieldChanges
                ))
            }
        }
        return changes
    }

    // MARK: Dependencies

    private static func dependencyChanges(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan
    ) -> [PlanHistoryItemChange] {
        let previousByID = Dictionary(nonThrowingUniquePairs: previous.tasks.map { ($0.id, $0) })
        let currentByID = Dictionary(nonThrowingUniquePairs: current.tasks.map { ($0.id, $0) })
        var changes: [PlanHistoryItemChange] = []

        for task in current.tasks {
            guard let baseTask = previousByID[task.id] else { continue }
            let previousPredecessors = Set(baseTask.predecessorTaskIDs)
            let currentPredecessors = Set(task.predecessorTaskIDs)
            for predecessorID in currentPredecessors.subtracting(previousPredecessors).sorted() {
                changes.append(PlanHistoryItemChange(
                    entity: .dependency,
                    changeKind: .added,
                    name: "\(taskName(predecessorID, in: currentByID, or: previousByID)) → \(task.name)"
                ))
            }
            for predecessorID in previousPredecessors.subtracting(currentPredecessors).sorted() {
                changes.append(PlanHistoryItemChange(
                    entity: .dependency,
                    changeKind: .removed,
                    name: "\(taskName(predecessorID, in: previousByID, or: currentByID)) → \(task.name)"
                ))
            }
        }
        return changes
    }

    private static func taskName(
        _ taskID: Int,
        in primary: [Int: NativePlanTask],
        or secondary: [Int: NativePlanTask]
    ) -> String {
        primary[taskID]?.name ?? secondary[taskID]?.name ?? "Task #\(taskID)"
    }

    // MARK: Assignments

    private static func assignmentChanges(
        from previous: NativeProjectPlan,
        to current: NativeProjectPlan
    ) -> [PlanHistoryItemChange] {
        let previousTasksByID = Dictionary(nonThrowingUniquePairs: previous.tasks.map { ($0.id, $0) })
        let currentTasksByID = Dictionary(nonThrowingUniquePairs: current.tasks.map { ($0.id, $0) })
        let previousResourcesByID = Dictionary(nonThrowingUniquePairs: previous.resources.map { ($0.id, $0) })
        let currentResourcesByID = Dictionary(nonThrowingUniquePairs: current.resources.map { ($0.id, $0) })

        func assignmentKey(_ assignment: NativePlanAssignment) -> String {
            "\(assignment.taskID)|\(assignment.resourceID.map(String.init) ?? "-")"
        }
        func assignmentName(_ assignment: NativePlanAssignment) -> String {
            let resourceName = assignment.resourceID.flatMap {
                currentResourcesByID[$0]?.name ?? previousResourcesByID[$0]?.name
            } ?? "Unassigned"
            let name = currentTasksByID[assignment.taskID]?.name
                ?? previousTasksByID[assignment.taskID]?.name
                ?? "Task #\(assignment.taskID)"
            return "\(resourceName) → \(name)"
        }

        let previousByKey = Dictionary(nonThrowingUniquePairs: previous.assignments.map { (assignmentKey($0), $0) })
        let currentByKey = Dictionary(nonThrowingUniquePairs: current.assignments.map { (assignmentKey($0), $0) })
        var changes: [PlanHistoryItemChange] = []

        for assignment in current.assignments where previousByKey[assignmentKey(assignment)] == nil {
            changes.append(PlanHistoryItemChange(entity: .assignment, changeKind: .added, name: assignmentName(assignment)))
        }
        for assignment in previous.assignments where currentByKey[assignmentKey(assignment)] == nil {
            changes.append(PlanHistoryItemChange(entity: .assignment, changeKind: .removed, name: assignmentName(assignment)))
        }
        for assignment in current.assignments {
            guard let baseAssignment = previousByKey[assignmentKey(assignment)],
                  baseAssignment.units != assignment.units else { continue }
            changes.append(PlanHistoryItemChange(
                entity: .assignment,
                changeKind: .modified,
                name: assignmentName(assignment),
                fieldChanges: [PlanHistoryFieldChange(
                    field: "Units",
                    oldValue: formattedPercent(baseAssignment.units),
                    newValue: formattedPercent(assignment.units)
                )]
            ))
        }
        return changes
    }

    // MARK: Summary

    private static func summaryText(for changes: [PlanHistoryItemChange]) -> String {
        var parts: [String] = []
        for entity in [PlanHistoryEntityKind.task, .resource, .dependency, .assignment, .plan] {
            let entityChanges = changes.filter { $0.entity == entity }
            guard !entityChanges.isEmpty else { continue }
            let noun = entity.rawValue.lowercased() + (entityChanges.count == 1 ? "" : "s")
            var kindParts: [String] = []
            for kind in [PlanHistoryChangeKind.added, .removed, .modified] {
                let count = entityChanges.filter { $0.changeKind == kind }.count
                if count > 0 {
                    kindParts.append("\(count) \(kind.rawValue.lowercased())")
                }
            }
            parts.append("\(entityChanges.count) \(noun) (\(kindParts.joined(separator: ", ")))")
        }
        return parts.isEmpty ? "Plan updated" : parts.joined(separator: " · ")
    }

    private static func formattedPercent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private static func formattedCurrency(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
