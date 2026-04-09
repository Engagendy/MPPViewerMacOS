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

enum TaskViewPreset: String, CaseIterable, Identifiable {
    case none = "Default"
    case overdueCritical = "Overdue Critical"
    case upcomingMilestones = "Upcoming Milestones"
    case inProgress = "In Progress"
    case flaggedReview = "Flagged Review"
    case openIssues = "Open Issues"
    case completed = "Completed"

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
    var baselineSlippedOnly: Bool = false
    var hasDependenciesOnly: Bool = false
    var annotatedOnly: Bool = false
    var unresolvedOnly: Bool = false
    var followUpOnly: Bool = false

    var isActive: Bool {
        status != .all || resourceID != nil || dateRangeStart != nil || dateRangeEnd != nil ||
        criticalOnly || milestoneOnly || priorityRange != nil || !textSearch.isEmpty || flaggedOnly ||
        baselineSlippedOnly || hasDependenciesOnly || annotatedOnly || unresolvedOnly || followUpOnly
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
        baselineSlippedOnly = false
        hasDependenciesOnly = false
        annotatedOnly = false
        unresolvedOnly = false
        followUpOnly = false
    }

    func matches(
        _ task: ProjectTask,
        assignments: [ResourceAssignment],
        resources: [ProjectResource],
        flaggedTaskIDs: Set<Int> = [],
        annotations: [Int: TaskReviewAnnotation] = [:],
        today: Date = Date()
    ) -> Bool {
        let annotation = annotations[task.uniqueID]

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

        if flaggedOnly {
            guard flaggedTaskIDs.contains(task.uniqueID) else { return false }
        }

        if baselineSlippedOnly {
            guard (task.finishVarianceDays ?? task.startVarianceDays ?? 0) > 0 else { return false }
        }

        if hasDependenciesOnly {
            let predecessorCount = task.predecessors?.count ?? 0
            let successorCount = task.successors?.count ?? 0
            guard predecessorCount + successorCount > 0 else { return false }
        }

        if annotatedOnly {
            guard annotation?.hasContent == true else { return false }
        }

        if unresolvedOnly {
            guard annotation?.isUnresolved == true else { return false }
        }

        if followUpOnly {
            guard annotation?.needsFollowUp == true else { return false }
        }

        // Text search
        if !textSearch.isEmpty {
            let search = textSearch.lowercased()
            let nameMatch = task.name?.lowercased().contains(search) == true
            let wbsMatch = task.wbs?.lowercased().contains(search) == true
            let idMatch = task.id.map(String.init)?.contains(search) == true
            let notesMatch = task.notes?.lowercased().contains(search) == true
            let customFieldMatch = task.customFields?.values.contains(where: { $0.displayString.lowercased().contains(search) }) == true
            let annotationMatch = annotation?.note.lowercased().contains(search) == true
            let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
            let resourceMatch = taskAssignments.contains { assignment in
                guard let resourceID = assignment.resourceUniqueID else { return false }
                return resources.first(where: { $0.uniqueID == resourceID })?.name?.lowercased().contains(search) == true
            }
            let keywordMatch =
                (search == "critical" && task.critical == true) ||
                (search == "milestone" && task.isDisplayMilestone) ||
                (search == "summary" && task.summary == true) ||
                (search == "overdue" && task.isOverdue) ||
                (search == "baseline slip" && (task.finishVarianceDays ?? task.startVarianceDays ?? 0) > 0) ||
                (search == "open issue" && annotation?.isUnresolved == true) ||
                (search == "follow up" && annotation?.needsFollowUp == true) ||
                (search == "reviewed" && annotation?.hasContent == true)
            guard nameMatch || wbsMatch || idMatch || notesMatch || customFieldMatch || annotationMatch || resourceMatch || keywordMatch else { return false }
        }

        return true
    }

    mutating func applyPreset(_ preset: TaskViewPreset) {
        clear()
        switch preset {
        case .none:
            break
        case .overdueCritical:
            status = .overdue
            criticalOnly = true
        case .upcomingMilestones:
            status = .incomplete
            milestoneOnly = true
        case .inProgress:
            status = .inProgress
        case .flaggedReview:
            flaggedOnly = true
        case .openIssues:
            unresolvedOnly = true
        case .completed:
            status = .complete
        }
    }
}
