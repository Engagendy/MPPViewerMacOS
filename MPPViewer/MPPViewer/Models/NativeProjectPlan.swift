import Foundation
import SwiftData
import CoreData

private extension KeyedDecodingContainer {
    func decodeLossyUUIDIfPresent(forKey key: Key) -> UUID? {
        if let uuid = try? decodeIfPresent(UUID.self, forKey: key) {
            return uuid
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return UUID(uuidString: string)
        }
        return nil
    }
}

@globalActor
actor PlanActor {
    static let shared = PlanActor()
}

enum NativePlanFormatError: LocalizedError {
    case unsupportedSchemaVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(found, supported):
            return "This plan was saved by a newer version of Planroom (format v\(found); this app supports up to v\(supported)). Update Planroom to open it."
        }
    }
}

struct NativeProjectPlan: Codable, Hashable {
    /// Bump when the .mppplan format changes in a way older app versions cannot read.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var portfolioID: UUID
    var title: String
    var manager: String
    var company: String
    var statusDate: Date
    var portfolioWorkspace: String?
    var portfolioProgram: String?
    var portfolioSponsor: String?
    var portfolioStage: String?
    var portfolioHealth: String?
    var portfolioPriorityBand: String?
    var portfolioApprovalState: String?
    var portfolioStrategicAlignment: Int?
    var portfolioRiskScore: Int?
    var portfolioObjective: String?
    var portfolioReviewDate: Date?
    var portfolioReviewCadenceDays: Int?
    var portfolioArchiveReason: String?
    var defaultCalendarUniqueID: Int?
    var tasks: [NativePlanTask]
    var resources: [NativePlanResource]
    var assignments: [NativePlanAssignment]
    var calendars: [NativePlanCalendar]
    var boardColumns: [String]
    var workflowColumns: [NativeBoardWorkflowColumn]
    var typeWorkflowOverrides: [NativeBoardTypeWorkflow]
    var sprints: [NativePlanSprint]
    var statusSnapshots: [NativeStatusSnapshot]
    /// Visual-only holidays / observances (e.g. Ramadan) shown as timeline bands.
    /// Never consulted by the scheduler.
    var timelineEvents: [PlanTimelineEvent]
    /// Visual-only per-resource leave shown as bands on that resource's rows.
    /// Never consulted by the scheduler.
    var resourceLeaves: [PlanResourceLeave]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case portfolioID
        case title
        case manager
        case company
        case statusDate
        case portfolioWorkspace
        case portfolioProgram
        case portfolioSponsor
        case portfolioStage
        case portfolioHealth
        case portfolioPriorityBand
        case portfolioApprovalState
        case portfolioStrategicAlignment
        case portfolioRiskScore
        case portfolioObjective
        case portfolioReviewDate
        case portfolioReviewCadenceDays
        case portfolioArchiveReason
        case defaultCalendarUniqueID
        case tasks
        case resources
        case assignments
        case calendars
        case boardColumns
        case workflowColumns
        case typeWorkflowOverrides
        case sprints
        case statusSnapshots
        case timelineEvents
        case resourceLeaves
    }

    static let defaultBoardColumns = ["Backlog", "Ready", "In Progress", "Review", "Done"]

    static func empty() -> NativeProjectPlan {
        let standardCalendar = NativePlanCalendar.standard(id: 1)
        return NativeProjectPlan(
            portfolioID: UUID(),
            title: "Untitled Plan",
            manager: "",
            company: "",
            statusDate: Calendar.current.startOfDay(for: Date()),
            portfolioWorkspace: "Default Workspace",
            portfolioProgram: nil,
            portfolioSponsor: nil,
            portfolioStage: "Planning",
            portfolioHealth: "Green",
            portfolioPriorityBand: "Medium",
            portfolioApprovalState: "Proposed",
            portfolioStrategicAlignment: 50,
            portfolioRiskScore: 25,
            portfolioObjective: nil,
            portfolioReviewDate: nil,
            portfolioReviewCadenceDays: 14,
            portfolioArchiveReason: nil,
            defaultCalendarUniqueID: standardCalendar.id,
            tasks: [],
            resources: [],
            assignments: [],
            calendars: [standardCalendar],
            boardColumns: defaultBoardColumns,
            workflowColumns: defaultWorkflowColumns(for: defaultBoardColumns),
            typeWorkflowOverrides: defaultTypeWorkflowOverrides(for: defaultBoardColumns),
            sprints: [],
            statusSnapshots: []
        )
    }

    init(
        portfolioID: UUID,
        title: String,
        manager: String,
        company: String,
        statusDate: Date,
        portfolioWorkspace: String? = nil,
        portfolioProgram: String? = nil,
        portfolioSponsor: String? = nil,
        portfolioStage: String? = nil,
        portfolioHealth: String? = nil,
        portfolioPriorityBand: String? = nil,
        portfolioApprovalState: String? = nil,
        portfolioStrategicAlignment: Int? = nil,
        portfolioRiskScore: Int? = nil,
        portfolioObjective: String? = nil,
        portfolioReviewDate: Date? = nil,
        portfolioReviewCadenceDays: Int? = nil,
        portfolioArchiveReason: String? = nil,
        defaultCalendarUniqueID: Int?,
        tasks: [NativePlanTask],
        resources: [NativePlanResource],
        assignments: [NativePlanAssignment],
        calendars: [NativePlanCalendar],
        boardColumns: [String],
        workflowColumns: [NativeBoardWorkflowColumn],
        typeWorkflowOverrides: [NativeBoardTypeWorkflow],
        sprints: [NativePlanSprint],
        statusSnapshots: [NativeStatusSnapshot],
        timelineEvents: [PlanTimelineEvent] = [],
        resourceLeaves: [PlanResourceLeave] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.portfolioID = portfolioID
        self.title = title
        self.manager = manager
        self.company = company
        self.statusDate = statusDate
        self.portfolioWorkspace = portfolioWorkspace
        self.portfolioProgram = portfolioProgram
        self.portfolioSponsor = portfolioSponsor
        self.portfolioStage = portfolioStage
        self.portfolioHealth = portfolioHealth
        self.portfolioPriorityBand = portfolioPriorityBand
        self.portfolioApprovalState = portfolioApprovalState
        self.portfolioStrategicAlignment = portfolioStrategicAlignment
        self.portfolioRiskScore = portfolioRiskScore
        self.portfolioObjective = portfolioObjective
        self.portfolioReviewDate = portfolioReviewDate
        self.portfolioReviewCadenceDays = portfolioReviewCadenceDays
        self.portfolioArchiveReason = portfolioArchiveReason
        self.defaultCalendarUniqueID = defaultCalendarUniqueID
        self.tasks = tasks
        self.resources = resources
        self.assignments = assignments
        self.calendars = calendars
        let normalizedBoardColumns = Self.normalizedBoardColumns(boardColumns)
        let synchronizedStorage = Self.synchronizedWorkflowStorage(
            boardColumns: normalizedBoardColumns,
            workflowColumns: workflowColumns,
            typeWorkflowOverrides: typeWorkflowOverrides
        )
        self.workflowColumns = synchronizedStorage.workflowColumns
        self.boardColumns = self.workflowColumns.map(\.name)
        self.typeWorkflowOverrides = synchronizedStorage.typeWorkflowOverrides
        self.sprints = sprints
        self.statusSnapshots = statusSnapshots
        self.timelineEvents = timelineEvents
        self.resourceLeaves = resourceLeaves
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Files written before versioning have no schemaVersion field and are treated as v1.
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard decodedVersion <= Self.currentSchemaVersion else {
            throw NativePlanFormatError.unsupportedSchemaVersion(
                found: decodedVersion,
                supported: Self.currentSchemaVersion
            )
        }
        schemaVersion = Self.currentSchemaVersion
        portfolioID = container.decodeLossyUUIDIfPresent(forKey: .portfolioID) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Plan"
        manager = try container.decodeIfPresent(String.self, forKey: .manager) ?? ""
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        statusDate = try container.decodeIfPresent(Date.self, forKey: .statusDate) ?? Calendar.current.startOfDay(for: Date())
        portfolioWorkspace = try container.decodeIfPresent(String.self, forKey: .portfolioWorkspace)
        portfolioProgram = try container.decodeIfPresent(String.self, forKey: .portfolioProgram)
        portfolioSponsor = try container.decodeIfPresent(String.self, forKey: .portfolioSponsor)
        portfolioStage = try container.decodeIfPresent(String.self, forKey: .portfolioStage)
        portfolioHealth = try container.decodeIfPresent(String.self, forKey: .portfolioHealth)
        portfolioPriorityBand = try container.decodeIfPresent(String.self, forKey: .portfolioPriorityBand)
        portfolioApprovalState = try container.decodeIfPresent(String.self, forKey: .portfolioApprovalState)
        portfolioStrategicAlignment = try container.decodeIfPresent(Int.self, forKey: .portfolioStrategicAlignment)
        portfolioRiskScore = try container.decodeIfPresent(Int.self, forKey: .portfolioRiskScore)
        portfolioObjective = try container.decodeIfPresent(String.self, forKey: .portfolioObjective)
        portfolioReviewDate = try container.decodeIfPresent(Date.self, forKey: .portfolioReviewDate)
        portfolioReviewCadenceDays = try container.decodeIfPresent(Int.self, forKey: .portfolioReviewCadenceDays)
        portfolioArchiveReason = try container.decodeIfPresent(String.self, forKey: .portfolioArchiveReason)
        defaultCalendarUniqueID = try container.decodeIfPresent(Int.self, forKey: .defaultCalendarUniqueID)
        tasks = try container.decodeIfPresent([NativePlanTask].self, forKey: .tasks) ?? []
        resources = try container.decodeIfPresent([NativePlanResource].self, forKey: .resources) ?? []
        assignments = try container.decodeIfPresent([NativePlanAssignment].self, forKey: .assignments) ?? []
        calendars = try container.decodeIfPresent([NativePlanCalendar].self, forKey: .calendars) ?? []
        let decodedBoardColumns = try container.decodeIfPresent([String].self, forKey: .boardColumns) ?? Self.defaultBoardColumns
        let decodedWorkflowColumns = try container.decodeIfPresent([NativeBoardWorkflowColumn].self, forKey: .workflowColumns) ?? []
        let decodedTypeWorkflowOverrides = try container.decodeIfPresent([NativeBoardTypeWorkflow].self, forKey: .typeWorkflowOverrides)
        let synchronizedStorage = Self.synchronizedWorkflowStorage(
            boardColumns: Self.normalizedBoardColumns(decodedBoardColumns),
            workflowColumns: decodedWorkflowColumns,
            typeWorkflowOverrides: decodedTypeWorkflowOverrides ?? Self.defaultTypeWorkflowOverrides(for: decodedBoardColumns)
        )
        workflowColumns = synchronizedStorage.workflowColumns
        boardColumns = workflowColumns.map(\.name)
        typeWorkflowOverrides = synchronizedStorage.typeWorkflowOverrides
        sprints = try container.decodeIfPresent([NativePlanSprint].self, forKey: .sprints) ?? []
        statusSnapshots = try container.decodeIfPresent([NativeStatusSnapshot].self, forKey: .statusSnapshots) ?? []
        timelineEvents = try container.decodeIfPresent([PlanTimelineEvent].self, forKey: .timelineEvents) ?? []
        resourceLeaves = try container.decodeIfPresent([PlanResourceLeave].self, forKey: .resourceLeaves) ?? []
    }

    static func normalizedBoardColumns(_ columns: [String]) -> [String] {
        var seen: Set<String> = []
        let normalized = columns.compactMap { column -> String? in
            let trimmed = column.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        return normalized.isEmpty ? defaultBoardColumns : normalized
    }

    static func defaultWIPLimit(for lane: String) -> Int? {
        switch lane.lowercased() {
        case "ready":
            return 12
        case "in progress":
            return 8
        case "review":
            return 6
        default:
            return nil
        }
    }

    static func defaultWorkflowColumns(for boardColumns: [String]) -> [NativeBoardWorkflowColumn] {
        defaultWorkflowColumns(for: boardColumns, itemType: nil)
    }

    static func defaultWorkflowColumns(for boardColumns: [String], itemType: String?) -> [NativeBoardWorkflowColumn] {
        let normalized = normalizedBoardColumns(boardColumns)
        let normalizedType = itemType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return normalized.enumerated().map { index, column in
            var allowed: [String] = []
            switch normalizedType {
            case "bug":
                allowed = bugDefaultTransitions(for: column, columns: normalized)
            case "milestone":
                allowed = milestoneDefaultTransitions(for: column, columns: normalized)
            default:
                if index > 0 {
                    allowed.append(normalized[index - 1])
                }
                if index + 1 < normalized.count {
                    allowed.append(normalized[index + 1])
                }
            }
            return NativeBoardWorkflowColumn(
                name: column,
                wipLimit: defaultWIPLimit(for: column),
                allowedTransitions: allowed
            )
        }
    }

    static func defaultTypeWorkflowOverrides(for boardColumns: [String]) -> [NativeBoardTypeWorkflow] {
        [
            NativeBoardTypeWorkflow(
                itemType: "Bug",
                columns: defaultWorkflowColumns(for: boardColumns, itemType: "Bug")
            ),
            NativeBoardTypeWorkflow(
                itemType: "Milestone",
                columns: defaultWorkflowColumns(for: boardColumns, itemType: "Milestone")
            )
        ]
    }

    static func synchronizedWorkflowColumns(
        boardColumns: [String],
        workflowColumns: [NativeBoardWorkflowColumn]
    ) -> [NativeBoardWorkflowColumn] {
        let normalizedBoardColumns = normalizedBoardColumns(boardColumns)
        guard !workflowColumns.isEmpty else {
            return defaultWorkflowColumns(for: normalizedBoardColumns)
        }

        var existingByName: [String: NativeBoardWorkflowColumn] = [:]
        for workflowColumn in workflowColumns {
            let key = workflowColumn.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            existingByName[key] = workflowColumn
        }

        var validNamesByLower: [String: String] = [:]
        for column in normalizedBoardColumns {
            validNamesByLower[column.lowercased()] = column
        }

        return normalizedBoardColumns.enumerated().map { index, column in
            var workflowColumn = existingByName[column.lowercased()]
                ?? NativeBoardWorkflowColumn(
                    name: column,
                    wipLimit: defaultWIPLimit(for: column),
                    allowedTransitions: []
                )
            workflowColumn.name = column
            workflowColumn.wipLimit = workflowColumn.wipLimit.flatMap { $0 > 0 ? $0 : nil }

            var seenTransitions: Set<String> = []
            let synchronizedTransitions = workflowColumn.allowedTransitions.compactMap { rawTransition -> String? in
                let trimmed = rawTransition.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let canonical = validNamesByLower[trimmed.lowercased()], canonical.compare(column, options: .caseInsensitive) != .orderedSame else {
                    return nil
                }
                let key = canonical.lowercased()
                guard seenTransitions.insert(key).inserted else { return nil }
                return canonical
            }

            if synchronizedTransitions.isEmpty, normalizedBoardColumns.count > 1, existingByName[column.lowercased()] == nil {
                var fallback: [String] = []
                if index > 0 {
                    fallback.append(normalizedBoardColumns[index - 1])
                }
                if index + 1 < normalizedBoardColumns.count {
                    fallback.append(normalizedBoardColumns[index + 1])
                }
                workflowColumn.allowedTransitions = fallback
            } else {
                workflowColumn.allowedTransitions = synchronizedTransitions
            }
            return workflowColumn
        }
    }

    static func synchronizedTypeWorkflowOverrides(
        boardColumns: [String],
        overrides: [NativeBoardTypeWorkflow]
    ) -> [NativeBoardTypeWorkflow] {
        var seenTypes: Set<String> = []
        return overrides.compactMap { override in
            let normalizedType = override.itemType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedType.isEmpty else { return nil }
            let key = normalizedType.lowercased()
            guard seenTypes.insert(key).inserted else { return nil }
            return NativeBoardTypeWorkflow(
                id: override.id,
                itemType: normalizedType,
                columns: synchronizedWorkflowColumns(
                    boardColumns: boardColumns,
                    workflowColumns: override.columns
                )
            )
        }
    }

    static func synchronizedWorkflowStorage(
        boardColumns: [String],
        workflowColumns: [NativeBoardWorkflowColumn],
        typeWorkflowOverrides: [NativeBoardTypeWorkflow]
    ) -> (workflowColumns: [NativeBoardWorkflowColumn], typeWorkflowOverrides: [NativeBoardTypeWorkflow]) {
        let normalizedBoardColumns = normalizedBoardColumns(boardColumns)
        var usedWorkflowColumnIDs: Set<UUID> = []
        let sharedWorkflow = synchronizedWorkflowColumns(
            boardColumns: normalizedBoardColumns,
            workflowColumns: workflowColumns
        ).map { column in
            makeWorkflowColumnStorageSafe(column, usedIDs: &usedWorkflowColumnIDs)
        }

        var usedOverrideIDs: Set<UUID> = []
        let overrides = synchronizedTypeWorkflowOverrides(
            boardColumns: normalizedBoardColumns,
            overrides: typeWorkflowOverrides
        ).map { override in
            let overrideID = makeUniqueStorageID(override.id, usedIDs: &usedOverrideIDs)
            let columns = synchronizedWorkflowColumns(
                boardColumns: normalizedBoardColumns,
                workflowColumns: override.columns
            ).map { column in
                makeWorkflowColumnStorageSafe(column, usedIDs: &usedWorkflowColumnIDs)
            }
            return NativeBoardTypeWorkflow(
                id: overrideID,
                itemType: override.itemType,
                columns: columns
            )
        }

        return (sharedWorkflow, overrides)
    }

    private static func makeWorkflowColumnStorageSafe(
        _ column: NativeBoardWorkflowColumn,
        usedIDs: inout Set<UUID>
    ) -> NativeBoardWorkflowColumn {
        NativeBoardWorkflowColumn(
            id: makeUniqueStorageID(column.id, usedIDs: &usedIDs),
            name: column.name,
            wipLimit: column.wipLimit,
            allowedTransitions: column.allowedTransitions
        )
    }

    private static func makeUniqueStorageID(_ candidate: UUID, usedIDs: inout Set<UUID>) -> UUID {
        if usedIDs.insert(candidate).inserted {
            return candidate
        }

        var fallback = UUID()
        while !usedIDs.insert(fallback).inserted {
            fallback = UUID()
        }
        return fallback
    }

    private static func bugDefaultTransitions(for column: String, columns: [String]) -> [String] {
        let lowerColumns = columns.map { $0.lowercased() }
        guard let currentIndex = lowerColumns.firstIndex(of: column.lowercased()) else { return [] }

        if column.compare("Review", options: .caseInsensitive) == .orderedSame {
            return []
        }

        let reviewIndex = lowerColumns.firstIndex(of: "review")
        let previousIndex = currentIndex > 0 ? currentIndex - 1 : nil
        let nextIndex = currentIndex + 1 < columns.count ? currentIndex + 1 : nil

        var transitions: [String] = []
        if let previousIndex, previousIndex != reviewIndex {
            transitions.append(columns[previousIndex])
        }
        if let nextIndex, nextIndex != reviewIndex {
            transitions.append(columns[nextIndex])
        }
        return transitions
    }

    private static func milestoneDefaultTransitions(for column: String, columns: [String]) -> [String] {
        let lowerColumns = columns.map { $0.lowercased() }
        guard let backlog = lowerColumns.firstIndex(of: "backlog"),
              let ready = lowerColumns.firstIndex(of: "ready"),
              let done = lowerColumns.firstIndex(of: "done") else {
            return defaultWorkflowColumns(for: columns).first(where: { $0.name.compare(column, options: .caseInsensitive) == .orderedSame })?.allowedTransitions ?? []
        }

        switch column.lowercased() {
        case columns[backlog].lowercased():
            return [columns[ready]]
        case columns[ready].lowercased():
            return [columns[backlog], columns[done]]
        case columns[done].lowercased():
            return [columns[ready]]
        default:
            return []
        }
    }

    static func decode(from data: Data) throws -> NativeProjectPlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NativeProjectPlan.self, from: data)
            .normalizedResourceIDsForAssignmentCompatibility()
    }

    init(projectModel: ProjectModel) {
        let calendar = Calendar.current
        let projectsTasks = projectModel.tasks
        let projectResources = projectModel.resources
        let projectAssignments = projectModel.assignments
        let projectCalendars = projectModel.calendars

        func parsedDate(_ raw: String?) -> Date? {
            raw.flatMap(DateFormatting.parseMPXJDate).map { calendar.startOfDay(for: $0) }
        }

        func durationDays(for task: ProjectTask, start: Date, finish: Date) -> Int {
            if task.milestone == true { return 1 }
            if let duration = task.duration, duration > 0 {
                return max(1, Int(ceil(Double(duration) / (8.0 * 3600.0))))
            }
            let daySpan = (calendar.dateComponents([.day], from: start, to: finish).day ?? 0) + 1
            return max(1, daySpan)
        }

        func boardStatus(for task: ProjectTask) -> String {
            if (task.percentComplete ?? 0) >= 100 { return "Done" }
            if (task.percentComplete ?? 0) > 0 { return "In Progress" }
            return "Backlog"
        }

        func agileType(for task: ProjectTask) -> String {
            if let raw = task.type?.nonEmpty { return raw }
            if task.summary == true { return "Epic" }
            if task.milestone == true { return "Milestone" }
            return "Story"
        }

        func nativeCalendarDay(
            from dayInfo: CalendarDayInfo?,
            fallback: NativeCalendarDay
        ) -> NativeCalendarDay {
            guard let dayInfo else { return fallback }
            if dayInfo.isDefault {
                return .inherited()
            }
            if dayInfo.isWorking {
                let firstRange = dayInfo.hours?.first
                return .workingDay(
                    from: firstRange?.from?.nonEmpty ?? "08:00",
                    to: firstRange?.to?.nonEmpty ?? "17:00"
                )
            }
            return .nonWorking()
        }

        let statusDate = projectModel.properties.statusDate.flatMap(DateFormatting.parseMPXJDate)
            ?? calendar.startOfDay(for: Date())
        let defaultCalendarUniqueID = projectModel.properties.defaultCalendarUniqueId
            ?? projectCalendars.first?.uniqueID
            ?? 1

        let nativeTasks = projectsTasks.map { task in
            let start = task.startDate ?? statusDate
            let finish = task.finishDate ?? start
            let normalizedStart = calendar.startOfDay(for: min(start, finish))
            let normalizedFinish = calendar.startOfDay(for: max(start, finish))

            return NativePlanTask(
                id: task.id ?? task.uniqueID,
                name: task.displayName,
                startDate: parsedDate(task.start) ?? normalizedStart,
                finishDate: parsedDate(task.finish) ?? normalizedFinish,
                durationDays: durationDays(for: task, start: normalizedStart, finish: normalizedFinish),
                outlineLevel: max(1, task.outlineLevel ?? 1),
                isMilestone: task.milestone ?? false,
                manuallyScheduled: false,
                percentComplete: max(0, task.percentComplete ?? 0),
                priority: task.priority ?? 500,
                notes: task.notes ?? "",
                predecessorTaskIDs: task.predecessors?.compactMap { $0.taskUniqueID }.sorted() ?? [],
                baselineStartDate: parsedDate(task.baselineStart),
                baselineFinishDate: parsedDate(task.baselineFinish),
                baselineDurationDays: task.baselineDuration.map { max(1, Int(ceil(Double($0) / (8.0 * 3600.0)))) },
                fixedCost: max(0, task.cost ?? 0),
                baselineCost: task.baselineCost,
                actualCost: task.actualCost,
                actualStartDate: parsedDate(task.actualStart),
                actualFinishDate: parsedDate(task.actualFinish),
                constraintType: task.constraintType,
                constraintDate: parsedDate(task.constraintDate),
                calendarUniqueID: nil,
                isActive: task.active ?? true,
                agileType: agileType(for: task),
                boardStatus: boardStatus(for: task),
                storyPoints: nil,
                sprintID: nil,
                epicName: "",
                tags: [],
                uniqueID: UUID(uuidString: task.guid ?? "") ?? UUID()
            )
        }

        let nativeResources = projectResources.map { resource in
            NativePlanResource(
                id: resource.uniqueID ?? resource.id ?? 0,
                name: resource.name?.nonEmpty ?? "Unnamed Resource",
                type: resource.type?.nonEmpty ?? "Work",
                maxUnits: resource.maxUnits ?? 100,
                standardRate: resource.standardRate ?? 0,
                overtimeRate: resource.overtimeRate ?? 0,
                costPerUse: resource.costPerUse ?? 0,
                emailAddress: resource.emailAddress ?? "",
                group: resource.group ?? "",
                initials: resource.initials ?? "",
                notes: resource.notes ?? "",
                calendarUniqueID: resource.calendarUniqueID,
                accrueAt: resource.accrueAt?.nonEmpty ?? "end",
                active: resource.active ?? true,
                uniqueID: UUID(uuidString: resource.guid ?? "") ?? UUID()
            )
        }

        let nativeAssignments = projectAssignments.map { assignment in
            NativePlanAssignment(
                id: assignment.uniqueID ?? assignment.taskUniqueID ?? 0,
                taskID: assignment.taskUniqueID ?? 0,
                resourceID: assignment.resourceUniqueID,
                units: assignment.assignmentUnits ?? 100,
                workSeconds: assignment.work,
                actualWorkSeconds: assignment.actualWork,
                remainingWorkSeconds: assignment.remainingWork,
                overtimeWorkSeconds: nil,
                notes: "",
                uniqueID: UUID(uuidString: assignment.guid ?? "") ?? UUID()
            )
        }

        let nativeCalendars = projectCalendars.isEmpty
            ? [NativePlanCalendar.standard(id: defaultCalendarUniqueID, name: "Standard")]
            : projectCalendars.map { calendarRow in
                let inheritedFallback = calendarRow.parentUniqueID == nil ? nil : NativeCalendarDay.inherited()
                return NativePlanCalendar(
                    id: calendarRow.uniqueID ?? defaultCalendarUniqueID,
                    name: calendarRow.name?.nonEmpty ?? "Calendar",
                    parentUniqueID: calendarRow.parentUniqueID,
                    type: calendarRow.type?.nonEmpty ?? "Standard",
                    personal: calendarRow.personal ?? false,
                    sunday: nativeCalendarDay(from: calendarRow.sunday, fallback: inheritedFallback ?? .nonWorking()),
                    monday: nativeCalendarDay(from: calendarRow.monday, fallback: inheritedFallback ?? .workingDay()),
                    tuesday: nativeCalendarDay(from: calendarRow.tuesday, fallback: inheritedFallback ?? .workingDay()),
                    wednesday: nativeCalendarDay(from: calendarRow.wednesday, fallback: inheritedFallback ?? .workingDay()),
                    thursday: nativeCalendarDay(from: calendarRow.thursday, fallback: inheritedFallback ?? .workingDay()),
                    friday: nativeCalendarDay(from: calendarRow.friday, fallback: inheritedFallback ?? .workingDay()),
                    saturday: nativeCalendarDay(from: calendarRow.saturday, fallback: inheritedFallback ?? .nonWorking()),
                    exceptions: calendarRow.exceptions?.map { exception in
                        NativeCalendarException(
                            name: exception.name?.nonEmpty ?? "Exception",
                            fromDate: exception.fromDate ?? statusDate,
                            toDate: exception.toDate ?? exception.fromDate ?? statusDate,
                            type: exception.type?.nonEmpty ?? "non_working"
                        )
                    } ?? []
                )
            }

        self.init(
            portfolioID: UUID(),
            title: projectModel.properties.projectTitle?.nonEmpty ?? "Imported Project",
            manager: projectModel.properties.manager?.nonEmpty ?? "",
            company: projectModel.properties.company?.nonEmpty ?? "",
            statusDate: statusDate,
            portfolioWorkspace: nil,
            portfolioProgram: nil,
            portfolioSponsor: nil,
            portfolioStage: nil,
            portfolioHealth: nil,
            portfolioPriorityBand: nil,
            portfolioObjective: nil,
            portfolioReviewDate: nil,
            defaultCalendarUniqueID: defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars,
            boardColumns: Self.defaultBoardColumns,
            workflowColumns: Self.defaultWorkflowColumns(for: Self.defaultBoardColumns),
            typeWorkflowOverrides: Self.defaultTypeWorkflowOverrides(for: Self.defaultBoardColumns),
            sprints: [],
            statusSnapshots: []
        )
        self = normalizedResourceIDsForAssignmentCompatibility()
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(normalizedResourceIDsForAssignmentCompatibility())
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

    func nextSprintID() -> Int {
        (sprints.map(\.id).max() ?? 0) + 1
    }

    /// The contiguous block of rows forming `taskID`'s subtree (the task and
    /// every following row with a deeper outline level).
    func taskSubtreeRange(startingAt index: Int) -> Range<Int> {
        let baseLevel = tasks[index].outlineLevel
        var endIndex = index + 1
        while tasks.indices.contains(endIndex), tasks[endIndex].outlineLevel > baseLevel {
            endIndex += 1
        }
        return index ..< endIndex
    }

    /// Moves a task's whole subtree next to an anchor row. Hierarchy is
    /// positional: after the move the subtree's root level is clamped so the
    /// row above it can legally be its parent or sibling, which is what lets
    /// a task hop from one summary into another.
    /// - Returns: true when the plan changed.
    @discardableResult
    mutating func relocateTaskSubtree(taskID: Int, anchorTaskID: Int, placeAfterAnchor: Bool) -> Bool {
        guard taskID != anchorTaskID,
              let sourceIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let sourceRange = taskSubtreeRange(startingAt: sourceIndex)
        guard let anchorIndex = tasks.firstIndex(where: { $0.id == anchorTaskID }),
              !sourceRange.contains(anchorIndex) else { return false }

        var block = Array(tasks[sourceRange])
        tasks.removeSubrange(sourceRange)

        guard let newAnchorIndex = tasks.firstIndex(where: { $0.id == anchorTaskID }) else {
            tasks.insert(contentsOf: block, at: min(sourceRange.lowerBound, tasks.count))
            return false
        }

        let insertionIndex = placeAfterAnchor ? newAnchorIndex + 1 : newAnchorIndex
        let precedingLevel = insertionIndex > 0 ? tasks[insertionIndex - 1].outlineLevel : 0
        let rootLevel = block[0].outlineLevel
        let clampedRootLevel = max(1, min(rootLevel, precedingLevel + 1))
        let levelDelta = clampedRootLevel - rootLevel
        if levelDelta != 0 {
            for index in block.indices {
                block[index].outlineLevel = max(1, block[index].outlineLevel + levelDelta)
            }
        }

        tasks.insert(contentsOf: block, at: insertionIndex)
        return true
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
            isActive: true,
            agileType: "Story",
            boardStatus: "Backlog",
            storyPoints: nil,
            sprintID: nil,
            epicName: "",
            tags: []
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

    func makeSprint(name: String? = nil) -> NativePlanSprint {
        let start = Calendar.current.startOfDay(for: statusDate)
        let finish = Calendar.current.date(byAdding: .day, value: 13, to: start) ?? start
        return NativePlanSprint(
            id: nextSprintID(),
            name: name ?? "Sprint \(nextSprintID())",
            goal: "",
            startDate: start,
            endDate: finish,
            capacityPoints: 20,
            teamName: "",
            state: "Planning"
        )
    }

    mutating func reschedule() {
        tasks = PlanScheduler.scheduleSync(self).tasks
    }

    mutating func reschedule() async {
        tasks = await PlanScheduler.schedule(self).tasks
    }

    /// Incremental reschedule: only the changed tasks, their transitive
    /// successors, and ancestor summaries are recomputed. Pass an empty set
    /// (or use `reschedule()`) after structural changes.
    mutating func reschedule(changedTaskIDs: Set<Int>) async {
        tasks = await PlanScheduler.schedule(
            self,
            changedTaskIDs: changedTaskIDs.isEmpty ? nil : changedTaskIDs
        ).tasks
    }

    mutating func captureBaseline() {
        let scheduledTasks = PlanScheduler.scheduleSync(self).tasks
        let scheduledByID = Dictionary(nonThrowingUniquePairs: scheduledTasks.map { ($0.id, $0) })
        let financialsByTaskID = financialSnapshots(for: scheduledTasks)
        for index in tasks.indices {
            guard let scheduled = scheduledByID[tasks[index].id] else { continue }
            tasks[index].baselineStartDate = scheduled.startDate
            tasks[index].baselineFinishDate = scheduled.finishDate
            tasks[index].baselineDurationDays = scheduled.isMilestone ? 0 : max(1, scheduled.durationDays)
            tasks[index].baselineCost = financialsByTaskID[tasks[index].id]?.plannedCost
        }
    }

    mutating func captureStatusSnapshot(name: String? = nil, notes: String = "") {
        let project = asProjectModel()
        let workTasks = project.tasks.filter { $0.summary != true }
        let metrics = EVMCalculator.projectMetrics(tasks: workTasks, statusDate: statusDate)
        let sprintSnapshots = sprints.map { sprint in
            let sprintTasks = tasks.filter { $0.sprintID == sprint.id && $0.isActive }
            let committedPoints = sprintTasks.reduce(0) { partial, task in
                partial + max(0, task.storyPoints ?? 0)
            }
            let completedPoints = sprintTasks.reduce(0) { partial, task in
                guard (task.percentComplete >= 100) || task.boardStatus == "Done" else { return partial }
                return partial + max(0, task.storyPoints ?? 0)
            }
            return NativeSprintSnapshot(
                sprintID: sprint.id,
                sprintName: sprint.name,
                committedPoints: committedPoints,
                completedPoints: completedPoints
            )
        }

        let snapshot = NativeStatusSnapshot(
            name: name?.nonEmpty ?? "Status \(DateFormatting.simpleDate(statusDate))",
            capturedAt: Date(),
            statusDate: statusDate,
            taskCount: workTasks.count,
            completedTaskCount: workTasks.filter(\.isCompleted).count,
            inProgressTaskCount: workTasks.filter(\.isInProgress).count,
            bac: metrics.bac,
            pv: metrics.pv,
            ev: metrics.ev,
            ac: metrics.ac,
            cpi: metrics.cpi,
            spi: metrics.spi,
            eac: metrics.eac,
            vac: metrics.vac,
            notes: notes,
            sprintSnapshots: sprintSnapshots
        )

        statusSnapshots.append(snapshot)
        statusSnapshots.sort { $0.statusDate < $1.statusDate }
    }

    func asProjectModel(scheduleResult: PlanScheduleResult? = nil) -> ProjectModel {
        if let repairedPlan = resourceIDCompatibilityRepairedPlan() {
            return repairedPlan.asProjectModel(scheduleResult: scheduleResult)
        }

        let scheduleResult = scheduleResult ?? PlanScheduler.scheduleSync(self)
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
                acwp: hierarchy.isSummary ? nil : financials?.actualCost,
                customFields: task.customFields.isEmpty ? nil : task.customFields.mapValues { AnyCodable($0) },
                barColorHex: task.barColorHex
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
            shortApplicationName: "Planroom",
            fullApplicationName: "Planroom"
        )

        let tasksByID: [Int: ProjectTask] = Dictionary(nonThrowingUniquePairs: projectTasks.map { ($0.uniqueID, $0) })
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

    func summaryParentTaskIDs(for sourceTasks: [NativePlanTask]? = nil) -> Set<Int> {
        buildHierarchyMetadata(for: sourceTasks)
            .compactMap { $0.value.isSummary ? $0.key : nil }
            .reduce(into: Set<Int>()) { partialResult, taskID in
                partialResult.insert(taskID)
            }
    }

    private func durationSeconds(startDate: Date, finishDate: Date, calendar: Calendar) -> Int {
        let dayDelta = (calendar.dateComponents([.day], from: startDate, to: finishDate).day ?? 0) + 1
        return max(1, dayDelta) * 8 * 3600
    }

    private func financialSnapshots(for scheduledTasks: [NativePlanTask]) -> [Int: NativeTaskFinancialSnapshot] {
        let resourcesByID = Dictionary(nonThrowingUniquePairs: resources.map { ($0.id, $0) })
        let assignmentsByTaskID = Dictionary(grouping: assignments, by: \.taskID)
        let hierarchyByTaskID = buildHierarchyMetadata(for: scheduledTasks)

        return Dictionary(nonThrowingUniquePairs: scheduledTasks.compactMap { task in
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
    var uniqueID: UUID
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
    var agileType: String
    var boardStatus: String
    var storyPoints: Int?
    var sprintID: Int?
    var epicName: String
    var tags: [String]
    var customFields: [String: String]
    var barColorHex: String?

    enum CodingKeys: String, CodingKey {
        case uniqueID
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
        case agileType
        case boardStatus
        case storyPoints
        case sprintID
        case epicName
        case tags
        case customFields
        case barColorHex
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
        isActive: Bool,
        agileType: String,
        boardStatus: String,
        storyPoints: Int?,
        sprintID: Int?,
        epicName: String,
        tags: [String],
        customFields: [String: String] = [:],
        barColorHex: String? = nil,
        uniqueID: UUID = UUID()
    ) {
        self.uniqueID = uniqueID
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
        self.agileType = agileType.isEmpty ? "Story" : agileType
        self.boardStatus = boardStatus.isEmpty ? "Backlog" : boardStatus
        self.storyPoints = storyPoints
        self.sprintID = sprintID
        self.epicName = epicName
        self.tags = tags
        self.customFields = customFields
        self.barColorHex = barColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueID = container.decodeLossyUUIDIfPresent(forKey: .uniqueID) ?? UUID()
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
        agileType = try container.decodeIfPresent(String.self, forKey: .agileType) ?? "Story"
        boardStatus = try container.decodeIfPresent(String.self, forKey: .boardStatus) ?? "Backlog"
        storyPoints = try container.decodeIfPresent(Int.self, forKey: .storyPoints)
        sprintID = try container.decodeIfPresent(Int.self, forKey: .sprintID)
        epicName = try container.decodeIfPresent(String.self, forKey: .epicName) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        barColorHex = try container.decodeIfPresent(String.self, forKey: .barColorHex)
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
    var uniqueID: UUID
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

    var accrueAtValue: String {
        Self.normalizedAccrueAt(accrueAt)
    }

    private static func normalizedAccrueAt(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "start", "prorated", "end":
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return "end"
        }
    }

    enum CodingKeys: String, CodingKey {
        case uniqueID
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
        active: Bool,
        uniqueID: UUID = UUID()
    ) {
        self.uniqueID = uniqueID
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
        self.accrueAt = Self.normalizedAccrueAt(accrueAt)
        self.active = active
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueID = container.decodeLossyUUIDIfPresent(forKey: .uniqueID) ?? UUID()
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
        accrueAt = Self.normalizedAccrueAt(try container.decodeIfPresent(String.self, forKey: .accrueAt) ?? "end")
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
            guid: uniqueID.uuidString
        )
    }
}

struct NativePlanAssignment: Codable, Identifiable, Hashable {
    var uniqueID: UUID
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
        case uniqueID
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
        notes: String,
        uniqueID: UUID = UUID()
    ) {
        self.uniqueID = uniqueID
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
        uniqueID = container.decodeLossyUUIDIfPresent(forKey: .uniqueID) ?? UUID()
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
            guid: uniqueID.uuidString
        )
    }
}

struct NativePlanSprint: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var goal: String
    var startDate: Date
    var endDate: Date
    var capacityPoints: Int
    var teamName: String
    var state: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case goal
        case startDate
        case endDate
        case capacityPoints
        case teamName
        case state
    }

    init(
        id: Int,
        name: String,
        goal: String,
        startDate: Date,
        endDate: Date,
        capacityPoints: Int,
        teamName: String,
        state: String
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: max(startDate, endDate))
        self.capacityPoints = max(0, capacityPoints)
        self.teamName = teamName
        self.state = state.isEmpty ? "Planning" : state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        startDate = Calendar.current.startOfDay(for: try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date())
        endDate = Calendar.current.startOfDay(for: try container.decodeIfPresent(Date.self, forKey: .endDate) ?? startDate)
        capacityPoints = max(0, try container.decodeIfPresent(Int.self, forKey: .capacityPoints) ?? 0)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "Planning"
    }
}

struct NativeBoardWorkflowColumn: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var wipLimit: Int?
    var allowedTransitions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case wipLimit
        case allowedTransitions
    }

    init(
        id: UUID = UUID(),
        name: String,
        wipLimit: Int? = nil,
        allowedTransitions: [String] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wipLimit = wipLimit.flatMap { $0 > 0 ? $0 : nil }

        var seen: Set<String> = []
        self.allowedTransitions = allowedTransitions.compactMap { transition in
            let trimmed = transition.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID(),
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Backlog",
            wipLimit: try container.decodeIfPresent(Int.self, forKey: .wipLimit),
            allowedTransitions: try container.decodeIfPresent([String].self, forKey: .allowedTransitions) ?? []
        )
    }
}

struct NativeBoardTypeWorkflow: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var itemType: String
    var columns: [NativeBoardWorkflowColumn]

    enum CodingKeys: String, CodingKey {
        case id
        case itemType
        case columns
    }

    init(
        id: UUID = UUID(),
        itemType: String,
        columns: [NativeBoardWorkflowColumn]
    ) {
        self.id = id
        self.itemType = itemType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.columns = columns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID(),
            itemType: try container.decodeIfPresent(String.self, forKey: .itemType) ?? "Task",
            columns: try container.decodeIfPresent([NativeBoardWorkflowColumn].self, forKey: .columns) ?? []
        )
    }
}

struct NativeStatusSnapshot: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var capturedAt: Date
    var statusDate: Date
    var taskCount: Int
    var completedTaskCount: Int
    var inProgressTaskCount: Int
    var bac: Double
    var pv: Double
    var ev: Double
    var ac: Double
    var cpi: Double
    var spi: Double
    var eac: Double
    var vac: Double
    var notes: String
    var sprintSnapshots: [NativeSprintSnapshot]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case capturedAt
        case statusDate
        case taskCount
        case completedTaskCount
        case inProgressTaskCount
        case bac
        case pv
        case ev
        case ac
        case cpi
        case spi
        case eac
        case vac
        case notes
        case sprintSnapshots
    }

    init(
        id: UUID = UUID(),
        name: String,
        capturedAt: Date,
        statusDate: Date,
        taskCount: Int,
        completedTaskCount: Int,
        inProgressTaskCount: Int,
        bac: Double,
        pv: Double,
        ev: Double,
        ac: Double,
        cpi: Double,
        spi: Double,
        eac: Double,
        vac: Double,
        notes: String,
        sprintSnapshots: [NativeSprintSnapshot]
    ) {
        self.id = id
        self.name = name
        self.capturedAt = capturedAt
        self.statusDate = statusDate
        self.taskCount = taskCount
        self.completedTaskCount = completedTaskCount
        self.inProgressTaskCount = inProgressTaskCount
        self.bac = bac
        self.pv = pv
        self.ev = ev
        self.ac = ac
        self.cpi = cpi
        self.spi = spi
        self.eac = eac
        self.vac = vac
        self.notes = notes
        self.sprintSnapshots = sprintSnapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Snapshot"
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
        statusDate = try container.decodeIfPresent(Date.self, forKey: .statusDate) ?? capturedAt
        taskCount = try container.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        completedTaskCount = try container.decodeIfPresent(Int.self, forKey: .completedTaskCount) ?? 0
        inProgressTaskCount = try container.decodeIfPresent(Int.self, forKey: .inProgressTaskCount) ?? 0
        bac = try container.decodeIfPresent(Double.self, forKey: .bac) ?? 0
        pv = try container.decodeIfPresent(Double.self, forKey: .pv) ?? 0
        ev = try container.decodeIfPresent(Double.self, forKey: .ev) ?? 0
        ac = try container.decodeIfPresent(Double.self, forKey: .ac) ?? 0
        cpi = try container.decodeIfPresent(Double.self, forKey: .cpi) ?? 0
        spi = try container.decodeIfPresent(Double.self, forKey: .spi) ?? 0
        eac = try container.decodeIfPresent(Double.self, forKey: .eac) ?? 0
        vac = try container.decodeIfPresent(Double.self, forKey: .vac) ?? 0
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sprintSnapshots = try container.decodeIfPresent([NativeSprintSnapshot].self, forKey: .sprintSnapshots) ?? []
    }
}

struct NativeSprintSnapshot: Codable, Hashable {
    var sprintID: Int
    var sprintName: String
    var committedPoints: Int
    var completedPoints: Int
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

    private var shouldInheritAllWeekdaysFromParent: Bool {
        guard parentUniqueID != nil,
              personal,
              type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "RESOURCE" else {
            return false
        }

        return [sunday, monday, tuesday, wednesday, thursday, friday, saturday]
            .allSatisfy(\.isEmptyNonWorkingDay)
    }

    func normalizedForInheritedResourceCalendar() -> NativePlanCalendar {
        guard shouldInheritAllWeekdaysFromParent else { return self }
        var copy = self
        copy.sunday = .inherited()
        copy.monday = .inherited()
        copy.tuesday = .inherited()
        copy.wednesday = .inherited()
        copy.thursday = .inherited()
        copy.friday = .inherited()
        copy.saturday = .inherited()
        return copy
    }

    func asProjectCalendar() -> ProjectCalendar {
        let calendar = normalizedForInheritedResourceCalendar()
        return ProjectCalendar(
            uniqueID: calendar.id,
            name: calendar.name.nonEmpty,
            parentUniqueID: calendar.parentUniqueID,
            type: calendar.type.nonEmpty,
            personal: calendar.personal,
            sunday: calendar.sunday.asCalendarDayInfo(),
            monday: calendar.monday.asCalendarDayInfo(),
            tuesday: calendar.tuesday.asCalendarDayInfo(),
            wednesday: calendar.wednesday.asCalendarDayInfo(),
            thursday: calendar.thursday.asCalendarDayInfo(),
            friday: calendar.friday.asCalendarDayInfo(),
            saturday: calendar.saturday.asCalendarDayInfo(),
            exceptions: calendar.exceptions.map { $0.asCalendarException() }
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

    static func inherited() -> NativeCalendarDay {
        NativeCalendarDay(type: "default", from: "", to: "")
    }

    static func nonWorking() -> NativeCalendarDay {
        NativeCalendarDay(type: "non_working", from: "", to: "")
    }

    var normalizedType: String {
        type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isWorking: Bool {
        normalizedType == "working"
    }

    var isDefault: Bool {
        normalizedType.isEmpty || normalizedType == "default"
    }

    var isEmptyNonWorkingDay: Bool {
        normalizedType == "non_working"
            && from.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func asCalendarDayInfo() -> CalendarDayInfo {
        if isDefault {
            return CalendarDayInfo(type: "default", hours: nil)
        }

        let workingHours: [CalendarHours]?
        if isWorking,
           let fromValue = from.nonEmpty,
           let toValue = to.nonEmpty {
            workingHours = [CalendarHours(from: fromValue, to: toValue)]
        } else {
            workingHours = nil
        }

        return CalendarDayInfo(
            type: isWorking ? "working" : "non_working",
            hours: workingHours
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Exception"
        fromDate = try container.decodeIfPresent(Date.self, forKey: .fromDate) ?? Date()
        toDate = try container.decodeIfPresent(Date.self, forKey: .toDate) ?? fromDate
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "non_working"
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

/// A visual-only holiday, observance, or event drawn as a band across the
/// timeline. Purely presentational — the scheduler never reads these.
struct PlanTimelineEvent: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case holiday
        case observance
        case event

        var id: String { rawValue }

        var label: String {
            switch self {
            case .holiday: return "Holiday"
            case .observance: return "Observance"
            case .event: return "Event"
            }
        }

        var defaultColorHex: String {
            switch self {
            case .holiday: return "#E5484D"    // red
            case .observance: return "#8E5AD6" // purple
            case .event: return "#2F7DE1"      // blue
            }
        }
    }

    var id: UUID
    var name: String
    var startDate: Date
    var endDate: Date
    var kind: Kind
    /// Optional override; when empty the kind's default color is used.
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        kind: Kind = .holiday,
        colorHex: String = ""
    ) {
        self.id = id
        self.name = name
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        self.kind = kind
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, name, startDate, endDate, kind, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Event"
        let start = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        startDate = Calendar.current.startOfDay(for: start)
        let end = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? start
        endDate = Calendar.current.startOfDay(for: end)
        kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .holiday
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
    }

    var effectiveColorHex: String {
        colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultColorHex
            : colorHex
    }
}

/// A visual-only leave/absence window for a single resource, drawn as a band on
/// that resource's task rows. Purely presentational — the scheduler ignores it.
struct PlanResourceLeave: Codable, Identifiable, Hashable {
    var id: UUID
    var resourceID: Int
    var name: String
    var startDate: Date
    var endDate: Date
    var colorHex: String

    static let defaultColorHex = "#F5A524" // amber

    init(
        id: UUID = UUID(),
        resourceID: Int,
        name: String = "Leave",
        startDate: Date,
        endDate: Date,
        colorHex: String = ""
    ) {
        self.id = id
        self.resourceID = resourceID
        self.name = name
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = Calendar.current.startOfDay(for: endDate)
        self.colorHex = colorHex
    }

    enum CodingKeys: String, CodingKey {
        case id, resourceID, name, startDate, endDate, colorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyUUIDIfPresent(forKey: .id) ?? UUID()
        resourceID = try container.decodeIfPresent(Int.self, forKey: .resourceID) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Leave"
        let start = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        startDate = Calendar.current.startOfDay(for: start)
        let end = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? start
        endDate = Calendar.current.startOfDay(for: end)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
    }

    var effectiveColorHex: String {
        colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultColorHex
            : colorHex
    }
}

private struct TaskHierarchyMetadata {
    let outlineLevel: Int
    let outlineNumber: String
    let parentTaskUniqueID: Int?
    let isSummary: Bool
}

struct PlanScheduleResult {
    let tasks: [NativePlanTask]
    let criticalTaskIDs: Set<Int>
    let totalSlackSecondsByTaskID: [Int: Int]
}

enum PlanScheduler {
    @PlanActor
    static func schedule(_ plan: NativeProjectPlan, changedTaskIDs: Set<Int>? = nil) -> PlanScheduleResult {
        scheduleSync(plan, changedTaskIDs: changedTaskIDs)
    }

    /// Schedules the plan. When `changedTaskIDs` is provided (incremental mode),
    /// tasks outside the affected set — the changed tasks, their transitive
    /// successors, and all ancestor summaries of those — are pre-seeded into the
    /// memo cache with their current (previously scheduled) dates, so the
    /// forward pass only recomputes what an edit could actually move. Structural
    /// changes (insert/delete/reorder/indent) must pass nil for a full pass.
    static func scheduleSync(_ plan: NativeProjectPlan, changedTaskIDs: Set<Int>? = nil) -> PlanScheduleResult {
        guard !plan.tasks.isEmpty else {
            return PlanScheduleResult(tasks: [], criticalTaskIDs: [], totalSlackSecondsByTaskID: [:])
        }

        let calendar = Calendar.current
        let workingDaySearchLimit = 366 * 50
        let hierarchy = plan.buildHierarchyMetadata(for: plan.tasks)
        let originalByID = Dictionary(nonThrowingUniquePairs: plan.tasks.map { ($0.id, $0) })
        let calendarsByID = Dictionary(nonThrowingUniquePairs: plan.calendars.map { ($0.id, $0.asProjectCalendar()) })
        let exceptionRangesByCalendarID: [Int: [(Date, Date, Bool)]] = Dictionary(
            uniqueKeysWithValues: plan.calendars.map { planCalendar in
                let ranges = planCalendar.exceptions.map { exception in
                    (
                        calendar.startOfDay(for: exception.fromDate),
                        calendar.startOfDay(for: exception.toDate),
                        exception.type.lowercased() == "working"
                    )
                }
                return (planCalendar.id, ranges)
            }
        )

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
        var workingCalendarAvailabilityByID: [Int: Bool] = [:]

        // Incremental mode: freeze every task an edit cannot move. Stored dates
        // on frozen tasks ARE the previous schedule (the scheduler writes its
        // results back to plan.tasks), so seeding them as already-scheduled is
        // exact, not an approximation.
        if let changedTaskIDs, !changedTaskIDs.isEmpty,
           changedTaskIDs.allSatisfy({ originalByID[$0] != nil }) {
            var affected = changedTaskIDs

            // Transitive successors of every changed task.
            var frontier = Array(changedTaskIDs)
            while let taskID = frontier.popLast() {
                for successorID in successorMap[taskID] ?? [] where !affected.contains(successorID) {
                    affected.insert(successorID)
                    frontier.append(successorID)
                }
            }

            // Ancestor summaries roll up from children, so every ancestor of an
            // affected task must recompute too.
            for taskID in affected {
                var parentID = hierarchy[taskID]?.parentTaskUniqueID
                while let currentParentID = parentID, !affected.contains(currentParentID) {
                    affected.insert(currentParentID)
                    parentID = hierarchy[currentParentID]?.parentTaskUniqueID
                }
            }

            for task in plan.tasks where !affected.contains(task.id) {
                scheduledByID[task.id] = task
            }
        }

        func resolvedWeeklyWorkingDay(
            weekday: Int,
            projectCalendar: ProjectCalendar?,
            visitedCalendarIDs: Set<Int> = []
        ) -> Bool {
            guard let projectCalendar else {
                return weekday >= 2 && weekday <= 6
            }

            if let calendarID = projectCalendar.uniqueID,
               visitedCalendarIDs.contains(calendarID) {
                return weekday >= 2 && weekday <= 6
            }

            let nextVisitedCalendarIDs: Set<Int>
            if let calendarID = projectCalendar.uniqueID {
                nextVisitedCalendarIDs = visitedCalendarIDs.union([calendarID])
            } else {
                nextVisitedCalendarIDs = visitedCalendarIDs
            }

            if let dayInfo = projectCalendar.dayForWeekday(weekday), !dayInfo.isDefault {
                return dayInfo.isWorking
            }

            if let parentID = projectCalendar.parentUniqueID,
               let parentCalendar = calendarsByID[parentID] {
                return resolvedWeeklyWorkingDay(
                    weekday: weekday,
                    projectCalendar: parentCalendar,
                    visitedCalendarIDs: nextVisitedCalendarIDs
                )
            }

            return weekday >= 2 && weekday <= 6
        }

        func calendarHasWorkingWeekday(_ projectCalendar: ProjectCalendar?) -> Bool {
            guard let projectCalendar else { return true }
            if let calendarID = projectCalendar.uniqueID,
               let cachedAvailability = workingCalendarAvailabilityByID[calendarID] {
                return cachedAvailability
            }

            return (1 ... 7).contains { weekday in
                resolvedWeeklyWorkingDay(weekday: weekday, projectCalendar: projectCalendar)
            }
        }

        func effectiveCalendar(for task: NativePlanTask) -> ProjectCalendar? {
            if let calendarID = task.calendarUniqueID ?? plan.defaultCalendarUniqueID {
                let projectCalendar = calendarsByID[calendarID]
                let hasWorkingWeekday = calendarHasWorkingWeekday(projectCalendar)
                workingCalendarAvailabilityByID[calendarID] = hasWorkingWeekday
                return hasWorkingWeekday ? projectCalendar : nil
            }
            return nil
        }

        func exceptionRanges(for projectCalendar: ProjectCalendar?) -> [(Date, Date, Bool)] {
            guard let calendarID = projectCalendar?.uniqueID else { return [] }
            return exceptionRangesByCalendarID[calendarID] ?? []
        }

        func isWorkingDate(_ date: Date, projectCalendar: ProjectCalendar?) -> Bool {
            let day = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: day)
            let ranges = exceptionRanges(for: projectCalendar)
            for (rangeStart, rangeEnd, isWorking) in ranges where day >= rangeStart && day <= rangeEnd {
                return isWorking
            }
            if let projectCalendar {
                return resolvedWeeklyWorkingDay(weekday: weekday, projectCalendar: projectCalendar)
            }
            return weekday >= 2 && weekday <= 6
        }

        func nextWorkingDay(onOrAfter date: Date, projectCalendar: ProjectCalendar?) -> Date {
            var current = calendar.startOfDay(for: date)
            for _ in 0 ..< workingDaySearchLimit {
                if isWorkingDate(current, projectCalendar: projectCalendar) {
                    return current
                }
                current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            }
            return calendar.startOfDay(for: date)
        }

        func previousWorkingDay(onOrBefore date: Date, projectCalendar: ProjectCalendar?) -> Date {
            var current = calendar.startOfDay(for: date)
            for _ in 0 ..< workingDaySearchLimit {
                if isWorkingDate(current, projectCalendar: projectCalendar) {
                    return current
                }
                current = calendar.date(byAdding: .day, value: -1, to: current) ?? current
            }
            return calendar.startOfDay(for: date)
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
            let stepLimit = max(workingDaySearchLimit, remaining * 14 + 14)
            var stepCount = 0

            while remaining > 0 && stepCount < stepLimit {
                current = calendar.date(byAdding: .day, value: delta > 0 ? 1 : -1, to: current) ?? current
                stepCount += 1
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
            let spanDays = (calendar.dateComponents([.day], from: normalizedStart, to: normalizedFinish).day ?? 0) + 1
            guard spanDays <= workingDaySearchLimit else {
                return max(1, Int(ceil(Double(spanDays) * 5.0 / 7.0)))
            }
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
                // FS link: this task must finish on the working day strictly
                // before the successor's latest start, otherwise every
                // predecessor on a critical chain gains one day of phantom
                // slack and falls off the critical path.
                let successorLimits = successors.map { successorID in
                    shiftWorkingDays(
                        from: latestStart(taskID: successorID),
                        by: -1,
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
            let dayDistance = abs(calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? 0)
            guard dayDistance <= workingDaySearchLimit else {
                return direction * Int(ceil(Double(dayDistance) * 5.0 / 7.0))
            }
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

@Model
final class PortfolioProjectPlan {
    @Attribute(.unique) var portfolioID: UUID
    var title: String
    var manager: String
    var company: String
    var statusDate: Date
    var portfolioWorkspace: String?
    var portfolioProgram: String?
    var portfolioSponsor: String?
    var portfolioStage: String?
    var portfolioHealth: String?
    var portfolioPriorityBand: String?
    var portfolioApprovalState: String?
    var portfolioStrategicAlignment: Int?
    var portfolioRiskScore: Int?
    var portfolioObjective: String?
    var portfolioReviewDate: Date?
    var portfolioReviewCadenceDays: Int?
    var portfolioArchiveReason: String?
    var defaultCalendarUniqueID: Int?
    var boardColumns: [String]
    var portfolioBudget: Double
    var portfolioActualCost: Double
    var taskCount: Int
    var updatedAt: Date
    var isArchived: Bool?
    /// Visual-only timeline holidays/observances/events. Default enables
    /// SwiftData lightweight migration for plans saved before this field existed.
    var timelineEvents: [PlanTimelineEvent] = []
    /// Visual-only per-resource leave windows.
    var resourceLeaves: [PlanResourceLeave] = []

    var isArchivedValue: Bool {
        isArchived ?? false
    }

    @Relationship(deleteRule: .cascade, inverse: \PortfolioPlanTask.plan)
    var tasks: [PortfolioPlanTask]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioPlanResource.plan)
    var resources: [PortfolioPlanResource]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioPlanCalendar.plan)
    var calendars: [PortfolioPlanCalendar]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioPlanSprint.plan)
    var sprints: [PortfolioPlanSprint]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioStatusSnapshot.plan)
    var statusSnapshots: [PortfolioStatusSnapshot]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioWorkflowColumn.plan)
    var workflowColumns: [PortfolioWorkflowColumn]

    @Relationship(deleteRule: .cascade, inverse: \PortfolioTypeWorkflow.plan)
    var typeWorkflowOverrides: [PortfolioTypeWorkflow]

    init(nativePlan: NativeProjectPlan) {
        self.portfolioID = nativePlan.portfolioID
        self.title = nativePlan.title
        self.manager = nativePlan.manager
        self.company = nativePlan.company
        self.statusDate = nativePlan.statusDate
        self.portfolioWorkspace = nativePlan.portfolioWorkspace
        self.portfolioProgram = nativePlan.portfolioProgram
        self.portfolioSponsor = nativePlan.portfolioSponsor
        self.portfolioStage = nativePlan.portfolioStage
        self.portfolioHealth = nativePlan.portfolioHealth
        self.portfolioPriorityBand = nativePlan.portfolioPriorityBand
        self.portfolioApprovalState = nativePlan.portfolioApprovalState
        self.portfolioStrategicAlignment = nativePlan.portfolioStrategicAlignment
        self.portfolioRiskScore = nativePlan.portfolioRiskScore
        self.portfolioObjective = nativePlan.portfolioObjective
        self.portfolioReviewDate = nativePlan.portfolioReviewDate
        self.portfolioReviewCadenceDays = nativePlan.portfolioReviewCadenceDays
        self.portfolioArchiveReason = nativePlan.portfolioArchiveReason
        self.defaultCalendarUniqueID = nativePlan.defaultCalendarUniqueID
        self.boardColumns = NativeProjectPlan.normalizedBoardColumns(nativePlan.boardColumns)
        self.portfolioBudget = 0
        self.portfolioActualCost = 0
        self.taskCount = 0
        self.updatedAt = Date()
        self.isArchived = false
        self.tasks = []
        self.resources = []
        self.calendars = []
        self.sprints = []
        self.statusSnapshots = []
        self.workflowColumns = []
        self.typeWorkflowOverrides = []
        self.timelineEvents = nativePlan.timelineEvents
        self.resourceLeaves = nativePlan.resourceLeaves
        update(from: nativePlan)
    }

    func update(from nativePlan: NativeProjectPlan, in context: ModelContext? = nil) {
        let nativePlan = nativePlan.normalizedResourceIDsForAssignmentCompatibility()
        title = nativePlan.title
        manager = nativePlan.manager
        company = nativePlan.company
        statusDate = nativePlan.statusDate
        portfolioWorkspace = nativePlan.portfolioWorkspace
        portfolioProgram = nativePlan.portfolioProgram
        portfolioSponsor = nativePlan.portfolioSponsor
        portfolioStage = nativePlan.portfolioStage
        portfolioHealth = nativePlan.portfolioHealth
        portfolioPriorityBand = nativePlan.portfolioPriorityBand
        portfolioApprovalState = nativePlan.portfolioApprovalState
        portfolioStrategicAlignment = nativePlan.portfolioStrategicAlignment
        portfolioRiskScore = nativePlan.portfolioRiskScore
        portfolioObjective = nativePlan.portfolioObjective
        portfolioReviewDate = nativePlan.portfolioReviewDate
        portfolioReviewCadenceDays = nativePlan.portfolioReviewCadenceDays
        portfolioArchiveReason = nativePlan.portfolioArchiveReason
        defaultCalendarUniqueID = nativePlan.defaultCalendarUniqueID
        boardColumns = NativeProjectPlan.normalizedBoardColumns(nativePlan.boardColumns)
        updatedAt = Date()
        isArchived = isArchived ?? false
        timelineEvents = nativePlan.timelineEvents
        resourceLeaves = nativePlan.resourceLeaves

        syncResources(from: nativePlan.resources, in: context)
        syncCalendars(from: nativePlan.calendars, in: context)
        syncSprints(from: nativePlan.sprints, in: context)
        syncStatusSnapshots(from: nativePlan.statusSnapshots, in: context)
        syncWorkflowColumns(from: nativePlan.workflowColumns, in: context)
        syncTypeWorkflowOverrides(from: nativePlan.typeWorkflowOverrides, in: context)
        syncTasks(from: nativePlan.tasks, assignments: nativePlan.assignments, in: context)
        refreshPortfolioMetrics(from: nativePlan)
    }

    func refreshPortfolioMetrics(from nativePlan: NativeProjectPlan? = nil) {
        let source = nativePlan ?? nativePlanProjectionForUI()
        let project = source.asProjectModel()
        let workTasks = project.tasks.filter { $0.summary != true }
        let metrics = EVMCalculator.projectMetrics(tasks: workTasks, statusDate: source.statusDate)
        portfolioBudget = metrics.bac
        portfolioActualCost = metrics.ac
        taskCount = source.tasks.count
    }

    func asNativePlan() -> NativeProjectPlan {
        nativePlanProjectionForUI()
    }

    func asNativePlan(in context: ModelContext) throws -> NativeProjectPlan {
        let identifier = portfolioID
        let taskRows = try context.fetch(
            FetchDescriptor<PortfolioPlanTask>(
                predicate: #Predicate { task in
                    task.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.orderIndex)]
            )
        )
        let resourceRows = try context.fetch(
            FetchDescriptor<PortfolioPlanResource>(
                predicate: #Predicate { resource in
                    resource.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.legacyID)]
            )
        )
        let taskLegacyIDs = Set(taskRows.map(\.legacyID))
        let assignmentRows = try context.fetch(
            FetchDescriptor<PortfolioPlanAssignment>(
                sortBy: [SortDescriptor(\.taskLegacyID), SortDescriptor(\.legacyID)]
            )
        )
        .filter { taskLegacyIDs.contains($0.taskLegacyID) }
        let calendarRows = try context.fetch(
            FetchDescriptor<PortfolioPlanCalendar>(
                predicate: #Predicate { calendar in
                    calendar.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.legacyID)]
            )
        )
        let sprintRows = try context.fetch(
            FetchDescriptor<PortfolioPlanSprint>(
                predicate: #Predicate { sprint in
                    sprint.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.legacyID)]
            )
        )
        let statusSnapshotRows = try context.fetch(
            FetchDescriptor<PortfolioStatusSnapshot>(
                predicate: #Predicate { snapshot in
                    snapshot.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.statusDate), SortDescriptor(\.capturedAt)]
            )
        )
        let workflowColumnRows = try context.fetch(
            FetchDescriptor<PortfolioWorkflowColumn>(
                predicate: #Predicate { column in
                    column.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.orderIndex), SortDescriptor(\.name)]
            )
        )
        let typeWorkflowRows = try context.fetch(
            FetchDescriptor<PortfolioTypeWorkflow>(
                predicate: #Predicate { workflow in
                    workflow.plan?.portfolioID == identifier
                },
                sortBy: [SortDescriptor(\.itemType)]
            )
        )

        let nativeCalendars = calendarRows.map { $0.asNativeCalendar() }
        return NativeProjectPlan(
            portfolioID: portfolioID,
            title: title,
            manager: manager,
            company: company,
            statusDate: statusDate,
            portfolioWorkspace: portfolioWorkspace,
            portfolioProgram: portfolioProgram,
            portfolioSponsor: portfolioSponsor,
            portfolioStage: portfolioStage,
            portfolioHealth: portfolioHealth,
            portfolioPriorityBand: portfolioPriorityBand,
            portfolioApprovalState: portfolioApprovalState,
            portfolioStrategicAlignment: portfolioStrategicAlignment,
            portfolioRiskScore: portfolioRiskScore,
            portfolioObjective: portfolioObjective,
            portfolioReviewDate: portfolioReviewDate,
            portfolioReviewCadenceDays: portfolioReviewCadenceDays,
            portfolioArchiveReason: portfolioArchiveReason,
            defaultCalendarUniqueID: defaultCalendarUniqueID,
            tasks: taskRows.map { $0.asNativeTask() },
            resources: resourceRows.map { $0.asNativeResource() },
            assignments: assignmentRows.map { $0.asNativeAssignment() },
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: boardColumns,
            workflowColumns: workflowColumnRows.map { $0.asNativeWorkflowColumn() },
            typeWorkflowOverrides: typeWorkflowRows.map { $0.asNativeTypeWorkflow() },
            sprints: sprintRows.map { $0.asNativeSprint() },
            statusSnapshots: statusSnapshotRows.map { $0.asNativeStatusSnapshot() },
            timelineEvents: timelineEvents,
            resourceLeaves: resourceLeaves
        )
        .normalizedResourceIDsForAssignmentCompatibility()
    }

    func editorSnapshotForUI() -> NativeProjectPlan {
        nativePlanProjectionForUI()
    }

    func projectModelForUI(scheduleResult: PlanScheduleResult? = nil) -> ProjectModel {
        let projection = nativePlanProjectionForUI()
        return projection.asProjectModel(scheduleResult: scheduleResult)
    }

    func buildAnalysisForUI() -> NativePlanAnalysis {
        NativePlanAnalysis.build(fromProjection: self)
    }

    @MainActor
    func buildAnalysisForUIAsync() async -> NativePlanAnalysis {
        await NativePlanAnalysis.buildAsync(fromProjection: self)
    }

    func makeResourceForUI(name: String = "New Resource") -> NativePlanResource {
        NativePlanResource(
            id: (resources.map(\.legacyID).max() ?? 0) + 1,
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
            calendarUniqueID: nil,
            accrueAt: "end",
            active: true
        )
    }

    func makeCalendarForUI(name: String = "New Calendar") -> NativePlanCalendar {
        NativePlanCalendar.standard(
            id: (calendars.map(\.legacyID).max() ?? 0) + 1,
            name: name
        )
    }

    private func nativePlanProjectionForUI() -> NativeProjectPlan {
        let nativeTasks = nativeTasksForUI
        let nativeResources = nativeResourcesForUI
        let nativeCalendars = nativeCalendarsForUI
        let nativeSprints = nativeSprintsForUI
        let nativeStatusSnapshots = nativeStatusSnapshotsForUI
        let nativeWorkflowColumns = nativeWorkflowColumnsForUI
        let nativeTypeWorkflowOverrides = nativeTypeWorkflowOverridesForUI
        let nativeAssignments = nativeAssignmentsForUI

        return NativeProjectPlan(
            portfolioID: portfolioID,
            title: title,
            manager: manager,
            company: company,
            statusDate: statusDate,
            portfolioWorkspace: portfolioWorkspace,
            portfolioProgram: portfolioProgram,
            portfolioSponsor: portfolioSponsor,
            portfolioStage: portfolioStage,
            portfolioHealth: portfolioHealth,
            portfolioPriorityBand: portfolioPriorityBand,
            portfolioApprovalState: portfolioApprovalState,
            portfolioStrategicAlignment: portfolioStrategicAlignment,
            portfolioRiskScore: portfolioRiskScore,
            portfolioObjective: portfolioObjective,
            portfolioReviewDate: portfolioReviewDate,
            portfolioReviewCadenceDays: portfolioReviewCadenceDays,
            portfolioArchiveReason: portfolioArchiveReason,
            defaultCalendarUniqueID: defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: boardColumns,
            workflowColumns: nativeWorkflowColumns,
            typeWorkflowOverrides: nativeTypeWorkflowOverrides,
            sprints: nativeSprints,
            statusSnapshots: nativeStatusSnapshots,
            timelineEvents: timelineEvents,
            resourceLeaves: resourceLeaves
        )
        .normalizedResourceIDsForAssignmentCompatibility()
    }

    var nativeTimelineEventsForUI: [PlanTimelineEvent] {
        timelineEvents.sorted { $0.startDate < $1.startDate }
    }

    var nativeResourceLeavesForUI: [PlanResourceLeave] {
        resourceLeaves.sorted { $0.startDate < $1.startDate }
    }

    var orderedTaskRows: [PortfolioPlanTask] {
        tasks.sorted { $0.orderIndex < $1.orderIndex }
    }

    var nativeTasksForUI: [NativePlanTask] {
        orderedTaskRows.map { $0.asNativeTask() }
    }

    var nativeAssignmentsForUI: [NativePlanAssignment] {
        orderedTaskRows.flatMap { task in
            task.assignments
                .sorted { $0.legacyID < $1.legacyID }
                .map { $0.asNativeAssignment(taskLegacyID: task.legacyID) }
        }
    }

    var nativeResourcesForUI: [NativePlanResource] {
        resources
            .sorted { $0.legacyID < $1.legacyID }
            .map { $0.asNativeResource() }
    }

    var nativeCalendarsForUI: [NativePlanCalendar] {
        calendars
            .sorted { $0.legacyID < $1.legacyID }
            .map { $0.asNativeCalendar() }
    }

    var nativeSprintsForUI: [NativePlanSprint] {
        sprints
            .sorted { $0.legacyID < $1.legacyID }
            .map { $0.asNativeSprint() }
    }

    var nativeStatusSnapshotsForUI: [NativeStatusSnapshot] {
        statusSnapshots
            .sorted { lhs, rhs in
                if lhs.statusDate == rhs.statusDate {
                    return lhs.capturedAt < rhs.capturedAt
                }
                return lhs.statusDate < rhs.statusDate
            }
            .map { $0.asNativeStatusSnapshot() }
    }

    var nativeWorkflowColumnsForUI: [NativeBoardWorkflowColumn] {
        workflowColumns
            .sorted { lhs, rhs in
                lhs.orderIndex == rhs.orderIndex ? lhs.name < rhs.name : lhs.orderIndex < rhs.orderIndex
            }
            .map { $0.asNativeWorkflowColumn() }
    }

    var nativeTypeWorkflowOverridesForUI: [NativeBoardTypeWorkflow] {
        typeWorkflowOverrides
            .sorted { $0.itemType.localizedCaseInsensitiveCompare($1.itemType) == .orderedAscending }
            .map { $0.asNativeTypeWorkflow() }
    }

    func visibleTaskFetchDescriptor() -> FetchDescriptor<PortfolioPlanTask> {
        let identifier = portfolioID
        return FetchDescriptor<PortfolioPlanTask>(
            predicate: #Predicate { task in
                task.isHiddenInGantt == false && task.plan?.portfolioID == identifier
            },
            sortBy: [SortDescriptor(\.orderIndex)]
        )
    }

    private func syncResources(from nativeResources: [NativePlanResource], in context: ModelContext?) {
        let existingResources = resources
        let existingByID = Dictionary(nonThrowingUniquePairs: existingResources.map { ($0.uniqueID, $0) }, keepLast: false)
        let existingByLegacyID = Dictionary(nonThrowingUniquePairs: existingResources.map { ($0.legacyID, $0) }, keepLast: false)
        var selectedResources: Set<ObjectIdentifier> = []
        var synchronizedResources: [PortfolioPlanResource] = []
        var matchedByID = existingByID

        for nativeResource in nativeResources {
            let model: PortfolioPlanResource
            if let existing = matchedByID[nativeResource.uniqueID],
               selectedResources.insert(ObjectIdentifier(existing)).inserted {
                model = existing
            } else if let existing = existingByLegacyID[nativeResource.id],
                      selectedResources.insert(ObjectIdentifier(existing)).inserted {
                model = existing
            } else {
                model = PortfolioPlanResource(nativeResource: nativeResource)
            }

            model.update(from: nativeResource)
            model.accrueAt = model.accrueAtValue
            model.plan = self
            synchronizedResources.append(model)
            matchedByID[nativeResource.uniqueID] = model
        }

        resources = synchronizedResources
        let removedResources = existingResources.filter { !selectedResources.contains(ObjectIdentifier($0)) }
        removedResources.forEach { context?.delete($0) }
    }

    private func syncCalendars(from nativeCalendars: [NativePlanCalendar], in context: ModelContext?) {
        let incomingIDs = Set(nativeCalendars.map(\.id))
        var seenExistingIDs: Set<Int> = []
        var removedCalendars: [PortfolioPlanCalendar] = []
        calendars.removeAll { calendar in
            let shouldRemove = !incomingIDs.contains(calendar.legacyID) || !seenExistingIDs.insert(calendar.legacyID).inserted
            if shouldRemove {
                removedCalendars.append(calendar)
            }
            return shouldRemove
        }
        removedCalendars.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: calendars.map { ($0.legacyID, $0) })
        for nativeCalendar in nativeCalendars {
            if let existing = existingByID[nativeCalendar.id] {
                existing.update(from: nativeCalendar)
            } else {
                let model = PortfolioPlanCalendar(nativeCalendar: nativeCalendar)
                model.plan = self
                calendars.append(model)
                existingByID[nativeCalendar.id] = model
            }
        }
    }

    private func syncSprints(from nativeSprints: [NativePlanSprint], in context: ModelContext?) {
        let incomingIDs = Set(nativeSprints.map(\.id))
        var seenExistingIDs: Set<Int> = []
        var removedSprints: [PortfolioPlanSprint] = []
        sprints.removeAll { sprint in
            let shouldRemove = !incomingIDs.contains(sprint.legacyID) || !seenExistingIDs.insert(sprint.legacyID).inserted
            if shouldRemove {
                removedSprints.append(sprint)
            }
            return shouldRemove
        }
        removedSprints.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: sprints.map { ($0.legacyID, $0) })
        for nativeSprint in nativeSprints {
            if let existing = existingByID[nativeSprint.id] {
                existing.update(from: nativeSprint)
            } else {
                let model = PortfolioPlanSprint(nativeSprint: nativeSprint)
                model.plan = self
                sprints.append(model)
                existingByID[nativeSprint.id] = model
            }
        }
    }

    private func syncStatusSnapshots(from nativeSnapshots: [NativeStatusSnapshot], in context: ModelContext?) {
        let incomingIDs = Set(nativeSnapshots.map(\.id))
        var seenExistingIDs: Set<UUID> = []
        var removedSnapshots: [PortfolioStatusSnapshot] = []
        statusSnapshots.removeAll { snapshot in
            let shouldRemove = !incomingIDs.contains(snapshot.uniqueID) || !seenExistingIDs.insert(snapshot.uniqueID).inserted
            if shouldRemove {
                removedSnapshots.append(snapshot)
            }
            return shouldRemove
        }
        removedSnapshots.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: statusSnapshots.map { ($0.uniqueID, $0) })
        for nativeSnapshot in nativeSnapshots {
            if let existing = existingByID[nativeSnapshot.id] {
                existing.update(from: nativeSnapshot, in: context)
            } else {
                let model = PortfolioStatusSnapshot(nativeSnapshot: nativeSnapshot)
                model.plan = self
                statusSnapshots.append(model)
                existingByID[nativeSnapshot.id] = model
            }
        }
    }

    private func syncWorkflowColumns(from nativeColumns: [NativeBoardWorkflowColumn], in context: ModelContext?) {
        let incomingIDs = Set(nativeColumns.map(\.id))
        var seenExistingIDs: Set<UUID> = []
        var removedColumns: [PortfolioWorkflowColumn] = []
        workflowColumns.removeAll { column in
            let shouldRemove = !incomingIDs.contains(column.uniqueID) || !seenExistingIDs.insert(column.uniqueID).inserted
            if shouldRemove {
                removedColumns.append(column)
            }
            return shouldRemove
        }
        removedColumns.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: workflowColumns.map { ($0.uniqueID, $0) })
        for (orderIndex, nativeColumn) in nativeColumns.enumerated() {
            if let existing = existingByID[nativeColumn.id] {
                existing.update(from: nativeColumn, orderIndex: orderIndex)
            } else {
                let model = PortfolioWorkflowColumn(nativeColumn: nativeColumn, orderIndex: orderIndex)
                model.plan = self
                workflowColumns.append(model)
                existingByID[nativeColumn.id] = model
            }
        }
    }

    private func syncTypeWorkflowOverrides(from nativeOverrides: [NativeBoardTypeWorkflow], in context: ModelContext?) {
        let incomingIDs = Set(nativeOverrides.map(\.id))
        var seenExistingIDs: Set<UUID> = []
        var removedOverrides: [PortfolioTypeWorkflow] = []
        typeWorkflowOverrides.removeAll { typeWorkflow in
            let shouldRemove = !incomingIDs.contains(typeWorkflow.uniqueID) || !seenExistingIDs.insert(typeWorkflow.uniqueID).inserted
            if shouldRemove {
                removedOverrides.append(typeWorkflow)
            }
            return shouldRemove
        }
        removedOverrides.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: typeWorkflowOverrides.map { ($0.uniqueID, $0) })
        for nativeOverride in nativeOverrides {
            if let existing = existingByID[nativeOverride.id] {
                existing.update(from: nativeOverride, in: context)
            } else {
                let model = PortfolioTypeWorkflow(nativeTypeWorkflow: nativeOverride)
                model.plan = self
                typeWorkflowOverrides.append(model)
                existingByID[nativeOverride.id] = model
            }
        }
    }

    private func syncTasks(from nativeTasks: [NativePlanTask], assignments nativeAssignments: [NativePlanAssignment], in context: ModelContext?) {
        let assignmentsByTaskID = Dictionary(grouping: nativeAssignments, by: \.taskID)
        let resourceByID = Dictionary(nonThrowingUniquePairs: resources.map { ($0.legacyID, $0) })
        let existingTasks = tasks
        let existingByID = Dictionary(nonThrowingUniquePairs: existingTasks.map { ($0.uniqueID, $0) }, keepLast: false)
        let existingByLegacyID = Dictionary(nonThrowingUniquePairs: existingTasks.map { ($0.legacyID, $0) }, keepLast: false)
        var selectedTasks: Set<ObjectIdentifier> = []
        var synchronizedTasks: [PortfolioPlanTask] = []
        var matchedByID = existingByID

        for (orderIndex, nativeTask) in nativeTasks.enumerated() {
            let taskModel: PortfolioPlanTask
            if let existing = matchedByID[nativeTask.uniqueID],
               selectedTasks.insert(ObjectIdentifier(existing)).inserted {
                taskModel = existing
            } else if let existing = existingByLegacyID[nativeTask.id],
                      selectedTasks.insert(ObjectIdentifier(existing)).inserted {
                taskModel = existing
            } else {
                taskModel = PortfolioPlanTask(nativeTask: nativeTask, orderIndex: orderIndex)
            }

            taskModel.update(from: nativeTask, orderIndex: orderIndex)
            taskModel.plan = self
            synchronizedTasks.append(taskModel)
            matchedByID[nativeTask.uniqueID] = taskModel

            let taskAssignments = assignmentsByTaskID[nativeTask.id] ?? []
            taskModel.syncAssignments(from: taskAssignments, resourcesByLegacyID: resourceByID, in: context)
        }

        tasks = synchronizedTasks
        let removedTasks = existingTasks.filter { !selectedTasks.contains(ObjectIdentifier($0)) }
        removedTasks.forEach { context?.delete($0) }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodePayload<T: Encodable>(_ value: T) -> Data {
        (try? encoder().encode(value)) ?? Data()
    }

    private static func decodePayload<T: Decodable>(_ data: Data, fallback: T) -> T {
        guard !data.isEmpty, let decoded = try? decoder().decode(T.self, from: data) else { return fallback }
        return decoded
    }
}

@Model
final class PortfolioPlanTask {
    @Attribute(.unique) var uniqueID: UUID
    var legacyID: Int
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
    var agileType: String
    var boardStatus: String
    var storyPoints: Int?
    var sprintID: Int?
    var epicName: String
    var tags: [String]
    var customFields: [String: String]?
    var barColorHex: String?
    var orderIndex: Int
    var isCollapsed: Bool
    var isHiddenInGantt: Bool

    var plan: PortfolioProjectPlan?

    @Relationship(deleteRule: .cascade, inverse: \PortfolioPlanAssignment.task)
    var assignments: [PortfolioPlanAssignment]

    init(nativeTask: NativePlanTask, orderIndex: Int) {
        self.uniqueID = nativeTask.uniqueID
        self.legacyID = nativeTask.id
        self.name = nativeTask.name
        self.startDate = nativeTask.startDate
        self.finishDate = nativeTask.finishDate
        self.durationDays = nativeTask.durationDays
        self.outlineLevel = nativeTask.outlineLevel
        self.isMilestone = nativeTask.isMilestone
        self.manuallyScheduled = nativeTask.manuallyScheduled
        self.percentComplete = nativeTask.percentComplete
        self.priority = nativeTask.priority
        self.notes = nativeTask.notes
        self.predecessorTaskIDs = nativeTask.predecessorTaskIDs
        self.baselineStartDate = nativeTask.baselineStartDate
        self.baselineFinishDate = nativeTask.baselineFinishDate
        self.baselineDurationDays = nativeTask.baselineDurationDays
        self.fixedCost = nativeTask.fixedCost
        self.baselineCost = nativeTask.baselineCost
        self.actualCost = nativeTask.actualCost
        self.actualStartDate = nativeTask.actualStartDate
        self.actualFinishDate = nativeTask.actualFinishDate
        self.constraintType = nativeTask.constraintType
        self.constraintDate = nativeTask.constraintDate
        self.calendarUniqueID = nativeTask.calendarUniqueID
        self.isActive = nativeTask.isActive
        self.agileType = nativeTask.agileType
        self.boardStatus = nativeTask.boardStatus
        self.storyPoints = nativeTask.storyPoints
        self.sprintID = nativeTask.sprintID
        self.epicName = nativeTask.epicName
        self.tags = nativeTask.tags
        self.customFields = nativeTask.customFields.isEmpty ? nil : nativeTask.customFields
        self.barColorHex = nativeTask.barColorHex
        self.orderIndex = orderIndex
        self.isCollapsed = false
        self.isHiddenInGantt = false
        self.assignments = []
    }

    func update(from nativeTask: NativePlanTask, orderIndex: Int) {
        uniqueID = nativeTask.uniqueID
        legacyID = nativeTask.id
        name = nativeTask.name
        startDate = nativeTask.startDate
        finishDate = nativeTask.finishDate
        durationDays = nativeTask.durationDays
        outlineLevel = nativeTask.outlineLevel
        isMilestone = nativeTask.isMilestone
        manuallyScheduled = nativeTask.manuallyScheduled
        percentComplete = nativeTask.percentComplete
        priority = nativeTask.priority
        notes = nativeTask.notes
        predecessorTaskIDs = nativeTask.predecessorTaskIDs
        baselineStartDate = nativeTask.baselineStartDate
        baselineFinishDate = nativeTask.baselineFinishDate
        baselineDurationDays = nativeTask.baselineDurationDays
        fixedCost = nativeTask.fixedCost
        baselineCost = nativeTask.baselineCost
        actualCost = nativeTask.actualCost
        actualStartDate = nativeTask.actualStartDate
        actualFinishDate = nativeTask.actualFinishDate
        constraintType = nativeTask.constraintType
        constraintDate = nativeTask.constraintDate
        calendarUniqueID = nativeTask.calendarUniqueID
        isActive = nativeTask.isActive
        agileType = nativeTask.agileType
        boardStatus = nativeTask.boardStatus
        storyPoints = nativeTask.storyPoints
        sprintID = nativeTask.sprintID
        epicName = nativeTask.epicName
        tags = nativeTask.tags
        customFields = nativeTask.customFields.isEmpty ? nil : nativeTask.customFields
        barColorHex = nativeTask.barColorHex
        self.orderIndex = orderIndex
    }

    func syncAssignments(
        from nativeAssignments: [NativePlanAssignment],
        resourcesByLegacyID: [Int: PortfolioPlanResource],
        in context: ModelContext? = nil
    ) {
        let existingAssignments = assignments
        let existingByID = Dictionary(nonThrowingUniquePairs: existingAssignments.map { ($0.uniqueID, $0) }, keepLast: false)
        let existingByLegacyID = Dictionary(nonThrowingUniquePairs: existingAssignments.map { ($0.legacyID, $0) }, keepLast: false)
        var selectedAssignments: Set<ObjectIdentifier> = []
        var synchronizedAssignments: [PortfolioPlanAssignment] = []
        var matchedByID = existingByID

        for nativeAssignment in nativeAssignments {
            let assignmentModel: PortfolioPlanAssignment
            if let existing = matchedByID[nativeAssignment.uniqueID],
               selectedAssignments.insert(ObjectIdentifier(existing)).inserted {
                assignmentModel = existing
            } else if let existing = existingByLegacyID[nativeAssignment.id],
                      selectedAssignments.insert(ObjectIdentifier(existing)).inserted {
                assignmentModel = existing
            } else {
                assignmentModel = PortfolioPlanAssignment(nativeAssignment: nativeAssignment)
            }

            assignmentModel.update(from: nativeAssignment)
            assignmentModel.task = self
            assignmentModel.resource = nativeAssignment.resourceID.flatMap { resourcesByLegacyID[$0] }
            synchronizedAssignments.append(assignmentModel)
            matchedByID[nativeAssignment.uniqueID] = assignmentModel
        }

        assignments = synchronizedAssignments
        let removedAssignments = existingAssignments.filter { !selectedAssignments.contains(ObjectIdentifier($0)) }
        removedAssignments.forEach { context?.delete($0) }
    }

    func asNativeTask() -> NativePlanTask {
        NativePlanTask(
            id: legacyID,
            name: name,
            startDate: startDate,
            finishDate: finishDate,
            durationDays: durationDays,
            outlineLevel: outlineLevel,
            isMilestone: isMilestone,
            manuallyScheduled: manuallyScheduled,
            percentComplete: percentComplete,
            priority: priority,
            notes: notes,
            predecessorTaskIDs: predecessorTaskIDs,
            baselineStartDate: baselineStartDate,
            baselineFinishDate: baselineFinishDate,
            baselineDurationDays: baselineDurationDays,
            fixedCost: fixedCost,
            baselineCost: baselineCost,
            actualCost: actualCost,
            actualStartDate: actualStartDate,
            actualFinishDate: actualFinishDate,
            constraintType: constraintType,
            constraintDate: constraintDate,
            calendarUniqueID: calendarUniqueID,
            isActive: isActive,
            agileType: agileType,
            boardStatus: boardStatus,
            storyPoints: storyPoints,
            sprintID: sprintID,
            epicName: epicName,
            tags: tags,
            customFields: customFields ?? [:],
            barColorHex: barColorHex,
            uniqueID: uniqueID
        )
    }
}

@Model
final class PortfolioPlanResource {
    @Attribute(.unique) var uniqueID: UUID
    var legacyID: Int
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
    var accrueAt: String?
    var active: Bool

    var plan: PortfolioProjectPlan?

    var accrueAtValue: String {
        guard let raw = accrueAt?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return "end"
        }
        switch raw {
        case "start", "prorated", "end":
            return raw
        default:
            return "end"
        }
    }

    init(nativeResource: NativePlanResource) {
        self.uniqueID = nativeResource.uniqueID
        self.legacyID = nativeResource.id
        self.name = nativeResource.name
        self.type = nativeResource.type
        self.maxUnits = nativeResource.maxUnits
        self.standardRate = nativeResource.standardRate
        self.overtimeRate = nativeResource.overtimeRate
        self.costPerUse = nativeResource.costPerUse
        self.emailAddress = nativeResource.emailAddress
        self.group = nativeResource.group
        self.initials = nativeResource.initials
        self.notes = nativeResource.notes
        self.calendarUniqueID = nativeResource.calendarUniqueID
        self.accrueAt = nativeResource.accrueAtValue
        self.active = nativeResource.active
    }

    func update(from nativeResource: NativePlanResource) {
        uniqueID = nativeResource.uniqueID
        legacyID = nativeResource.id
        name = nativeResource.name
        type = nativeResource.type
        maxUnits = nativeResource.maxUnits
        standardRate = nativeResource.standardRate
        overtimeRate = nativeResource.overtimeRate
        costPerUse = nativeResource.costPerUse
        emailAddress = nativeResource.emailAddress
        group = nativeResource.group
        initials = nativeResource.initials
        notes = nativeResource.notes
        calendarUniqueID = nativeResource.calendarUniqueID
        accrueAt = nativeResource.accrueAtValue
        active = nativeResource.active
    }

    func asNativeResource() -> NativePlanResource {
        NativePlanResource(
            id: legacyID,
            name: name,
            type: type,
            maxUnits: maxUnits,
            standardRate: standardRate,
            overtimeRate: overtimeRate,
            costPerUse: costPerUse,
            emailAddress: emailAddress,
            group: group,
            initials: initials,
            notes: notes,
            calendarUniqueID: calendarUniqueID,
            accrueAt: accrueAtValue,
            active: active,
            uniqueID: uniqueID
        )
    }
}

@Model
final class PortfolioPlanCalendar {
    @Attribute(.unique) var uniqueID: UUID
    var legacyID: Int
    var name: String
    var parentUniqueID: Int?
    var type: String
    var personal: Bool
    var sundayPayload: Data
    var mondayPayload: Data
    var tuesdayPayload: Data
    var wednesdayPayload: Data
    var thursdayPayload: Data
    var fridayPayload: Data
    var saturdayPayload: Data
    var exceptionsPayload: Data

    var plan: PortfolioProjectPlan?

    init(nativeCalendar: NativePlanCalendar) {
        self.uniqueID = UUID()
        self.legacyID = nativeCalendar.id
        self.name = nativeCalendar.name
        self.parentUniqueID = nativeCalendar.parentUniqueID
        self.type = nativeCalendar.type
        self.personal = nativeCalendar.personal
        self.sundayPayload = Self.encodePayload(nativeCalendar.sunday)
        self.mondayPayload = Self.encodePayload(nativeCalendar.monday)
        self.tuesdayPayload = Self.encodePayload(nativeCalendar.tuesday)
        self.wednesdayPayload = Self.encodePayload(nativeCalendar.wednesday)
        self.thursdayPayload = Self.encodePayload(nativeCalendar.thursday)
        self.fridayPayload = Self.encodePayload(nativeCalendar.friday)
        self.saturdayPayload = Self.encodePayload(nativeCalendar.saturday)
        self.exceptionsPayload = Self.encodePayload(nativeCalendar.exceptions)
    }

    func update(from nativeCalendar: NativePlanCalendar) {
        legacyID = nativeCalendar.id
        name = nativeCalendar.name
        parentUniqueID = nativeCalendar.parentUniqueID
        type = nativeCalendar.type
        personal = nativeCalendar.personal
        sundayPayload = Self.encodePayload(nativeCalendar.sunday)
        mondayPayload = Self.encodePayload(nativeCalendar.monday)
        tuesdayPayload = Self.encodePayload(nativeCalendar.tuesday)
        wednesdayPayload = Self.encodePayload(nativeCalendar.wednesday)
        thursdayPayload = Self.encodePayload(nativeCalendar.thursday)
        fridayPayload = Self.encodePayload(nativeCalendar.friday)
        saturdayPayload = Self.encodePayload(nativeCalendar.saturday)
        exceptionsPayload = Self.encodePayload(nativeCalendar.exceptions)
    }

    var sunday: NativeCalendarDay {
        get { Self.decodePayload(sundayPayload, fallback: .nonWorking()) }
        set { sundayPayload = Self.encodePayload(newValue) }
    }

    var monday: NativeCalendarDay {
        get { Self.decodePayload(mondayPayload, fallback: .workingDay()) }
        set { mondayPayload = Self.encodePayload(newValue) }
    }

    var tuesday: NativeCalendarDay {
        get { Self.decodePayload(tuesdayPayload, fallback: .workingDay()) }
        set { tuesdayPayload = Self.encodePayload(newValue) }
    }

    var wednesday: NativeCalendarDay {
        get { Self.decodePayload(wednesdayPayload, fallback: .workingDay()) }
        set { wednesdayPayload = Self.encodePayload(newValue) }
    }

    var thursday: NativeCalendarDay {
        get { Self.decodePayload(thursdayPayload, fallback: .workingDay()) }
        set { thursdayPayload = Self.encodePayload(newValue) }
    }

    var friday: NativeCalendarDay {
        get { Self.decodePayload(fridayPayload, fallback: .workingDay()) }
        set { fridayPayload = Self.encodePayload(newValue) }
    }

    var saturday: NativeCalendarDay {
        get { Self.decodePayload(saturdayPayload, fallback: .nonWorking()) }
        set { saturdayPayload = Self.encodePayload(newValue) }
    }

    var exceptions: [NativeCalendarException] {
        get { Self.decodePayload(exceptionsPayload, fallback: []) }
        set { exceptionsPayload = Self.encodePayload(newValue) }
    }

    func asNativeCalendar() -> NativePlanCalendar {
        NativePlanCalendar(
            id: legacyID,
            name: name,
            parentUniqueID: parentUniqueID,
            type: type,
            personal: personal,
            sunday: sunday,
            monday: monday,
            tuesday: tuesday,
            wednesday: wednesday,
            thursday: thursday,
            friday: friday,
            saturday: saturday,
            exceptions: exceptions
        )
        .normalizedForInheritedResourceCalendar()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodePayload<T: Encodable>(_ value: T) -> Data {
        (try? encoder().encode(value)) ?? Data()
    }

    private static func decodePayload<T: Decodable>(_ data: Data, fallback: T) -> T {
        guard !data.isEmpty, let decoded = try? decoder().decode(T.self, from: data) else { return fallback }
        return decoded
    }
}

@Model
final class PortfolioPlanSprint {
    @Attribute(.unique) var uniqueID: UUID
    var legacyID: Int
    var name: String
    var goal: String
    var startDate: Date
    var endDate: Date
    var capacityPoints: Int
    var teamName: String
    var state: String

    var plan: PortfolioProjectPlan?

    init(nativeSprint: NativePlanSprint) {
        self.uniqueID = UUID()
        self.legacyID = nativeSprint.id
        self.name = nativeSprint.name
        self.goal = nativeSprint.goal
        self.startDate = nativeSprint.startDate
        self.endDate = nativeSprint.endDate
        self.capacityPoints = nativeSprint.capacityPoints
        self.teamName = nativeSprint.teamName
        self.state = nativeSprint.state
    }

    func update(from nativeSprint: NativePlanSprint) {
        legacyID = nativeSprint.id
        name = nativeSprint.name
        goal = nativeSprint.goal
        startDate = Calendar.current.startOfDay(for: nativeSprint.startDate)
        endDate = Calendar.current.startOfDay(for: nativeSprint.endDate)
        capacityPoints = max(0, nativeSprint.capacityPoints)
        teamName = nativeSprint.teamName
        state = nativeSprint.state
    }

    func asNativeSprint() -> NativePlanSprint {
        NativePlanSprint(
            id: legacyID,
            name: name,
            goal: goal,
            startDate: startDate,
            endDate: endDate,
            capacityPoints: capacityPoints,
            teamName: teamName,
            state: state
        )
    }
}

@Model
final class PortfolioWorkflowColumn {
    @Attribute(.unique) var uniqueID: UUID
    var orderIndex: Int
    var name: String
    var wipLimit: Int?
    var allowedTransitionsPayload: Data

    var plan: PortfolioProjectPlan?
    var typeWorkflow: PortfolioTypeWorkflow?

    init(nativeColumn: NativeBoardWorkflowColumn, orderIndex: Int) {
        self.uniqueID = nativeColumn.id
        self.orderIndex = orderIndex
        self.name = nativeColumn.name
        self.wipLimit = nativeColumn.wipLimit
        self.allowedTransitionsPayload = Self.encodePayload(nativeColumn.allowedTransitions)
    }

    func update(from nativeColumn: NativeBoardWorkflowColumn, orderIndex: Int) {
        self.orderIndex = orderIndex
        name = nativeColumn.name
        wipLimit = nativeColumn.wipLimit
        allowedTransitionsPayload = Self.encodePayload(nativeColumn.allowedTransitions)
    }

    var allowedTransitions: [String] {
        get { Self.decodePayload(allowedTransitionsPayload, fallback: []) }
        set { allowedTransitionsPayload = Self.encodePayload(newValue) }
    }

    func asNativeWorkflowColumn() -> NativeBoardWorkflowColumn {
        NativeBoardWorkflowColumn(
            id: uniqueID,
            name: name,
            wipLimit: wipLimit,
            allowedTransitions: allowedTransitions
        )
    }

    private static func encoder() -> JSONEncoder {
        JSONEncoder()
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func encodePayload<T: Encodable>(_ value: T) -> Data {
        (try? encoder().encode(value)) ?? Data()
    }

    private static func decodePayload<T: Decodable>(_ data: Data, fallback: T) -> T {
        guard !data.isEmpty, let decoded = try? decoder().decode(T.self, from: data) else { return fallback }
        return decoded
    }
}

@Model
final class PortfolioTypeWorkflow {
    @Attribute(.unique) var uniqueID: UUID
    var itemType: String

    var plan: PortfolioProjectPlan?

    @Relationship(deleteRule: .cascade, inverse: \PortfolioWorkflowColumn.typeWorkflow)
    var columns: [PortfolioWorkflowColumn]

    init(nativeTypeWorkflow: NativeBoardTypeWorkflow) {
        self.uniqueID = nativeTypeWorkflow.id
        self.itemType = nativeTypeWorkflow.itemType
        self.columns = nativeTypeWorkflow.columns.enumerated().map { index, column in
            PortfolioWorkflowColumn(nativeColumn: column, orderIndex: index)
        }
        self.columns.forEach { $0.typeWorkflow = self }
    }

    func update(from nativeTypeWorkflow: NativeBoardTypeWorkflow, in context: ModelContext? = nil) {
        itemType = nativeTypeWorkflow.itemType
        syncColumns(from: nativeTypeWorkflow.columns, in: context)
    }

    func asNativeTypeWorkflow() -> NativeBoardTypeWorkflow {
        NativeBoardTypeWorkflow(
            id: uniqueID,
            itemType: itemType,
            columns: columns
                .sorted { lhs, rhs in lhs.orderIndex == rhs.orderIndex ? lhs.name < rhs.name : lhs.orderIndex < rhs.orderIndex }
                .map { $0.asNativeWorkflowColumn() }
        )
    }

    private func syncColumns(from nativeColumns: [NativeBoardWorkflowColumn], in context: ModelContext?) {
        let incomingIDs = Set(nativeColumns.map(\.id))
        var seenExistingIDs: Set<UUID> = []
        var removedColumns: [PortfolioWorkflowColumn] = []
        columns.removeAll { column in
            let shouldRemove = !incomingIDs.contains(column.uniqueID) || !seenExistingIDs.insert(column.uniqueID).inserted
            if shouldRemove {
                removedColumns.append(column)
            }
            return shouldRemove
        }
        removedColumns.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: columns.map { ($0.uniqueID, $0) })
        for (orderIndex, nativeColumn) in nativeColumns.enumerated() {
            if let existing = existingByID[nativeColumn.id] {
                existing.update(from: nativeColumn, orderIndex: orderIndex)
            } else {
                let model = PortfolioWorkflowColumn(nativeColumn: nativeColumn, orderIndex: orderIndex)
                model.typeWorkflow = self
                columns.append(model)
                existingByID[nativeColumn.id] = model
            }
        }
    }
}

@Model
final class PortfolioStatusSnapshot {
    @Attribute(.unique) var uniqueID: UUID
    var name: String
    var capturedAt: Date
    var statusDate: Date
    var taskCount: Int
    var completedTaskCount: Int
    var inProgressTaskCount: Int
    var bac: Double
    var pv: Double
    var ev: Double
    var ac: Double
    var cpi: Double
    var spi: Double
    var eac: Double
    var vac: Double
    var notes: String

    var plan: PortfolioProjectPlan?

    @Relationship(deleteRule: .cascade, inverse: \PortfolioSprintStatusSnapshot.snapshot)
    var sprintSnapshots: [PortfolioSprintStatusSnapshot]

    init(nativeSnapshot: NativeStatusSnapshot) {
        self.uniqueID = nativeSnapshot.id
        self.name = nativeSnapshot.name
        self.capturedAt = nativeSnapshot.capturedAt
        self.statusDate = nativeSnapshot.statusDate
        self.taskCount = nativeSnapshot.taskCount
        self.completedTaskCount = nativeSnapshot.completedTaskCount
        self.inProgressTaskCount = nativeSnapshot.inProgressTaskCount
        self.bac = nativeSnapshot.bac
        self.pv = nativeSnapshot.pv
        self.ev = nativeSnapshot.ev
        self.ac = nativeSnapshot.ac
        self.cpi = nativeSnapshot.cpi
        self.spi = nativeSnapshot.spi
        self.eac = nativeSnapshot.eac
        self.vac = nativeSnapshot.vac
        self.notes = nativeSnapshot.notes
        self.sprintSnapshots = nativeSnapshot.sprintSnapshots.map { PortfolioSprintStatusSnapshot(nativeSnapshot: $0) }
        self.sprintSnapshots.forEach { $0.snapshot = self }
    }

    func update(from nativeSnapshot: NativeStatusSnapshot, in context: ModelContext? = nil) {
        name = nativeSnapshot.name
        capturedAt = nativeSnapshot.capturedAt
        statusDate = nativeSnapshot.statusDate
        taskCount = nativeSnapshot.taskCount
        completedTaskCount = nativeSnapshot.completedTaskCount
        inProgressTaskCount = nativeSnapshot.inProgressTaskCount
        bac = nativeSnapshot.bac
        pv = nativeSnapshot.pv
        ev = nativeSnapshot.ev
        ac = nativeSnapshot.ac
        cpi = nativeSnapshot.cpi
        spi = nativeSnapshot.spi
        eac = nativeSnapshot.eac
        vac = nativeSnapshot.vac
        notes = nativeSnapshot.notes
        syncSprintSnapshots(from: nativeSnapshot.sprintSnapshots, in: context)
    }

    func asNativeStatusSnapshot() -> NativeStatusSnapshot {
        NativeStatusSnapshot(
            id: uniqueID,
            name: name,
            capturedAt: capturedAt,
            statusDate: statusDate,
            taskCount: taskCount,
            completedTaskCount: completedTaskCount,
            inProgressTaskCount: inProgressTaskCount,
            bac: bac,
            pv: pv,
            ev: ev,
            ac: ac,
            cpi: cpi,
            spi: spi,
            eac: eac,
            vac: vac,
            notes: notes,
            sprintSnapshots: sprintSnapshots.sorted { $0.sprintID < $1.sprintID }.map { $0.asNativeSprintSnapshot() }
        )
    }

    private func syncSprintSnapshots(from nativeSnapshots: [NativeSprintSnapshot], in context: ModelContext?) {
        let incomingIDs = Set(nativeSnapshots.map(\.sprintID))
        var seenExistingIDs: Set<Int> = []
        var removedSnapshots: [PortfolioSprintStatusSnapshot] = []
        sprintSnapshots.removeAll { snapshot in
            let shouldRemove = !incomingIDs.contains(snapshot.sprintID) || !seenExistingIDs.insert(snapshot.sprintID).inserted
            if shouldRemove {
                removedSnapshots.append(snapshot)
            }
            return shouldRemove
        }
        removedSnapshots.forEach { context?.delete($0) }

        var existingByID = Dictionary(nonThrowingUniquePairs: sprintSnapshots.map { ($0.sprintID, $0) })
        for nativeSnapshot in nativeSnapshots {
            if let existing = existingByID[nativeSnapshot.sprintID] {
                existing.update(from: nativeSnapshot)
            } else {
                let model = PortfolioSprintStatusSnapshot(nativeSnapshot: nativeSnapshot)
                model.snapshot = self
                sprintSnapshots.append(model)
                existingByID[nativeSnapshot.sprintID] = model
            }
        }
    }
}

@Model
final class PortfolioSprintStatusSnapshot {
    @Attribute(.unique) var uniqueID: UUID
    var sprintID: Int
    var sprintName: String
    var committedPoints: Int
    var completedPoints: Int

    var snapshot: PortfolioStatusSnapshot?

    init(nativeSnapshot: NativeSprintSnapshot) {
        self.uniqueID = UUID()
        self.sprintID = nativeSnapshot.sprintID
        self.sprintName = nativeSnapshot.sprintName
        self.committedPoints = nativeSnapshot.committedPoints
        self.completedPoints = nativeSnapshot.completedPoints
    }

    func update(from nativeSnapshot: NativeSprintSnapshot) {
        sprintID = nativeSnapshot.sprintID
        sprintName = nativeSnapshot.sprintName
        committedPoints = nativeSnapshot.committedPoints
        completedPoints = nativeSnapshot.completedPoints
    }

    func asNativeSprintSnapshot() -> NativeSprintSnapshot {
        NativeSprintSnapshot(
            sprintID: sprintID,
            sprintName: sprintName,
            committedPoints: committedPoints,
            completedPoints: completedPoints
        )
    }
}

@Model
final class PortfolioPlanAssignment {
    @Attribute(.unique) var uniqueID: UUID
    var legacyID: Int
    var taskLegacyID: Int
    var resourceLegacyID: Int?
    var units: Double
    var workSeconds: Int?
    var actualWorkSeconds: Int?
    var remainingWorkSeconds: Int?
    var overtimeWorkSeconds: Int?
    var notes: String

    var task: PortfolioPlanTask?
    var resource: PortfolioPlanResource?

    init(nativeAssignment: NativePlanAssignment) {
        self.uniqueID = nativeAssignment.uniqueID
        self.legacyID = nativeAssignment.id
        self.taskLegacyID = nativeAssignment.taskID
        self.resourceLegacyID = nativeAssignment.resourceID
        self.units = nativeAssignment.units
        self.workSeconds = nativeAssignment.workSeconds
        self.actualWorkSeconds = nativeAssignment.actualWorkSeconds
        self.remainingWorkSeconds = nativeAssignment.remainingWorkSeconds
        self.overtimeWorkSeconds = nativeAssignment.overtimeWorkSeconds
        self.notes = nativeAssignment.notes
    }

    func update(from nativeAssignment: NativePlanAssignment) {
        uniqueID = nativeAssignment.uniqueID
        legacyID = nativeAssignment.id
        taskLegacyID = nativeAssignment.taskID
        resourceLegacyID = nativeAssignment.resourceID
        units = nativeAssignment.units
        workSeconds = nativeAssignment.workSeconds
        actualWorkSeconds = nativeAssignment.actualWorkSeconds
        remainingWorkSeconds = nativeAssignment.remainingWorkSeconds
        overtimeWorkSeconds = nativeAssignment.overtimeWorkSeconds
        notes = nativeAssignment.notes
    }

    func asNativeAssignment(taskLegacyID overrideTaskID: Int? = nil) -> NativePlanAssignment {
        NativePlanAssignment(
            id: legacyID,
            taskID: overrideTaskID ?? taskLegacyID,
            resourceID: resourceLegacyID,
            units: units,
            workSeconds: workSeconds,
            actualWorkSeconds: actualWorkSeconds,
            remainingWorkSeconds: remainingWorkSeconds,
            overtimeWorkSeconds: overtimeWorkSeconds,
            notes: notes,
            uniqueID: uniqueID
        )
    }
}

@Model
final class PortfolioCrossProjectDependency {
    @Attribute(.unique) var uniqueID: UUID
    var sourcePlanID: UUID
    var sourcePlanTitle: String
    var sourceTaskUniqueID: UUID
    var sourceTaskLegacyID: Int
    var sourceTaskName: String
    var targetPlanID: UUID
    var targetPlanTitle: String
    var targetTaskUniqueID: UUID
    var targetTaskLegacyID: Int
    var targetTaskName: String
    var relationType: String
    var lagDays: Int
    var note: String
    var updatedAt: Date

    init(
        sourcePlan: PortfolioProjectPlan,
        sourceTask: PortfolioPlanTask,
        targetPlan: PortfolioProjectPlan,
        targetTask: PortfolioPlanTask,
        relationType: String,
        lagDays: Int,
        note: String
    ) {
        uniqueID = UUID()
        sourcePlanID = sourcePlan.portfolioID
        sourcePlanTitle = Self.trimmedOrFallback(sourcePlan.title, fallback: "Untitled Plan")
        sourceTaskUniqueID = sourceTask.uniqueID
        sourceTaskLegacyID = sourceTask.legacyID
        sourceTaskName = Self.trimmedOrFallback(sourceTask.name, fallback: "Untitled Task")
        targetPlanID = targetPlan.portfolioID
        targetPlanTitle = Self.trimmedOrFallback(targetPlan.title, fallback: "Untitled Plan")
        targetTaskUniqueID = targetTask.uniqueID
        targetTaskLegacyID = targetTask.legacyID
        targetTaskName = Self.trimmedOrFallback(targetTask.name, fallback: "Untitled Task")
        self.relationType = Self.normalizedRelationType(relationType)
        self.lagDays = lagDays
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedAt = Date()
    }

    @discardableResult
    func refresh(
        sourcePlan: PortfolioProjectPlan?,
        sourceTask: PortfolioPlanTask?,
        targetPlan: PortfolioProjectPlan?,
        targetTask: PortfolioPlanTask?
    ) -> Bool {
        var didChange = false

        if let sourcePlan {
            let normalizedPlanTitle = Self.trimmedOrFallback(sourcePlan.title, fallback: "Untitled Plan")
            if sourcePlanID != sourcePlan.portfolioID {
                sourcePlanID = sourcePlan.portfolioID
                didChange = true
            }
            if sourcePlanTitle != normalizedPlanTitle {
                sourcePlanTitle = normalizedPlanTitle
                didChange = true
            }
        }
        if let sourceTask {
            let normalizedTaskName = Self.trimmedOrFallback(sourceTask.name, fallback: "Untitled Task")
            if sourceTaskUniqueID != sourceTask.uniqueID {
                sourceTaskUniqueID = sourceTask.uniqueID
                didChange = true
            }
            if sourceTaskLegacyID != sourceTask.legacyID {
                sourceTaskLegacyID = sourceTask.legacyID
                didChange = true
            }
            if sourceTaskName != normalizedTaskName {
                sourceTaskName = normalizedTaskName
                didChange = true
            }
        }
        if let targetPlan {
            let normalizedPlanTitle = Self.trimmedOrFallback(targetPlan.title, fallback: "Untitled Plan")
            if targetPlanID != targetPlan.portfolioID {
                targetPlanID = targetPlan.portfolioID
                didChange = true
            }
            if targetPlanTitle != normalizedPlanTitle {
                targetPlanTitle = normalizedPlanTitle
                didChange = true
            }
        }
        if let targetTask {
            let normalizedTaskName = Self.trimmedOrFallback(targetTask.name, fallback: "Untitled Task")
            if targetTaskUniqueID != targetTask.uniqueID {
                targetTaskUniqueID = targetTask.uniqueID
                didChange = true
            }
            if targetTaskLegacyID != targetTask.legacyID {
                targetTaskLegacyID = targetTask.legacyID
                didChange = true
            }
            if targetTaskName != normalizedTaskName {
                targetTaskName = normalizedTaskName
                didChange = true
            }
        }
        let normalizedRelation = Self.normalizedRelationType(relationType)
        if relationType != normalizedRelation {
            relationType = normalizedRelation
            didChange = true
        }

        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if note != normalizedNote {
            note = normalizedNote
            didChange = true
        }

        if didChange {
            updatedAt = Date()
        }
        return didChange
    }

    private static func normalizedRelationType(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["FS", "SS", "FF", "SF"].contains(normalized) ? normalized : "FS"
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct PortfolioReviewViewSettings: Codable, Hashable {
    var registryScope: String
    var healthScope: String
    var approvalScope: String
    var grouping: String
    var searchText: String
    var cadenceDays: Int
}

struct PortfolioReviewSnapshotPayload: Codable, Hashable {
    struct ProjectSummary: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let riskBand: String
        let score: Int
        let workspace: String
        let program: String
        let overdueTaskCount: Int
        let slippedMilestoneCount: Int
        let costOverrun: Double
        let completionPercent: Double
    }

    struct AttentionItem: Codable, Hashable, Identifiable {
        let id: String
        let severity: String
        let headline: String
        let planTitle: String
        let detail: String
    }

    struct ProgramSummary: Codable, Hashable, Identifiable {
        let id: String
        let program: String
        let projectCount: Int
        let atRiskProjectCount: Int
        let reviewDueCount: Int
        let slippedMilestoneCount: Int
        let totalBudget: Double
        let totalActualCost: Double
        let nextMilestoneDate: Date?
    }

    struct DependencySummary: Codable, Hashable, Identifiable {
        let id: String
        let severity: String
        let sourcePlanTitle: String
        let sourceTaskName: String
        let targetPlanTitle: String
        let targetTaskName: String
        let relationType: String
        let lagDays: Int
        let blockerReason: String
        let targetDate: Date
    }

    let title: String
    let presetName: String?
    let capturedAt: Date
    let viewSettings: PortfolioReviewViewSettings
    let visibleProjectCount: Int
    let activeProjectCount: Int
    let archivedProjectCount: Int
    let workspaceCount: Int
    let programCount: Int
    let atRiskProjectCount: Int
    let approvedCount: Int
    let intakeCount: Int
    let onHoldCount: Int
    let reviewDueCount: Int
    let overdueTaskCount: Int
    let blockedDependencyCount: Int
    let highDependencyCount: Int
    let crossProgramDependencyCount: Int
    let slippedMilestoneCount: Int
    let roadmapProgramCount: Int
    let overloadedResourceCount: Int
    let budgetTotal: Double
    let actualCostTotal: Double
    let projectSummaries: [ProjectSummary]
    let attentionItems: [AttentionItem]
    let programItems: [ProgramSummary]
    let dependencyItems: [DependencySummary]
}

struct PortfolioReviewDelta: Hashable {
    let current: PortfolioReviewSnapshotPayload
    let baseline: PortfolioReviewSnapshotPayload
    let visibleProjectDelta: Int
    let atRiskProjectDelta: Int
    let blockedDependencyDelta: Int
    let highDependencyDelta: Int
    let reviewDueDelta: Int
    let slippedMilestoneDelta: Int
    let overloadedResourceDelta: Int
    let overdueTaskDelta: Int
    let budgetDelta: Double
    let actualCostDelta: Double
    let newAttentionHeadlines: [String]
    let resolvedAttentionHeadlines: [String]
    let newBlockedDependencies: [String]
}

@Model
final class PortfolioReviewPreset {
    @Attribute(.unique) var uniqueID: UUID
    var name: String
    var registryScope: String
    var healthScope: String
    var approvalScope: String
    var grouping: String
    var searchText: String
    var cadenceDays: Int
    var updatedAt: Date

    init(name: String, viewSettings: PortfolioReviewViewSettings) {
        uniqueID = UUID()
        self.name = Self.trimmedOrFallback(name, fallback: "Portfolio Review")
        registryScope = viewSettings.registryScope
        healthScope = viewSettings.healthScope
        approvalScope = viewSettings.approvalScope
        grouping = viewSettings.grouping
        searchText = viewSettings.searchText
        cadenceDays = max(7, viewSettings.cadenceDays)
        updatedAt = Date()
    }

    var viewSettings: PortfolioReviewViewSettings {
        PortfolioReviewViewSettings(
            registryScope: registryScope,
            healthScope: healthScope,
            approvalScope: approvalScope,
            grouping: grouping,
            searchText: searchText,
            cadenceDays: max(7, cadenceDays)
        )
    }

    func update(name: String, viewSettings: PortfolioReviewViewSettings) {
        self.name = Self.trimmedOrFallback(name, fallback: "Portfolio Review")
        registryScope = viewSettings.registryScope
        healthScope = viewSettings.healthScope
        approvalScope = viewSettings.approvalScope
        grouping = viewSettings.grouping
        searchText = viewSettings.searchText
        cadenceDays = max(7, viewSettings.cadenceDays)
        updatedAt = Date()
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

@Model
final class PortfolioReviewSnapshot {
    @Attribute(.unique) var uniqueID: UUID
    var title: String
    var presetID: UUID?
    var presetName: String?
    var createdAt: Date
    var registryScope: String
    var healthScope: String
    var approvalScope: String
    var grouping: String
    var searchText: String
    var cadenceDays: Int
    var visibleProjectCount: Int
    var atRiskProjectCount: Int
    var blockedDependencyCount: Int
    var slippedMilestoneCount: Int
    var overloadedResourceCount: Int
    var budgetTotal: Double
    var actualCostTotal: Double
    var payloadData: Data

    init(title: String, preset: PortfolioReviewPreset?, payload: PortfolioReviewSnapshotPayload) {
        uniqueID = UUID()
        self.title = Self.trimmedOrFallback(title, fallback: payload.title)
        presetID = preset?.uniqueID
        presetName = preset?.name ?? payload.presetName
        createdAt = payload.capturedAt
        registryScope = payload.viewSettings.registryScope
        healthScope = payload.viewSettings.healthScope
        approvalScope = payload.viewSettings.approvalScope
        grouping = payload.viewSettings.grouping
        searchText = payload.viewSettings.searchText
        cadenceDays = max(7, payload.viewSettings.cadenceDays)
        visibleProjectCount = payload.visibleProjectCount
        atRiskProjectCount = payload.atRiskProjectCount
        blockedDependencyCount = payload.blockedDependencyCount
        slippedMilestoneCount = payload.slippedMilestoneCount
        overloadedResourceCount = payload.overloadedResourceCount
        budgetTotal = payload.budgetTotal
        actualCostTotal = payload.actualCostTotal
        payloadData = Self.encodePayload(payload)
    }

    var viewSettings: PortfolioReviewViewSettings {
        PortfolioReviewViewSettings(
            registryScope: registryScope,
            healthScope: healthScope,
            approvalScope: approvalScope,
            grouping: grouping,
            searchText: searchText,
            cadenceDays: max(7, cadenceDays)
        )
    }

    var payload: PortfolioReviewSnapshotPayload {
        get {
            Self.decodePayload(
                payloadData,
                fallback: PortfolioReviewSnapshotPayload(
                    title: title,
                    presetName: presetName,
                    capturedAt: createdAt,
                    viewSettings: viewSettings,
                    visibleProjectCount: visibleProjectCount,
                    activeProjectCount: visibleProjectCount,
                    archivedProjectCount: 0,
                    workspaceCount: 0,
                    programCount: 0,
                    atRiskProjectCount: atRiskProjectCount,
                    approvedCount: 0,
                    intakeCount: 0,
                    onHoldCount: 0,
                    reviewDueCount: 0,
                    overdueTaskCount: 0,
                    blockedDependencyCount: blockedDependencyCount,
                    highDependencyCount: 0,
                    crossProgramDependencyCount: 0,
                    slippedMilestoneCount: slippedMilestoneCount,
                    roadmapProgramCount: 0,
                    overloadedResourceCount: overloadedResourceCount,
                    budgetTotal: budgetTotal,
                    actualCostTotal: actualCostTotal,
                    projectSummaries: [],
                    attentionItems: [],
                    programItems: [],
                    dependencyItems: []
                )
            )
        }
        set {
            title = Self.trimmedOrFallback(title, fallback: newValue.title)
            presetName = presetName ?? newValue.presetName
            createdAt = newValue.capturedAt
            registryScope = newValue.viewSettings.registryScope
            healthScope = newValue.viewSettings.healthScope
            approvalScope = newValue.viewSettings.approvalScope
            grouping = newValue.viewSettings.grouping
            searchText = newValue.viewSettings.searchText
            cadenceDays = max(7, newValue.viewSettings.cadenceDays)
            visibleProjectCount = newValue.visibleProjectCount
            atRiskProjectCount = newValue.atRiskProjectCount
            blockedDependencyCount = newValue.blockedDependencyCount
            slippedMilestoneCount = newValue.slippedMilestoneCount
            overloadedResourceCount = newValue.overloadedResourceCount
            budgetTotal = newValue.budgetTotal
            actualCostTotal = newValue.actualCostTotal
            payloadData = Self.encodePayload(newValue)
        }
    }

    func update(title: String, preset: PortfolioReviewPreset?, payload: PortfolioReviewSnapshotPayload) {
        self.title = Self.trimmedOrFallback(title, fallback: payload.title)
        presetID = preset?.uniqueID
        presetName = preset?.name ?? payload.presetName
        self.payload = payload
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodePayload<T: Encodable>(_ value: T) -> Data {
        (try? encoder().encode(value)) ?? Data()
    }

    private static func decodePayload<T: Decodable>(_ data: Data, fallback: T) -> T {
        guard !data.isEmpty, let decoded = try? decoder().decode(T.self, from: data) else { return fallback }
        return decoded
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum PortfolioProjectSynchronizerError: LocalizedError {
    case storeRecoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .storeRecoveryRequired(let details):
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "The portfolio data store is inconsistent. Restart MPPViewer and reopen the file. The project can remain open in read-only mode."
            }
            return "The portfolio data store is inconsistent. Restart MPPViewer and reopen the file. The project can remain open in read-only mode. Details: \(trimmed)"
        }
    }
}

enum PortfolioProjectSynchronizer {
    @MainActor
    @discardableResult
    static func upsert(nativePlan: NativeProjectPlan, in context: ModelContext) throws -> PortfolioProjectPlan {
        let normalizedPlan = nativePlan.normalizedForStorage()
        return try upsert(normalizedPlan, in: context)
    }

    @MainActor
    private static func upsert(_ nativePlan: NativeProjectPlan, in context: ModelContext) throws -> PortfolioProjectPlan {
        let identifier = nativePlan.portfolioID
        let descriptor = FetchDescriptor<PortfolioProjectPlan>(
            predicate: #Predicate { plan in
                plan.portfolioID == identifier
            }
        )

        do {
            if let existing = try context.fetch(descriptor).first {
                existing.update(from: nativePlan, in: context)
                try context.save()
                return existing
            } else {
                let created = PortfolioProjectPlan(nativePlan: nativePlan)
                context.insert(created)
                try context.save()
                return created
            }
        } catch {
            context.rollback()
            if requiresStoreRecovery(error) {
                throw PortfolioProjectSynchronizerError.storeRecoveryRequired(error.localizedDescription)
            }
            throw error
        }
    }

    private static func requiresStoreRecovery(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == 1560 || nsError.code == 1570 || nsError.code == 133020 || nsError.code == 133021 || nsError.code == 134110 {
                return true
            }
            if let message = nsError.localizedDescription.lowercased() as String?,
               message.contains("validation") || message.contains("missing attribute values") || message.contains("constraint") || message.contains("duplicate") {
                return true
            }
        }

        if let underlying = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
            return underlying.contains(where: requiresStoreRecovery)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return requiresStoreRecovery(underlying)
        }

        return false
    }
}

private extension NativeProjectPlan {
    func normalizedResourceIDsForAssignmentCompatibility() -> NativeProjectPlan {
        resourceIDCompatibilityRepairedPlan() ?? self
    }

    func resourceIDCompatibilityRepairedPlan() -> NativeProjectPlan? {
        guard let offset = resourceIDCompatibilityRepairOffset() else { return nil }

        var repaired = self
        repaired.resources = resources.map { nativeResource in
            var resource = nativeResource
            if let calendarID = resource.calendarUniqueID {
                resource.id = calendarID - offset
            }
            return resource
        }
        return repaired
    }

    func resourceIDCompatibilityRepairOffset() -> Int? {
        guard !resources.isEmpty, !assignments.isEmpty else { return nil }

        let assignmentResourceIDs = assignments.compactMap(\.resourceID)
        guard !assignmentResourceIDs.isEmpty else { return nil }

        let currentResourceIDs = Set(resources.map(\.id))
        let missingAssignmentResourceIDs = Set(assignmentResourceIDs).subtracting(currentResourceIDs)
        guard !missingAssignmentResourceIDs.isEmpty else { return nil }

        let offsets = resources.compactMap { resource -> Int? in
            guard let calendarID = resource.calendarUniqueID else { return nil }
            let offset = calendarID - resource.id
            return offset == 0 ? nil : offset
        }
        let offsetCounts = Dictionary(grouping: offsets, by: { $0 }).mapValues(\.count)
        guard let bestOffset = offsetCounts.sorted(by: { lhs, rhs in
            lhs.value == rhs.value ? abs(lhs.key) < abs(rhs.key) : lhs.value > rhs.value
        }).first,
            bestOffset.value >= max(3, resources.count / 2) else {
            return nil
        }

        let repairedResourceIDs = resources.map { resource in
            resource.calendarUniqueID.map { $0 - bestOffset.key } ?? resource.id
        }
        guard Set(repairedResourceIDs).count == resources.count else { return nil }

        let currentMatchCount = assignmentResourceIDs.filter(currentResourceIDs.contains).count
        let repairedResourceIDSet = Set(repairedResourceIDs)
        let repairedMatchCount = assignmentResourceIDs.filter(repairedResourceIDSet.contains).count

        guard repairedMatchCount > currentMatchCount,
              repairedMatchCount >= assignmentResourceIDs.count / 2 else {
            return nil
        }

        return bestOffset.key
    }

    func normalizedForStorage() -> NativeProjectPlan {
        var normalized = normalizedResourceIDsForAssignmentCompatibility()

        normalized.boardColumns = Self.normalizedBoardColumns(normalized.boardColumns)
        let synchronizedStorage = Self.synchronizedWorkflowStorage(
            boardColumns: normalized.boardColumns,
            workflowColumns: normalized.workflowColumns,
            typeWorkflowOverrides: normalized.typeWorkflowOverrides
        )
        normalized.workflowColumns = synchronizedStorage.workflowColumns
        normalized.boardColumns = synchronizedStorage.workflowColumns.map(\.name)
        normalized.typeWorkflowOverrides = synchronizedStorage.typeWorkflowOverrides

        normalized.resources = normalized.resources.map { nativeResource in
            var resource = nativeResource
            resource.accrueAt = resource.accrueAtValue
            resource.name = resource.name.nonEmpty ?? "Unnamed Resource"
            resource.type = resource.type.nonEmpty ?? "Work"
            return resource
        }

        return normalized
    }
}

@ModelActor
actor PlanSchedulerModelActor {
    func reschedule(planID: PersistentIdentifier) async throws {
        guard let storedPlan = modelContext.model(for: planID) as? PortfolioProjectPlan else { return }
        var nativePlan = storedPlan.asNativePlan()
        await nativePlan.reschedule()
        storedPlan.update(from: nativePlan, in: modelContext)
        try modelContext.save()
    }
}
