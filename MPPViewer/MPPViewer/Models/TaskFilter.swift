import Foundation

// MARK: - Task Status Filter

enum TaskStatus: String, CaseIterable, Identifiable {
    case all = "All"
    case complete = "Complete"
    case incomplete = "Incomplete"
    case inProgress = "In Progress"
    case notStarted = "Not Started"
    case overdue = "Overdue"

    var id: String { rawValue }
}

// MARK: - Task Grouping

enum TaskGrouping: String, CaseIterable, Identifiable {
    case none = "None"
    case resource = "Resource"
    case outlineLevel = "Outline Level"
    case status = "Status"
    case priority = "Priority"
    case wbsPrefix = "WBS Prefix"

    var id: String { rawValue }
}

// MARK: - Filter Criteria

struct TaskFilterCriteria {
    var status: TaskStatus = .all
    var resourceID: Int? = nil
    var dateRangeStart: Date? = nil
    var dateRangeEnd: Date? = nil
    var criticalOnly: Bool = false
    var milestoneOnly: Bool = false
    var priorityRange: ClosedRange<Int>? = nil
    var textSearch: String = ""
    var flaggedOnly: Bool = false

    var isActive: Bool {
        status != .all || resourceID != nil || dateRangeStart != nil || dateRangeEnd != nil ||
        criticalOnly || milestoneOnly || priorityRange != nil || !textSearch.isEmpty || flaggedOnly
    }

    mutating func clear() {
        status = .all
        resourceID = nil
        dateRangeStart = nil
        dateRangeEnd = nil
        criticalOnly = false
        milestoneOnly = false
        priorityRange = nil
        textSearch = ""
        flaggedOnly = false
    }

    func matches(_ task: ProjectTask, assignments: [ResourceAssignment], today: Date = Date()) -> Bool {
        // Status filter
        switch status {
        case .all:
            break
        case .complete:
            guard (task.percentComplete ?? 0) >= 100 else { return false }
        case .incomplete:
            guard (task.percentComplete ?? 0) < 100 else { return false }
        case .inProgress:
            let pct = task.percentComplete ?? 0
            guard pct > 0 && pct < 100 else { return false }
        case .notStarted:
            guard (task.percentComplete ?? 0) == 0 else { return false }
        case .overdue:
            let pct = task.percentComplete ?? 0
            guard pct < 100, let finish = task.finishDate, finish < today else { return false }
        }

        // Resource filter
        if let rid = resourceID {
            let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
            guard taskAssignments.contains(where: { $0.resourceUniqueID == rid }) else { return false }
        }

        // Date range filter
        if let rangeStart = dateRangeStart {
            guard let taskStart = task.startDate, taskStart >= rangeStart else { return false }
        }
        if let rangeEnd = dateRangeEnd {
            guard let taskFinish = task.finishDate, taskFinish <= rangeEnd else { return false }
        }

        // Critical only
        if criticalOnly {
            guard task.critical == true else { return false }
        }

        // Milestone only
        if milestoneOnly {
            guard task.milestone == true else { return false }
        }

        // Priority range
        if let range = priorityRange, let p = task.priority {
            guard range.contains(p) else { return false }
        }

        // Text search
        if !textSearch.isEmpty {
            let search = textSearch.lowercased()
            let nameMatch = task.name?.lowercased().contains(search) == true
            let wbsMatch = task.wbs?.lowercased().contains(search) == true
            let notesMatch = task.notes?.lowercased().contains(search) == true
            guard nameMatch || wbsMatch || notesMatch else { return false }
        }

        return true
    }
}
