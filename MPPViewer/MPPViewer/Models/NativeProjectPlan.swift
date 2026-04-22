import Foundation

struct NativeProjectPlan: Codable, Hashable {
    var title: String
    var manager: String
    var company: String
    var statusDate: Date
    var defaultCalendarUniqueID: Int?
    var tasks: [NativePlanTask]
    var resources: [NativePlanResource]
    var assignments: [NativePlanAssignment]
    var calendars: [NativePlanCalendar]

    enum CodingKeys: String, CodingKey {
        case title
        case manager
        case company
        case statusDate
        case defaultCalendarUniqueID
        case tasks
        case resources
        case assignments
        case calendars
    }

    static func empty() -> NativeProjectPlan {
        let standardCalendar = NativePlanCalendar.standard(id: 1)
        return NativeProjectPlan(
            title: "Untitled Plan",
            manager: "",
            company: "",
            statusDate: Calendar.current.startOfDay(for: Date()),
            defaultCalendarUniqueID: standardCalendar.id,
            tasks: [],
            resources: [],
            assignments: [],
            calendars: [standardCalendar]
        )
    }

    init(
        title: String,
        manager: String,
        company: String,
        statusDate: Date,
        defaultCalendarUniqueID: Int?,
        tasks: [NativePlanTask],
        resources: [NativePlanResource],
        assignments: [NativePlanAssignment],
        calendars: [NativePlanCalendar]
    ) {
        self.title = title
        self.manager = manager
        self.company = company
        self.statusDate = statusDate
        self.defaultCalendarUniqueID = defaultCalendarUniqueID
        self.tasks = tasks
        self.resources = resources
        self.assignments = assignments
        self.calendars = calendars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Plan"
        manager = try container.decodeIfPresent(String.self, forKey: .manager) ?? ""
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        statusDate = try container.decodeIfPresent(Date.self, forKey: .statusDate) ?? Calendar.current.startOfDay(for: Date())
        defaultCalendarUniqueID = try container.decodeIfPresent(Int.self, forKey: .defaultCalendarUniqueID)
        tasks = try container.decodeIfPresent([NativePlanTask].self, forKey: .tasks) ?? []
        resources = try container.decodeIfPresent([NativePlanResource].self, forKey: .resources) ?? []
        assignments = try container.decodeIfPresent([NativePlanAssignment].self, forKey: .assignments) ?? []
        calendars = try container.decodeIfPresent([NativePlanCalendar].self, forKey: .calendars) ?? []
    }

    static func decode(from data: Data) throws -> NativeProjectPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NativeProjectPlan.self, from: data)
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    func nextTaskID() -> Int {
        (tasks.map(\.id).max() ?? 0) + 1
    }

    func nextResourceID() -> Int {
        (resources.map(\.id).max() ?? 0) + 1
    }

    func nextAssignmentID() -> Int {
        (assignments.map(\.id).max() ?? 0) + 1
    }

    func nextCalendarID() -> Int {
        (calendars.map(\.id).max() ?? 0) + 1
    }

    func makeTask(name: String = "New Task", anchoredTo date: Date? = nil) -> NativePlanTask {
        let baseDate = Calendar.current.startOfDay(for: date ?? statusDate)
        return NativePlanTask(
            id: nextTaskID(),
            name: name,
            startDate: baseDate,
            finishDate: baseDate,
            durationDays: 1,
            outlineLevel: 1,
            isMilestone: false,
            manuallyScheduled: false,
            percentComplete: 0,
            priority: 500,
            notes: "",
            predecessorTaskIDs: [],
            baselineStartDate: nil,
            baselineFinishDate: nil,
            baselineDurationDays: nil,
            fixedCost: 0,
            baselineCost: nil,
            actualCost: nil,
            actualStartDate: nil,
            actualFinishDate: nil,
            constraintType: nil,
            constraintDate: nil,
            calendarUniqueID: nil,
            isActive: true
        )
    }

    func makeResource(name: String = "New Resource") -> NativePlanResource {
        NativePlanResource(
            id: nextResourceID(),
            name: name,
            type: "Work",
            maxUnits: 100,
            standardRate: 0,
            overtimeRate: 0,
            costPerUse: 0,
            emailAddress: "",
            group: "",
            initials: "",
            notes: "",
            calendarUniqueID: defaultCalendarUniqueID,
            accrueAt: "end",
            active: true
        )
    }

    func makeAssignment(taskID: Int, resourceID: Int? = nil) -> NativePlanAssignment {
        NativePlanAssignment(
            id: nextAssignmentID(),
            taskID: taskID,
            resourceID: resourceID,
            units: 100,
            workSeconds: nil,
            actualWorkSeconds: nil,
            remainingWorkSeconds: nil,
            overtimeWorkSeconds: nil,
            notes: ""
        )
    }

    func makeCalendar(name: String = "New Calendar") -> NativePlanCalendar {
        NativePlanCalendar.standard(id: nextCalendarID(), name: name)
    }

    mutating func reschedule() {
        tasks = PlanScheduler.schedule(self).tasks
    }

    mutating func captureBaseline() {
        let scheduledTasks = PlanScheduler.schedule(self).tasks
        let scheduledByID = Dictionary(uniqueKeysWithValues: scheduledTasks.map { ($0.id, $0) })
        let financialsByTaskID = financialSnapshots(for: scheduledTasks)
        for index in tasks.indices {
            guard let scheduled = scheduledByID[tasks[index].id] else { continue }
            tasks[index].baselineStartDate = scheduled.startDate
            tasks[index].baselineFinishDate = scheduled.finishDate
            tasks[index].baselineDurationDays = scheduled.isMilestone ? 0 : max(1, scheduled.durationDays)
            tasks[index].baselineCost = financialsByTaskID[tasks[index].id]?.plannedCost
        }
    }

    func asProjectModel() -> ProjectModel {
        let scheduleResult = PlanScheduler.schedule(self)
        let scheduledTasks = scheduleResult.tasks
        let criticalTaskIDs = scheduleResult.criticalTaskIDs
        let calendar = Calendar.current
        let taskHierarchy = buildHierarchyMetadata(for: scheduledTasks)
        let financialsByTaskID = financialSnapshots(for: scheduledTasks)

        let successorMap = Dictionary(grouping: scheduledTasks.flatMap { task in
            task.predecessorTaskIDs.map { predecessorID in
                (predecessorID, task.id)
            }
        }, by: \.0).mapValues { pairs in
            pairs.map(\.1).sorted()
        }

        let projectTasks = scheduledTasks.map { task in
            let predecessorRelations = task.predecessorTaskIDs.sorted().map { predecessorID in
                TaskRelation(uniqueID: predecessorID, taskUniqueID: predecessorID, type: "FS", lag: nil)
            }
            let successorRelations = (successorMap[task.id] ?? []).map { successorID in
                TaskRelation(uniqueID: successorID, taskUniqueID: successorID, type: "FS", lag: nil)
            }
            let hierarchy = taskHierarchy[task.id] ?? TaskHierarchyMetadata(
                outlineLevel: max(1, task.outlineLevel),
                outlineNumber: String(task.id),
                parentTaskUniqueID: nil,
                isSummary: false
            )

            let normalizedStart = calendar.startOfDay(for: min(task.startDate, task.finishDate))
            let normalizedFinish = calendar.startOfDay(for: max(task.startDate, task.finishDate))
            let startString = scheduleString(for: normalizedStart, hour: 8)
            let finishString = task.isMilestone
                ? startString
                : scheduleString(for: normalizedFinish, hour: 17)
            let durationSeconds = task.isMilestone ? 0 : max(1, task.durationDays) * 8 * 3600

            let actualDuration = durationSeconds > 0 ? Int((task.percentComplete / 100.0) * Double(durationSeconds)) : 0
            let remainingDuration = max(0, durationSeconds - actualDuration)
            let financials = financialsByTaskID[task.id]
            let actualStartString = task.actualStartDate.map { scheduleString(for: $0, hour: 8) }
            let actualFinishString = task.actualFinishDate.map { scheduleString(for: $0, hour: task.isMilestone ? 8 : 17) }

            return ProjectTask(
                uniqueID: task.id,
                id: task.id,
                name: task.name,
                wbs: hierarchy.outlineNumber,
                outlineLevel: hierarchy.outlineLevel,
                outlineNumber: hierarchy.outlineNumber,
                start: startString,
                finish: finishString,
                actualStart: actualStartString ?? (task.percentComplete > 0 ? startString : nil),
                actualFinish: actualFinishString ?? (task.percentComplete >= 100 ? finishString : nil),
                duration: durationSeconds,
                actualDuration: actualDuration,
                remainingDuration: remainingDuration,
                percentComplete: task.percentComplete,
                percentWorkComplete: task.percentComplete,
                milestone: task.isMilestone,
                summary: hierarchy.isSummary,
                critical: criticalTaskIDs.contains(task.id) ? true : nil,
                cost: hierarchy.isSummary ? nil : financials?.plannedCost,
                work: hierarchy.isSummary ? durationSeconds : (financials?.plannedWorkSeconds ?? durationSeconds),
                notes: task.notes.nonEmpty,
                priority: task.priority,
                parentTaskUniqueID: hierarchy.parentTaskUniqueID,
                constraintType: task.constraintType,
                constraintDate: task.constraintDate.map(DateFormatting.simpleDate),
                totalSlack: scheduleResult.totalSlackSecondsByTaskID[task.id],
                freeSlack: scheduleResult.totalSlackSecondsByTaskID[task.id],
                predecessors: predecessorRelations.isEmpty ? nil : predecessorRelations,
                successors: successorRelations.isEmpty ? nil : successorRelations,
                active: task.isActive,
                guid: nil,
                type: hierarchy.isSummary ? "Summary" : (task.isMilestone ? "Milestone" : "Task"),
                baselineStart: task.baselineStartDate.map { scheduleString(for: $0, hour: 8) },
                baselineFinish: task.baselineFinishDate.map { scheduleString(for: $0, hour: task.isMilestone ? 8 : 17) },
                baselineDuration: task.baselineDurationDays.map { $0 == 0 ? 0 : max(1, $0) * 8 * 3600 },
                baselineCost: hierarchy.isSummary ? nil : financials?.budgetAtCompletion,
                baselineWork: hierarchy.isSummary ? nil : financials?.plannedWorkSeconds,
                actualCost: hierarchy.isSummary ? nil : financials?.actualCost,
                bcws: hierarchy.isSummary ? nil : financials?.plannedValue,
                bcwp: hierarchy.isSummary ? nil : financials?.earnedValue,
                acwp: hierarchy.isSummary ? nil : financials?.actualCost
            )
        }

        let projectStart = scheduledTasks.map(\.startDate).min().map { scheduleString(for: $0, hour: 8) }
        let projectFinish = scheduledTasks.map(\.finishDate).max().map { scheduleString(for: $0, hour: 17) }
        let properties = ProjectProperties(
            projectTitle: title.nonEmpty ?? "Untitled Plan",
            author: nil,
            lastAuthor: nil,
            manager: manager.nonEmpty,
            company: company.nonEmpty,
            startDate: projectStart,
            finishDate: projectFinish,
            statusDate: scheduleString(for: statusDate, hour: 8),
            creationDate: nil,
            lastSaved: nil,
            currencySymbol: nil,
            currencyCode: nil,
            comments: nil,
            subject: nil,
            category: "Native Plan",
            keywords: nil,
            defaultCalendarUniqueId: defaultCalendarUniqueID,
            shortApplicationName: "MPP Viewer",
            fullApplicationName: "MPP Viewer"
        )

        let tasksByID: [Int: ProjectTask] = Dictionary(uniqueKeysWithValues: projectTasks.map { ($0.uniqueID, $0) })
        for task in projectTasks {
            task.children = []
        }

        var rootTasks: [ProjectTask] = []
        for task in projectTasks {
            if let parentID = task.parentTaskUniqueID, let parent = tasksByID[parentID] {
                parent.children.append(task)
            } else {
                rootTasks.append(task)
            }
        }

        let projectResources = resources.map { $0.asProjectResource() }
        let projectAssignments = assignments.map { assignment in
            assignment.asResourceAssignment(
                tasksByID: tasksByID,
                plannedWorkSeconds: financialsByTaskID[assignment.taskID]?.assignmentPlannedWorkSecondsByAssignmentID[assignment.id],
                actualWorkSeconds: financialsByTaskID[assignment.taskID]?.assignmentActualWorkSecondsByAssignmentID[assignment.id],
                remainingWorkSeconds: financialsByTaskID[assignment.taskID]?.assignmentRemainingWorkSecondsByAssignmentID[assignment.id],
                cost: financialsByTaskID[assignment.taskID]?.assignmentPlannedCostByAssignmentID[assignment.id]
            )
        }
        let projectCalendars = calendars.map { $0.asProjectCalendar() }

        return ProjectModel(
            properties: properties,
            tasks: projectTasks,
            resources: projectResources,
            assignments: projectAssignments,
            calendars: projectCalendars,
            rootTasks: rootTasks,
            tasksByID: tasksByID
        )
    }

    fileprivate func buildHierarchyMetadata(for sourceTasks: [NativePlanTask]? = nil) -> [Int: TaskHierarchyMetadata] {
        let sourceTasks = sourceTasks ?? tasks
        guard !sourceTasks.isEmpty else { return [:] }

        var metadataByTaskID: [Int: TaskHierarchyMetadata] = [:]
        var numbering: [Int: Int] = [:]
        var taskIDByLevel: [Int: Int] = [:]

        for (index, task) in sourceTasks.enumerated() {
            let previousLevel = index > 0 ? max(1, sourceTasks[index - 1].outlineLevel) : 1
            let level = min(max(1, task.outlineLevel), previousLevel + 1)

            numbering[level, default: 0] += 1
            numbering.keys.filter { $0 > level }.forEach { numbering.removeValue(forKey: $0) }

            let outlineNumber = (1 ... level)
                .compactMap { numbering[$0] }
                .map(String.init)
                .joined(separator: ".")

            taskIDByLevel[level] = task.id
            taskIDByLevel.keys.filter { $0 > level }.forEach { taskIDByLevel.removeValue(forKey: $0) }

            let nextLevel = index + 1 < sourceTasks.count ? max(1, sourceTasks[index + 1].outlineLevel) : 1
            metadataByTaskID[task.id] = TaskHierarchyMetadata(
                outlineLevel: level,
                outlineNumber: outlineNumber,
                parentTaskUniqueID: level > 1 ? taskIDByLevel[level - 1] : nil,
                isSummary: nextLevel > level
            )
        }

        return metadataByTaskID
    }

    private func durationSeconds(startDate: Date, finishDate: Date, calendar: Calendar) -> Int {
        let dayDelta = (calendar.dateComponents([.day], from: startDate, to: finishDate).day ?? 0) + 1
        return max(1, dayDelta) * 8 * 3600
    }

    private func financialSnapshots(for scheduledTasks: [NativePlanTask]) -> [Int: NativeTaskFinancialSnapshot] {
        let resourcesByID = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })
        let assignmentsByTaskID = Dictionary(grouping: assignments, by: \.taskID)
        let hierarchyByTaskID = buildHierarchyMetadata(for: scheduledTasks)

        return Dictionary(uniqueKeysWithValues: scheduledTasks.compactMap { task in
            let hierarchy = hierarchyByTaskID[task.id]
            guard hierarchy?.isSummary != true else {
                return (task.id, NativeTaskFinancialSnapshot.zero)
            }

            let plannedTaskWorkSeconds = task.isMilestone ? 0 : max(1, task.durationDays) * 8 * 3600
            let earnedPercent = min(1, max(0, task.percentComplete / 100.0))
            let plannedPercent = EVMCalculator.computePlannedPercent(
                baselineStart: task.baselineStartDate ?? task.startDate,
                baselineFinish: task.baselineFinishDate ?? task.finishDate,
                statusDate: statusDate
            )
            let taskAssignments = assignmentsByTaskID[task.id] ?? []

            var plannedCost = max(0, task.fixedCost)
            var actualCost = max(0, task.fixedCost) * earnedPercent
            var plannedValueAccumulator = max(0, task.fixedCost) * plannedPercent
            var plannedWorkSeconds = 0
            var assignmentPlannedCostByAssignmentID: [Int: Double] = [:]
            var assignmentPlannedWorkSecondsByAssignmentID: [Int: Int] = [:]
            var assignmentActualWorkSecondsByAssignmentID: [Int: Int] = [:]
            var assignmentRemainingWorkSecondsByAssignmentID: [Int: Int] = [:]
            var assignmentOvertimeWorkSecondsByAssignmentID: [Int: Int] = [:]

            for assignment in taskAssignments {
                let plannedAssignmentWork = max(
                    0,
                    assignment.workSeconds
                        ?? Int((Double(plannedTaskWorkSeconds) * max(0, assignment.units)) / 100.0)
                )
                let actualAssignmentWork = max(
                    0,
                    assignment.actualWorkSeconds
                        ?? max(
                            0,
                            min(
                                plannedAssignmentWork,
                                assignment.remainingWorkSeconds.map { plannedAssignmentWork - $0 } ?? Int(Double(plannedAssignmentWork) * earnedPercent)
                            )
                        )
                )
                let remainingAssignmentWork = max(
                    0,
                    assignment.remainingWorkSeconds ?? max(0, plannedAssignmentWork - actualAssignmentWork)
                )
                let overtimeAssignmentWork = max(
                    0,
                    min(actualAssignmentWork, assignment.overtimeWorkSeconds ?? 0)
                )

                let resource = assignment.resourceID.flatMap { resourcesByID[$0] }
                let standardRate = max(0, resource?.standardRate ?? 0)
                let overtimeRate = max(0, resource?.overtimeRate ?? standardRate)
                let costPerUse = max(0, resource?.costPerUse ?? 0)
                let regularActualWork = max(0, actualAssignmentWork - overtimeAssignmentWork)
                let plannedLaborCost = (Double(plannedAssignmentWork) / 3600.0) * standardRate
                let actualLaborCost =
                    (Double(regularActualWork) / 3600.0) * standardRate +
                    (Double(overtimeAssignmentWork) / 3600.0) * overtimeRate
                let plannedAccrual = accrualFraction(
                    accrueAt: resource?.accrueAt,
                    plannedPercent: plannedPercent,
                    hasStarted: statusDate >= (task.baselineStartDate ?? task.startDate),
                    hasFinished: statusDate >= (task.baselineFinishDate ?? task.finishDate)
                )
                let actualAccrual = accrualFraction(
                    accrueAt: resource?.accrueAt,
                    plannedPercent: min(1, max(0, task.percentComplete / 100.0)),
                    hasStarted: task.actualStartDate != nil || task.percentComplete > 0,
                    hasFinished: task.actualFinishDate != nil || task.percentComplete >= 100
                )
                let plannedAssignmentCost = plannedLaborCost + (plannedAssignmentWork > 0 ? costPerUse : 0)
                let actualAssignmentCost = actualLaborCost + (plannedAssignmentWork > 0 ? costPerUse * actualAccrual : 0)
                let plannedAssignmentValue = (plannedLaborCost * plannedPercent) + (plannedAssignmentWork > 0 ? costPerUse * plannedAccrual : 0)

                plannedCost += plannedAssignmentCost
                actualCost += actualAssignmentCost
                plannedValueAccumulator += plannedAssignmentValue
                plannedWorkSeconds += plannedAssignmentWork
                assignmentPlannedCostByAssignmentID[assignment.id] = plannedAssignmentCost
                assignmentPlannedWorkSecondsByAssignmentID[assignment.id] = plannedAssignmentWork
                assignmentActualWorkSecondsByAssignmentID[assignment.id] = actualAssignmentWork
                assignmentRemainingWorkSecondsByAssignmentID[assignment.id] = remainingAssignmentWork
                assignmentOvertimeWorkSecondsByAssignmentID[assignment.id] = overtimeAssignmentWork
            }

            if let overriddenActualCost = task.actualCost {
                actualCost = max(0, overriddenActualCost)
            }

            let budgetAtCompletion = max(0, task.baselineCost ?? plannedCost)
            let plannedValue = task.baselineCost != nil ? budgetAtCompletion * plannedPercent : plannedValueAccumulator
            let earnedValue = budgetAtCompletion * earnedPercent

            return (
                task.id,
                NativeTaskFinancialSnapshot(
                    plannedCost: plannedCost,
                    budgetAtCompletion: budgetAtCompletion,
                    actualCost: actualCost,
                    plannedValue: plannedValue,
                    earnedValue: earnedValue,
                    plannedWorkSeconds: plannedWorkSeconds > 0 ? plannedWorkSeconds : plannedTaskWorkSeconds,
                    assignmentPlannedCostByAssignmentID: assignmentPlannedCostByAssignmentID,
                    assignmentPlannedWorkSecondsByAssignmentID: assignmentPlannedWorkSecondsByAssignmentID,
                    assignmentActualWorkSecondsByAssignmentID: assignmentActualWorkSecondsByAssignmentID,
                    assignmentRemainingWorkSecondsByAssignmentID: assignmentRemainingWorkSecondsByAssignmentID,
                    assignmentOvertimeWorkSecondsByAssignmentID: assignmentOvertimeWorkSecondsByAssignmentID
                )
            )
        })
    }

    private func scheduleString(for date: Date, hour: Int) -> String {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        components.second = 0
        let scheduled = Calendar.current.date(from: components) ?? date
        return DateFormatting.mpxjDateTime(scheduled)
    }

    private func accrualFraction(accrueAt: String?, plannedPercent: Double, hasStarted: Bool, hasFinished: Bool) -> Double {
        switch accrueAt?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "start":
            return hasStarted ? 1 : 0
        case "end":
            return hasFinished ? 1 : 0
        default:
            return min(1, max(0, plannedPercent))
        }
    }
}

struct NativePlanTask: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var startDate: Date
    var finishDate: Date
    var durationDays: Int
    var outlineLevel: Int
    var isMilestone: Bool
    var manuallyScheduled: Bool
    var percentComplete: Double
    var priority: Int
    var notes: String
    var predecessorTaskIDs: [Int]
    var baselineStartDate: Date?
    var baselineFinishDate: Date?
    var baselineDurationDays: Int?
    var fixedCost: Double
    var baselineCost: Double?
    var actualCost: Double?
    var actualStartDate: Date?
    var actualFinishDate: Date?
    var constraintType: String?
    var constraintDate: Date?
    var calendarUniqueID: Int?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startDate
        case finishDate
        case durationDays
        case outlineLevel
        case isMilestone
        case manuallyScheduled
        case percentComplete
        case priority
        case notes
        case predecessorTaskIDs
        case baselineStartDate
        case baselineFinishDate
        case baselineDurationDays
        case fixedCost
        case baselineCost
        case actualCost
        case actualStartDate
        case actualFinishDate
        case constraintType
        case constraintDate
        case calendarUniqueID
        case isActive
    }

    init(
        id: Int,
        name: String,
        startDate: Date,
        finishDate: Date,
        durationDays: Int,
        outlineLevel: Int,
        isMilestone: Bool,
        manuallyScheduled: Bool,
        percentComplete: Double,
        priority: Int,
        notes: String,
        predecessorTaskIDs: [Int],
        baselineStartDate: Date?,
        baselineFinishDate: Date?,
        baselineDurationDays: Int?,
        fixedCost: Double,
        baselineCost: Double?,
        actualCost: Double?,
        actualStartDate: Date?,
        actualFinishDate: Date?,
        constraintType: String?,
        constraintDate: Date?,
        calendarUniqueID: Int?,
        isActive: Bool
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.finishDate = finishDate
        self.durationDays = max(1, durationDays)
        self.outlineLevel = max(1, outlineLevel)
        self.isMilestone = isMilestone
        self.manuallyScheduled = manuallyScheduled
        self.percentComplete = percentComplete
        self.priority = priority
        self.notes = notes
        self.predecessorTaskIDs = predecessorTaskIDs
        self.baselineStartDate = baselineStartDate.map { Calendar.current.startOfDay(for: $0) }
        self.baselineFinishDate = baselineFinishDate.map { Calendar.current.startOfDay(for: $0) }
        self.baselineDurationDays = baselineDurationDays
        self.fixedCost = max(0, fixedCost)
        self.baselineCost = baselineCost
        self.actualCost = actualCost
        self.actualStartDate = actualStartDate.map { Calendar.current.startOfDay(for: $0) }
        self.actualFinishDate = actualFinishDate.map { Calendar.current.startOfDay(for: $0) }
        self.constraintType = constraintType
        self.constraintDate = constraintDate.map { Calendar.current.startOfDay(for: $0) }
        self.calendarUniqueID = calendarUniqueID
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startDate = try container.decode(Date.self, forKey: .startDate)
        finishDate = try container.decode(Date.self, forKey: .finishDate)
        let decodedDurationDays = try container.decodeIfPresent(Int.self, forKey: .durationDays)
        outlineLevel = max(1, try container.decodeIfPresent(Int.self, forKey: .outlineLevel) ?? 1)
        isMilestone = try container.decode(Bool.self, forKey: .isMilestone)
        manuallyScheduled = try container.decodeIfPresent(Bool.self, forKey: .manuallyScheduled) ?? false
        percentComplete = try container.decode(Double.self, forKey: .percentComplete)
        priority = try container.decode(Int.self, forKey: .priority)
        notes = try container.decode(String.self, forKey: .notes)
        predecessorTaskIDs = try container.decode([Int].self, forKey: .predecessorTaskIDs)
        baselineStartDate = try container.decodeIfPresent(Date.self, forKey: .baselineStartDate).map { Calendar.current.startOfDay(for: $0) }
        baselineFinishDate = try container.decodeIfPresent(Date.self, forKey: .baselineFinishDate).map { Calendar.current.startOfDay(for: $0) }
        baselineDurationDays = try container.decodeIfPresent(Int.self, forKey: .baselineDurationDays)
        fixedCost = max(0, try container.decodeIfPresent(Double.self, forKey: .fixedCost) ?? 0)
        baselineCost = try container.decodeIfPresent(Double.self, forKey: .baselineCost)
        actualCost = try container.decodeIfPresent(Double.self, forKey: .actualCost)
        actualStartDate = try container.decodeIfPresent(Date.self, forKey: .actualStartDate).map { Calendar.current.startOfDay(for: $0) }
        actualFinishDate = try container.decodeIfPresent(Date.self, forKey: .actualFinishDate).map { Calendar.current.startOfDay(for: $0) }
        constraintType = try container.decodeIfPresent(String.self, forKey: .constraintType)
        constraintDate = try container.decodeIfPresent(Date.self, forKey: .constraintDate).map { Calendar.current.startOfDay(for: $0) }
        calendarUniqueID = try container.decodeIfPresent(Int.self, forKey: .calendarUniqueID)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        let normalizedStart = Calendar.current.startOfDay(for: min(startDate, finishDate))
        let normalizedFinish = Calendar.current.startOfDay(for: max(startDate, finishDate))
        startDate = normalizedStart
        finishDate = normalizedFinish
        if let decodedDurationDays {
            durationDays = max(1, decodedDurationDays)
        } else {
            let daySpan = (Calendar.current.dateComponents([.day], from: normalizedStart, to: normalizedFinish).day ?? 0) + 1
            durationDays = max(1, daySpan)
        }
    }

    var normalizedFinishDate: Date {
        max(startDate, finishDate)
    }

    var normalizedDurationDays: Int {
        isMilestone ? 0 : max(1, durationDays)
    }
}

struct NativePlanResource: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var type: String
    var maxUnits: Double
    var standardRate: Double
    var overtimeRate: Double
    var costPerUse: Double
    var emailAddress: String
    var group: String
    var initials: String
    var notes: String
    var calendarUniqueID: Int?
    var accrueAt: String
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case maxUnits
        case standardRate
        case overtimeRate
        case costPerUse
        case emailAddress
        case group
        case initials
        case notes
        case calendarUniqueID
        case accrueAt
        case active
    }

    init(
        id: Int,
        name: String,
        type: String,
        maxUnits: Double,
        standardRate: Double,
        overtimeRate: Double,
        costPerUse: Double,
        emailAddress: String,
        group: String,
        initials: String,
        notes: String,
        calendarUniqueID: Int?,
        accrueAt: String,
        active: Bool
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.maxUnits = maxUnits
        self.standardRate = max(0, standardRate)
        self.overtimeRate = max(0, overtimeRate)
        self.costPerUse = max(0, costPerUse)
        self.emailAddress = emailAddress
        self.group = group
        self.initials = initials
        self.notes = notes
        self.calendarUniqueID = calendarUniqueID
        self.accrueAt = accrueAt.isEmpty ? "end" : accrueAt
        self.active = active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Work"
        maxUnits = try container.decodeIfPresent(Double.self, forKey: .maxUnits) ?? 100
        standardRate = max(0, try container.decodeIfPresent(Double.self, forKey: .standardRate) ?? 0)
        overtimeRate = max(0, try container.decodeIfPresent(Double.self, forKey: .overtimeRate) ?? 0)
        costPerUse = max(0, try container.decodeIfPresent(Double.self, forKey: .costPerUse) ?? 0)
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress) ?? ""
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        initials = try container.decodeIfPresent(String.self, forKey: .initials) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        calendarUniqueID = try container.decodeIfPresent(Int.self, forKey: .calendarUniqueID)
        accrueAt = try container.decodeIfPresent(String.self, forKey: .accrueAt) ?? "end"
        active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }

    func asProjectResource() -> ProjectResource {
        ProjectResource(
            uniqueID: id,
            id: id,
            name: name.nonEmpty ?? "Unnamed Resource",
            type: type.nonEmpty,
            maxUnits: maxUnits,
            standardRate: standardRate,
            overtimeRate: overtimeRate,
            costPerUse: costPerUse,
            emailAddress: emailAddress.nonEmpty,
            group: group.nonEmpty,
            initials: initials.nonEmpty,
            notes: notes.nonEmpty,
            calendarUniqueID: calendarUniqueID,
            accrueAt: accrueAt.nonEmpty,
            active: active,
            guid: nil
        )
    }
}

struct NativePlanAssignment: Codable, Identifiable, Hashable {
    var id: Int
    var taskID: Int
    var resourceID: Int?
    var units: Double
    var workSeconds: Int?
    var actualWorkSeconds: Int?
    var remainingWorkSeconds: Int?
    var overtimeWorkSeconds: Int?
    var notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case taskID
        case resourceID
        case units
        case workSeconds
        case actualWorkSeconds
        case remainingWorkSeconds
        case overtimeWorkSeconds
        case notes
    }

    init(
        id: Int,
        taskID: Int,
        resourceID: Int?,
        units: Double,
        workSeconds: Int?,
        actualWorkSeconds: Int?,
        remainingWorkSeconds: Int?,
        overtimeWorkSeconds: Int?,
        notes: String
    ) {
        self.id = id
        self.taskID = taskID
        self.resourceID = resourceID
        self.units = max(0, units)
        self.workSeconds = workSeconds
        self.actualWorkSeconds = actualWorkSeconds
        self.remainingWorkSeconds = remainingWorkSeconds
        self.overtimeWorkSeconds = overtimeWorkSeconds
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        taskID = try container.decode(Int.self, forKey: .taskID)
        resourceID = try container.decodeIfPresent(Int.self, forKey: .resourceID)
        units = max(0, try container.decodeIfPresent(Double.self, forKey: .units) ?? 100)
        workSeconds = try container.decodeIfPresent(Int.self, forKey: .workSeconds)
        actualWorkSeconds = try container.decodeIfPresent(Int.self, forKey: .actualWorkSeconds)
        remainingWorkSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingWorkSeconds)
        overtimeWorkSeconds = try container.decodeIfPresent(Int.self, forKey: .overtimeWorkSeconds)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func asResourceAssignment(
        tasksByID: [Int: ProjectTask],
        plannedWorkSeconds: Int?,
        actualWorkSeconds: Int?,
        remainingWorkSeconds: Int?,
        cost: Double?
    ) -> ResourceAssignment {
        let task = tasksByID[taskID]
        return ResourceAssignment(
            uniqueID: id,
            taskUniqueID: taskID,
            resourceUniqueID: resourceID,
            assignmentUnits: units,
            work: plannedWorkSeconds ?? workSeconds,
            actualWork: actualWorkSeconds ?? self.actualWorkSeconds,
            remainingWork: remainingWorkSeconds ?? self.remainingWorkSeconds,
            start: task?.start,
            finish: task?.finish,
            cost: cost,
            guid: nil
        )
    }
}

private struct NativeTaskFinancialSnapshot {
    let plannedCost: Double
    let budgetAtCompletion: Double
    let actualCost: Double
    let plannedValue: Double
    let earnedValue: Double
    let plannedWorkSeconds: Int
    let assignmentPlannedCostByAssignmentID: [Int: Double]
    let assignmentPlannedWorkSecondsByAssignmentID: [Int: Int]
    let assignmentActualWorkSecondsByAssignmentID: [Int: Int]
    let assignmentRemainingWorkSecondsByAssignmentID: [Int: Int]
    let assignmentOvertimeWorkSecondsByAssignmentID: [Int: Int]

    static let zero = NativeTaskFinancialSnapshot(
        plannedCost: 0,
        budgetAtCompletion: 0,
        actualCost: 0,
        plannedValue: 0,
        earnedValue: 0,
        plannedWorkSeconds: 0,
        assignmentPlannedCostByAssignmentID: [:],
        assignmentPlannedWorkSecondsByAssignmentID: [:],
        assignmentActualWorkSecondsByAssignmentID: [:],
        assignmentRemainingWorkSecondsByAssignmentID: [:],
        assignmentOvertimeWorkSecondsByAssignmentID: [:]
    )
}

struct NativePlanCalendar: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var parentUniqueID: Int?
    var type: String
    var personal: Bool
    var sunday: NativeCalendarDay
    var monday: NativeCalendarDay
    var tuesday: NativeCalendarDay
    var wednesday: NativeCalendarDay
    var thursday: NativeCalendarDay
    var friday: NativeCalendarDay
    var saturday: NativeCalendarDay
    var exceptions: [NativeCalendarException]

    static func standard(id: Int, name: String = "Standard") -> NativePlanCalendar {
        NativePlanCalendar(
            id: id,
            name: name,
            parentUniqueID: nil,
            type: "Standard",
            personal: false,
            sunday: .nonWorking(),
            monday: .workingDay(),
            tuesday: .workingDay(),
            wednesday: .workingDay(),
            thursday: .workingDay(),
            friday: .workingDay(),
            saturday: .nonWorking(),
            exceptions: []
        )
    }

    func asProjectCalendar() -> ProjectCalendar {
        ProjectCalendar(
            uniqueID: id,
            name: name.nonEmpty,
            parentUniqueID: parentUniqueID,
            type: type.nonEmpty,
            personal: personal,
            sunday: sunday.asCalendarDayInfo(),
            monday: monday.asCalendarDayInfo(),
            tuesday: tuesday.asCalendarDayInfo(),
            wednesday: wednesday.asCalendarDayInfo(),
            thursday: thursday.asCalendarDayInfo(),
            friday: friday.asCalendarDayInfo(),
            saturday: saturday.asCalendarDayInfo(),
            exceptions: exceptions.map { $0.asCalendarException() }
        )
    }
}

struct NativeCalendarDay: Codable, Hashable {
    var type: String
    var from: String
    var to: String

    static func workingDay(from: String = "08:00", to: String = "17:00") -> NativeCalendarDay {
        NativeCalendarDay(type: "working", from: from, to: to)
    }

    static func nonWorking() -> NativeCalendarDay {
        NativeCalendarDay(type: "non_working", from: "", to: "")
    }

    var isWorking: Bool {
        type.lowercased() == "working"
    }

    func asCalendarDayInfo() -> CalendarDayInfo {
        CalendarDayInfo(
            type: isWorking ? "working" : "non_working",
            hours: isWorking ? [CalendarHours(from: from.nonEmpty, to: to.nonEmpty)] : nil
        )
    }
}

struct NativeCalendarException: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fromDate: Date
    var toDate: Date
    var type: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fromDate
        case toDate
        case type
    }

    init(id: UUID = UUID(), name: String, fromDate: Date, toDate: Date, type: String) {
        self.id = id
        self.name = name
        self.fromDate = fromDate
        self.toDate = toDate
        self.type = type
    }

    func asCalendarException() -> CalendarException {
        CalendarException(
            name: name.nonEmpty,
            from: DateFormatting.simpleDate(fromDate),
            to: DateFormatting.simpleDate(toDate),
            type: type
        )
    }
}

private struct TaskHierarchyMetadata {
    let outlineLevel: Int
    let outlineNumber: String
    let parentTaskUniqueID: Int?
    let isSummary: Bool
}

private struct PlanScheduleResult {
    let tasks: [NativePlanTask]
    let criticalTaskIDs: Set<Int>
    let totalSlackSecondsByTaskID: [Int: Int]
}

private enum PlanScheduler {
    static func schedule(_ plan: NativeProjectPlan) -> PlanScheduleResult {
        guard !plan.tasks.isEmpty else {
            return PlanScheduleResult(tasks: [], criticalTaskIDs: [], totalSlackSecondsByTaskID: [:])
        }

        let calendar = Calendar.current
        let hierarchy = plan.buildHierarchyMetadata(for: plan.tasks)
        let originalByID = Dictionary(uniqueKeysWithValues: plan.tasks.map { ($0.id, $0) })
        let calendarsByID = Dictionary(uniqueKeysWithValues: plan.calendars.map { ($0.id, $0.asProjectCalendar()) })

        var childIDsByParentID: [Int: [Int]] = [:]
        for (taskID, metadata) in hierarchy {
            if let parentID = metadata.parentTaskUniqueID {
                childIDsByParentID[parentID, default: []].append(taskID)
            }
        }

        let successorMap = Dictionary(grouping: plan.tasks.flatMap { task in
            task.predecessorTaskIDs.map { predecessorID in
                (predecessorID, task.id)
            }
        }, by: \.0).mapValues { pairs in
            pairs.map(\.1).sorted()
        }

        var scheduledByID: [Int: NativePlanTask] = [:]
        var schedulingStack: Set<Int> = []

        func effectiveCalendar(for task: NativePlanTask) -> ProjectCalendar? {
            if let calendarID = task.calendarUniqueID ?? plan.defaultCalendarUniqueID {
                return calendarsByID[calendarID]
            }
            return nil
        }

        func exceptionRanges(for projectCalendar: ProjectCalendar?) -> [(Date, Date, Bool)] {
            guard let exceptions = projectCalendar?.exceptions else { return [] }
            return exceptions.compactMap { exception in
                guard let from = exception.fromDate, let to = exception.toDate else { return nil }
                return (
                    calendar.startOfDay(for: from),
                    calendar.startOfDay(for: to),
                    exception.isWorking
                )
            }
        }

        func isWorkingDate(_ date: Date, projectCalendar: ProjectCalendar?) -> Bool {
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)
            let ranges = exceptionRanges(for: projectCalendar)
            for (rangeStart, rangeEnd, isWorking) in ranges where day >= rangeStart && day <= rangeEnd {
                return isWorking
            }
            if let projectCalendar {
                return projectCalendar.resolvedIsWorkingDay(weekday: weekday, calendarsByID: calendarsByID)
            }
            return weekday >= 2 && weekday <= 6
        }

        func nextWorkingDay(onOrAfter date: Date, projectCalendar: ProjectCalendar?) -> Date {
            var current = calendar.startOfDay(for: date)
            while !isWorkingDate(current, projectCalendar: projectCalendar) {
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
            return current
        }

        func previousWorkingDay(onOrBefore date: Date, projectCalendar: ProjectCalendar?) -> Date {
            var current = calendar.startOfDay(for: date)
            while !isWorkingDate(current, projectCalendar: projectCalendar) {
                current = calendar.date(byAdding: .day, value: -1, to: current) ?? current
            }
            return current
        }

        func shiftWorkingDays(from date: Date, by delta: Int, projectCalendar: ProjectCalendar?) -> Date {
            if delta == 0 {
                return delta >= 0
                    ? nextWorkingDay(onOrAfter: date, projectCalendar: projectCalendar)
                    : previousWorkingDay(onOrBefore: date, projectCalendar: projectCalendar)
            }

            var current = delta > 0
                ? nextWorkingDay(onOrAfter: date, projectCalendar: projectCalendar)
                : previousWorkingDay(onOrBefore: date, projectCalendar: projectCalendar)
            var remaining = abs(delta)

            while remaining > 0 {
                current = calendar.date(byAdding: .day, value: delta > 0 ? 1 : -1, to: current) ?? current
                if isWorkingDate(current, projectCalendar: projectCalendar) {
                    remaining -= 1
                }
            }

            return current
        }

        func addWorkingSpan(start: Date, durationDays: Int, projectCalendar: ProjectCalendar?) -> Date {
            guard durationDays > 1 else {
                return nextWorkingDay(onOrAfter: start, projectCalendar: projectCalendar)
            }
            return shiftWorkingDays(
                from: nextWorkingDay(onOrAfter: start, projectCalendar: projectCalendar),
                by: durationDays - 1,
                projectCalendar: projectCalendar
            )
        }

        func workingDaySpan(from start: Date, to finish: Date, projectCalendar: ProjectCalendar?) -> Int {
            let normalizedStart = calendar.startOfDay(for: min(start, finish))
            let normalizedFinish = calendar.startOfDay(for: max(start, finish))
            var current = normalizedStart
            var count = 0

            while current <= normalizedFinish {
                if isWorkingDate(current, projectCalendar: projectCalendar) {
                    count += 1
                }
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? normalizedFinish
            }

            return max(1, count)
        }

        func schedulingFallback(for task: NativePlanTask) -> NativePlanTask {
            var normalized = task
            normalized.startDate = calendar.startOfDay(for: normalized.startDate)
            normalized.finishDate = normalized.isMilestone
                ? normalized.startDate
                : max(normalized.startDate, calendar.startOfDay(for: normalized.finishDate))
            normalized.durationDays = normalized.isMilestone
                ? 1
                : max(1, workingDaySpan(
                    from: normalized.startDate,
                    to: normalized.finishDate,
                    projectCalendar: effectiveCalendar(for: normalized)
                ))
            return normalized
        }

        func scheduledTask(taskID: Int) -> NativePlanTask {
            if let cached = scheduledByID[taskID] {
                return cached
            }

            guard let original = originalByID[taskID] else {
                return plan.makeTask(name: "Missing Task")
            }

            if schedulingStack.contains(taskID) {
                return schedulingFallback(for: original)
            }

            schedulingStack.insert(taskID)
            let childIDs = childIDsByParentID[taskID] ?? []
            let scheduled: NativePlanTask

            if !childIDs.isEmpty {
                let childTasks = childIDs.map(scheduledTask(taskID:))
                var summary = original
                let summaryStart = childTasks.map(\.startDate).min() ?? calendar.startOfDay(for: original.startDate)
                let summaryFinish = childTasks.map(\.finishDate).max() ?? summaryStart
                summary.startDate = summaryStart
                summary.finishDate = summaryFinish
                summary.durationDays = workingDaySpan(
                    from: summaryStart,
                    to: summaryFinish,
                    projectCalendar: effectiveCalendar(for: summary)
                )
                summary.isMilestone = false
                scheduled = summary
            } else if original.manuallyScheduled {
                scheduled = schedulingFallback(for: original)
            } else {
                var autoTask = original
                let projectCalendar = effectiveCalendar(for: autoTask)
                let seededStart = nextWorkingDay(onOrAfter: autoTask.startDate, projectCalendar: projectCalendar)
                var scheduledStart = seededStart

                for predecessorID in autoTask.predecessorTaskIDs {
                    let predecessorTask = scheduledTask(taskID: predecessorID)
                    let predecessorCalendar = effectiveCalendar(for: predecessorTask)
                    let earliestStart = shiftWorkingDays(
                        from: predecessorTask.finishDate,
                        by: 1,
                        projectCalendar: predecessorCalendar
                    )
                    if earliestStart > scheduledStart {
                        scheduledStart = earliestStart
                    }
                }

                let constraintType = normalizedConstraintType(autoTask.constraintType)
                let constraintDate = autoTask.constraintDate.map { calendar.startOfDay(for: $0) }

                if let constraintDate {
                    switch constraintType {
                    case "MSO":
                        scheduledStart = nextWorkingDay(onOrAfter: constraintDate, projectCalendar: projectCalendar)
                    case "SNET":
                        let constrainedStart = nextWorkingDay(onOrAfter: constraintDate, projectCalendar: projectCalendar)
                        if constrainedStart > scheduledStart {
                            scheduledStart = constrainedStart
                        }
                    default:
                        break
                    }
                }

                autoTask.startDate = scheduledStart
                var scheduledFinish = autoTask.isMilestone
                    ? scheduledStart
                    : addWorkingSpan(
                        start: scheduledStart,
                        durationDays: autoTask.normalizedDurationDays,
                        projectCalendar: projectCalendar
                    )

                if let constraintDate {
                    switch constraintType {
                    case "MFO":
                        scheduledFinish = nextWorkingDay(onOrAfter: constraintDate, projectCalendar: projectCalendar)
                        autoTask.startDate = autoTask.isMilestone
                            ? scheduledFinish
                            : shiftWorkingDays(
                                from: scheduledFinish,
                                by: -(max(1, autoTask.durationDays) - 1),
                                projectCalendar: projectCalendar
                            )
                    case "FNET":
                        let constrainedFinish = nextWorkingDay(onOrAfter: constraintDate, projectCalendar: projectCalendar)
                        if constrainedFinish > scheduledFinish {
                            scheduledFinish = constrainedFinish
                            autoTask.startDate = autoTask.isMilestone
                                ? scheduledFinish
                                : shiftWorkingDays(
                                    from: scheduledFinish,
                                    by: -(max(1, autoTask.durationDays) - 1),
                                    projectCalendar: projectCalendar
                                )
                        }
                    default:
                        break
                    }
                }

                autoTask.finishDate = scheduledFinish
                autoTask.durationDays = autoTask.isMilestone ? 1 : max(1, autoTask.durationDays)
                scheduled = autoTask
            }

            schedulingStack.remove(taskID)
            scheduledByID[taskID] = scheduled
            return scheduled
        }

        let scheduledTasks = plan.tasks.map { scheduledTask(taskID: $0.id) }
        let projectFinish = scheduledTasks.map(\.finishDate).max() ?? calendar.startOfDay(for: plan.statusDate)

        var latestFinishByID: [Int: Date] = [:]
        var backwardStack: Set<Int> = []

        func latestStart(taskID: Int) -> Date {
            let task = scheduledByID[taskID] ?? scheduledTask(taskID: taskID)
            let projectCalendar = effectiveCalendar(for: task)
            let latestFinish = latestFinishDate(taskID: taskID)
            if task.isMilestone {
                return latestFinish
            }
            return shiftWorkingDays(
                from: latestFinish,
                by: -(max(1, task.durationDays) - 1),
                projectCalendar: projectCalendar
            )
        }

        func latestFinishDate(taskID: Int) -> Date {
            if let cached = latestFinishByID[taskID] {
                return cached
            }

            if backwardStack.contains(taskID) {
                return scheduledByID[taskID]?.finishDate ?? projectFinish
            }

            backwardStack.insert(taskID)
            let task = scheduledByID[taskID] ?? scheduledTask(taskID: taskID)
            let projectCalendar = effectiveCalendar(for: task)
            let successors = successorMap[taskID] ?? []
            let latestFinish: Date

            if successors.isEmpty {
                latestFinish = projectFinish
            } else {
                let successorLimits = successors.map { successorID in
                    previousWorkingDay(
                        onOrBefore: latestStart(taskID: successorID),
                        projectCalendar: projectCalendar
                    )
                }
                latestFinish = successorLimits.min() ?? projectFinish
            }

            let boundedFinish = max(task.finishDate, latestFinish)
            latestFinishByID[taskID] = boundedFinish
            backwardStack.remove(taskID)
            return boundedFinish
        }

        func workingDayDelta(from start: Date, to end: Date, projectCalendar: ProjectCalendar?) -> Int {
            let normalizedStart = calendar.startOfDay(for: start)
            let normalizedEnd = calendar.startOfDay(for: end)
            if normalizedStart == normalizedEnd {
                return 0
            }

            let direction = normalizedStart < normalizedEnd ? 1 : -1
            var current = normalizedStart
            var count = 0

            while current != normalizedEnd {
                current = calendar.date(byAdding: .day, value: direction, to: current) ?? normalizedEnd
                if isWorkingDate(current, projectCalendar: projectCalendar) {
                    count += direction
                }
            }

            return count
        }

        var slackByTaskID: [Int: Int] = [:]
        var criticalTaskIDs: Set<Int> = []

        for task in scheduledTasks {
            let taskCalendar = effectiveCalendar(for: task)
            let lateStart = latestStart(taskID: task.id)
            let slackDays = workingDayDelta(from: task.startDate, to: lateStart, projectCalendar: taskCalendar)
            let slackSeconds = max(0, slackDays) * 8 * 3600
            slackByTaskID[task.id] = slackSeconds
            if slackDays <= 0 {
                criticalTaskIDs.insert(task.id)
            }
        }

        for task in scheduledTasks.reversed() {
            if let childIDs = childIDsByParentID[task.id], !childIDs.isEmpty,
               childIDs.contains(where: criticalTaskIDs.contains) {
                criticalTaskIDs.insert(task.id)
                slackByTaskID[task.id] = 0
            }
        }

        return PlanScheduleResult(
            tasks: scheduledTasks,
            criticalTaskIDs: criticalTaskIDs,
            totalSlackSecondsByTaskID: slackByTaskID
        )
    }
}

private func normalizedConstraintType(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: " ", with: "")

    switch normalized {
    case "", "ASAP", "AS SOON AS POSSIBLE":
        return "ASAP"
    case "SNET", "STARTNOEARLIERTHAN":
        return "SNET"
    case "FNET", "FINISHNOEARLIERTHAN":
        return "FNET"
    case "MSO", "MUSTSTARTON":
        return "MSO"
    case "MFO", "MUSTFINISHON":
        return "MFO"
    default:
        return normalized
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
