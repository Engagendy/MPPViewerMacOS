import AppKit
import UniformTypeIdentifiers

enum CSVExporter {

    private static let importDateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "dd/MM/yyyy",
            "MM/dd/yyyy",
            "dd-MM-yyyy",
            "MM-dd-yyyy"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            return formatter
        }
    }()

    @MainActor
    static func selectTaskImportSession() -> CSVTaskImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVTaskImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultTaskMapping(for: headerRow)
        )
    }

    @MainActor
    static func applyTaskImport(_ session: CSVTaskImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let nameIndex = session.mapping[.name] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Task Name` before importing.")
            return nil
        }

        var plan = originalPlan
        let existingResourceNames = Set(plan.resources.map { normalizedLookupKey($0.name) })
        var knownResourceNames = existingResourceNames
        var nextSyntheticTaskSourceID = 1
        var sourceTaskIDToImportedTaskID: [String: Int] = [:]
        var pendingPredecessors: [(taskID: Int, rowNumber: Int, tokens: [String])] = []
        var importedTaskCount = 0
        var importedAssignmentCount = 0
        var autoCreatedResourceCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let taskName = stringValue(in: row, at: nameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !taskName.isEmpty else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: nil, severity: .warning, message: "Skipped row because `Task Name` is empty."))
                continue
            }

            let sourceTaskID = sourceIdentifier(
                from: row,
                mappedIndex: session.mapping[.sourceID] ?? nil,
                fallback: nextSyntheticTaskSourceID
            )
            nextSyntheticTaskSourceID += 1

            let rawStart = session.mapping[.startDate].flatMap { stringValue(in: row, at: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let rawFinish = session.mapping[.finishDate].flatMap { stringValue(in: row, at: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

            let start = dateValue(in: row, at: session.mapping[.startDate] ?? nil)
            let finish = dateValue(in: row, at: session.mapping[.finishDate] ?? nil)
            let actualStart = dateValue(in: row, at: session.mapping[.actualStartDate] ?? nil)
            let actualFinish = dateValue(in: row, at: session.mapping[.actualFinishDate] ?? nil)
            let parsedDurationDays = durationDaysValue(in: row, at: session.mapping[.duration] ?? nil)
            let parsedMilestone = boolValue(in: row, at: session.mapping[.milestone] ?? nil)
            let inferredMilestone = parsedMilestone ?? ((parsedDurationDays == 0) ? true : nil)
            let isMilestone = inferredMilestone ?? false

            var task = plan.makeTask(name: taskName, anchoredTo: start ?? plan.statusDate)
            task.startDate = Calendar.current.startOfDay(for: start ?? task.startDate)
            task.finishDate = Calendar.current.startOfDay(for: finish ?? task.startDate)
            task.durationDays = max(1, parsedDurationDays ?? durationDaysBetween(start: task.startDate, finish: task.finishDate))
            task.isMilestone = isMilestone
            task.manuallyScheduled = boolValue(in: row, at: session.mapping[.manualScheduling] ?? nil) ?? false
            task.percentComplete = doubleValue(in: row, at: session.mapping[.percentComplete] ?? nil) ?? 0
            task.priority = intValue(in: row, at: session.mapping[.priority] ?? nil) ?? 500
            task.notes = stringValue(in: row, at: session.mapping[.notes] ?? nil)
            task.fixedCost = max(0, doubleValue(in: row, at: session.mapping[.fixedCost] ?? nil) ?? task.fixedCost)
            task.baselineCost = doubleValue(in: row, at: session.mapping[.baselineCost] ?? nil)
            task.actualCost = doubleValue(in: row, at: session.mapping[.actualCost] ?? nil)
            task.actualStartDate = actualStart.map { Calendar.current.startOfDay(for: $0) }
            task.actualFinishDate = actualFinish.map { Calendar.current.startOfDay(for: $0) }
            task.outlineLevel = outlineLevelValue(
                in: row,
                mappedIndex: session.mapping[.outlineLevel] ?? nil,
                wbsIndex: session.mapping[.wbs] ?? nil
            ) ?? 1
            let rawCalendarName = stringValue(in: row, at: session.mapping[.calendar] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            task.calendarUniqueID = calendarIDValue(in: row, at: session.mapping[.calendar] ?? nil, calendars: plan.calendars)
            task.isActive = boolValue(in: row, at: session.mapping[.active] ?? nil) ?? true

            if task.isMilestone {
                task.finishDate = task.startDate
                task.durationDays = 1
            } else if finish == nil && !task.manuallyScheduled {
                task.finishDate = task.startDate
            }

            if task.actualFinishDate != nil {
                task.percentComplete = 100
            } else if task.actualStartDate != nil, task.percentComplete == 0 {
                task.percentComplete = 1
            }

            plan.tasks.append(task)
            importedTaskCount += 1
            sourceTaskIDToImportedTaskID[sourceTaskID] = task.id

            if !rawStart.isEmpty, start == nil {
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: task.id, severity: .warning, message: "Could not parse start date `\(rawStart)`; used the plan status date instead."))
            }

            if !rawFinish.isEmpty, finish == nil {
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: task.id, severity: .warning, message: "Could not parse finish date `\(rawFinish)`; the scheduler will infer it."))
            }

            let rawActualStart = stringValue(in: row, at: session.mapping[.actualStartDate] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawActualStart.isEmpty, actualStart == nil {
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: task.id, severity: .warning, message: "Could not parse actual start `\(rawActualStart)`; left actual start empty."))
            }

            let rawActualFinish = stringValue(in: row, at: session.mapping[.actualFinishDate] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawActualFinish.isEmpty, actualFinish == nil {
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: task.id, severity: .warning, message: "Could not parse actual finish `\(rawActualFinish)`; left actual finish empty."))
            }

            if !rawCalendarName.isEmpty, task.calendarUniqueID == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: task.id,
                    severity: .warning,
                    message: "Calendar `\(rawCalendarName)` was not found; the task uses the project default calendar.",
                    fixAction: .createTaskCalendar(name: rawCalendarName, taskID: task.id)
                ))
            }

            let predecessorTokens = predecessorTokens(in: row, at: session.mapping[.predecessors] ?? nil)
            if !predecessorTokens.isEmpty {
                pendingPredecessors.append((taskID: task.id, rowNumber: rowNumber, tokens: predecessorTokens))
            }

            let assignmentSpecs = assignmentSpecs(
                in: row,
                resourceNamesIndex: session.mapping[.resourceNames] ?? nil,
                assignmentsIndex: session.mapping[.assignments] ?? nil,
                unitsIndex: session.mapping[.units] ?? nil
            )
            for spec in assignmentSpecs {
                let key = normalizedLookupKey(spec.name)
                if !knownResourceNames.contains(key) {
                    let resource = plan.makeResource(name: spec.name)
                    plan.resources.append(resource)
                    knownResourceNames.insert(key)
                    autoCreatedResourceCount += 1
                }

                guard let resourceID = plan.resources.first(where: { normalizedLookupKey($0.name) == key })?.id else { continue }
                var assignment = plan.makeAssignment(taskID: task.id, resourceID: resourceID)
                assignment.units = spec.units ?? 100
                plan.assignments.append(assignment)
                importedAssignmentCount += 1
            }
        }

        let existingTaskIDs = Set(plan.tasks.map(\.id))
        for pending in pendingPredecessors {
            guard let taskIndex = plan.tasks.firstIndex(where: { $0.id == pending.taskID }) else { continue }
            let resolved = pending.tokens.compactMap { token -> Int? in
                if let imported = sourceTaskIDToImportedTaskID[token] {
                    return imported
                }
                if let existing = Int(token), existingTaskIDs.contains(existing) {
                    return existing
                }
                return nil
            }
            .filter { $0 != pending.taskID }

            let resolvedTokens = Set(resolved.map(String.init))
            let unresolved = pending.tokens.filter { !resolvedTokens.contains($0) }
            for token in unresolved {
                issues.append(CSVImportIssue(rowNumber: pending.rowNumber, targetID: pending.taskID, severity: .warning, message: "Predecessor `\(token)` could not be resolved and was skipped."))
            }

            plan.tasks[taskIndex].predecessorTaskIDs = Array(Set(resolved)).sorted()
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Task Import Complete",
                summaryLines: [
                    "Imported \(importedTaskCount) tasks",
                    "Created \(importedAssignmentCount) assignments",
                    "Auto-created \(autoCreatedResourceCount) resources",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func selectResourceImportSession() -> CSVResourceImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVResourceImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultResourceMapping(for: headerRow)
        )
    }

    @MainActor
    static func selectAssignmentImportSession() -> CSVAssignmentImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVAssignmentImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultAssignmentMapping(for: headerRow)
        )
    }

    @MainActor
    static func selectDependencyImportSession() -> CSVDependencyImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVDependencyImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultDependencyMapping(for: headerRow)
        )
    }

    @MainActor
    static func selectConstraintImportSession() -> CSVConstraintImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVConstraintImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultConstraintMapping(for: headerRow)
        )
    }

    @MainActor
    static func selectBaselineImportSession() -> CSVBaselineImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVBaselineImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultBaselineMapping(for: headerRow)
        )
    }

    @MainActor
    static func applyResourceImport(_ session: CSVResourceImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let nameIndex = session.mapping[.name] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Resource Name` before importing.")
            return nil
        }

        var plan = originalPlan
        var importedCount = 0
        var updatedCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let resourceName = stringValue(in: row, at: nameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !resourceName.isEmpty else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: nil, severity: .warning, message: "Skipped row because `Resource Name` is empty."))
                continue
            }

            let key = normalizedLookupKey(resourceName)
            let resourceIndex = plan.resources.firstIndex { normalizedLookupKey($0.name) == key }
            let existing = resourceIndex.map { plan.resources[$0] }
            var resource = existing ?? plan.makeResource(name: resourceName)

            resource.name = resourceName
            resource.type = stringValue(in: row, at: session.mapping[.type] ?? nil).nonEmpty ?? resource.type
            resource.maxUnits = doubleValue(in: row, at: session.mapping[.maxUnits] ?? nil) ?? resource.maxUnits
            resource.standardRate = max(0, doubleValue(in: row, at: session.mapping[.standardRate] ?? nil) ?? resource.standardRate)
            resource.overtimeRate = max(0, doubleValue(in: row, at: session.mapping[.overtimeRate] ?? nil) ?? resource.overtimeRate)
            resource.costPerUse = max(0, doubleValue(in: row, at: session.mapping[.costPerUse] ?? nil) ?? resource.costPerUse)
            resource.emailAddress = stringValue(in: row, at: session.mapping[.email] ?? nil)
            resource.group = stringValue(in: row, at: session.mapping[.group] ?? nil)
            resource.initials = stringValue(in: row, at: session.mapping[.initials] ?? nil)
            resource.notes = stringValue(in: row, at: session.mapping[.notes] ?? nil)
            resource.accrueAt = stringValue(in: row, at: session.mapping[.accrueAt] ?? nil).nonEmpty ?? resource.accrueAt
            let rawCalendarName = stringValue(in: row, at: session.mapping[.calendar] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCalendarID = calendarIDValue(in: row, at: session.mapping[.calendar] ?? nil, calendars: plan.calendars)
            if !rawCalendarName.isEmpty, resolvedCalendarID == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: resource.id,
                    severity: .warning,
                    message: "Calendar `\(rawCalendarName)` was not found; kept the existing calendar for `\(resourceName)`.",
                    fixAction: .createResourceCalendar(name: rawCalendarName, resourceID: resource.id)
                ))
            }
            resource.calendarUniqueID = resolvedCalendarID ?? resource.calendarUniqueID
            resource.active = boolValue(in: row, at: session.mapping[.active] ?? nil) ?? resource.active

            if let resourceIndex {
                plan.resources[resourceIndex] = resource
                updatedCount += 1
            } else {
                plan.resources.append(resource)
                importedCount += 1
            }
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Resource Import Complete",
                summaryLines: [
                    "Imported \(importedCount) resources",
                    "Updated \(updatedCount) existing resources",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func selectCalendarImportSession() -> CSVCalendarImportSession? {
        guard let selected = selectTabularFile(),
              let headerRow = selected.rows.first else {
            return nil
        }

        let dataRows = Array(selected.rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return CSVCalendarImportSession(
            fileName: selected.url.lastPathComponent,
            headers: headerRow,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: defaultCalendarMapping(for: headerRow)
        )
    }

    @MainActor
    static func applyCalendarImport(_ session: CSVCalendarImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let nameIndex = session.mapping[.name] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Calendar Name` before importing.")
            return nil
        }

        var plan = originalPlan
        var calendarIDsByKey = Dictionary(uniqueKeysWithValues: plan.calendars.map { (normalizedLookupKey($0.name), $0.id) })
        var pendingParentInfoByCalendarID: [Int: (normalized: String?, raw: String?)] = [:]
        var importedCount = 0
        var updatedCount = 0
        var exceptionCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let calendarName = stringValue(in: row, at: nameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !calendarName.isEmpty else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: nil, severity: .warning, message: "Skipped row because `Calendar Name` is empty."))
                continue
            }

            let key = normalizedLookupKey(calendarName)
            let existingIndex = plan.calendars.firstIndex { normalizedLookupKey($0.name) == key }
            var calendar = existingIndex.map { plan.calendars[$0] } ?? plan.makeCalendar(name: calendarName)

            calendar.name = calendarName
            calendar.type = stringValue(in: row, at: session.mapping[.type] ?? nil).nonEmpty ?? calendar.type
            calendar.personal = boolValue(in: row, at: session.mapping[.personal] ?? nil) ?? calendar.personal

            for descriptor in weekdayImportDescriptors {
                applyCalendarDay(
                    to: &calendar,
                    weekday: descriptor.weekday,
                    workingIndex: session.mapping[descriptor.workingField] ?? nil,
                    fromIndex: session.mapping[descriptor.fromField] ?? nil,
                    toIndex: session.mapping[descriptor.toField] ?? nil,
                    row: row
                )
            }

            if let rawParentName = stringValue(in: row, at: session.mapping[.parentName] ?? nil).nonEmpty {
                pendingParentInfoByCalendarID[calendar.id] = (normalizedLookupKey(rawParentName), rawParentName)
            } else if session.mapping[.parentName] != nil {
                pendingParentInfoByCalendarID[calendar.id] = (nil, nil)
            }

            let rawExceptionFrom = stringValue(in: row, at: session.mapping[.exceptionFromDate] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawExceptionTo = stringValue(in: row, at: session.mapping[.exceptionToDate] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            if (!rawExceptionFrom.isEmpty || !rawExceptionTo.isEmpty), importedException(from: row, session: session) == nil {
                issues.append(CSVImportIssue(rowNumber: rowNumber, targetID: calendar.id, severity: .warning, message: "Exception dates could not be parsed for calendar `\(calendarName)`; the exception row was skipped."))
            }

            if let exception = importedException(from: row, session: session) {
                if !containsCalendarException(exception, in: calendar.exceptions) {
                    calendar.exceptions.append(exception)
                    exceptionCount += 1
                }
            }

            if let existingIndex {
                plan.calendars[existingIndex] = calendar
                updatedCount += 1
            } else {
                plan.calendars.append(calendar)
                calendarIDsByKey[key] = calendar.id
                importedCount += 1
            }
        }

        calendarIDsByKey = Dictionary(uniqueKeysWithValues: plan.calendars.map { (normalizedLookupKey($0.name), $0.id) })
        for index in plan.calendars.indices {
            guard let parentInfo = pendingParentInfoByCalendarID[plan.calendars[index].id] else { continue }
            if let parentKey = parentInfo.normalized, let parentID = calendarIDsByKey[parentKey], parentID != plan.calendars[index].id {
                plan.calendars[index].parentUniqueID = parentID
            } else {
                if let rawParentName = parentInfo.raw {
                    issues.append(CSVImportIssue(
                        rowNumber: nil,
                        targetID: plan.calendars[index].id,
                        severity: .warning,
                        message: "Parent calendar `\(rawParentName)` was not found for `\(plan.calendars[index].name)`; parent link was cleared.",
                        fixAction: .createParentCalendar(name: rawParentName, calendarID: plan.calendars[index].id)
                    ))
                }
                plan.calendars[index].parentUniqueID = nil
            }
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Calendar Import Complete",
                summaryLines: [
                    "Imported \(importedCount) calendars",
                    "Updated \(updatedCount) existing calendars",
                    "Added \(exceptionCount) exceptions",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func applyAssignmentImport(_ session: CSVAssignmentImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        let taskIDIndex = session.mapping[.taskID] ?? nil
        let taskNameIndex = session.mapping[.taskName] ?? nil
        guard taskIDIndex != nil || taskNameIndex != nil else {
            showImportAlert(title: "Import Failed", message: "Map either `Task ID` or `Task Name` before importing assignments.")
            return nil
        }

        guard let resourceNameIndex = session.mapping[.resourceName] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Resource Name` before importing assignments.")
            return nil
        }

        var plan = originalPlan
        let taskNameLookup = Dictionary(grouping: plan.tasks.indices, by: { normalizedLookupKey(plan.tasks[$0].name) })
        var resourceLookup = Dictionary(uniqueKeysWithValues: plan.resources.map { (normalizedLookupKey($0.name), $0.id) })
        var createdCount = 0
        var updatedCount = 0
        var autoCreatedResourceCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let rawTaskID = stringValue(in: row, at: taskIDIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTaskName = stringValue(in: row, at: taskNameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let resourceName = stringValue(in: row, at: resourceNameIndex).trimmingCharacters(in: .whitespacesAndNewlines)

            let taskIndex: Int?
            if !rawTaskID.isEmpty {
                if let taskID = Int(rawTaskID),
                   let resolvedIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) {
                    taskIndex = resolvedIndex
                } else {
                    skippedRowCount += 1
                    issues.append(CSVImportIssue(
                        rowNumber: rowNumber,
                        targetID: nil,
                        severity: .warning,
                        message: "Task ID `\(rawTaskID)` was not found; the assignment row was skipped."
                    ))
                    continue
                }
            } else if !rawTaskName.isEmpty {
                let matches = taskNameLookup[normalizedLookupKey(rawTaskName)] ?? []
                if matches.count == 1, let resolvedIndex = matches.first {
                    taskIndex = resolvedIndex
                } else if matches.count > 1 {
                    skippedRowCount += 1
                    issues.append(CSVImportIssue(
                        rowNumber: rowNumber,
                        targetID: nil,
                        severity: .warning,
                        message: "Task name `\(rawTaskName)` matched multiple tasks; use `Task ID` to disambiguate."
                    ))
                    continue
                } else {
                    skippedRowCount += 1
                    issues.append(CSVImportIssue(
                        rowNumber: rowNumber,
                        targetID: nil,
                        severity: .warning,
                        message: "Task name `\(rawTaskName)` was not found; the assignment row was skipped."
                    ))
                    continue
                }
            } else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: nil,
                    severity: .warning,
                    message: "Skipped row because no task reference was mapped."
                ))
                continue
            }

            guard let taskIndex else { continue }
            let taskID = plan.tasks[taskIndex].id

            guard !resourceName.isEmpty else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Skipped row because `Resource Name` is empty."
                ))
                continue
            }

            let resourceKey = normalizedLookupKey(resourceName)
            let resourceID: Int
            if let existingResourceID = resourceLookup[resourceKey] {
                resourceID = existingResourceID
            } else {
                let resource = plan.makeResource(name: resourceName)
                plan.resources.append(resource)
                resourceLookup[resourceKey] = resource.id
                resourceID = resource.id
                autoCreatedResourceCount += 1
            }

            let units = doubleValue(in: row, at: session.mapping[.units] ?? nil) ?? 100
            let workHoursRaw = stringValue(in: row, at: session.mapping[.workHours] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let workHours = doubleValue(in: row, at: session.mapping[.workHours] ?? nil)
            let actualWorkHoursRaw = stringValue(in: row, at: session.mapping[.actualWorkHours] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let actualWorkHours = doubleValue(in: row, at: session.mapping[.actualWorkHours] ?? nil)
            let remainingWorkHoursRaw = stringValue(in: row, at: session.mapping[.remainingWorkHours] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainingWorkHours = doubleValue(in: row, at: session.mapping[.remainingWorkHours] ?? nil)
            let overtimeWorkHoursRaw = stringValue(in: row, at: session.mapping[.overtimeWorkHours] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)
            let overtimeWorkHours = doubleValue(in: row, at: session.mapping[.overtimeWorkHours] ?? nil)
            let notes = stringValue(in: row, at: session.mapping[.notes] ?? nil)

            if !workHoursRaw.isEmpty, workHours == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Work Hours `\(workHoursRaw)` could not be parsed; kept the assignment work empty."
                ))
            }

            if !actualWorkHoursRaw.isEmpty, actualWorkHours == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Actual Work Hours `\(actualWorkHoursRaw)` could not be parsed; kept actual work empty."
                ))
            }

            if !remainingWorkHoursRaw.isEmpty, remainingWorkHours == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Remaining Work Hours `\(remainingWorkHoursRaw)` could not be parsed; kept remaining work empty."
                ))
            }

            if !overtimeWorkHoursRaw.isEmpty, overtimeWorkHours == nil {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Overtime Work Hours `\(overtimeWorkHoursRaw)` could not be parsed; kept overtime work empty."
                ))
            }

            if let assignmentIndex = plan.assignments.firstIndex(where: { $0.taskID == taskID && $0.resourceID == resourceID }) {
                plan.assignments[assignmentIndex].units = max(0, units)
                plan.assignments[assignmentIndex].notes = notes
                plan.assignments[assignmentIndex].workSeconds = workHours.map { Int(max(0, $0) * 3600) }
                plan.assignments[assignmentIndex].actualWorkSeconds = actualWorkHours.map { Int(max(0, $0) * 3600) }
                plan.assignments[assignmentIndex].remainingWorkSeconds = remainingWorkHours.map { Int(max(0, $0) * 3600) }
                plan.assignments[assignmentIndex].overtimeWorkSeconds = overtimeWorkHours.map { Int(max(0, $0) * 3600) }
                updatedCount += 1
            } else {
                var assignment = plan.makeAssignment(taskID: taskID, resourceID: resourceID)
                assignment.units = max(0, units)
                assignment.notes = notes
                assignment.workSeconds = workHours.map { Int(max(0, $0) * 3600) }
                assignment.actualWorkSeconds = actualWorkHours.map { Int(max(0, $0) * 3600) }
                assignment.remainingWorkSeconds = remainingWorkHours.map { Int(max(0, $0) * 3600) }
                assignment.overtimeWorkSeconds = overtimeWorkHours.map { Int(max(0, $0) * 3600) }
                plan.assignments.append(assignment)
                createdCount += 1
            }
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Assignment Import Complete",
                summaryLines: [
                    "Created \(createdCount) assignments",
                    "Updated \(updatedCount) existing assignments",
                    "Auto-created \(autoCreatedResourceCount) resources",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func applyDependencyImport(_ session: CSVDependencyImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        let taskIDIndex = session.mapping[.taskID] ?? nil
        let taskNameIndex = session.mapping[.taskName] ?? nil
        guard taskIDIndex != nil || taskNameIndex != nil else {
            showImportAlert(title: "Import Failed", message: "Map either `Task ID` or `Task Name` before importing dependencies.")
            return nil
        }

        guard let predecessorsIndex = session.mapping[.predecessors] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Predecessors` before importing dependencies.")
            return nil
        }

        var plan = originalPlan
        let taskNameLookup = Dictionary(grouping: plan.tasks.indices, by: { normalizedLookupKey(plan.tasks[$0].name) })
        let taskIDSet = Set(plan.tasks.map(\.id))
        var updatedTaskCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        func resolveTaskIndex(taskIDText: String, taskNameText: String) -> Int? {
            if !taskIDText.isEmpty, let taskID = Int(taskIDText) {
                return plan.tasks.firstIndex(where: { $0.id == taskID })
            }

            if !taskNameText.isEmpty {
                let matches = taskNameLookup[normalizedLookupKey(taskNameText)] ?? []
                return matches.count == 1 ? matches.first : nil
            }

            return nil
        }

        func resolvePredecessorID(token: String) -> Int? {
            if let taskID = Int(token), taskIDSet.contains(taskID) {
                return taskID
            }

            let matches = taskNameLookup[normalizedLookupKey(token)] ?? []
            return matches.count == 1 ? plan.tasks[matches[0]].id : nil
        }

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let rawTaskID = stringValue(in: row, at: taskIDIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTaskName = stringValue(in: row, at: taskNameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let predecessorTokens = predecessorTokens(in: row, at: predecessorsIndex)

            guard let taskIndex = resolveTaskIndex(taskIDText: rawTaskID, taskNameText: rawTaskName) else {
                skippedRowCount += 1
                let taskReference = rawTaskID.nonEmpty ?? rawTaskName.nonEmpty ?? "unknown task"
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: nil,
                    severity: .warning,
                    message: "Task `\(taskReference)` was not found or was ambiguous; the dependency row was skipped."
                ))
                continue
            }

            let taskID = plan.tasks[taskIndex].id
            if predecessorTokens.isEmpty {
                plan.tasks[taskIndex].predecessorTaskIDs = []
                updatedTaskCount += 1
                continue
            }

            let resolved = predecessorTokens.compactMap(resolvePredecessorID).filter { $0 != taskID }
            let resolvedSet = Set(resolved)
            let unresolved = predecessorTokens.filter { token in
                guard let resolvedID = resolvePredecessorID(token: token) else { return true }
                return !resolvedSet.contains(resolvedID)
            }

            for token in unresolved {
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Predecessor `\(token)` could not be resolved and was skipped."
                ))
            }

            plan.tasks[taskIndex].predecessorTaskIDs = Array(resolvedSet).sorted()
            updatedTaskCount += 1
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Dependency Import Complete",
                summaryLines: [
                    "Updated \(updatedTaskCount) task dependency lists",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func applyConstraintImport(_ session: CSVConstraintImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        let taskIDIndex = session.mapping[.taskID] ?? nil
        let taskNameIndex = session.mapping[.taskName] ?? nil
        guard taskIDIndex != nil || taskNameIndex != nil else {
            showImportAlert(title: "Import Failed", message: "Map either `Task ID` or `Task Name` before importing constraints.")
            return nil
        }

        guard let constraintTypeIndex = session.mapping[.constraintType] ?? nil else {
            showImportAlert(title: "Import Failed", message: "Map a column to `Constraint Type` before importing constraints.")
            return nil
        }

        var plan = originalPlan
        let taskNameLookup = Dictionary(grouping: plan.tasks.indices, by: { normalizedLookupKey(plan.tasks[$0].name) })
        var updatedTaskCount = 0
        var clearedTaskCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let rawTaskID = stringValue(in: row, at: taskIDIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTaskName = stringValue(in: row, at: taskNameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawConstraintType = stringValue(in: row, at: constraintTypeIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawConstraintDate = stringValue(in: row, at: session.mapping[.constraintDate] ?? nil).trimmingCharacters(in: .whitespacesAndNewlines)

            let taskIndex: Int?
            if !rawTaskID.isEmpty, let taskID = Int(rawTaskID) {
                taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID })
            } else if !rawTaskName.isEmpty {
                let matches = taskNameLookup[normalizedLookupKey(rawTaskName)] ?? []
                taskIndex = matches.count == 1 ? matches.first : nil
            } else {
                taskIndex = nil
            }

            guard let taskIndex else {
                skippedRowCount += 1
                let taskReference = rawTaskID.nonEmpty ?? rawTaskName.nonEmpty ?? "unknown task"
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: nil,
                    severity: .warning,
                    message: "Task `\(taskReference)` was not found or was ambiguous; the constraint row was skipped."
                ))
                continue
            }

            let taskID = plan.tasks[taskIndex].id
            let normalizedType = normalizedImportedConstraintType(rawConstraintType)
            let constraintDate = dateValue(from: rawConstraintDate)

            if normalizedType == nil || normalizedType == "ASAP" {
                plan.tasks[taskIndex].constraintType = nil
                plan.tasks[taskIndex].constraintDate = nil
                clearedTaskCount += 1
                continue
            }

            guard ["SNET", "FNET", "MSO", "MFO"].contains(normalizedType ?? "") else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Constraint type `\(rawConstraintType)` is not supported; the row was skipped."
                ))
                continue
            }

            guard let constraintDate else {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Constraint date `\(rawConstraintDate)` could not be parsed; the row was skipped."
                ))
                continue
            }

            plan.tasks[taskIndex].constraintType = normalizedType
            plan.tasks[taskIndex].constraintDate = Calendar.current.startOfDay(for: constraintDate)
            updatedTaskCount += 1
        }

        plan.reschedule()
        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Constraint Import Complete",
                summaryLines: [
                    "Updated \(updatedTaskCount) task constraints",
                    "Cleared \(clearedTaskCount) constraints",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

    @MainActor
    static func applyBaselineImport(_ session: CSVBaselineImportSession, into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        let taskIDIndex = session.mapping[.taskID] ?? nil
        let taskNameIndex = session.mapping[.taskName] ?? nil
        guard taskIDIndex != nil || taskNameIndex != nil else {
            showImportAlert(title: "Import Failed", message: "Map either `Task ID` or `Task Name` before importing baselines.")
            return nil
        }

        let startIndex = session.mapping[.baselineStart] ?? nil
        let finishIndex = session.mapping[.baselineFinish] ?? nil
        let durationIndex = session.mapping[.baselineDuration] ?? nil
        guard startIndex != nil || finishIndex != nil || durationIndex != nil else {
            showImportAlert(title: "Import Failed", message: "Map at least one baseline field before importing.")
            return nil
        }

        var plan = originalPlan
        let taskNameLookup = Dictionary(grouping: plan.tasks.indices, by: { normalizedLookupKey(plan.tasks[$0].name) })
        var updatedTaskCount = 0
        var clearedTaskCount = 0
        var skippedRowCount = 0
        var issues: [CSVImportIssue] = []

        for (rowOffset, row) in session.dataRows.enumerated() {
            let rowNumber = rowOffset + 2
            let rawTaskID = stringValue(in: row, at: taskIDIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTaskName = stringValue(in: row, at: taskNameIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawBaselineStart = stringValue(in: row, at: startIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawBaselineFinish = stringValue(in: row, at: finishIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawBaselineDuration = stringValue(in: row, at: durationIndex).trimmingCharacters(in: .whitespacesAndNewlines)

            let taskIndex: Int?
            if !rawTaskID.isEmpty, let taskID = Int(rawTaskID) {
                taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID })
            } else if !rawTaskName.isEmpty {
                let matches = taskNameLookup[normalizedLookupKey(rawTaskName)] ?? []
                taskIndex = matches.count == 1 ? matches.first : nil
            } else {
                taskIndex = nil
            }

            guard let taskIndex else {
                skippedRowCount += 1
                let taskReference = rawTaskID.nonEmpty ?? rawTaskName.nonEmpty ?? "unknown task"
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: nil,
                    severity: .warning,
                    message: "Task `\(taskReference)` was not found or was ambiguous; the baseline row was skipped."
                ))
                continue
            }

            let taskID = plan.tasks[taskIndex].id
            let baselineStart = dateValue(from: rawBaselineStart)
            let baselineFinish = dateValue(from: rawBaselineFinish)
            let baselineDurationDays = durationDaysValue(from: rawBaselineDuration)

            if !rawBaselineStart.isEmpty, baselineStart == nil {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Baseline start `\(rawBaselineStart)` could not be parsed; the row was skipped."
                ))
                continue
            }

            if !rawBaselineFinish.isEmpty, baselineFinish == nil {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Baseline finish `\(rawBaselineFinish)` could not be parsed; the row was skipped."
                ))
                continue
            }

            if !rawBaselineDuration.isEmpty, baselineDurationDays == nil {
                skippedRowCount += 1
                issues.append(CSVImportIssue(
                    rowNumber: rowNumber,
                    targetID: taskID,
                    severity: .warning,
                    message: "Baseline duration `\(rawBaselineDuration)` could not be parsed; the row was skipped."
                ))
                continue
            }

            if rawBaselineStart.isEmpty, rawBaselineFinish.isEmpty, rawBaselineDuration.isEmpty {
                plan.tasks[taskIndex].baselineStartDate = nil
                plan.tasks[taskIndex].baselineFinishDate = nil
                plan.tasks[taskIndex].baselineDurationDays = nil
                clearedTaskCount += 1
                continue
            }

            let normalizedStart = (baselineStart ?? baselineFinish).map { Calendar.current.startOfDay(for: $0) }
            let normalizedFinish = (baselineFinish ?? baselineStart).map { Calendar.current.startOfDay(for: $0) }

            if let normalizedStart, let normalizedFinish {
                plan.tasks[taskIndex].baselineStartDate = min(normalizedStart, normalizedFinish)
                plan.tasks[taskIndex].baselineFinishDate = max(normalizedStart, normalizedFinish)
            } else {
                plan.tasks[taskIndex].baselineStartDate = normalizedStart
                plan.tasks[taskIndex].baselineFinishDate = normalizedFinish
            }

            if let baselineDurationDays {
                plan.tasks[taskIndex].baselineDurationDays = baselineDurationDays
            } else if let start = plan.tasks[taskIndex].baselineStartDate,
                      let finish = plan.tasks[taskIndex].baselineFinishDate {
                let inferredDays = durationDaysBetween(start: start, finish: finish)
                plan.tasks[taskIndex].baselineDurationDays = start == finish
                    ? (plan.tasks[taskIndex].isMilestone ? 0 : 1)
                    : max(1, inferredDays)
            } else {
                plan.tasks[taskIndex].baselineDurationDays = plan.tasks[taskIndex].isMilestone ? 0 : nil
            }

            updatedTaskCount += 1
        }

        return CSVImportResult(
            plan: plan,
            report: CSVImportReport(
                title: "Baseline Import Complete",
                summaryLines: [
                    "Updated \(updatedTaskCount) task baselines",
                    "Cleared \(clearedTaskCount) task baselines",
                    "Skipped \(skippedRowCount) rows"
                ],
                issues: issues
            )
        )
    }

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

        var csv = taskExportHeaders.joined(separator: ",") + "\n"
        appendRows(tasks: tasks, allTasks: allTasks, resources: resources, assignments: assignments, to: &csv)

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportTasksToExcel(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        resources: [ProjectResource],
        assignments: [ResourceAssignment],
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xls") ?? .data]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var rows: [[String]] = []
        appendExcelRows(
            tasks: tasks,
            allTasks: allTasks,
            resources: resources,
            assignments: assignments,
            to: &rows
        )

        let workbook = excelWorkbookXML(
            headers: taskExportHeaders,
            rows: rows,
            sheetName: "Task List"
        )

        try? workbook.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportTaskImportTemplateCSV() {
        exportCSVTemplate(
            headers: taskImportTemplateHeaders,
            sampleRows: taskImportTemplateSampleRows,
            fileName: "Task Import Template.csv"
        )
    }

    @MainActor
    static func exportTaskImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: taskImportTemplateHeaders,
            sampleRows: taskImportTemplateSampleRows,
            sheetName: "Task Import",
            fileName: "Task Import Example.xls"
        )
    }

    @MainActor
    static func exportResourceImportTemplateCSV() {
        exportCSVTemplate(
            headers: resourceImportTemplateHeaders,
            sampleRows: resourceImportTemplateSampleRows,
            fileName: "Resource Import Template.csv"
        )
    }

    @MainActor
    static func exportResourceImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: resourceImportTemplateHeaders,
            sampleRows: resourceImportTemplateSampleRows,
            sheetName: "Resource Import",
            fileName: "Resource Import Example.xls"
        )
    }

    @MainActor
    static func exportCalendarImportTemplateCSV() {
        exportCSVTemplate(
            headers: calendarImportTemplateHeaders,
            sampleRows: calendarImportTemplateSampleRows,
            fileName: "Calendar Import Template.csv"
        )
    }

    @MainActor
    static func exportCalendarImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: calendarImportTemplateHeaders,
            sampleRows: calendarImportTemplateSampleRows,
            sheetName: "Calendar Import",
            fileName: "Calendar Import Example.xls"
        )
    }

    @MainActor
    static func exportAssignmentImportTemplateCSV() {
        exportCSVTemplate(
            headers: assignmentImportTemplateHeaders,
            sampleRows: assignmentImportTemplateSampleRows,
            fileName: "Assignment Import Template.csv"
        )
    }

    @MainActor
    static func exportAssignmentImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: assignmentImportTemplateHeaders,
            sampleRows: assignmentImportTemplateSampleRows,
            sheetName: "Assignment Import",
            fileName: "Assignment Import Example.xls"
        )
    }

    @MainActor
    static func exportDependencyImportTemplateCSV() {
        exportCSVTemplate(
            headers: dependencyImportTemplateHeaders,
            sampleRows: dependencyImportTemplateSampleRows,
            fileName: "Dependency Import Template.csv"
        )
    }

    @MainActor
    static func exportDependencyImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: dependencyImportTemplateHeaders,
            sampleRows: dependencyImportTemplateSampleRows,
            sheetName: "Dependency Import",
            fileName: "Dependency Import Example.xls"
        )
    }

    @MainActor
    static func exportConstraintImportTemplateCSV() {
        exportCSVTemplate(
            headers: constraintImportTemplateHeaders,
            sampleRows: constraintImportTemplateSampleRows,
            fileName: "Constraint Import Template.csv"
        )
    }

    @MainActor
    static func exportConstraintImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: constraintImportTemplateHeaders,
            sampleRows: constraintImportTemplateSampleRows,
            sheetName: "Constraint Import",
            fileName: "Constraint Import Example.xls"
        )
    }

    @MainActor
    static func exportBaselineImportTemplateCSV() {
        exportCSVTemplate(
            headers: baselineImportTemplateHeaders,
            sampleRows: baselineImportTemplateSampleRows,
            fileName: "Baseline Import Template.csv"
        )
    }

    @MainActor
    static func exportBaselineImportTemplateExcel() {
        exportWorkbookTemplate(
            headers: baselineImportTemplateHeaders,
            sampleRows: baselineImportTemplateSampleRows,
            sheetName: "Baseline Import",
            fileName: "Baseline Import Example.xls"
        )
    }

    @MainActor
    static func importTasksFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectTaskImportSession() else { return nil }
        return applyTaskImport(session, into: originalPlan)
    }

    @MainActor
    static func importResourcesFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectResourceImportSession() else { return nil }
        return applyResourceImport(session, into: originalPlan)
    }

    @MainActor
    static func importCalendarsFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectCalendarImportSession() else { return nil }
        return applyCalendarImport(session, into: originalPlan)
    }

    @MainActor
    static func importAssignmentsFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectAssignmentImportSession() else { return nil }
        return applyAssignmentImport(session, into: originalPlan)
    }

    @MainActor
    static func importDependenciesFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectDependencyImportSession() else { return nil }
        return applyDependencyImport(session, into: originalPlan)
    }

    @MainActor
    static func importConstraintsFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectConstraintImportSession() else { return nil }
        return applyConstraintImport(session, into: originalPlan)
    }

    @MainActor
    static func importBaselinesFromCSV(into originalPlan: NativeProjectPlan) -> CSVImportResult? {
        guard let session = selectBaselineImportSession() else { return nil }
        return applyBaselineImport(session, into: originalPlan)
    }

    @MainActor
    static func exportOpenIssuesToCSV(
        project: ProjectModel,
        reviewAnnotations: [Int: TaskReviewAnnotation],
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let openIssues = reviewAnnotations.compactMap { uniqueID, annotation -> (ProjectTask, TaskReviewAnnotation)? in
            guard let task = project.tasksByID[uniqueID], annotation.isUnresolved else { return nil }
            return (task, annotation)
        }
        .sorted { lhs, rhs in
            if lhs.1.needsFollowUp != rhs.1.needsFollowUp {
                return lhs.1.needsFollowUp && !rhs.1.needsFollowUp
            }
            return lhs.0.displayName < rhs.0.displayName
        }

        var csv = "ID,WBS,Name,Review Status,Needs Follow-Up,Last Updated,Start,Finish,Critical,Baseline Slip Days,Note\n"
        let dateFormatter = ISO8601DateFormatter()

        for (task, annotation) in openIssues {
            let baselineSlip = task.finishVarianceDays ?? task.startVarianceDays
            let row = [
                task.id.map(String.init) ?? "",
                task.wbs ?? "",
                task.displayName,
                annotation.status.rawValue,
                annotation.needsFollowUp ? "Yes" : "No",
                annotation.updatedAt.map(dateFormatter.string(from:)) ?? "",
                DateFormatting.shortDate(task.start),
                DateFormatting.shortDate(task.finish),
                task.critical == true ? "Yes" : "No",
                baselineSlip.map(String.init) ?? "",
                annotation.trimmedNote
            ]
            .map { escapeCSV($0) }
            .joined(separator: ",")
            csv += row + "\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportImportReportToCSV(_ report: CSVImportReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = suggestedImportReportFileName(for: report)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "Section,Row,Target ID,Severity,Fix Action,Message\n"

        for line in report.summaryLines {
            let row = ["Summary", "", "", "", "", line]
                .map(escapeCSV)
                .joined(separator: ",")
            csv += row + "\n"
        }

        for issue in report.issues {
            let row = [
                "Issue",
                issue.rowNumber.map(String.init) ?? "",
                issue.targetID.map(String.init) ?? "",
                issue.severity.rawValue,
                issue.fixAction?.title ?? "",
                issue.message
            ]
            .map(escapeCSV)
            .joined(separator: ",")
            csv += row + "\n"
        }

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
            let actualStart = DateFormatting.shortDate(task.actualStart)
            let actualFinish = DateFormatting.shortDate(task.actualFinish)
            let pctComplete = task.percentComplete.map { "\(Int($0))" } ?? ""
            let cost = task.cost.map { String(format: "%.2f", $0) } ?? ""
            let baselineCost = task.baselineCost.map { String(format: "%.2f", $0) } ?? ""
            let actualCost = task.actualCost.map { String(format: "%.2f", $0) } ?? ""

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
            let assignmentSummary = taskAssignments.compactMap { assignment -> String? in
                guard let resourceID = assignment.resourceUniqueID,
                      let resourceName = resources.first(where: { $0.uniqueID == resourceID })?.name else { return nil }
                let units = assignment.assignmentUnits.map { "\(Int($0))%" } ?? ""
                return units.isEmpty ? resourceName : "\(resourceName) (\(units))"
            }.joined(separator: "; ")

            let row = [
                id,
                wbs,
                name,
                task.summary == true ? "Yes" : "No",
                task.milestone == true ? "Yes" : "No",
                duration,
                start,
                finish,
                actualStart,
                actualFinish,
                pctComplete,
                cost,
                baselineCost,
                actualCost,
                predText,
                resourceNames,
                assignmentSummary
            ]
                .map { escapeCSV($0) }
                .joined(separator: ",")
            csv += row + "\n"

            if !task.children.isEmpty {
                appendRows(tasks: task.children, allTasks: allTasks, resources: resources, assignments: assignments, to: &csv)
            }
        }
    }

    private static func appendExcelRows(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        resources: [ProjectResource],
        assignments: [ResourceAssignment],
        to rows: inout [[String]]
    ) {
        for task in tasks {
            let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
            let resourceNames = taskAssignments.compactMap { assignment in
                resources.first(where: { $0.uniqueID == assignment.resourceUniqueID })?.name
            }
            .joined(separator: "; ")

            let resourceUnits = taskAssignments.compactMap { assignment -> String? in
                guard let resourceID = assignment.resourceUniqueID,
                      let resourceName = resources.first(where: { $0.uniqueID == resourceID })?.name else { return nil }
                let units = assignment.assignmentUnits.map { "\(Int($0))%" } ?? ""
                return units.isEmpty ? resourceName : "\(resourceName) (\(units))"
            }
            .joined(separator: "; ")

            let predecessors: String = {
                guard let preds = task.predecessors, !preds.isEmpty else { return "" }
                return preds.compactMap { relation -> String? in
                    guard let predecessor = allTasks[relation.targetTaskUniqueID] else { return nil }
                    let taskID = predecessor.id.map(String.init) ?? "\(relation.targetTaskUniqueID)"
                    let suffix = relation.type == "FS" ? "" : (relation.type ?? "")
                    return taskID + suffix
                }
                .joined(separator: "; ")
            }()

            rows.append([
                task.id.map(String.init) ?? "",
                task.wbs ?? "",
                task.displayName,
                task.summary == true ? "Yes" : "No",
                task.milestone == true ? "Yes" : "No",
                task.durationDisplay,
                DateFormatting.shortDate(task.start),
                DateFormatting.shortDate(task.finish),
                DateFormatting.shortDate(task.actualStart),
                DateFormatting.shortDate(task.actualFinish),
                task.percentComplete.map { "\(Int($0))" } ?? "",
                task.cost.map { String(format: "%.2f", $0) } ?? "",
                task.baselineCost.map { String(format: "%.2f", $0) } ?? "",
                task.actualCost.map { String(format: "%.2f", $0) } ?? "",
                task.critical == true ? "Yes" : "No",
                predecessors,
                resourceNames,
                resourceUnits
            ])

            if !task.children.isEmpty {
                appendExcelRows(
                    tasks: task.children,
                    allTasks: allTasks,
                    resources: resources,
                    assignments: assignments,
                    to: &rows
                )
            }
        }
    }

    private static func excelWorkbookXML(headers: [String], rows: [[String]], sheetName: String) -> String {
        let xmlRows = ([headers] + rows).map { row in
            let cells = row.map { value in
                """
                <Cell><Data ss:Type="String">\(escapeXML(value))</Data></Cell>
                """
            }
            .joined()
            return "<Row>\(cells)</Row>"
        }
        .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <?mso-application progid="Excel.Sheet"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:o="urn:schemas-microsoft-com:office:office"
         xmlns:x="urn:schemas-microsoft-com:office:excel"
         xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
         xmlns:html="http://www.w3.org/TR/REC-html40">
        <Worksheet ss:Name="\(escapeXML(sheetName))">
        <Table>
        \(xmlRows)
        </Table>
        </Worksheet>
        </Workbook>
        """
    }

    @MainActor
    private static func exportCSVTemplate(headers: [String], sampleRows: [[String]], fileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let csv = ([headers] + sampleRows)
            .map { row in row.map(escapeCSV).joined(separator: ",") }
            .joined(separator: "\n") + "\n"

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private static func exportWorkbookTemplate(
        headers: [String],
        sampleRows: [[String]],
        sheetName: String,
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xls") ?? .data]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let workbook = excelWorkbookXML(headers: headers, rows: sampleRows, sheetName: sheetName)
        try? workbook.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func suggestedImportReportFileName(for report: CSVImportReport) -> String {
        let base = report.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "")
        return "\(base).csv"
    }

    private static func loadText(from url: URL) -> String? {
        let text: String?
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            text = utf8
        } else if let unicode = try? String(contentsOf: url, encoding: .unicode) {
            text = unicode
        } else if let iso = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = iso
        } else {
            text = nil
        }

        return text
    }

    private static func loadCSVRows(from url: URL) -> [[String]]? {
        guard let text = loadText(from: url) else { return nil }
        return parseCSVRows(text)
    }

    private static func loadSpreadsheetMLRows(from url: URL) -> [[String]]? {
        guard let data = try? Data(contentsOf: url),
              let document = try? XMLDocument(data: data, options: []) else {
            return nil
        }

        guard let rowNodes = try? document.nodes(forXPath: "/*[local-name()='Workbook']/*[local-name()='Worksheet'][1]/*[local-name()='Table']/*[local-name()='Row']"),
              !rowNodes.isEmpty else {
            return nil
        }

        var rows: [[String]] = []

        for rowNode in rowNodes {
            guard let rowElement = rowNode as? XMLElement else { continue }
            guard let cellNodes = try? rowElement.nodes(forXPath: "./*[local-name()='Cell']") else { continue }

            var row: [String] = []
            var nextColumnIndex = 1

            for cellNode in cellNodes {
                guard let cellElement = cellNode as? XMLElement else { continue }

                if let indexString = cellElement.attribute(forName: "ss:Index")?.stringValue ?? cellElement.attribute(forName: "Index")?.stringValue,
                   let index = Int(indexString), index > nextColumnIndex {
                    row.append(contentsOf: Array(repeating: "", count: index - nextColumnIndex))
                    nextColumnIndex = index
                }

                let value: String
                let dataNodes = try? cellElement.nodes(forXPath: "./*[local-name()='Data']")
                if let dataNode = dataNodes?.first {
                    value = dataNode.stringValue ?? ""
                } else {
                    value = cellElement.stringValue ?? ""
                }

                row.append(value.trimmingCharacters(in: .newlines))
                nextColumnIndex += 1
            }

            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
        }

        return rows.isEmpty ? nil : rows
    }

    private static func loadTabularRows(from url: URL) -> [[String]]? {
        switch url.pathExtension.lowercased() {
        case "csv":
            return loadCSVRows(from: url)
        case "xls", "xml":
            return loadSpreadsheetMLRows(from: url) ?? loadCSVRows(from: url)
        default:
            return loadCSVRows(from: url) ?? loadSpreadsheetMLRows(from: url)
        }
    }

    @MainActor
    private static func selectTabularFile() -> (url: URL, rows: [[String]])? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "xls") ?? .data,
            UTType.xml
        ]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let rows = loadTabularRows(from: url), !rows.isEmpty else {
            showImportAlert(title: "Import Failed", message: "The selected CSV or Excel-compatible file could not be read.")
            return nil
        }
        return (url, rows)
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            switch character {
            case "\"":
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                currentRow.append(currentField)
                                currentField = ""
                            } else if next == "\n" {
                                currentRow.append(currentField)
                                rows.append(currentRow)
                                currentRow = []
                                currentField = ""
                            } else if next == "\r" {
                                currentRow.append(currentField)
                                rows.append(currentRow)
                                currentRow = []
                                currentField = ""
                            } else {
                                currentField.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            case ",":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    currentField = ""
                }
            case "\n":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                }
            case "\r":
                if inQuotes {
                    currentField.append(character)
                } else {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                }
            default:
                currentField.append(character)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "%", with: "percent")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultTaskMapping(for headers: [String]) -> [CSVTaskImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVTaskImportField: Int?] = [:]
        for field in CSVTaskImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultResourceMapping(for headers: [String]) -> [CSVResourceImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVResourceImportField: Int?] = [:]
        for field in CSVResourceImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultAssignmentMapping(for headers: [String]) -> [CSVAssignmentImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVAssignmentImportField: Int?] = [:]
        for field in CSVAssignmentImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultDependencyMapping(for headers: [String]) -> [CSVDependencyImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVDependencyImportField: Int?] = [:]
        for field in CSVDependencyImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultConstraintMapping(for headers: [String]) -> [CSVConstraintImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVConstraintImportField: Int?] = [:]
        for field in CSVConstraintImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultBaselineMapping(for headers: [String]) -> [CSVBaselineImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVBaselineImportField: Int?] = [:]
        for field in CSVBaselineImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func defaultCalendarMapping(for headers: [String]) -> [CSVCalendarImportField: Int?] {
        let normalizedHeaders = headers.map(normalizeHeader)
        var mapping: [CSVCalendarImportField: Int?] = [:]
        for field in CSVCalendarImportField.allCases {
            mapping[field] = index(in: normalizedHeaders, matchingAnyOf: field.aliases)
        }
        return mapping
    }

    private static func index(in headers: [String], matchingAnyOf names: [String]) -> Int? {
        let normalizedNames = Set(names.map(normalizeHeader))
        return headers.firstIndex { normalizedNames.contains($0) }
    }

    private static func stringValue(in row: [String], at index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index]
    }

    private static func stringValue(in row: [String], headers index: Int?) -> String {
        stringValue(in: row, at: index)
    }

    private static func sourceIdentifier(from row: [String], headers: [String], fallback: Int) -> String {
        if let explicit = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["id", "taskid", "uniqueid"]))
            .nonEmpty {
            return explicit
        }
        return String(fallback)
    }

    private static func sourceIdentifier(from row: [String], mappedIndex: Int?, fallback: Int) -> String {
        if let explicit = stringValue(in: row, at: mappedIndex).nonEmpty {
            return explicit
        }
        return String(fallback)
    }

    private static func predecessorTokens(in row: [String], headers: [String]) -> [String] {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["predecessors", "preds", "predecessor"]))
        return predecessorTokens(from: raw)
    }

    private static func predecessorTokens(in row: [String], at index: Int?) -> [String] {
        predecessorTokens(from: stringValue(in: row, at: index))
    }

    private static func predecessorTokens(from raw: String) -> [String] {
        return raw
            .split(whereSeparator: { ",;".contains($0) })
            .map { token in
                token.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "FS", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: "SS", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: "FF", with: "", options: [.caseInsensitive])
                    .replacingOccurrences(of: "SF", with: "", options: [.caseInsensitive])
            }
            .filter { !$0.isEmpty }
    }

    private static func dateValue(in row: [String], headers: [String], names: [String]) -> Date? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: names))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return dateValue(from: raw)
    }

    private static func dateValue(in row: [String], at index: Int?) -> Date? {
        let raw = stringValue(in: row, at: index)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return dateValue(from: raw)
    }

    private static func dateValue(from raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        if let mpxj = DateFormatting.parseMPXJDate(raw) {
            return mpxj
        }
        for formatter in importDateFormatters {
            if let parsed = formatter.date(from: raw) {
                return parsed
            }
        }
        return nil
    }

    private static func intValue(in row: [String], headers: [String], names: [String]) -> Int? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: names))
        return intValue(from: raw)
    }

    private static func intValue(in row: [String], at index: Int?) -> Int? {
        intValue(from: stringValue(in: row, at: index))
    }

    private static func intValue(from raw: String) -> Int? {
        let digits = raw.filter { $0.isNumber || $0 == "-" }
        return Int(digits)
    }

    private static func normalizedImportedConstraintType(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "", "ASAP", "ASSOONASPOSSIBLE":
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

    private static func doubleValue(in row: [String], headers: [String], names: [String]) -> Double? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: names))
        return doubleValue(from: raw)
    }

    private static func doubleValue(in row: [String], at index: Int?) -> Double? {
        doubleValue(from: stringValue(in: row, at: index))
    }

    private static func doubleValue(from raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func boolValue(in row: [String], headers: [String], names: [String]) -> Bool? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: names))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return boolValue(from: raw)
    }

    private static func boolValue(in row: [String], at index: Int?) -> Bool? {
        let raw = stringValue(in: row, at: index)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return boolValue(from: raw)
    }

    private static func boolValue(from raw: String) -> Bool? {
        guard !raw.isEmpty else { return nil }
        if ["true", "yes", "y", "1"].contains(raw) { return true }
        if ["false", "no", "n", "0"].contains(raw) { return false }
        return nil
    }

    private static func durationDaysValue(in row: [String], headers: [String]) -> Int? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["duration", "durationdays", "dur"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return durationDaysValue(from: raw)
    }

    private static func durationDaysValue(in row: [String], at index: Int?) -> Int? {
        let raw = stringValue(in: row, at: index)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return durationDaysValue(from: raw)
    }

    private static func durationDaysValue(from raw: String) -> Int? {
        guard !raw.isEmpty else { return nil }

        let numberText = raw.filter { $0.isNumber || $0 == "." }
        guard let numeric = Double(numberText) else { return nil }
        if raw.contains("h") {
            return max(0, Int(ceil(numeric / 8.0)))
        }
        return max(0, Int(ceil(numeric)))
    }

    private static func outlineLevelValue(in row: [String], headers: [String]) -> Int? {
        if let explicit = intValue(in: row, headers: headers, names: ["outlinelevel", "level"]) {
            return max(1, explicit)
        }
        let wbs = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["wbs", "outlinenumber"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return outlineLevelValue(explicit: nil, wbs: wbs)
    }

    private static func outlineLevelValue(in row: [String], mappedIndex: Int?, wbsIndex: Int?) -> Int? {
        let explicit = intValue(in: row, at: mappedIndex)
        let wbs = stringValue(in: row, at: wbsIndex).trimmingCharacters(in: .whitespacesAndNewlines)
        return outlineLevelValue(explicit: explicit, wbs: wbs)
    }

    private static func outlineLevelValue(explicit: Int?, wbs: String) -> Int? {
        if let explicit {
            return max(1, explicit)
        }
        if !wbs.isEmpty {
            return max(1, wbs.split(separator: ".").count)
        }
        return nil
    }

    private static func durationDaysBetween(start: Date, finish: Date) -> Int {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: min(start, finish))
        let normalizedFinish = calendar.startOfDay(for: max(start, finish))
        let days = (calendar.dateComponents([.day], from: normalizedStart, to: normalizedFinish).day ?? 0) + 1
        return max(1, days)
    }

    private static func calendarIDValue(
        in row: [String],
        headers: [String],
        calendars: [NativePlanCalendar]
    ) -> Int? {
        let raw = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["calendar", "basecalendar", "taskcalendar"]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return calendarIDValue(from: raw, calendars: calendars)
    }

    private static func calendarIDValue(
        in row: [String],
        at index: Int?,
        calendars: [NativePlanCalendar]
    ) -> Int? {
        let raw = stringValue(in: row, at: index)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return calendarIDValue(from: raw, calendars: calendars)
    }

    private static func calendarIDValue(from raw: String, calendars: [NativePlanCalendar]) -> Int? {
        guard !raw.isEmpty else { return nil }
        let key = normalizedLookupKey(raw)
        return calendars.first(where: { normalizedLookupKey($0.name) == key })?.id
    }

    private static func assignmentSpecs(in row: [String], headers: [String]) -> [ImportedAssignmentSpec] {
        let assignmentsRaw = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["assignments", "resourceassignments"]))
        let resourceNamesRaw = stringValue(in: row, at: index(in: headers, matchingAnyOf: ["resourcenames", "resources", "resource"]))
        let defaultUnits = doubleValue(in: row, headers: headers, names: ["units", "assignmentunits", "resourceunits"])
        return assignmentSpecs(assignmentsRaw: assignmentsRaw, resourceNamesRaw: resourceNamesRaw, defaultUnits: defaultUnits)
    }

    private static func assignmentSpecs(
        in row: [String],
        resourceNamesIndex: Int?,
        assignmentsIndex: Int?,
        unitsIndex: Int?
    ) -> [ImportedAssignmentSpec] {
        let assignmentsRaw = stringValue(in: row, at: assignmentsIndex)
        let resourceNamesRaw = stringValue(in: row, at: resourceNamesIndex)
        let defaultUnits = doubleValue(in: row, at: unitsIndex)
        return assignmentSpecs(assignmentsRaw: assignmentsRaw, resourceNamesRaw: resourceNamesRaw, defaultUnits: defaultUnits)
    }

    private static func assignmentSpecs(assignmentsRaw: String, resourceNamesRaw: String, defaultUnits: Double?) -> [ImportedAssignmentSpec] {
        if assignmentsRaw.nonEmpty != nil {
            return parseAssignmentSpecs(assignmentsRaw)
        }

        if resourceNamesRaw.nonEmpty != nil {
            return resourceNamesRaw
                .split(whereSeparator: { ";,".contains($0) })
                .map { ImportedAssignmentSpec(name: $0.trimmingCharacters(in: .whitespacesAndNewlines), units: defaultUnits) }
                .filter { !$0.name.isEmpty }
        }

        return []
    }

    private static func parseAssignmentSpecs(_ raw: String) -> [ImportedAssignmentSpec] {
        raw
            .split(whereSeparator: { ";,".contains($0) })
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                if let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"), open < close {
                    let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let unitsText = String(trimmed[trimmed.index(after: open)..<close])
                        .replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return ImportedAssignmentSpec(name: name, units: Double(unitsText))
                }

                return ImportedAssignmentSpec(name: trimmed, units: nil)
            }
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func applyCalendarDay(
        to calendar: inout NativePlanCalendar,
        weekday: Int,
        workingIndex: Int?,
        fromIndex: Int?,
        toIndex: Int?,
        row: [String]
    ) {
        let existing = calendarDay(in: calendar, weekday: weekday)
        let from = stringValue(in: row, at: fromIndex).nonEmpty ?? existing.from
        let to = stringValue(in: row, at: toIndex).nonEmpty ?? existing.to

        let day: NativeCalendarDay
        if let isWorking = boolValue(in: row, at: workingIndex) {
            day = isWorking
                ? .workingDay(from: from.isEmpty ? "08:00" : from, to: to.isEmpty ? "17:00" : to)
                : .nonWorking()
        } else if (fromIndex != nil || toIndex != nil), (!from.isEmpty || !to.isEmpty) {
            day = .workingDay(from: from.isEmpty ? "08:00" : from, to: to.isEmpty ? "17:00" : to)
        } else {
            day = existing
        }

        setCalendarDay(&calendar, weekday: weekday, value: day)
    }

    private static func calendarDay(in calendar: NativePlanCalendar, weekday: Int) -> NativeCalendarDay {
        switch weekday {
        case 1: return calendar.sunday
        case 2: return calendar.monday
        case 3: return calendar.tuesday
        case 4: return calendar.wednesday
        case 5: return calendar.thursday
        case 6: return calendar.friday
        default: return calendar.saturday
        }
    }

    private static func setCalendarDay(_ calendar: inout NativePlanCalendar, weekday: Int, value: NativeCalendarDay) {
        switch weekday {
        case 1: calendar.sunday = value
        case 2: calendar.monday = value
        case 3: calendar.tuesday = value
        case 4: calendar.wednesday = value
        case 5: calendar.thursday = value
        case 6: calendar.friday = value
        default: calendar.saturday = value
        }
    }

    private static func importedException(from row: [String], session: CSVCalendarImportSession) -> NativeCalendarException? {
        let name = stringValue(in: row, at: session.mapping[.exceptionName] ?? nil).nonEmpty
        let fromDate = dateValue(in: row, at: session.mapping[.exceptionFromDate] ?? nil)
        let toDate = dateValue(in: row, at: session.mapping[.exceptionToDate] ?? nil)
        let type = stringValue(in: row, at: session.mapping[.exceptionType] ?? nil).nonEmpty ?? "non_working"

        guard name != nil || fromDate != nil || toDate != nil else { return nil }
        let normalizedFrom = Calendar.current.startOfDay(for: fromDate ?? toDate ?? Date())
        let normalizedTo = Calendar.current.startOfDay(for: toDate ?? normalizedFrom)
        return NativeCalendarException(
            name: name ?? "Exception",
            fromDate: min(normalizedFrom, normalizedTo),
            toDate: max(normalizedFrom, normalizedTo),
            type: type
        )
    }

    private static func containsCalendarException(_ candidate: NativeCalendarException, in exceptions: [NativeCalendarException]) -> Bool {
        exceptions.contains {
            normalizedLookupKey($0.name) == normalizedLookupKey(candidate.name)
                && Calendar.current.isDate($0.fromDate, inSameDayAs: candidate.fromDate)
                && Calendar.current.isDate($0.toDate, inSameDayAs: candidate.toDate)
                && normalizedLookupKey($0.type) == normalizedLookupKey(candidate.type)
        }
    }

    @MainActor
    private static func showImportAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private let taskExportHeaders = [
    "ID",
    "WBS",
    "Name",
    "Summary",
    "Milestone",
    "Duration",
    "Start",
    "Finish",
    "Actual Start",
    "Actual Finish",
    "% Complete",
    "Cost",
    "Baseline Cost",
    "Actual Cost",
    "Critical",
    "Predecessors",
    "Resource Names",
    "Assignments"
]

private let taskImportTemplateHeaders = [
    "Task ID",
    "WBS",
    "Task Name",
    "Outline Level",
    "Start",
    "Finish",
    "Actual Start",
    "Actual Finish",
    "Duration",
    "% Complete",
    "Fixed Cost",
    "Baseline Cost",
    "Actual Cost",
    "Priority",
    "Milestone",
    "Predecessors",
    "Calendar",
    "Manual Scheduling",
    "Active",
    "Resource Names",
    "Assignments",
    "Units",
    "Notes"
]

private let taskImportTemplateSampleRows = [
    ["1", "1", "Project Kickoff", "1", "2026-05-04", "2026-05-04", "2026-05-04", "2026-05-04", "1d", "100", "1500", "1500", "1500", "700", "Yes", "", "Standard", "No", "Yes", "Project Manager", "Project Manager (100%)", "100", "Milestone to start the plan"],
    ["2", "1.1", "Discovery", "2", "2026-05-05", "2026-05-09", "2026-05-05", "", "5d", "40", "800", "2500", "1200", "500", "No", "1", "Standard", "No", "Yes", "Business Analyst; Planner", "Business Analyst (100%); Planner (50%)", "100", "Requirements and assumptions"],
    ["3", "1.2", "Draft Schedule", "2", "2026-05-12", "2026-05-16", "", "", "5d", "0", "400", "1800", "", "500", "No", "2", "Standard", "No", "Yes", "Planner", "Planner (100%)", "100", "First planning pass"],
    ["4", "2", "Executive Review", "1", "2026-05-19", "2026-05-19", "", "", "0d", "0", "500", "900", "", "600", "Yes", "3", "Standard", "No", "Yes", "Project Manager", "Project Manager (50%)", "50", "Approval gate"]
]

private let resourceImportTemplateHeaders = [
    "Resource Name",
    "Type",
    "Max Units",
    "Standard Rate",
    "Overtime Rate",
    "Cost Per Use",
    "Accrue At",
    "Email",
    "Group",
    "Initials",
    "Calendar",
    "Active",
    "Notes"
]

private let resourceImportTemplateSampleRows = [
    ["Project Manager", "Work", "100", "150", "200", "250", "start", "pm@example.com", "Management", "PM", "Standard", "Yes", "Coordinates approvals"],
    ["Business Analyst", "Work", "100", "110", "150", "0", "prorated", "ba@example.com", "PMO", "BA", "Standard", "Yes", "Leads discovery"],
    ["Planner", "Work", "100", "95", "140", "0", "prorated", "planner@example.com", "Controls", "PL", "Standard", "Yes", "Owns schedule logic"],
    ["Executive Sponsor", "Work", "25", "300", "400", "500", "end", "sponsor@example.com", "Leadership", "ES", "Executive", "Yes", "Part-time review role"]
]

private let assignmentImportTemplateHeaders = [
    "Task ID",
    "Task Name",
    "Resource Name",
    "Units",
    "Work Hours",
    "Actual Work Hours",
    "Remaining Work Hours",
    "Overtime Work Hours",
    "Notes"
]

private let assignmentImportTemplateSampleRows = [
    ["1", "Project Kickoff", "Project Manager", "100", "8", "8", "0", "0", "Owns the kickoff milestone"],
    ["2", "Discovery", "Business Analyst", "100", "40", "20", "20", "2", "Primary discovery lead"],
    ["2", "Discovery", "Planner", "50", "20", "8", "12", "0", "Supports sequencing and assumptions"],
    ["3", "Draft Schedule", "Planner", "100", "40", "0", "40", "4", "Builds the first detailed plan"]
]

private let dependencyImportTemplateHeaders = [
    "Task ID",
    "Task Name",
    "Predecessors"
]

private let dependencyImportTemplateSampleRows = [
    ["2", "Discovery", "1"],
    ["3", "Draft Schedule", "2"],
    ["4", "Executive Review", "2, 3"],
    ["5", "Approval", "Executive Review"]
]

private let constraintImportTemplateHeaders = [
    "Task ID",
    "Task Name",
    "Constraint Type",
    "Constraint Date"
]

private let constraintImportTemplateSampleRows = [
    ["2", "Discovery", "SNET", "2026-05-06"],
    ["3", "Draft Schedule", "FNET", "2026-05-19"],
    ["4", "Executive Review", "MSO", "2026-05-20"],
    ["5", "Approval", "ASAP", ""]
]

private let baselineImportTemplateHeaders = [
    "Task ID",
    "Task Name",
    "Baseline Start",
    "Baseline Finish",
    "Baseline Duration"
]

private let baselineImportTemplateSampleRows = [
    ["1", "Project Kickoff", "2026-05-04", "2026-05-04", "0d"],
    ["2", "Discovery", "2026-05-05", "2026-05-09", "5d"],
    ["3", "Draft Schedule", "2026-05-12", "2026-05-16", "5d"],
    ["4", "Executive Review", "2026-05-19", "2026-05-19", "0d"]
]

private let calendarImportTemplateHeaders = [
    "Calendar Name",
    "Parent Calendar",
    "Type",
    "Personal",
    "Sunday Working",
    "Sunday From",
    "Sunday To",
    "Monday Working",
    "Monday From",
    "Monday To",
    "Tuesday Working",
    "Tuesday From",
    "Tuesday To",
    "Wednesday Working",
    "Wednesday From",
    "Wednesday To",
    "Thursday Working",
    "Thursday From",
    "Thursday To",
    "Friday Working",
    "Friday From",
    "Friday To",
    "Saturday Working",
    "Saturday From",
    "Saturday To",
    "Exception Name",
    "Exception From",
    "Exception To",
    "Exception Type"
]

private let calendarImportTemplateSampleRows = [
    ["Standard", "", "Standard", "No", "No", "", "", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "No", "", "", "", "", "", ""],
    ["Executive", "Standard", "Executive", "No", "No", "", "", "Yes", "09:00", "16:00", "Yes", "09:00", "16:00", "Yes", "09:00", "16:00", "Yes", "09:00", "16:00", "Yes", "09:00", "13:00", "No", "", "", "", "", "", ""],
    ["Standard", "", "Standard", "No", "No", "", "", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "No", "", "", "Company Holiday", "2026-12-02", "2026-12-03", "non_working"],
    ["Planner Leave", "Standard", "Personal", "Yes", "No", "", "", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "Yes", "08:00", "17:00", "No", "", "", "Annual Leave", "2026-06-14", "2026-06-18", "non_working"]
]

private let weekdayImportDescriptors: [WeekdayImportDescriptor] = [
    WeekdayImportDescriptor(weekday: 1, workingField: .sundayWorking, fromField: .sundayFrom, toField: .sundayTo),
    WeekdayImportDescriptor(weekday: 2, workingField: .mondayWorking, fromField: .mondayFrom, toField: .mondayTo),
    WeekdayImportDescriptor(weekday: 3, workingField: .tuesdayWorking, fromField: .tuesdayFrom, toField: .tuesdayTo),
    WeekdayImportDescriptor(weekday: 4, workingField: .wednesdayWorking, fromField: .wednesdayFrom, toField: .wednesdayTo),
    WeekdayImportDescriptor(weekday: 5, workingField: .thursdayWorking, fromField: .thursdayFrom, toField: .thursdayTo),
    WeekdayImportDescriptor(weekday: 6, workingField: .fridayWorking, fromField: .fridayFrom, toField: .fridayTo),
    WeekdayImportDescriptor(weekday: 7, workingField: .saturdayWorking, fromField: .saturdayFrom, toField: .saturdayTo)
]

private struct WeekdayImportDescriptor {
    let weekday: Int
    let workingField: CSVCalendarImportField
    let fromField: CSVCalendarImportField
    let toField: CSVCalendarImportField
}

private struct ImportedAssignmentSpec {
    let name: String
    let units: Double?
}

struct CSVTaskImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVTaskImportField: Int?]
}

enum CSVTaskImportField: String, CaseIterable, Identifiable {
    case name = "Task Name"
    case sourceID = "Task ID"
    case wbs = "WBS"
    case outlineLevel = "Outline Level"
    case startDate = "Start"
    case finishDate = "Finish"
    case actualStartDate = "Actual Start"
    case actualFinishDate = "Actual Finish"
    case duration = "Duration"
    case percentComplete = "% Complete"
    case fixedCost = "Fixed Cost"
    case baselineCost = "Baseline Cost"
    case actualCost = "Actual Cost"
    case priority = "Priority"
    case milestone = "Milestone"
    case predecessors = "Predecessors"
    case notes = "Notes"
    case calendar = "Calendar"
    case manualScheduling = "Manual Scheduling"
    case active = "Active"
    case resourceNames = "Resource Names"
    case assignments = "Assignments"
    case units = "Units"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .name: return ["taskname", "name", "task"]
        case .sourceID: return ["id", "taskid", "uniqueid"]
        case .wbs: return ["wbs", "outlinenumber"]
        case .outlineLevel: return ["outlinelevel", "level"]
        case .startDate: return ["start", "startdate"]
        case .finishDate: return ["finish", "finishdate", "end", "enddate"]
        case .actualStartDate: return ["actualstart", "actualstartdate"]
        case .actualFinishDate: return ["actualfinish", "actualfinishdate"]
        case .duration: return ["duration", "durationdays", "dur"]
        case .percentComplete: return ["percentcomplete", "complete", "pctcomplete"]
        case .fixedCost: return ["fixedcost", "taskfixedcost"]
        case .baselineCost: return ["baselinecost", "bac", "budgetatcompletion"]
        case .actualCost: return ["actualcost", "acwp", "costactual"]
        case .priority: return ["priority"]
        case .milestone: return ["milestone", "ismilestone"]
        case .predecessors: return ["predecessors", "preds", "predecessor"]
        case .notes: return ["notes", "note", "comments"]
        case .calendar: return ["calendar", "basecalendar", "taskcalendar"]
        case .manualScheduling: return ["manualscheduling", "manual", "manuallyscheduled"]
        case .active: return ["active", "isactive"]
        case .resourceNames: return ["resourcenames", "resources", "resource"]
        case .assignments: return ["assignments", "resourceassignments"]
        case .units: return ["units", "assignmentunits", "resourceunits"]
        }
    }
}

struct CSVResourceImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVResourceImportField: Int?]
}

struct CSVAssignmentImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVAssignmentImportField: Int?]
}

struct CSVDependencyImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVDependencyImportField: Int?]
}

struct CSVConstraintImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVConstraintImportField: Int?]
}

struct CSVBaselineImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVBaselineImportField: Int?]
}

enum CSVResourceImportField: String, CaseIterable, Identifiable {
    case name = "Resource Name"
    case type = "Type"
    case maxUnits = "Max Units"
    case standardRate = "Standard Rate"
    case overtimeRate = "Overtime Rate"
    case costPerUse = "Cost Per Use"
    case accrueAt = "Accrue At"
    case email = "Email"
    case group = "Group"
    case initials = "Initials"
    case notes = "Notes"
    case calendar = "Calendar"
    case active = "Active"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .name: return ["name", "resourcename", "resource"]
        case .type: return ["type", "resourcetype"]
        case .maxUnits: return ["maxunits", "units", "maxunit"]
        case .standardRate: return ["standardrate", "rate", "hourlyrate"]
        case .overtimeRate: return ["overtimerate", "otrate"]
        case .costPerUse: return ["costperuse", "perusecost"]
        case .accrueAt: return ["accrueat", "costaccrual", "accrual"]
        case .email: return ["email", "emailaddress"]
        case .group: return ["group", "resourcegroup"]
        case .initials: return ["initials", "initial"]
        case .notes: return ["notes", "note", "comments"]
        case .calendar: return ["calendar", "basecalendar", "resourcecalendar"]
        case .active: return ["active", "isactive"]
        }
    }
}

enum CSVAssignmentImportField: String, CaseIterable, Identifiable {
    case taskID = "Task ID"
    case taskName = "Task Name"
    case resourceName = "Resource Name"
    case units = "Units"
    case workHours = "Work Hours"
    case actualWorkHours = "Actual Work Hours"
    case remainingWorkHours = "Remaining Work Hours"
    case overtimeWorkHours = "Overtime Work Hours"
    case notes = "Notes"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .taskID: return ["taskid", "id", "uniqueid"]
        case .taskName: return ["taskname", "name", "task"]
        case .resourceName: return ["resourcename", "resource", "resourceidname"]
        case .units: return ["units", "assignmentunits", "resourceunits"]
        case .workHours: return ["workhours", "work", "hours", "plannedhours"]
        case .actualWorkHours: return ["actualworkhours", "actualhours", "actualwork"]
        case .remainingWorkHours: return ["remainingworkhours", "remaininghours", "remainingwork"]
        case .overtimeWorkHours: return ["overtimeworkhours", "overtimehours", "overtimework", "othours"]
        case .notes: return ["notes", "note", "comments"]
        }
    }
}

enum CSVDependencyImportField: String, CaseIterable, Identifiable {
    case taskID = "Task ID"
    case taskName = "Task Name"
    case predecessors = "Predecessors"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .taskID: return ["taskid", "id", "uniqueid", "successortaskid"]
        case .taskName: return ["taskname", "name", "task", "successortask"]
        case .predecessors: return ["predecessors", "preds", "predecessor", "links"]
        }
    }
}

enum CSVConstraintImportField: String, CaseIterable, Identifiable {
    case taskID = "Task ID"
    case taskName = "Task Name"
    case constraintType = "Constraint Type"
    case constraintDate = "Constraint Date"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .taskID: return ["taskid", "id", "uniqueid"]
        case .taskName: return ["taskname", "name", "task"]
        case .constraintType: return ["constrainttype", "constraint", "type"]
        case .constraintDate: return ["constraintdate", "date", "constrainton", "constraintday"]
        }
    }
}

enum CSVBaselineImportField: String, CaseIterable, Identifiable {
    case taskID = "Task ID"
    case taskName = "Task Name"
    case baselineStart = "Baseline Start"
    case baselineFinish = "Baseline Finish"
    case baselineDuration = "Baseline Duration"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .taskID: return ["taskid", "id", "uniqueid"]
        case .taskName: return ["taskname", "name", "task"]
        case .baselineStart: return ["baselinestart", "baseline1start", "plannedstart"]
        case .baselineFinish: return ["baselinefinish", "baseline1finish", "plannedfinish"]
        case .baselineDuration: return ["baselineduration", "baseline1duration", "plannedduration"]
        }
    }
}

struct CSVCalendarImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let headers: [String]
    let dataRows: [[String]]
    let previewRows: [[String]]
    var mapping: [CSVCalendarImportField: Int?]
}

enum CSVCalendarImportField: String, CaseIterable, Identifiable {
    case name = "Calendar Name"
    case parentName = "Parent Calendar"
    case type = "Type"
    case personal = "Personal"
    case sundayWorking = "Sunday Working"
    case sundayFrom = "Sunday From"
    case sundayTo = "Sunday To"
    case mondayWorking = "Monday Working"
    case mondayFrom = "Monday From"
    case mondayTo = "Monday To"
    case tuesdayWorking = "Tuesday Working"
    case tuesdayFrom = "Tuesday From"
    case tuesdayTo = "Tuesday To"
    case wednesdayWorking = "Wednesday Working"
    case wednesdayFrom = "Wednesday From"
    case wednesdayTo = "Wednesday To"
    case thursdayWorking = "Thursday Working"
    case thursdayFrom = "Thursday From"
    case thursdayTo = "Thursday To"
    case fridayWorking = "Friday Working"
    case fridayFrom = "Friday From"
    case fridayTo = "Friday To"
    case saturdayWorking = "Saturday Working"
    case saturdayFrom = "Saturday From"
    case saturdayTo = "Saturday To"
    case exceptionName = "Exception Name"
    case exceptionFromDate = "Exception From"
    case exceptionToDate = "Exception To"
    case exceptionType = "Exception Type"

    var id: String { rawValue }

    var aliases: [String] {
        switch self {
        case .name: return ["calendarname", "name", "calendar"]
        case .parentName: return ["parentcalendar", "parent", "basecalendar"]
        case .type: return ["type", "calendartype"]
        case .personal: return ["personal", "ispersonal", "personalcalendar"]
        case .sundayWorking: return ["sundayworking", "sunworking"]
        case .sundayFrom: return ["sundayfrom", "sunfrom"]
        case .sundayTo: return ["sundayto", "sunto"]
        case .mondayWorking: return ["mondayworking", "monworking"]
        case .mondayFrom: return ["mondayfrom", "monfrom"]
        case .mondayTo: return ["mondayto", "monto"]
        case .tuesdayWorking: return ["tuesdayworking", "tueworking"]
        case .tuesdayFrom: return ["tuesdayfrom", "tuefrom"]
        case .tuesdayTo: return ["tuesdayto", "tueto"]
        case .wednesdayWorking: return ["wednesdayworking", "wedworking"]
        case .wednesdayFrom: return ["wednesdayfrom", "wedfrom"]
        case .wednesdayTo: return ["wednesdayto", "wedto"]
        case .thursdayWorking: return ["thursdayworking", "thuworking"]
        case .thursdayFrom: return ["thursdayfrom", "thufrom"]
        case .thursdayTo: return ["thursdayto", "thuto"]
        case .fridayWorking: return ["fridayworking", "friworking"]
        case .fridayFrom: return ["fridayfrom", "frifrom"]
        case .fridayTo: return ["fridayto", "frito"]
        case .saturdayWorking: return ["saturdayworking", "satworking"]
        case .saturdayFrom: return ["saturdayfrom", "satfrom"]
        case .saturdayTo: return ["saturdayto", "satto"]
        case .exceptionName: return ["exceptionname", "holidayname", "leavename"]
        case .exceptionFromDate: return ["exceptionfrom", "exceptionstart", "holidayfrom", "leavefrom"]
        case .exceptionToDate: return ["exceptionto", "exceptionfinish", "holidayto", "leaveto"]
        case .exceptionType: return ["exceptiontype", "holidaytype", "leavetype"]
        }
    }
}

struct CSVImportResult {
    let plan: NativeProjectPlan
    let report: CSVImportReport
}

struct CSVImportReport: Identifiable {
    let id = UUID()
    let title: String
    let summaryLines: [String]
    let issues: [CSVImportIssue]
}

struct CSVImportIssue: Identifiable {
    let id = UUID()
    let rowNumber: Int?
    let targetID: Int?
    let severity: CSVImportIssueSeverity
    let message: String
    let fixAction: CSVImportFixAction?

    init(
        rowNumber: Int?,
        targetID: Int? = nil,
        severity: CSVImportIssueSeverity,
        message: String,
        fixAction: CSVImportFixAction? = nil
    ) {
        self.rowNumber = rowNumber
        self.targetID = targetID
        self.severity = severity
        self.message = message
        self.fixAction = fixAction
    }

    var rowLabel: String {
        if let rowNumber {
            return "Row \(rowNumber)"
        }
        return "General"
    }
}

enum CSVImportFixAction {
    case createTaskCalendar(name: String, taskID: Int)
    case createResourceCalendar(name: String, resourceID: Int)
    case createParentCalendar(name: String, calendarID: Int)

    var title: String {
        switch self {
        case .createTaskCalendar, .createResourceCalendar, .createParentCalendar:
            return "Create Calendar"
        }
    }
}

enum CSVImportIssueSeverity {
    case warning
    case error

    var rawValue: String {
        switch self {
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
