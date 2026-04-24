import SwiftUI
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let navigateToItem = Notification.Name("navigateToItem")
}

struct NativePlanAnalysis {
    struct HeaderMetrics {
        let plannedCost: Double
        let bac: Double
        let actualCost: Double
        let cpi: Double
        let spi: Double
        let eac: Double
    }

    let project: ProjectModel
    let evm: EVMMetrics
    let headerMetrics: HeaderMetrics
    let validationIssues: [ProjectValidationIssue]
    let diagnosticItems: [ProjectDiagnosticItem]
    let summaryParentTaskIDs: Set<Int>

    static let placeholder: NativePlanAnalysis = {
        let emptyProject = NativeProjectPlan.empty().asProjectModel()
        return NativePlanAnalysis(
            project: emptyProject,
            evm: .zero,
            headerMetrics: HeaderMetrics(
                plannedCost: 0,
                bac: 0,
                actualCost: 0,
                cpi: 0,
                spi: 0,
                eac: 0
            ),
            validationIssues: [],
            diagnosticItems: [],
            summaryParentTaskIDs: Set<Int>()
        )
    }()

    static func build(from plan: NativeProjectPlan) -> NativePlanAnalysis {
        let project = plan.asProjectModel()
        let evm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate)
        let plannedCost = project.tasks
            .filter { $0.summary != true }
            .compactMap(\.cost)
            .reduce(0, +)
        return NativePlanAnalysis(
            project: project,
            evm: evm,
            headerMetrics: HeaderMetrics(
                plannedCost: plannedCost,
                bac: evm.bac,
                actualCost: evm.ac,
                cpi: evm.cpi,
                spi: evm.spi,
                eac: evm.eac
            ),
            validationIssues: ProjectValidator.validate(project: project),
            diagnosticItems: ProjectDiagnostics.analyze(project: project),
            summaryParentTaskIDs: plan.summaryParentTaskIDs()
        )
    }

    static func build(fromProjection planModel: PortfolioProjectPlan) -> NativePlanAnalysis {
        let nativeTasks = planModel.nativeTasksForUI
        let nativeAssignments = planModel.nativeAssignmentsForUI
        let nativeResources = planModel.nativeResourcesForUI
        let nativeCalendars = planModel.nativeCalendarsForUI
        let nativeSprints = planModel.nativeSprintsForUI
        let nativeStatusSnapshots = planModel.nativeStatusSnapshotsForUI
        let nativeWorkflowColumns = planModel.nativeWorkflowColumnsForUI
        let nativeTypeWorkflowOverrides = planModel.nativeTypeWorkflowOverridesForUI
        let projection = NativeProjectPlan(
            portfolioID: planModel.portfolioID,
            title: planModel.title,
            manager: planModel.manager,
            company: planModel.company,
            statusDate: planModel.statusDate,
            defaultCalendarUniqueID: planModel.defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: planModel.boardColumns,
            workflowColumns: nativeWorkflowColumns,
            typeWorkflowOverrides: nativeTypeWorkflowOverrides,
            sprints: nativeSprints,
            statusSnapshots: nativeStatusSnapshots
        )
        return build(from: projection)
    }

    static func buildAsync(from plan: NativeProjectPlan) async -> NativePlanAnalysis {
        let scheduleResult = await PlanScheduler.schedule(plan)
        return await Task.detached(priority: .userInitiated) {
            let project = plan.asProjectModel(scheduleResult: scheduleResult)
            let evm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate)
            let plannedCost = project.tasks
                .filter { $0.summary != true }
                .compactMap(\.cost)
                .reduce(0, +)
            return NativePlanAnalysis(
                project: project,
                evm: evm,
                headerMetrics: HeaderMetrics(
                    plannedCost: plannedCost,
                    bac: evm.bac,
                    actualCost: evm.ac,
                    cpi: evm.cpi,
                    spi: evm.spi,
                    eac: evm.eac
                ),
                validationIssues: ProjectValidator.validate(project: project),
                diagnosticItems: ProjectDiagnostics.analyze(project: project),
                summaryParentTaskIDs: plan.summaryParentTaskIDs()
            )
        }.value
    }

    static func buildAsync(fromProjection planModel: PortfolioProjectPlan) async -> NativePlanAnalysis {
        let nativeTasks = planModel.nativeTasksForUI
        let nativeAssignments = planModel.nativeAssignmentsForUI
        let nativeResources = planModel.nativeResourcesForUI
        let nativeCalendars = planModel.nativeCalendarsForUI
        let nativeSprints = planModel.nativeSprintsForUI
        let nativeStatusSnapshots = planModel.nativeStatusSnapshotsForUI
        let nativeWorkflowColumns = planModel.nativeWorkflowColumnsForUI
        let nativeTypeWorkflowOverrides = planModel.nativeTypeWorkflowOverridesForUI
        let projection = NativeProjectPlan(
            portfolioID: planModel.portfolioID,
            title: planModel.title,
            manager: planModel.manager,
            company: planModel.company,
            statusDate: planModel.statusDate,
            defaultCalendarUniqueID: planModel.defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: planModel.boardColumns,
            workflowColumns: nativeWorkflowColumns,
            typeWorkflowOverrides: nativeTypeWorkflowOverrides,
            sprints: nativeSprints,
            statusSnapshots: nativeStatusSnapshots
        )
        return await buildAsync(from: projection)
    }
}

struct StatusOvertimeDriver: Identifiable {
    let assignment: NativePlanAssignment
    let resource: NativePlanResource?

    var id: Int { assignment.id }
}

struct StatusCenterDerivedContent {
    let workTasks: [ProjectTask]
    let statusMetrics: EVMMetrics
    let overdueCount: Int
    let inProgressCount: Int
    let missingActualCount: Int
    let filteredTasks: [ProjectTask]
    let assignmentsByTaskID: [Int: [NativePlanAssignment]]
    let topScheduleSlips: [ProjectTask]
    let topCostOverruns: [ProjectTask]
    let topOvertimeDrivers: [StatusOvertimeDriver]
    let sortedSnapshots: [NativeStatusSnapshot]

    static func build(
        project: ProjectModel,
        assignments: [NativePlanAssignment],
        resources: [NativePlanResource],
        statusDate: Date,
        snapshots: [NativeStatusSnapshot],
        filter: StatusTaskFilter,
        searchText: String
    ) -> StatusCenterDerivedContent {
        let workTasks = project.tasks.filter { $0.summary != true }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let assignmentsByTaskID = Dictionary(grouping: assignments, by: \.taskID)
        let resourcesByID = Dictionary(nonThrowingUniquePairs: resources.map { ($0.id, $0) })

        let filteredTasks = workTasks.filter { task in
            let matchesFilter = switch filter {
            case .all:
                true
            case .attention:
                taskStatusNeedsAttentionStatic(task, statusDate: statusDate)
            case .inProgress:
                task.isInProgress
            case .overdue:
                !task.isCompleted && ((task.finishDate ?? .distantFuture) < statusDate)
            case .missingActuals:
                ((task.percentComplete ?? 0) > 0 && task.actualStart == nil) || (task.isCompleted && task.actualFinish == nil)
            }

            guard matchesFilter else { return false }
            guard !trimmedSearch.isEmpty else { return true }
            return task.displayName.lowercased().contains(trimmedSearch)
                || (task.wbs?.lowercased().contains(trimmedSearch) == true)
                || (task.id.map(String.init)?.contains(trimmedSearch) == true)
        }

        let topScheduleSlips = Array(
            workTasks
                .filter { ($0.finishVarianceDays ?? 0) > 0 }
                .sorted { ($0.finishVarianceDays ?? 0) > ($1.finishVarianceDays ?? 0) }
                .prefix(5)
        )

        let topCostOverruns = Array(
            workTasks
                .filter { task in
                    let baseline = task.baselineCost ?? task.cost ?? 0
                    let actual = task.actualCost ?? 0
                    return baseline > 0 && actual > baseline
                }
                .sorted { lhs, rhs in
                    let lhsBaseline = lhs.baselineCost ?? lhs.cost ?? 0
                    let rhsBaseline = rhs.baselineCost ?? rhs.cost ?? 0
                    let lhsOverrun = (lhs.actualCost ?? 0) - lhsBaseline
                    let rhsOverrun = (rhs.actualCost ?? 0) - rhsBaseline
                    return lhsOverrun > rhsOverrun
                }
                .prefix(5)
        )

        let topOvertimeDrivers = assignments
            .filter { ($0.overtimeWorkSeconds ?? 0) > 0 }
            .sorted { ($0.overtimeWorkSeconds ?? 0) > ($1.overtimeWorkSeconds ?? 0) }
            .prefix(5)
            .map { assignment in
                StatusOvertimeDriver(
                    assignment: assignment,
                    resource: assignment.resourceID.flatMap { resourcesByID[$0] }
                )
            }

        return StatusCenterDerivedContent(
            workTasks: workTasks,
            statusMetrics: EVMCalculator.projectMetrics(tasks: workTasks, statusDate: statusDate),
            overdueCount: workTasks.filter { !$0.isCompleted && ($0.finishDate ?? .distantFuture) < statusDate }.count,
            inProgressCount: workTasks.filter(\.isInProgress).count,
            missingActualCount: workTasks.filter { task in
                let shouldHaveActualStart = (task.percentComplete ?? 0) > 0
                let shouldHaveActualFinish = task.isCompleted
                let missingStart = shouldHaveActualStart && task.actualStart == nil
                let missingFinish = shouldHaveActualFinish && task.actualFinish == nil
                return missingStart || missingFinish
            }.count,
            filteredTasks: filteredTasks,
            assignmentsByTaskID: assignmentsByTaskID,
            topScheduleSlips: topScheduleSlips,
            topCostOverruns: topCostOverruns,
            topOvertimeDrivers: topOvertimeDrivers,
            sortedSnapshots: snapshots.sorted(by: { $0.statusDate > $1.statusDate })
        )
    }

    private static func taskStatusNeedsAttentionStatic(_ task: ProjectTask, statusDate: Date) -> Bool {
        let overdue = !task.isCompleted && ((task.finishDate ?? .distantFuture) < statusDate)
        let hasCostOverrun = {
            let baseline = task.baselineCost ?? task.cost ?? 0
            let actual = task.actualCost ?? 0
            return baseline > 0 && actual > baseline
        }()
        let missingActualStart = (task.percentComplete ?? 0) > 0 && task.actualStart == nil
        let missingActualFinish = task.isCompleted && task.actualFinish == nil
        return overdue || hasCostOverrun || missingActualStart || missingActualFinish
    }
}

struct AgileLaneTasks: Identifiable {
    let lane: String
    let tasks: [NativePlanTask]
    let id: String

    init(lane: String, tasks: [NativePlanTask], id: String) {
        self.lane = lane
        self.tasks = tasks
        self.id = id
    }
}

struct AgileSwimlaneGroup: Identifiable {
    let key: String
    let title: String
    let tasks: [NativePlanTask]
    let lane: String
    let parentTaskID: Int?
    let representsHierarchyRoot: Bool

    var id: String { key }
}

struct AgileBoardDerivedContent {
    let agileTasks: [NativePlanTask]
    let backlogTasks: [NativePlanTask]
    let boardColumns: [String]
    let tasksByLane: [AgileLaneTasks]
    let sprintNamesByID: [Int: String]
    let taskByID: [Int: NativePlanTask]
    let taskOrderByID: [Int: Int]
    let parentTaskIDByTaskID: [Int: Int]
    let parentTaskNameByTaskID: [Int: String]
    let rootParentTaskIDByTaskID: [Int: Int]
    let hierarchyDepthByTaskID: [Int: Int]
    let latestSnapshot: NativeStatusSnapshot?
    let totalStoryPoints: Int
    let doneCount: Int
    let readyCount: Int
    let inProgressCount: Int
    let completedCount: Int

    static func build(
        tasks: [NativePlanTask],
        assignments: [NativePlanAssignment],
        resources: [NativePlanResource],
        sprints: [NativePlanSprint],
        boardColumns configuredBoardColumns: [String],
        workflowColumns: [NativeBoardWorkflowColumn],
        typeWorkflowOverrides: [NativeBoardTypeWorkflow],
        statusSnapshots: [NativeStatusSnapshot]
    ) -> AgileBoardDerivedContent {
        var summaryTaskIDs: Set<Int> = []
        for index in tasks.indices.dropLast() where tasks[index + 1].outlineLevel > tasks[index].outlineLevel {
            summaryTaskIDs.insert(tasks[index].id)
        }

        var taskOrderByID: [Int: Int] = [:]
        var parentTaskIDByTaskID: [Int: Int] = [:]
        var parentTaskNameByTaskID: [Int: String] = [:]
        var hierarchyDepthByTaskID: [Int: Int] = [:]
        var outlineStack: [(level: Int, id: Int, name: String)] = []

        for (index, task) in tasks.enumerated() {
            taskOrderByID[task.id] = index

            while let last = outlineStack.last, last.level >= task.outlineLevel {
                outlineStack.removeLast()
            }

            if let parent = outlineStack.last {
                parentTaskIDByTaskID[task.id] = parent.id
                parentTaskNameByTaskID[task.id] = parent.name
                hierarchyDepthByTaskID[task.id] = max(0, task.outlineLevel - 1)
            } else {
                hierarchyDepthByTaskID[task.id] = 0
            }

            outlineStack.append((level: task.outlineLevel, id: task.id, name: task.name))
        }

        let activeTasks = tasks.filter(\.isActive)
        let taskByID = Dictionary(nonThrowingUniquePairs: activeTasks.map { ($0.id, $0) })
        var rootParentTaskIDByTaskID: [Int: Int] = [:]

        for task in activeTasks {
            var rootID = task.id
            var currentID = task.id
            while let parentID = parentTaskIDByTaskID[currentID] {
                rootID = parentID
                currentID = parentID
            }
            rootParentTaskIDByTaskID[task.id] = rootID
        }

        let agileTasks = activeTasks.filter { task in
            !summaryTaskIDs.contains(task.id) || task.storyPoints != nil || !task.boardStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !task.epicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let taskStatuses = agileTasks
            .map(\.boardStatus)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var ordered: [String] = []

        let configuredColumns = workflowColumns.isEmpty ? configuredBoardColumns : workflowColumns.map(\.name)

        for column in configuredColumns where !column.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = column.trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(normalized.lowercased()).inserted {
                ordered.append(normalized)
            }
        }

        for status in taskStatuses where seen.insert(status.lowercased()).inserted {
            ordered.append(status)
        }

        let boardColumns = ordered.isEmpty ? NativeProjectPlan.defaultBoardColumns : ordered
        let grouped = Dictionary(grouping: agileTasks) { task in
            normalizedBoardStatus(task.boardStatus, boardColumns: boardColumns)
        }

        let laneColumns = boardColumns.enumerated().map { index, lane in
            (lane: lane, id: "\(index)|\(lane)")
        }
        let sprintNamesByID = Dictionary(nonThrowingUniquePairs: sprints.map { ($0.id, $0.name) })
        let readyCount = agileTasks.reduce(0) { partial, task in
            partial + (normalizedBoardStatus(task.boardStatus, boardColumns: boardColumns) == "Ready" ? 1 : 0)
        }
        let inProgressCount = agileTasks.reduce(0) { partial, task in
            partial + (normalizedBoardStatus(task.boardStatus, boardColumns: boardColumns) == "In Progress" ? 1 : 0)
        }
        let completedCount = agileTasks.reduce(0) { partial, task in
            partial + ((normalizedBoardStatus(task.boardStatus, boardColumns: boardColumns) == "Done" || task.percentComplete >= 100) ? 1 : 0)
        }

        return AgileBoardDerivedContent(
            agileTasks: agileTasks,
            backlogTasks: agileTasks.filter { $0.sprintID == nil },
            boardColumns: boardColumns,
            tasksByLane: laneColumns.map { laneDescriptor in
                AgileLaneTasks(
                    lane: laneDescriptor.lane,
                    tasks: grouped[laneDescriptor.lane] ?? [],
                    id: laneDescriptor.id
                )
            },
            sprintNamesByID: sprintNamesByID,
            taskByID: taskByID,
            taskOrderByID: taskOrderByID,
            parentTaskIDByTaskID: parentTaskIDByTaskID,
            parentTaskNameByTaskID: parentTaskNameByTaskID,
            rootParentTaskIDByTaskID: rootParentTaskIDByTaskID,
            hierarchyDepthByTaskID: hierarchyDepthByTaskID,
            latestSnapshot: statusSnapshots.sorted { $0.statusDate < $1.statusDate }.last,
            totalStoryPoints: agileTasks.reduce(0) { $0 + max(0, $1.storyPoints ?? 0) },
            doneCount: completedCount,
            readyCount: readyCount,
            inProgressCount: inProgressCount,
            completedCount: completedCount
        )
    }

    private static func normalizedBoardStatus(_ rawStatus: String, boardColumns: [String]) -> String {
        let normalized = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return boardColumns.first(where: { $0.compare(normalized, options: .caseInsensitive) == .orderedSame }) ?? boardColumns.first ?? "Backlog"
    }
}

struct StableDecimalTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        NativeDraftTextField(title: title, text: $text, trimsWhitespaceOnCommit: true)
    }
}

struct StableDraftTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        NativeDraftTextField(title: title, text: $text, trimsWhitespaceOnCommit: false)
    }
}

private struct NativeDraftTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var trimsWhitespaceOnCommit: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, trimsWhitespaceOnCommit: trimsWhitespaceOnCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = LightweightDraftTextField()
        textField.placeholderString = title
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = text
        context.coordinator.applyAppearance(to: textField, isEditing: false)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = title
        context.coordinator.trimsWhitespaceOnCommit = trimsWhitespaceOnCommit

        if !context.coordinator.isEditing, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var trimsWhitespaceOnCommit: Bool
        var isEditing = false

        init(text: Binding<String>, trimsWhitespaceOnCommit: Bool) {
            self._text = text
            self.trimsWhitespaceOnCommit = trimsWhitespaceOnCommit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            if let field = obj.object as? NSTextField {
                applyAppearance(to: field, isEditing: true)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            defer {
                isEditing = false
                if let field = obj.object as? NSTextField {
                    applyAppearance(to: field, isEditing: false)
                }
            }
            guard let field = obj.object as? NSTextField else { return }
            let committed = trimsWhitespaceOnCommit
                ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                : field.stringValue
            if field.stringValue != committed {
                field.stringValue = committed
            }
            text = committed
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        func applyAppearance(to field: NSTextField, isEditing: Bool) {
            field.layer?.borderColor = (isEditing ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.55)).cgColor
            field.layer?.borderWidth = isEditing ? 1.5 : 1
        }
    }
}

private final class LightweightDraftTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        cell = LightweightDraftTextFieldCell(textCell: "")
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = NSColor.controlBackgroundColor.blended(withFraction: 0.35, of: .windowBackgroundColor) ?? .controlBackgroundColor
        focusRingType = .none
        wantsLayer = true
        font = .systemFont(ofSize: 13, weight: .regular)
        textColor = .labelColor
        isEditable = true
        isSelectable = true
        lineBreakMode = .byTruncatingTail
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        layer?.backgroundColor = backgroundColor?.cgColor
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width, height: max(30, size.height + 10))
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = backgroundColor?.cgColor
    }
}

private final class LightweightDraftTextFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 10
    private let verticalInset: CGFloat = 6

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: rect.insetBy(dx: horizontalInset, dy: verticalInset), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: rect.insetBy(dx: horizontalInset, dy: verticalInset), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

struct AppFinanceTerm: Identifiable {
    let shortCode: String
    let fullName: String
    let meaning: String
    let guidance: String

    var id: String { shortCode }
}

struct AppFeatureGuide: Identifiable {
    let title: String
    let icon: String
    let availability: String
    let summary: String
    let details: [String]

    var id: String { title }
}

struct AppWorkflowGuide: Identifiable {
    let title: String
    let icon: String
    let summary: String
    let steps: [String]

    var id: String { title }
}

struct AppDocumentModeGuide: Identifiable {
    let typeName: String
    let bestFor: String
    let editing: String
    let notes: [String]

    var id: String { typeName }
}

enum AppHelpCatalog {
    static let financeTerms: [AppFinanceTerm] = [
        AppFinanceTerm(shortCode: "BAC", fullName: "Budget at Completion", meaning: "The full planned budget for the work when finished.", guidance: "Higher than expected later EAC means the forecast is overrunning BAC."),
        AppFinanceTerm(shortCode: "PV", fullName: "Planned Value", meaning: "How much budgeted work should have been earned by the status date.", guidance: "Use it as the schedule baseline for earned value."),
        AppFinanceTerm(shortCode: "EV", fullName: "Earned Value", meaning: "The budgeted value of the work actually completed so far.", guidance: "If EV lags PV, the work is behind plan."),
        AppFinanceTerm(shortCode: "AC", fullName: "Actual Cost", meaning: "What the work has actually cost so far.", guidance: "If AC rises faster than EV, cost efficiency is dropping."),
        AppFinanceTerm(shortCode: "CPI", fullName: "Cost Performance Index", meaning: "EV divided by AC, showing cost efficiency.", guidance: "Above 1.00 is favorable, below 1.00 means over budget for the value earned."),
        AppFinanceTerm(shortCode: "SPI", fullName: "Schedule Performance Index", meaning: "EV divided by PV, showing schedule efficiency.", guidance: "Above 1.00 is ahead of plan, below 1.00 is behind plan."),
        AppFinanceTerm(shortCode: "EAC", fullName: "Estimate at Completion", meaning: "The current forecast of total cost at finish.", guidance: "Compare EAC to BAC to see the likely final overrun or underrun."),
        AppFinanceTerm(shortCode: "ETC", fullName: "Estimate to Complete", meaning: "The forecast remaining cost from now to finish.", guidance: "ETC helps answer what is still expected to be spent."),
        AppFinanceTerm(shortCode: "VAC", fullName: "Variance at Completion", meaning: "BAC minus EAC, showing forecast budget variance at finish.", guidance: "Negative VAC means the current forecast ends over budget."),
        AppFinanceTerm(shortCode: "CV", fullName: "Cost Variance", meaning: "EV minus AC, showing whether earned value is ahead of or behind actual cost.", guidance: "Negative CV means the work has cost more than the value earned."),
        AppFinanceTerm(shortCode: "SV", fullName: "Schedule Variance", meaning: "EV minus PV, showing whether earned value is ahead of or behind planned value.", guidance: "Negative SV means progress is lagging the plan."),
        AppFinanceTerm(shortCode: "TCPI", fullName: "To-Complete Performance Index", meaning: "The cost efficiency needed on remaining work to hit the target budget.", guidance: "Well above 1.00 means the remaining work must perform unusually efficiently to recover."),
        AppFinanceTerm(shortCode: "BCWS", fullName: "Budgeted Cost of Work Scheduled", meaning: "Older term for PV.", guidance: "In this app, BCWS maps to planned value."),
        AppFinanceTerm(shortCode: "BCWP", fullName: "Budgeted Cost of Work Performed", meaning: "Older term for EV.", guidance: "In this app, BCWP maps to earned value."),
        AppFinanceTerm(shortCode: "ACWP", fullName: "Actual Cost of Work Performed", meaning: "Older term for AC.", guidance: "In this app, ACWP maps to actual cost."),
        AppFinanceTerm(shortCode: "WBS", fullName: "Work Breakdown Structure", meaning: "The outline code that shows a task’s place in the hierarchy.", guidance: "WBS is useful for grouping and locating summary and child tasks.")
    ]

    static let featureSections: [(title: String, items: [AppFeatureGuide])] = [
        (
            "Core Screens",
            [
                AppFeatureGuide(title: "Dashboard", icon: NavigationItem.dashboard.icon, availability: "MPP + Native Plan", summary: "Audience-focused review dashboard for project managers, executives, schedulers, and resource managers.", details: [
                    "Shows KPI cards, baseline alerts, schedule health, resource summary, milestones, and open review signals.",
                    "Supports snapshots, review templates, reminder cadence, and export-oriented review flows.",
                    "Best used as the first stop for health review rather than detailed editing."
                ]),
                AppFeatureGuide(title: "Executive Mode", icon: NavigationItem.executive.icon, availability: "MPP + Native Plan", summary: "Condensed executive health view for sponsor and steering review.", details: [
                    "Highlights progress, schedule position, cost outlook, major milestones, and top risks.",
                    "Provides summary-oriented exports and narrative review text.",
                    "Useful when you need a high-level read without planner detail."
                ]),
                AppFeatureGuide(title: "Summary", icon: NavigationItem.summary.icon, availability: "MPP + Native Plan", summary: "Read-only project property and project structure summary.", details: [
                    "Shows project metadata, counts, date bounds, calendars, cost basics, and structural facts.",
                    "Useful for orientation when opening a new project or validating file content."
                ])
            ]
        ),
        (
            "Plan Creation & Editing",
            [
                AppFeatureGuide(title: "Plan Builder", icon: NavigationItem.planner.icon, availability: "Native Plan Only", summary: "Primary native planning editor with grid entry and detailed inspector editing.", details: [
                    "Create, delete, duplicate, reorder, indent, and outdent tasks.",
                    "Edit dates, duration, predecessors, constraints, baselines, financial values, assignments, actuals, agile type, sprint, story points, epic, and tags.",
                    "Supports CSV/Excel-compatible imports for tasks, assignments, dependencies, constraints, baselines, plus starter templates and import reports."
                ]),
                AppFeatureGuide(title: "Agile Board", icon: NavigationItem.agileBoard.icon, availability: "Native Plan Only", summary: "Hybrid planning surface for backlog, sprint, and agile reporting on the same native plan data.", details: [
                    "Organizes native tasks into backlog and board lanes with status, sprint, epic, and story-point metadata.",
                    "Includes sprint planning, capacity review, and simple hybrid-agile reporting from saved status snapshots.",
                    "Keeps agile execution tied to the same dates, resources, calendars, and financial model used elsewhere in the app."
                ]),
                AppFeatureGuide(title: "Gantt Chart", icon: NavigationItem.gantt.icon, availability: "MPP Review + Native Edit", summary: "Timeline chart for visual schedule review and native plan editing.", details: [
                    "View mode keeps the chart clean for review; Edit mode unlocks task creation and visual schedule changes.",
                    "Supports drag to move or resize tasks, control-click source linking, dependency editing, and hierarchy actions.",
                    "Has a docked inspector with Task, Links, Staffing, and Finance tabs for selected items."
                ]),
                AppFeatureGuide(title: "Tasks", icon: NavigationItem.tasks.icon, availability: "MPP + Native Plan", summary: "Task table for task-by-task inspection and export.", details: [
                    "Searches by task name, ID, WBS, notes, resources, and custom fields.",
                    "Useful for broad task review when a Gantt is too visual or dense.",
                    "Exports task lists and issue-oriented CSV outputs."
                ]),
                AppFeatureGuide(title: "Milestones", icon: NavigationItem.milestones.icon, availability: "MPP + Native Plan", summary: "Milestone-focused view for upcoming checkpoints and completion review.", details: [
                    "Filters the project down to milestone tasks for schedule checkpoint review.",
                    "Useful for reporting and gate-readiness validation."
                ]),
                AppFeatureGuide(title: "Timeline", icon: NavigationItem.timeline.icon, availability: "MPP + Native Plan", summary: "High-level visual timeline for broader date-range review.", details: [
                    "Best for coarse schedule communication and presentation.",
                    "Shows the plan on a simpler temporal strip than the full editable Gantt."
                ]),
                AppFeatureGuide(title: "Schedule", icon: NavigationItem.schedule.icon, availability: "MPP + Native Plan", summary: "Read-focused schedule layout for inspecting time-phased task placement.", details: [
                    "Keeps schedule review separate from the more interactive Gantt editing surface.",
                    "Useful for scanning durations, placements, and summary alignment."
                ])
            ]
        ),
        (
            "Resources, Calendars & Status",
            [
                AppFeatureGuide(title: "Resources", icon: NavigationItem.resources.icon, availability: "MPP Review + Native Edit", summary: "Resource sheet and native resource editor for staffing data.", details: [
                    "For native plans, create and edit resources, rates, cost-per-use, max units, group, email, and base calendar.",
                    "For imported MPP files, review imported resources and their assignments in the read-only sheet.",
                    "Supports resource CSV/Excel-compatible imports, templates, and review mode."
                ]),
                AppFeatureGuide(title: "Calendar", icon: NavigationItem.calendar.icon, availability: "MPP Review + Native Edit", summary: "Calendar review and native calendar authoring for working time rules.", details: [
                    "Edit working days, time ranges, exceptions, project default calendar, and leave/holiday exceptions for native plans.",
                    "Imported projects keep the original read-only calendar inspection view.",
                    "Supports calendar CSV/Excel-compatible import, templates, and review mode."
                ]),
                AppFeatureGuide(title: "Workload", icon: NavigationItem.workload.icon, availability: "MPP + Native Plan", summary: "Resource allocation and time-phased workload review.", details: [
                    "Shows resource loading over time using task assignments and calendars.",
                    "Useful for spotting overloads, underuse, and overtime pressure."
                ]),
                AppFeatureGuide(title: "Status Center", icon: NavigationItem.statusCenter.icon, availability: "Native Plan Only", summary: "Periodic project-controls screen for updating actuals and reviewing live variance.", details: [
                    "Set the project status date and then update actual start, actual finish, progress, actual cost, status notes, and assignment actual/remaining/overtime work.",
                    "Includes filters like Needs Attention, In Progress, Overdue, and Missing Actuals.",
                    "Surfaces CPI, SPI, EAC, VAC, top slippages, cost overruns, overtime drivers, and saved status snapshot history."
                ])
            ]
        ),
        (
            "Analysis & Assurance",
            [
                AppFeatureGuide(title: "Validation", icon: NavigationItem.validation.icon, availability: "MPP + Native Plan", summary: "Project quality checks focused on structural and data-entry issues.", details: [
                    "Flags errors, warnings, and information-level validation items tied to specific tasks where possible.",
                    "Useful for catching finish-before-start, missing dates, weak baselines, and similar plan defects."
                ]),
                AppFeatureGuide(title: "Diagnostics", icon: NavigationItem.diagnostics.icon, availability: "MPP + Native Plan", summary: "Schedule signal analysis for dependency, constraint, and logic hotspots.", details: [
                    "Surfaces schedule-quality concerns beyond simple validation rules.",
                    "Good for explaining where the network is brittle or where planning assumptions need review."
                ]),
                AppFeatureGuide(title: "Dependency Explorer", icon: NavigationItem.dependencyExplorer.icon, availability: "MPP + Native Plan", summary: "Focused task-relationship analysis view.", details: [
                    "Lets you inspect predecessor and successor relationships more directly than the broader task table.",
                    "Useful for network review and impact tracing."
                ]),
                AppFeatureGuide(title: "Resource Risks", icon: NavigationItem.resourceRisks.icon, availability: "MPP + Native Plan", summary: "Risk-oriented resource analysis view.", details: [
                    "Highlights over-allocation and staffing hotspots from the current schedule and assignments.",
                    "Useful for triage before adjusting calendars, staffing, or sequencing."
                ]),
                AppFeatureGuide(title: "Critical Path", icon: NavigationItem.criticalPath.icon, availability: "MPP + Native Plan", summary: "Critical and near-critical schedule review.", details: [
                    "Shows work most likely to move finish dates or absorb float first.",
                    "Useful before baseline capture, forecast review, and status meetings."
                ]),
                AppFeatureGuide(title: "Compare", icon: NavigationItem.diff.icon, availability: "MPP + Native Plan", summary: "Baseline and file-to-file comparison view.", details: [
                    "Compares project versions, native plans, or baseline states to show change impact.",
                    "Useful for change review, forecast discussion, and auditability."
                ])
            ]
        ),
        (
            "Financial & Reporting",
            [
                AppFeatureGuide(title: "Earned Value", icon: NavigationItem.earnedValue.icon, availability: "MPP + Native Plan", summary: "Dedicated financial control and earned value screen.", details: [
                    "Shows project CPI, SPI, EAC, VAC, S-curve, and task-level EVM rows.",
                    "Useful after baselines, costs, and actuals are populated.",
                    "Includes an in-screen glossary because many financial labels are abbreviated."
                ]),
                AppFeatureGuide(title: "Guide & Help", icon: NavigationItem.helpCenter.icon, availability: "App-Wide", summary: "Built-in documentation, feature reference, workflow guide, glossary, and shortcuts.", details: [
                    "Available from the sidebar and the macOS Help menu.",
                    "Explains feature purpose, availability, and common workflow paths."
                ])
            ]
        )
    ]

    static let documentModes: [AppDocumentModeGuide] = [
        AppDocumentModeGuide(
            typeName: ".mpp",
            bestFor: "Reviewing Microsoft Project schedules on macOS",
            editing: "Read-only review and analysis",
            notes: [
                "Use imported MPP files for dashboard review, schedule analysis, workload, diagnostics, and exports.",
                "Imported MPP files keep original project data and do not unlock native editing screens like Plan Builder or Status Center."
            ]
        ),
        AppDocumentModeGuide(
            typeName: ".mppplan",
            bestFor: "Building and updating plans directly in the app",
            editing: "Full native editing",
            notes: [
                "Native plans unlock Plan Builder, Gantt editing, Resources, Calendar, Status Center, finance entry, imports, and native save/open later.",
                "Use `.mppplan` when the app is the working system for planning, statusing, and project controls."
            ]
        )
    ]

    static let workflows: [AppWorkflowGuide] = [
        AppWorkflowGuide(
            title: "Start Here",
            icon: "play.circle",
            summary: "Recommended first-run path for understanding the app quickly.",
            steps: [
                "Open the included showcase `.mppplan` to see a fully populated native schedule with resources, calendars, status, and finance already filled in.",
                "Visit `Dashboard` for overall health, then `Plan Builder` and `Gantt Chart` to see the two main editing surfaces.",
                "Continue to `Status Center`, `Earned Value`, `Resources`, and `Calendar` to see project controls and staffing workflows."
            ]
        ),
        AppWorkflowGuide(
            title: "Build a Native Plan",
            icon: "square.and.pencil",
            summary: "Use this path when creating or maintaining a plan directly in the app.",
            steps: [
                "Create a new `.mppplan` document or duplicate a native plan you already have.",
                "Use `Plan Builder` for grid-first entry, hierarchy editing, constraints, baselines, assignments, and finance values.",
                "Use `Gantt Chart` in Edit mode when date movement, visual resizing, linking, or structure changes are easier to do on a timeline.",
                "Use `Resources` and `Calendar` to set staffing, rates, working time, and exceptions before deeper controls work."
            ]
        ),
        AppWorkflowGuide(
            title: "Hybrid Agile Planning",
            icon: "rectangle.3.group.bubble.left",
            summary: "Use this path when you want backlog, sprint, and board flow on top of the same project schedule.",
            steps: [
                "Add agile metadata in `Plan Builder`, including agile type, board status, sprint, story points, epic, and tags.",
                "Open `Agile Board` to manage backlog flow, assign work into sprints, and review sprint capacity and committed points.",
                "Capture periodic snapshots in `Status Center`, then review trend and sprint reporting back in `Agile Board`."
            ]
        ),
        AppWorkflowGuide(
            title: "Import Spreadsheet Data",
            icon: "square.and.arrow.down",
            summary: "Use mapped imports when your source data already lives in spreadsheets.",
            steps: [
                "Open a native `.mppplan`, then use import actions in `Plan Builder`, `Resources`, or `Calendar`.",
                "Map your spreadsheet columns in the import sheet rather than forcing a fixed template shape.",
                "Review the import report for created, updated, skipped, and warning rows, then jump back to affected items if needed."
            ]
        ),
        AppWorkflowGuide(
            title: "Status and Controls Cycle",
            icon: "checklist",
            summary: "Use this path for weekly or periodic updates after the plan is underway.",
            steps: [
                "Set the project status date in `Status Center`, then update actual start, actual finish, progress, actual cost, and assignment actual/remaining/overtime work.",
                "Review `Earned Value` for CPI, SPI, EAC, VAC, S-curve shape, and task-level cost/schedule variance.",
                "Finish in `Validation`, `Diagnostics`, `Workload`, and `Dashboard` to identify issues, overloads, and review outputs."
            ]
        )
    ]

    static let importCoverage: [String] = [
        "Tasks, resources, calendars, assignments, dependencies, constraints, baselines, and financial fields support mapped CSV import.",
        "Excel-compatible `.xls` templates are included for bulk loading and recurring update cycles.",
        "Template exports provide starter sheets, while import reports let you reopen mapping, export warnings, and jump to affected items."
    ]
}

struct FinancialTermsLegendView: View {
    var terms: [AppFinanceTerm] = AppHelpCatalog.financeTerms

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial & EVM Terms")
                .font(.headline)
            Text("Short labels used in financial, status, and earned value views.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(terms) { term in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(term.shortCode)
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(term.fullName)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(term.meaning)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(term.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

struct FinancialTermsButton: View {
    var title = "Financial Terms"
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label(title, systemImage: "text.book.closed")
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollView {
                FinancialTermsLegendView()
                    .padding(16)
                    .frame(width: 520, alignment: .topLeading)
            }
        }
        .help("Open a glossary for financial and earned value abbreviations used in the app.")
    }
}

struct AppGuideView: View {
    let isEditablePlan: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Guide & Help")
                        .font(.largeTitle.weight(.semibold))
                    Text("A quick reference for building plans, updating status, and reading financial and earned value signals.")
                        .foregroundStyle(.secondary)
                }

                guideSection(
                    title: "What This App Covers",
                    icon: "square.text.square",
                    lines: [
                        "Open imported `.mpp` schedules for review and analysis.",
                        isEditablePlan ? "Create and edit native `.mppplan` schedules directly in the app." : "Create a new `.mppplan` document from File > New to edit plans directly in the app.",
                        "Review schedule, workload, resources, calendars, status, financials, and earned value from the same project model."
                    ]
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Use the included showcase plan as your first guided tour through the app.")
                            .font(.headline)
                        Text("Open `aurora-commerce-launch.mppplan` to see tasks, hierarchy, calendars, resources, assignments, status, and financial controls already populated.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Label("Native sample plan included", systemImage: "doc.badge.plus")
                                .font(.caption.weight(.semibold))
                            Label("Best viewed with Dashboard → Plan Builder → Gantt → Status Center", systemImage: "arrow.right.circle")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                } label: {
                    Label("Start With The Sample Plan", systemImage: "star")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(AppHelpCatalog.documentModes) { mode in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(mode.typeName)
                                        .font(.system(.headline, design: .monospaced))
                                    Text(mode.bestFor)
                                        .font(.subheadline.weight(.semibold))
                                }
                                Text("Editing: \(mode.editing)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(Array(mode.notes.enumerated()), id: \.offset) { note in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 6)
                                        Text(note.element)
                                            .font(.caption)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if mode.id != AppHelpCatalog.documentModes.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Document Modes", systemImage: "doc.on.doc")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(AppHelpCatalog.workflows) { workflow in
                            workflowCard(workflow)
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Common Workflows", systemImage: "point.3.filled.connected.trianglepath.dotted")
                }

                guideSection(
                    title: "Build a Plan",
                    icon: "square.and.pencil",
                    lines: [
                        "Use `Plan Builder` for fast grid entry and detailed task editing.",
                        "Use `Agile Board` when you need backlog, sprint, board-status, and story-point views on the same native plan.",
                        "Use `Gantt Chart` in `Edit` mode for visual move, resize, link, indent, and subtask changes.",
                        "Use `Resources` and `Calendar` to define staffing, base calendars, and leave exceptions."
                    ]
                )

                guideSection(
                    title: "Import & Templates",
                    icon: "square.and.arrow.down",
                    lines: [
                        "Task, resource, calendar, assignment, dependency, constraint, and baseline imports support CSV and Excel-compatible `.xls` files.",
                        "Template exports provide starter sheets for bulk loading and recurring updates.",
                        "Import reports can reopen mapping, export warnings, and jump to affected items."
                    ]
                )

                guideSection(
                    title: "Import Coverage",
                    icon: "tablecells",
                    lines: AppHelpCatalog.importCoverage
                )

                guideSection(
                    title: "Status & Control",
                    icon: "checklist",
                    lines: [
                        "Use `Status Center` to set status date, actual dates, progress, actual cost, assignment actual/remaining/overtime work, and capture reporting snapshots.",
                        "Use `Earned Value` for CPI, SPI, EAC, VAC, S-curve, and task-level EVM.",
                        "Use `Dashboard`, `Validation`, and `Diagnostics` to spot schedule-quality and resource-risk issues, then use `Agile Board` reports for sprint-specific trend review."
                    ]
                )

                guideSection(
                    title: "Useful Shortcuts",
                    icon: "command",
                    lines: [
                        "Command-1 through Command-9 open the first sidebar views directly.",
                        "In the planner grid, Tab and Shift-Tab move between cells, Enter moves down, and Command-Return adds a row.",
                        "In Gantt edit mode, Control-click a task bar starts dependency linking."
                    ]
                )

                guideSection(
                    title: "Document Types",
                    icon: "doc.on.doc",
                    lines: [
                        "Imported `.mpp` files are review-first documents. They feed analysis, dashboards, schedule views, and read-only inspection screens.",
                        isEditablePlan ? "This document is a native `.mppplan`, so plan creation, statusing, finance entry, resource editing, and calendar editing are available." : "Create a native `.mppplan` from `File > New` when you want in-app editing, imports, status updates, and native save/open later.",
                        "Many screens work for both document types, but native plans unlock editing workflows."
                    ]
                )

                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Feature Reference")
                            .font(.headline)
                        Text("Each major screen in the app, what it is for, and what you can do there.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(AppHelpCatalog.featureSections.enumerated()), id: \.offset) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.element.title)
                                    .font(.title3.weight(.semibold))

                                ForEach(section.element.items) { feature in
                                    featureCard(feature)
                                }
                            }

                            if section.offset != AppHelpCatalog.featureSections.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(8)
                } label: {
                    Label("Detailed Feature Guide", systemImage: "books.vertical")
                }

                GroupBox {
                    FinancialTermsLegendView()
                        .padding(8)
                } label: {
                    Label("Financial Glossary", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func guideSection(title: String, icon: String, lines: [String]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(item.element)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(8)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func featureCard(_ feature: AppFeatureGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(feature.title, systemImage: feature.icon)
                    .font(.headline)
                Text(feature.availability)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            }

            Text(feature.summary)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(feature.details.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(item.element)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func workflowCard(_ workflow: AppWorkflowGuide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(workflow.title, systemImage: workflow.icon)
                .font(.headline)

            Text(workflow.summary)
                .foregroundStyle(.primary)

            ForEach(Array(workflow.steps.enumerated()), id: \.offset) { item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(item.offset + 1).")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .leading)
                    Text(item.element)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case portfolio = "Portfolio"
    case dashboard = "Dashboard"
    case planner = "Plan Builder"
    case agileBoard = "Agile Board"
    case statusCenter = "Status Center"
    case executive = "Executive Mode"
    case summary = "Summary"
    case validation = "Validation"
    case diagnostics = "Diagnostics"
    case dependencyExplorer = "Dependency Explorer"
    case resourceRisks = "Resource Risks"
    case criticalPath = "Critical Path"
    case tasks = "Tasks"
    case gantt = "Gantt Chart"
    case schedule = "Schedule"
    case milestones = "Milestones"
    case resources = "Resources"
    case earnedValue = "Earned Value"
    case workload = "Workload"
    case calendar = "Calendar"
    case timeline = "Timeline"
    case diff = "Compare"
    case helpCenter = "Guide & Help"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .portfolio: return "square.stack.3d.up"
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .planner: return "square.and.pencil"
        case .agileBoard: return "rectangle.3.group.bubble.left"
        case .statusCenter: return "checklist"
        case .executive: return "display"
        case .summary: return "doc.text"
        case .validation: return "checklist.unchecked"
        case .diagnostics: return "stethoscope"
        case .dependencyExplorer: return "network"
        case .resourceRisks: return "person.crop.circle.badge.exclamationmark"
        case .criticalPath: return "point.topleft.down.curvedto.point.bottomright.up"
        case .tasks: return "list.bullet.indent"
        case .gantt: return "chart.bar.xaxis"
        case .schedule: return "rectangle.split.2x1"
        case .milestones: return "diamond.fill"
        case .resources: return "person.2"
        case .earnedValue: return "chart.line.uptrend.xyaxis"
        case .workload: return "person.badge.clock"
        case .calendar: return "calendar"
        case .timeline: return "rectangle.split.3x1"
        case .diff: return "arrow.triangle.2.circlepath"
        case .helpCenter: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @Binding var document: PlanningDocument
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PortfolioProjectPlan.updatedAt, order: .reverse)])
    private var portfolioPlans: [PortfolioProjectPlan]
    @StateObject private var store = ProjectStore()
    @State private var editableAnalysis: NativePlanAnalysis?
    @State private var selectedNav: NavigationItem?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var isFocusMode = false
    @State private var searchText = ""
    @State private var searchSuggestionTasks: [ProjectTask] = []
    @State private var searchSuggestionWorkItem: DispatchWorkItem?
    @State private var navigateToTaskID: Int?
    @State private var cachedFlaggedTaskIDs: Set<Int> = []
    @State private var editableWorkspaceError: String?
    @State private var selectedWorkspacePortfolioID: UUID?
    @State private var isRefreshingEditableAnalysis = false
    @State private var editableAnalysisGeneration = 0
    @AppStorage("flaggedTaskIDs") private var flaggedTaskIDsData: Data = Data()

    init(document: Binding<PlanningDocument>) {
        self._document = document
        self._editableAnalysis = State(initialValue: nil)
        self._cachedFlaggedTaskIDs = State(initialValue: (try? JSONDecoder().decode(Set<Int>.self, from: UserDefaults.standard.data(forKey: "flaggedTaskIDs") ?? Data())) ?? [])
        self._selectedWorkspacePortfolioID = State(initialValue: document.wrappedValue.editablePortfolioID)
    }

    private var flaggedTaskIDs: Binding<Set<Int>> {
        Binding(
            get: {
                cachedFlaggedTaskIDs
            },
            set: { newValue in
                cachedFlaggedTaskIDs = newValue
                flaggedTaskIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }

    private func computeSearchSuggestionTasks(for query: String, project: ProjectModel?) -> [ProjectTask] {
        guard let project, !query.isEmpty else { return [] }
        let search = query.lowercased()
        return project.tasks.filter { task in
            let directMatch =
                task.name?.lowercased().contains(search) == true ||
                task.wbs?.lowercased().contains(search) == true ||
                task.notes?.lowercased().contains(search) == true ||
                task.id.map(String.init)?.contains(search) == true ||
                task.customFields?.values.contains(where: { $0.displayString.lowercased().contains(search) }) == true
            let resourceMatch = project.assignments
                .filter { $0.taskUniqueID == task.uniqueID }
                .contains { assignment in
                    guard let resourceID = assignment.resourceUniqueID else { return false }
                    return project.resources.first(where: { $0.uniqueID == resourceID })?.name?.lowercased().contains(search) == true
                }
            return directMatch || resourceMatch
        }
        .prefix(10)
        .map { $0 }
    }

    private func scheduleSearchSuggestionsRefresh() {
        searchSuggestionWorkItem?.cancel()

        let query = searchText
        let project = currentProject
        let workItem = DispatchWorkItem {
            searchSuggestionTasks = computeSearchSuggestionTasks(for: query, project: project)
        }
        searchSuggestionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private var currentProject: ProjectModel? {
        if document.isEditablePlan {
            return editableAnalysis?.project
        }
        return store.project
    }

    private var editablePortfolioPlan: PortfolioProjectPlan? {
        guard let editablePortfolioID = document.editablePortfolioID else { return nil }
        return portfolioPlan(for: editablePortfolioID)
    }

    private var effectiveEditablePortfolioPlan: PortfolioProjectPlan? {
        guard document.isEditablePlan else { return nil }
        return editablePortfolioPlan
    }

    private var workspacePortfolioID: UUID? {
        selectedWorkspacePortfolioID ?? document.editablePortfolioID
    }

    private var effectiveWorkspacePortfolioPlan: PortfolioProjectPlan? {
        if let activeID = workspacePortfolioID {
            return portfolioPlan(for: activeID)
        }
        return nil
    }

    private var workspacePortfolioBinding: Binding<UUID?> {
        Binding(
            get: { workspacePortfolioID },
            set: { newValue in
                selectedWorkspacePortfolioID = newValue
                if document.isEditablePlan {
                    document.editablePortfolioID = newValue
                }
            }
        )
    }

    private var displayProject: ProjectModel? {
        if document.isEditablePlan {
            return editableAnalysis?.project
        }
        if let plan = effectiveWorkspacePortfolioPlan {
            return plan.asNativePlan().asProjectModel()
        }
        return currentProject
    }

    private func archiveEditablePlan(_ nativePlan: NativeProjectPlan) {
        document.editablePortfolioID = nativePlan.portfolioID
        document.editablePlanData = try? nativePlan.encodedData()
        document.editablePlanSeed = nil
    }

    private func portfolioPlan(for id: UUID?) -> PortfolioProjectPlan? {
        guard let editablePortfolioID = id ?? document.editablePortfolioID else { return nil }
        return portfolioPlans.first(where: { $0.portfolioID == editablePortfolioID })
    }

    private func normalizeEditablePlanResources(_ plan: PortfolioProjectPlan) {
        for resource in plan.resources {
            resource.accrueAt = resource.accrueAtValue
        }
    }

    private func seedNativePlanForEditableWorkspace() -> NativeProjectPlan? {
        if let nativePlan = document.nativePlan {
            return nativePlan
        }

        if let project = editableAnalysis?.project ?? store.project {
            return NativeProjectPlan(projectModel: project)
        }

        return nil
    }

    private func materializeEditableWorkspacePlan() -> PortfolioProjectPlan? {
        guard document.isEditablePlan else { return nil }

        guard var seedPlan = seedNativePlanForEditableWorkspace() else {
            let message = "Failed to materialize editable plan: missing seed data."
            editableWorkspaceError = message
            print(message)
            return nil
        }

        if let activePlanID = document.editablePortfolioID, seedPlan.portfolioID != activePlanID {
            seedPlan.portfolioID = activePlanID
        } else if document.editablePortfolioID == nil {
            document.editablePortfolioID = seedPlan.portfolioID
        }

        do {
            sanitizePortfolioStoreData()
            let upsertedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: seedPlan, in: modelContext)
            normalizeEditablePlanResources(upsertedPlan)
            archiveEditablePlan(seedPlan)
            return upsertedPlan
        } catch {
            let message = "Failed to materialize editable workspace plan: \(error)"
            editableWorkspaceError = message
            print(message)
            print("Attempting repair and retrying editable plan materialization.")
            sanitizePortfolioStoreData()

            do {
                let upsertedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: seedPlan, in: modelContext)
                normalizeEditablePlanResources(upsertedPlan)
                archiveEditablePlan(seedPlan)
                editableWorkspaceError = nil
                return upsertedPlan
            } catch {
                let retryMessage = "Failed again to materialize editable workspace plan: \(error)"
                editableWorkspaceError = retryMessage
                print(retryMessage)
                return nil
            }
        }
    }

    private func sanitizePortfolioStoreData() {
        do {
            var didMutate = false

            let resourceDescriptor = FetchDescriptor<PortfolioPlanResource>()
            let resources = try modelContext.fetch(resourceDescriptor)
            for resource in resources {
                let normalized = resource.accrueAtValue
                if resource.accrueAt != normalized {
                    resource.accrueAt = normalized
                    didMutate = true
                }
            }

            let planDescriptor = FetchDescriptor<PortfolioProjectPlan>()
            let plans = try modelContext.fetch(planDescriptor)
            for plan in plans {
                if plan.isArchived == nil {
                    plan.isArchived = false
                    didMutate = true
                }
            }

            if didMutate {
                try modelContext.save()
            }
        } catch {
            print("Failed to sanitize persisted portfolio data: \(error)")
        }
    }

    private var showEditableWorkspaceError: Binding<Bool> {
        Binding(
            get: { editableWorkspaceError != nil },
            set: { newValue in
                if !newValue {
                    editableWorkspaceError = nil
                }
            }
        )
    }

    private func ensureEditablePortfolioPlanLoaded() {
        guard document.isEditablePlan else { return }
        if document.editablePlanSeed == nil,
           let existingPlan = editablePortfolioPlan {
            normalizeEditablePlanResources(existingPlan)
            editableWorkspaceError = nil
            return
        }
        _ = materializeEditableWorkspacePlan()
    }

    private func refreshEditableWorkspaceState() {
        sanitizePortfolioStoreData()
        ensureEditablePortfolioPlanLoaded()
        refreshEditableAnalysis()
    }

    private func handleDocumentModeTask() async {
        if !document.isEditablePlan {
            if selectedWorkspacePortfolioID == nil {
                selectedWorkspacePortfolioID = defaultWorkspacePortfolioID()
            }
        }
        await handleDocumentModeChange()
    }

    private func handleViewAppear() {
        refreshCachedFlaggedTaskIDs()
        scheduleSearchSuggestionsRefresh()
        if selectedWorkspacePortfolioID == nil {
            selectedWorkspacePortfolioID = defaultWorkspacePortfolioID()
        }
    }

    private func handleNavigationNotification(_ notification: Notification) {
        if let item = notification.object as? NavigationItem {
            selectedNav = item
        }
    }

    private var editableWorkspaceAlertText: Text {
        Text(editableWorkspaceError ?? "The editable workspace could not be prepared. Open in read-only mode or re-import the file.")
    }

    private func defaultWorkspacePortfolioID() -> UUID? {
        if let editableID = document.editablePortfolioID {
            return editableID
        }
        if let activePlanID = portfolioPlans.first(where: { !$0.isArchivedValue })?.portfolioID {
            return activePlanID
        }
        return portfolioPlans.first?.portfolioID
    }

    @ViewBuilder
    private var detailContent: some View {
        if !document.isEditablePlan && store.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Converting MPP file...")
                    .foregroundStyle(.secondary)
            }
        } else if !document.isEditablePlan, let error = store.error {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Failed to load project")
                    .font(.headline)
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        } else if selectedNav == .portfolio {
            PortfolioDashboardView(activePortfolioID: workspacePortfolioBinding)
        } else if document.isEditablePlan, displayProject == nil {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.3)
                Text("Preparing plan workspace...")
                    .foregroundStyle(.secondary)
            }
        } else if let project = displayProject {
            detailView(for: selectedNav, project: project, portfolioPlan: effectiveWorkspacePortfolioPlan)
        } else {
            Text("No project loaded")
                .foregroundStyle(.secondary)
        }
    }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            SidebarView(selection: $selectedNav, showsPlanner: document.isEditablePlan)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var searchableRootView: some View {
        rootSplitView
        .searchable(text: $searchText, prompt: "Search tasks, IDs, WBS, resources, notes, or custom fields")
    }

    private var toolbarConfiguredView: some View {
        searchableRootView
        .task(id: document.editablePortfolioID) {
            await Task.yield()
            refreshEditableWorkspaceState()
        }
        .onChange(of: effectiveWorkspacePortfolioPlan?.updatedAt) { _, _ in
            refreshEditableAnalysis()
            if document.isEditablePlan, let nativePlan = effectiveEditablePortfolioPlan?.asNativePlan() {
                archiveEditablePlan(nativePlan)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFocusMode()
                } label: {
                    Image(systemName: isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .tint(isFocusMode ? .orange : .accentColor)
                .help(isFocusMode ? "Exit focus mode and restore the sidebar." : "Enter focus mode and hide the sidebar.")
            }
        }
    }

    private var searchSuggestionsConfiguredView: some View {
        toolbarConfiguredView
        .searchSuggestions {
            ForEach(searchSuggestionTasks) { task in
                Button {
                    selectedNav = .tasks
                    navigateToTaskID = task.uniqueID
                    searchText = ""
                } label: {
                    HStack {
                        if task.milestone == true {
                            Image(systemName: "diamond.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if task.summary == true {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        VStack(alignment: .leading) {
                            Text(task.displayName)
                                .font(.caption)
                            if let wbs = task.wbs {
                                Text(wbs)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var lifecycleConfiguredView: some View {
        searchSuggestionsConfiguredView
        .onAppear(perform: handleViewAppear)
        .onChange(of: searchText) { _, _ in
            scheduleSearchSuggestionsRefresh()
        }
        .onChange(of: currentProject?.tasks.count ?? 0) { _, _ in
            scheduleSearchSuggestionsRefresh()
        }
        .onChange(of: flaggedTaskIDsData) { _, _ in
            refreshCachedFlaggedTaskIDs()
        }
        .navigationTitle(
            displayProject?.properties.projectTitle
            ?? currentProject?.properties.projectTitle
            ?? "MPP Viewer"
        )
        .task(id: document.isEditablePlan) {
            await handleDocumentModeTask()
        }
        .onChange(of: document.editablePlanData) { _, _ in
            ensureEditablePortfolioPlanLoaded()
            refreshEditableAnalysis()
        }
        .onChange(of: workspacePortfolioID) { _, newValue in
            if document.isEditablePlan {
                document.editablePortfolioID = newValue
            }
            if newValue != nil {
                refreshEditableAnalysis()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToItem), perform: handleNavigationNotification)
    }

    private var alertConfiguredView: some View {
        lifecycleConfiguredView
        .alert("Plan Edit Not Available", isPresented: showEditableWorkspaceError) {
            Button("OK", role: .cancel) {
                editableWorkspaceError = nil
            }
        } message: {
            editableWorkspaceAlertText
        }
    }

    var body: some View {
        alertConfiguredView
    }

    @ViewBuilder
    private func detailView(
        for item: NavigationItem?,
        project: ProjectModel,
        portfolioPlan: PortfolioProjectPlan?
    ) -> some View {
        switch item {
        case .portfolio:
            PortfolioDashboardView(activePortfolioID: workspacePortfolioBinding)
        case .dashboard:
            DashboardView(project: project)
        case .planner:
            if let portfolioPlan {
                PlanEditorView(planModel: portfolioPlan)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing editable workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Read-Only Import",
                    systemImage: "lock",
                    description: Text("Open or create a native plan document to edit tasks in the app.")
                )
            }
        case .agileBoard:
            if let portfolioPlan {
                AgileBoardView(
                    planModel: portfolioPlan,
                    isFocusMode: $isFocusMode,
                    splitViewVisibility: $splitViewVisibility
                )
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing agile board workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Read-Only Import",
                    systemImage: "lock",
                    description: Text("Open or create a native plan document to manage backlog, sprints, and agile workflow in the app.")
                )
            }
        case .statusCenter:
            if let portfolioPlan {
                StatusCenterView(planModel: portfolioPlan, project: project)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing status workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Read-Only Import",
                    systemImage: "lock",
                    description: Text("Open or create a native plan document to apply status updates in the app.")
                )
            }
        case .executive:
            ExecutiveModeView(project: project)
        case .summary:
            ProjectSummaryView(project: project)
        case .validation:
            ProjectValidationView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .diagnostics:
            ProjectDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .dependencyExplorer:
            DependencyGraphExplorerView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .resourceRisks:
            ResourceDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .criticalPath:
            CriticalPathView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .tasks:
            TaskTableView(
                tasks: project.rootTasks,
                allTasks: project.tasksByID,
                searchText: searchText,
                resources: project.resources,
                assignments: project.assignments,
                flaggedTaskIDs: flaggedTaskIDs,
                navigateToTaskID: $navigateToTaskID
            )
        case .gantt:
            GanttChartView(project: project, searchText: searchText, planModel: portfolioPlan)
        case .schedule:
            ScheduleView(project: project, searchText: searchText)
        case .milestones:
            MilestonesView(tasks: project.tasks, allTasks: project.tasksByID, searchText: searchText)
        case .resources:
            if let portfolioPlan {
                NativeResourcesEditorView(
                    planModel: portfolioPlan,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing resource workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSheetView(
                    resources: project.resources,
                    assignments: project.assignments,
                    calendars: project.calendars,
                    defaultCalendarID: project.properties.defaultCalendarUniqueId,
                    allTasks: project.tasksByID,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            }
        case .earnedValue:
            EarnedValueView(project: project)
        case .workload:
            WorkloadView(project: project)
        case .calendar:
            if let portfolioPlan {
                NativeCalendarEditorView(planModel: portfolioPlan)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing calendar workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarView(calendars: project.calendars)
            }
        case .timeline:
            TimelineView(project: project)
        case .diff:
            DiffView(project: project)
        case .helpCenter:
            AppGuideView(isEditablePlan: portfolioPlan != nil)
        case .none:
            Text("Select a view from the sidebar")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshEditableAnalysis() {
        let requestID = editableAnalysisGeneration + 1
        editableAnalysisGeneration = requestID

        let nativePlan: NativeProjectPlan?
        if document.isEditablePlan,
           workspacePortfolioID == document.editablePortfolioID,
           let documentPlan = document.nativePlan {
            nativePlan = documentPlan
        } else if let editablePortfolioPlan = effectiveWorkspacePortfolioPlan {
            nativePlan = editablePortfolioPlan.asNativePlan()
        } else {
            nativePlan = document.nativePlan
        }

        guard let nativePlan else {
            editableAnalysis = nil
            isRefreshingEditableAnalysis = false
            return
        }

        isRefreshingEditableAnalysis = true
        Task {
            let builtAnalysis = await NativePlanAnalysis.buildAsync(from: nativePlan)
            await MainActor.run {
                guard requestID == editableAnalysisGeneration else { return }
                editableAnalysis = builtAnalysis
                isRefreshingEditableAnalysis = false
            }
        }
    }

    @MainActor
    private func promoteImportedProjectToEditableIfNeeded() async {
        guard !document.isEditablePlan else { return }
        guard editablePortfolioPlan == nil else { return }
        guard let project = projectModelForEditablePromotion() else { return }

        let nativePlan = NativeProjectPlan(projectModel: project)
        do {
            try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: modelContext)
            archiveEditablePlan(nativePlan)
            refreshEditableAnalysis()
            if shouldOpenPlannerForCurrentSelection() {
                selectedNav = .planner
            }
        } catch {
            assertionFailure("Failed to promote imported MPP to editable plan: \(error)")
        }
    }

    private func projectModelForEditablePromotion() -> ProjectModel? {
        if let project = editableAnalysis?.project {
            return project
        }
        if let project = store.project {
            return project
        }
        return document.nativePlan?.asProjectModel()
    }

    private func shouldOpenPlannerForCurrentSelection() -> Bool {
        switch selectedNav {
        case .none, .dashboard:
            return true
        default:
            return false
        }
    }

    private func shouldOpenDashboardForCurrentSelection() -> Bool {
        switch selectedNav {
        case .none, .planner:
            return true
        default:
            return false
        }
    }

    private func handleDocumentModeChange() async {
        if document.isEditablePlan {
            store.reset()
            refreshEditableAnalysis()
            await promoteImportedProjectToEditableIfNeeded()
            if shouldOpenPlannerForCurrentSelection() {
                selectedNav = .planner
            }
            return
        }

        editableAnalysis = nil
        let currentDocument = document
        await store.loadFromDocument(currentDocument)
        await promoteImportedProjectToEditableIfNeeded()

        if document.isEditablePlan {
            return
        }

        if shouldOpenDashboardForCurrentSelection() {
            selectedNav = .dashboard
        }
    }

    private func refreshCachedFlaggedTaskIDs() {
        cachedFlaggedTaskIDs = (try? JSONDecoder().decode(Set<Int>.self, from: flaggedTaskIDsData)) ?? []
    }

    private func toggleFocusMode() {
        let nextValue = !isFocusMode
        isFocusMode = nextValue
        splitViewVisibility = nextValue ? .detailOnly : .all
    }
}

struct ResourceDiagnosticsView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?
    @State private var cachedItems: [ResourceDiagnosticItem]

    private var items: [ResourceDiagnosticItem] {
        cachedItems
    }

    init(project: ProjectModel, navigateToTaskID: Binding<Int?>, selectedNav: Binding<NavigationItem?>) {
        self.project = project
        self._navigateToTaskID = navigateToTaskID
        self._selectedNav = selectedNav
        self._cachedItems = State(initialValue: ResourceDiagnostics.analyze(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Resource Risks")
                    .font(.headline)
                Text("(\(items.count) issues)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    riskChip(count: items.filter { $0.severity == .error }.count, label: "Errors", color: .red)
                    riskChip(count: items.filter { $0.severity == .warning }.count, label: "Warnings", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Resource Risks",
                    systemImage: "person.crop.circle.badge.checkmark",
                    description: Text("No resource over-allocation risks were detected by the current diagnostics.")
                )
            } else {
                Table(items) {
                    TableColumn("Alert") { item in
                        SeverityBadge(severity: item.severity)
                    }
                    .width(min: 90, ideal: 110, max: 130)

                    TableColumn("Resource") { item in
                        Text(item.resourceName)
                    }
                    .width(min: 180, ideal: 220)

                    TableColumn("Issue") { item in
                        Text(item.title)
                    }
                    .width(min: 150, ideal: 190)

                    TableColumn("Task") { item in
                        if let taskName = item.taskName, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName).lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(item.taskName ?? "")
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { item in
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 300, ideal: 520)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            cachedItems = ResourceDiagnostics.analyze(project: project)
        }
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func riskChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProjectDiagnosticsView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?
    @State private var cachedItems: [ProjectDiagnosticItem]

    private var items: [ProjectDiagnosticItem] {
        cachedItems
    }

    init(project: ProjectModel, navigateToTaskID: Binding<Int?>, selectedNav: Binding<NavigationItem?>) {
        self.project = project
        self._navigateToTaskID = navigateToTaskID
        self._selectedNav = selectedNav
        self._cachedItems = State(initialValue: ProjectDiagnostics.analyze(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Text("(\(items.count) signals)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    diagnosticChip(count: items.filter { $0.category == .constraints }.count, label: "Constraints", color: .orange)
                    diagnosticChip(count: items.filter { $0.category == .dependencies }.count, label: "Dependencies", color: .blue)
                    diagnosticChip(count: items.filter { $0.category == .flow }.count, label: "Flow", color: .purple)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "No Diagnostics",
                    systemImage: "stethoscope",
                    description: Text("No dependency or constraint hotspots were detected by the current diagnostics.")
                )
            } else {
                Table(items) {
                    TableColumn("Category") { item in
                        Label(item.category.label, systemImage: item.category.icon)
                            .foregroundStyle(item.category.color)
                    }
                    .width(min: 100, ideal: 120, max: 140)

                    TableColumn("Signal") { item in
                        Text(item.title)
                    }
                    .width(min: 170, ideal: 220)

                    TableColumn("Task ID") { item in
                        if let taskID = item.taskID, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskID).monospacedDigit()
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("")
                        }
                    }
                    .width(min: 50, ideal: 70, max: 90)

                    TableColumn("Task") { item in
                        if let taskName = item.taskName, let taskUniqueID = item.taskUniqueID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName).lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(item.taskName ?? "Project")
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { item in
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 320, ideal: 520)
                }
            }
        }
        .onAppear {
            cachedItems = ProjectDiagnostics.analyze(project: project)
        }
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func diagnosticChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProjectValidationView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    @State private var selectedSeverity: ValidationSeverityFilter = .all
    @State private var sortOrder = [KeyPathComparator(\ProjectValidationIssue.sortSeverityRank, order: .reverse)]
    @State private var cachedAllIssues: [ProjectValidationIssue]

    private var issues: [ProjectValidationIssue] {
        let filtered: [ProjectValidationIssue]
        switch selectedSeverity {
        case .all:
            filtered = cachedAllIssues
        case .errors:
            filtered = cachedAllIssues.filter { $0.severity == .error }
        case .warnings:
            filtered = cachedAllIssues.filter { $0.severity == .warning }
        case .info:
            filtered = cachedAllIssues.filter { $0.severity == .info }
        }
        return filtered.sorted(using: sortOrder)
    }

    init(project: ProjectModel, navigateToTaskID: Binding<Int?>, selectedNav: Binding<NavigationItem?>) {
        self.project = project
        self._navigateToTaskID = navigateToTaskID
        self._selectedNav = selectedNav
        self._cachedAllIssues = State(initialValue: ProjectValidator.validate(project: project))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Validation Report")
                    .font(.headline)
                Text("(\(issues.count) issues)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    validationChip(count: issues.filter { $0.severity == .error }.count, label: "Errors", color: .red)
                    validationChip(count: issues.filter { $0.severity == .warning }.count, label: "Warnings", color: .orange)
                    validationChip(count: issues.filter { $0.severity == .info }.count, label: "Info", color: .blue)
                }

                Divider().frame(height: 16)

                Button {
                    exportValidationReport()
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Picker("Severity", selection: $selectedSeverity) {
                    ForEach(ValidationSeverityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if issues.isEmpty {
                ContentUnavailableView(
                    "No Validation Issues",
                    systemImage: "checkmark.shield",
                    description: Text("The imported project passed the current validation checks.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Table(issues, sortOrder: $sortOrder) {
                    TableColumn("Severity", value: \.sortSeverityRank) { issue in
                        Label(issue.severity.label, systemImage: issue.severity.icon)
                            .foregroundStyle(issue.severity.color)
                    }
                    .width(min: 90, ideal: 110, max: 130)

                    TableColumn("Rule", value: \.rule) { issue in
                        Text(issue.rule)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Task ID") { issue in
                        if let taskUniqueID = issue.taskUniqueID, let taskID = issue.taskID {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskID)
                                    .monospacedDigit()
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(issue.taskID ?? "")
                                .monospacedDigit()
                        }
                    }
                    .width(min: 50, ideal: 70, max: 90)

                    TableColumn("Task") { issue in
                        if let taskUniqueID = issue.taskUniqueID, let taskName = issue.taskName {
                            Button {
                                openTask(taskUniqueID)
                            } label: {
                                Text(taskName)
                                    .lineLimit(2)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(issue.taskName ?? "Project")
                                .lineLimit(2)
                        }
                    }
                    .width(min: 180, ideal: 260)

                    TableColumn("Details") { issue in
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .width(min: 300, ideal: 520)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            cachedAllIssues = ProjectValidator.validate(project: project)
        }
    }

    private func validationChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func openTask(_ uniqueID: Int) {
        selectedNav = .tasks
        navigateToTaskID = uniqueID
    }

    private func exportValidationReport() {
        let formatter = ISO8601DateFormatter()
        let fileName = "Validation Report \(PDFExporter.fileNameTimestamp).csv"
        let header = ["severity", "rule", "task_id", "task_name", "message", "created_at"].joined(separator: ",")
        let rows = issues.map { issue in
            [
                csv(issue.severity.label),
                csv(issue.rule),
                csv(issue.taskID ?? ""),
                csv(issue.taskName ?? "Project"),
                csv(issue.message),
                csv(formatter.string(from: Date()))
            ].joined(separator: ",")
        }
        let csvData = ([header] + rows).joined(separator: "\n")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csvData.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func csv(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum ValidationSeverity: Int, Comparable {
    case info = 1
    case warning = 2
    case error = 3

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

}

enum ValidationSeverityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errors = "Errors"
    case warnings = "Warnings"
    case info = "Info"

    var id: String { rawValue }
}

struct ProjectValidationIssue: Identifiable {
    let id = UUID()
    let severity: ValidationSeverity
    let rule: String
    let taskUniqueID: Int?
    let taskID: String?
    let taskName: String?
    let message: String

    var sortSeverityRank: Int {
        severity.rawValue
    }
}

enum ProjectValidator {
    static func validate(project: ProjectModel) -> [ProjectValidationIssue] {
        var issues: [ProjectValidationIssue] = []
        let taskAssignments = Dictionary(grouping: project.assignments, by: { $0.taskUniqueID ?? -1 })

        for task in project.tasks {
            if task.summary == true && task.milestone == true {
                issues.append(issue(
                    .warning,
                    rule: "Summary Marked As Milestone",
                    task: task,
                    "Task is flagged as both summary and milestone in the source data."
                ))
            }

            if task.milestone == true && !task.isDisplayMilestone {
                issues.append(issue(
                    .warning,
                    rule: "Suspicious Milestone",
                    task: task,
                    "Task has a raw milestone flag but behaves like a duration task instead of a zero-duration checkpoint."
                ))
            }

            if let start = task.startDate, let finish = task.finishDate, finish < start {
                issues.append(issue(
                    .error,
                    rule: "Finish Before Start",
                    task: task,
                    "Finish date is earlier than start date."
                ))
            }

            if task.summary != true && (task.startDate == nil || task.finishDate == nil) {
                issues.append(issue(
                    .warning,
                    rule: "Missing Schedule Dates",
                    task: task,
                    "Non-summary task is missing a start date, finish date, or both."
                ))
            }

            if let percent = task.percentComplete, percent > 0, task.actualStart == nil {
                issues.append(issue(
                    .info,
                    rule: "Progress Without Actual Start",
                    task: task,
                    "Task has progress recorded but no actual start date."
                ))
            }

            if let percent = task.percentComplete, percent >= 100, task.actualFinish == nil {
                issues.append(issue(
                    .info,
                    rule: "Completed Without Actual Finish",
                    task: task,
                    "Task is marked complete but no actual finish date is present."
                ))
            }

            if task.active == false, (taskAssignments[task.uniqueID]?.isEmpty == false) {
                issues.append(issue(
                    .warning,
                    rule: "Inactive Task With Assignments",
                    task: task,
                    "Task is inactive but still has assigned resources."
                ))
            }

            for relation in task.predecessors ?? [] {
                if project.tasksByID[relation.targetTaskUniqueID] == nil {
                    issues.append(issue(
                        .error,
                        rule: "Missing Predecessor Target",
                        task: task,
                        "Predecessor references missing task unique ID \(relation.targetTaskUniqueID)."
                    ))
                }
            }

            for relation in task.successors ?? [] {
                if project.tasksByID[relation.targetTaskUniqueID] == nil {
                    issues.append(issue(
                        .error,
                        rule: "Missing Successor Target",
                        task: task,
                        "Successor references missing task unique ID \(relation.targetTaskUniqueID)."
                    ))
                }
            }
        }

        if project.tasks.isEmpty {
            issues.append(ProjectValidationIssue(
                severity: .error,
                rule: "Empty Project",
                taskUniqueID: nil,
                taskID: nil,
                taskName: nil,
                message: "The parsed project contains no tasks."
            ))
        }

        return issues
    }

    private static func issue(
        _ severity: ValidationSeverity,
        rule: String,
        task: ProjectTask,
        _ message: String
    ) -> ProjectValidationIssue {
        ProjectValidationIssue(
            severity: severity,
            rule: rule,
            taskUniqueID: task.uniqueID,
            taskID: task.id.map(String.init) ?? task.outlineNumber,
            taskName: task.displayName,
            message: message
        )
    }
}

enum DiagnosticCategory {
    case constraints
    case dependencies
    case flow

    var label: String {
        switch self {
        case .constraints: return "Constraint"
        case .dependencies: return "Dependency"
        case .flow: return "Flow"
        }
    }

    var icon: String {
        switch self {
        case .constraints: return "lock.fill"
        case .dependencies: return "link"
        case .flow: return "arrow.triangle.branch"
        }
    }

    var color: Color {
        switch self {
        case .constraints: return .orange
        case .dependencies: return .blue
        case .flow: return .purple
        }
    }
}

struct ProjectDiagnosticItem: Identifiable {
    let id = UUID()
    let category: DiagnosticCategory
    let title: String
    let taskUniqueID: Int?
    let taskID: String?
    let taskName: String?
    let message: String
}

enum ProjectDiagnostics {
    static func analyze(project: ProjectModel) -> [ProjectDiagnosticItem] {
        var items: [ProjectDiagnosticItem] = []
        let calendar = Calendar.current

        for task in project.tasks {
            if let constraint = normalizedConstraint(task.constraintType) {
                items.append(item(
                    category: .constraints,
                    title: "Explicit Constraint",
                    task: task,
                        message: "Task uses constraint `\(constraint)` which can reduce scheduling flexibility."
                    ))

                if let constraintDate = task.constraintDate.flatMap(DateFormatting.parseMPXJDate) {
                    let comparisonDate: Date? = {
                        let lowered = constraint.lowercased()
                        if lowered.contains("start") { return task.startDate }
                        if lowered.contains("finish") { return task.finishDate }
                        return task.startDate ?? task.finishDate
                    }()

                    if let comparisonDate {
                        let drift = abs(calendar.dateComponents([.day], from: comparisonDate, to: constraintDate).day ?? 0)
                        if drift >= 2 {
                            items.append(item(
                                category: .constraints,
                                title: "Constraint Date Drift",
                                task: task,
                                message: "Constraint date \(DateFormatting.shortDate(constraintDate)) differs from scheduled date \(DateFormatting.shortDate(comparisonDate)) by \(drift) days."
                            ))
                        }
                    }
                } else {
                    items.append(item(
                        category: .constraints,
                        title: "Constraint Missing Date",
                        task: task,
                        message: "Task has explicit constraint `\(constraint)` but no constraint date is present."
                    ))
                }
            }

            let predecessorCount = task.predecessors?.count ?? 0
            let successorCount = task.successors?.count ?? 0
            let totalLinks = predecessorCount + successorCount
            if totalLinks >= 6 {
                items.append(item(
                    category: .dependencies,
                    title: "Dependency-Heavy Task",
                    task: task,
                    message: "Task has \(predecessorCount) predecessors and \(successorCount) successors."
                ))
            }

            if successorCount >= 5 {
                items.append(item(
                    category: .dependencies,
                    title: "Successor Fan-Out",
                    task: task,
                    message: "Task drives \(successorCount) successor links and may act as a delivery bottleneck."
                ))
            }

            for relation in task.predecessors ?? [] {
                let lag = relation.lag ?? 0
                if abs(lag) >= 16 * 3600 {
                    items.append(item(
                        category: .dependencies,
                        title: lag > 0 ? "Long Lag Dependency" : "Lead Dependency",
                        task: task,
                        message: "Predecessor link \(relation.type ?? "FS") uses \(DurationFormatting.formatSeconds(abs(lag))) \(lag > 0 ? "lag" : "lead")."
                    ))
                }

                if let predecessor = project.tasksByID[relation.targetTaskUniqueID],
                   let predecessorFinish = predecessor.finishDate,
                   let taskStart = task.startDate,
                   predecessorFinish > taskStart,
                   relation.type == nil || relation.type == "FS" {
                    let overlapDays = calendar.dateComponents([.day], from: taskStart, to: predecessorFinish).day ?? 0
                    if overlapDays >= 1 {
                        items.append(item(
                            category: .dependencies,
                            title: "Predecessor Finish After Start",
                            task: task,
                            message: "FS predecessor `\(predecessor.displayName)` finishes \(overlapDays) days after this task starts."
                        ))
                    }
                }
            }

            if task.critical == true,
               (task.predecessors?.isEmpty != false),
               (task.successors?.isEmpty != false),
               task.summary != true {
                items.append(item(
                    category: .flow,
                    title: "Isolated Critical Task",
                    task: task,
                    message: "Critical task has no linked predecessors or successors."
                ))
            }

            if task.summary != true,
               let percent = task.percentComplete,
               percent == 0,
               let predecessorCount = task.predecessors?.count,
               predecessorCount >= 3 {
                items.append(item(
                    category: .flow,
                    title: "Blocked Start Risk",
                    task: task,
                    message: "Not-started task depends on \(predecessorCount) predecessors."
                ))
            }

            if task.critical == true, predecessorCount >= 2, successorCount >= 2 {
                items.append(item(
                    category: .flow,
                    title: "Critical Chain Hub",
                    task: task,
                    message: "Critical task sits in a dense chain with \(predecessorCount) predecessors and \(successorCount) successors."
                ))
            }
        }

        return items
    }

    private static func normalizedConstraint(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.lowercased()
        if lowered == "as soon as possible" || lowered == "as late as possible" || lowered == "asap" || lowered == "alap" {
            return nil
        }
        return normalized
    }

    private static func item(
        category: DiagnosticCategory,
        title: String,
        task: ProjectTask,
        message: String
    ) -> ProjectDiagnosticItem {
        ProjectDiagnosticItem(
            category: category,
            title: title,
            taskUniqueID: task.uniqueID,
            taskID: task.id.map(String.init) ?? task.outlineNumber,
            taskName: task.displayName,
            message: message
        )
    }
}

struct ResourceDiagnosticItem: Identifiable {
    let id = UUID()
    let severity: ValidationSeverity
    let resourceName: String
    let title: String
    let taskUniqueID: Int?
    let taskName: String?
    let message: String
}

enum ResourceDiagnostics {
    static func analyze(project: ProjectModel) -> [ResourceDiagnosticItem] {
        let calendar = Calendar.current
        var items: [ResourceDiagnosticItem] = []
        let resources = project.resources.filter { $0.type?.lowercased() == "work" || $0.type == nil }

        for resource in resources {
            guard let resourceID = resource.uniqueID else { continue }
            let resourceAssignments = project.assignments.filter { $0.resourceUniqueID == resourceID }
            let maxUnits = resource.maxUnits ?? 100

            for assignment in resourceAssignments {
                if let units = assignment.assignmentUnits, units > maxUnits + 0.1 {
                    let start = assignmentDate(assignment.start) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.startDate
                    let finish = assignmentDate(assignment.finish) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.finishDate
                    let rangeText = dateRangeText(start: start, finish: finish)
                    items.append(item(
                        severity: .warning,
                        resource: resource,
                        title: "Assignment Exceeds Max Units",
                        task: project.tasksByID[assignment.taskUniqueID ?? -1],
                        message: "Assignment uses \(Int(units))% against resource max units of \(Int(maxUnits))%\(rangeText.isEmpty ? "" : " during \(rangeText)")."
                    ))
                }
            }

            let intervals = resourceAssignments.compactMap { assignment -> ResourceInterval? in
                guard let start = assignmentDate(assignment.start) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.startDate,
                      let finish = assignmentDate(assignment.finish) ?? project.tasksByID[assignment.taskUniqueID ?? -1]?.finishDate
                else { return nil }
                let startDay = calendar.startOfDay(for: start)
                let finishDay = calendar.startOfDay(for: finish)
                return ResourceInterval(
                    taskUniqueID: assignment.taskUniqueID,
                    start: min(startDay, finishDay),
                    finish: max(startDay, finishDay),
                    units: assignment.assignmentUnits ?? 100
                )
            }

            guard !intervals.isEmpty else { continue }

            var peakUnits: Double = 0
            var peakDay: Date?
            var overallocatedDays: [Date: Double] = [:]
            for interval in intervals {
                var day = interval.start
                while day <= interval.finish {
                    let totalUnits = intervals
                        .filter { $0.start <= day && $0.finish >= day }
                        .reduce(0.0) { $0 + $1.units }
                    if totalUnits > maxUnits + 0.1 {
                        overallocatedDays[day] = totalUnits
                    }
                    if totalUnits > peakUnits {
                        peakUnits = totalUnits
                        peakDay = day
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }

            if peakUnits > maxUnits + 0.1, let peakDay {
                let peakAssignments = intervals
                    .filter { $0.start <= peakDay && $0.finish >= peakDay }
                    .compactMap { interval in project.tasksByID[interval.taskUniqueID ?? -1]?.displayName }
                    .prefix(3)
                    .joined(separator: ", ")
                let overloadRange = contiguousRange(from: overallocatedDays.keys.sorted())
                let overloadRangeText = overloadRange.map { "\(DateFormatting.shortDate($0.start)) to \(DateFormatting.shortDate($0.finish))" } ?? DateFormatting.shortDate(peakDay)

                items.append(item(
                    severity: peakUnits >= maxUnits * 1.5 ? .error : .warning,
                    resource: resource,
                    title: "Overallocated Resource",
                    task: nil,
                    message: "Peak allocation reaches \(Int(peakUnits))% within overload window \(overloadRangeText). Top overlapping tasks near the peak: \(peakAssignments)."
                ))

                if let overloadRange {
                    let durationDays = calendar.dateComponents([.day], from: overloadRange.start, to: overloadRange.finish).day ?? 0
                    if durationDays >= 4 {
                        items.append(item(
                            severity: .warning,
                            resource: resource,
                            title: "Sustained Overload Window",
                            task: nil,
                            message: "Resource stays overallocated for \(durationDays + 1) consecutive days from \(DateFormatting.shortDate(overloadRange.start)) to \(DateFormatting.shortDate(overloadRange.finish))."
                        ))
                    }
                }
            }
        }

        return items
    }

    private static func assignmentDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateFormatting.parseMPXJDate(value)
    }

    private static func dateRangeText(start: Date?, finish: Date?) -> String {
        guard let start, let finish else { return "" }
        return "\(DateFormatting.shortDate(start)) to \(DateFormatting.shortDate(finish))"
    }

    private static func contiguousRange(from days: [Date]) -> (start: Date, finish: Date)? {
        guard let first = days.first else { return nil }
        let calendar = Calendar.current
        var bestStart = first
        var bestFinish = first
        var currentStart = first
        var currentFinish = first

        for day in days.dropFirst() {
            let delta = calendar.dateComponents([.day], from: currentFinish, to: day).day ?? 0
            if delta == 1 {
                currentFinish = day
            } else {
                if spanDays(calendar, currentStart, currentFinish) > spanDays(calendar, bestStart, bestFinish) {
                    bestStart = currentStart
                    bestFinish = currentFinish
                }
                currentStart = day
                currentFinish = day
            }
        }

        if spanDays(calendar, currentStart, currentFinish) > spanDays(calendar, bestStart, bestFinish) {
            bestStart = currentStart
            bestFinish = currentFinish
        }

        return (bestStart, bestFinish)
    }

    private static func spanDays(_ calendar: Calendar, _ start: Date, _ finish: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: finish).day ?? 0
    }

    private static func item(
        severity: ValidationSeverity,
        resource: ProjectResource,
        title: String,
        task: ProjectTask?,
        message: String
    ) -> ResourceDiagnosticItem {
        ResourceDiagnosticItem(
            severity: severity,
            resourceName: resource.name ?? "Resource \(resource.uniqueID ?? 0)",
            title: title,
            taskUniqueID: task?.uniqueID,
            taskName: task?.displayName,
            message: message
        )
    }
}

private struct SeverityBadge: View {
    let severity: ValidationSeverity

    var body: some View {
        Label(severity.label, systemImage: severity.icon)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(severity.color.opacity(0.18))
            )
            .foregroundStyle(severity.color)
    }
}

private struct ResourceInterval {
    let taskUniqueID: Int?
    let start: Date
    let finish: Date
    let units: Double
}

struct CriticalPathView: View {
    let project: ProjectModel
    @Binding var navigateToTaskID: Int?
    @Binding var selectedNav: NavigationItem?

    private var criticalTasks: [ProjectTask] {
        project.tasks
            .filter { $0.summary != true && $0.critical == true }
            .sorted {
                ($0.startDate ?? .distantFuture, $0.id ?? .max) < ($1.startDate ?? .distantFuture, $1.id ?? .max)
            }
    }

    private var nearCriticalTasks: [ProjectTask] {
        project.tasks
            .filter {
                $0.summary != true &&
                $0.critical != true &&
                (($0.totalSlack ?? $0.freeSlack ?? Int.max) <= 16 * 3600)
            }
            .sorted { ($0.totalSlack ?? $0.freeSlack ?? Int.max) < ($1.totalSlack ?? $1.freeSlack ?? Int.max) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Critical Path")
                    .font(.headline)
                Spacer()
                summaryChip("\(criticalTasks.count) critical", color: .red)
                if !nearCriticalTasks.isEmpty {
                    summaryChip("\(nearCriticalTasks.count) near-critical", color: .orange)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Driving Tasks") {
                        if criticalTasks.isEmpty {
                            Text("No critical tasks were flagged in the imported data.")
                                .foregroundStyle(.secondary)
                                .padding(4)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(criticalTasks) { task in
                                    criticalRow(task, highlight: .red)
                                    if task.uniqueID != criticalTasks.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }

                    GroupBox("Near-Critical / Float Watch") {
                        if nearCriticalTasks.isEmpty {
                            Text("No near-critical tasks with low float/slack were found in the imported data.")
                                .foregroundStyle(.secondary)
                                .padding(4)
                        } else {
                            let nearCriticalList = Array(nearCriticalTasks.prefix(25))
                            LazyVStack(spacing: 8) {
                                ForEach(nearCriticalList) { task in
                                    criticalRow(task, highlight: .orange)
                                    if task.uniqueID != nearCriticalList.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func criticalRow(_ task: ProjectTask, highlight: Color) -> some View {
        Button {
            selectedNav = .tasks
            navigateToTaskID = task.uniqueID
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(highlight)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(task.id.map(String.init) ?? "\(task.uniqueID)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(task.displayName)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 12) {
                        meta("Start", DateFormatting.shortDate(task.start))
                        meta("Finish", DateFormatting.shortDate(task.finish))
                        meta("Total Float", task.totalSlackDisplay ?? "N/A")
                        meta("Free Float", task.freeSlackDisplay ?? "N/A")
                        meta("Progress", task.percentCompleteDisplay)
                    }

                    if let preds = task.predecessors, !preds.isEmpty {
                        Text("Predecessors: \(preds.compactMap { project.tasksByID[$0.targetTaskUniqueID]?.id.map(String.init) ?? "\($0.targetTaskUniqueID)" }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "N/A" : value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

private func summaryChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct StatusCenterView: View {
    @Environment(\.modelContext) private var modelContext

    let planModel: PortfolioProjectPlan
    let project: ProjectModel

    @State private var derivedContent: StatusCenterDerivedContent
    @State private var selectedTaskID: Int?
    @State private var filter: StatusTaskFilter = .attention
    @State private var searchText = ""

    private var workTasks: [ProjectTask] {
        derivedContent.workTasks
    }

    private var statusMetrics: EVMMetrics {
        derivedContent.statusMetrics
    }

    private var overdueCount: Int {
        derivedContent.overdueCount
    }

    private var inProgressCount: Int {
        derivedContent.inProgressCount
    }

    private var missingActualCount: Int {
        derivedContent.missingActualCount
    }

    private var filteredTasks: [ProjectTask] {
        derivedContent.filteredTasks
    }

    private var selectedProjectTask: ProjectTask? {
        guard let selectedTaskID else { return nil }
        return project.tasksByID[selectedTaskID]
    }

    private var nativeAssignments: [NativePlanAssignment] {
        planModel.nativeAssignmentsForUI
    }

    private var nativeResources: [NativePlanResource] {
        planModel.nativeResourcesForUI
    }

    private var nativeStatusSnapshots: [NativeStatusSnapshot] {
        planModel.nativeStatusSnapshotsForUI
    }

    private var currentStatusDate: Date {
        planModel.statusDate
    }

    private var selectedAssignments: [NativePlanAssignment] {
        guard let selectedTaskID else { return [] }
        return nativeAssignments
            .filter { $0.taskID == selectedTaskID }
            .sorted { $0.id < $1.id }
    }

    private var topScheduleSlips: [ProjectTask] {
        derivedContent.topScheduleSlips
    }

    private var topCostOverruns: [ProjectTask] {
        derivedContent.topCostOverruns
    }

    private var topOvertimeDrivers: [StatusOvertimeDriver] {
        derivedContent.topOvertimeDrivers
    }

    init(planModel: PortfolioProjectPlan, project: ProjectModel) {
        self.planModel = planModel
        self.project = project
        self._derivedContent = State(
            initialValue: StatusCenterDerivedContent.build(
                project: project,
                assignments: planModel.nativeAssignmentsForUI,
                resources: planModel.nativeResourcesForUI,
                statusDate: planModel.statusDate,
                snapshots: planModel.nativeStatusSnapshotsForUI,
                filter: .attention,
                searchText: ""
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider()
            metricsStrip
            Divider()

            HStack(spacing: 0) {
                taskListPane
                    .frame(minWidth: 420, idealWidth: 540, maxWidth: 680)

                Divider()

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            refreshDerivedContent()
            if selectedTaskID == nil {
                selectedTaskID = filteredTasks.first?.uniqueID ?? workTasks.first?.uniqueID
            }
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: planModel.tasks.map(\.legacyID)) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                return
            }

            if let selectedTaskID, ids.contains(selectedTaskID) {
                return
            }

            selectedTaskID = ids.first
        }
        .onChange(of: filter) { _, _ in
            refreshDerivedContent()
            if let selectedTaskID, filteredTasks.contains(where: { $0.uniqueID == selectedTaskID }) {
                return
            }
            selectedTaskID = filteredTasks.first?.uniqueID
        }
        .onChange(of: searchText) { _, _ in
            refreshDerivedContent()
            if let selectedTaskID, filteredTasks.contains(where: { $0.uniqueID == selectedTaskID }) {
                return
            }
            selectedTaskID = filteredTasks.first?.uniqueID
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func persistStatusStoreChanges(refreshMetrics: Bool = true) {
        planModel.updatedAt = Date()
        if refreshMetrics {
            planModel.refreshPortfolioMetrics()
        }
        try? modelContext.save()
        refreshDerivedContent()
    }

    private func withStatusTask(_ taskID: Int, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return }
        update(task)
        persistStatusStoreChanges()
    }

    private func withStatusAssignment(_ assignmentID: Int, _ update: (PortfolioPlanAssignment) -> Void) {
        guard let assignment = planModel.tasks
            .flatMap(\.assignments)
            .first(where: { $0.legacyID == assignmentID }) else { return }
        update(assignment)
        persistStatusStoreChanges()
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Status Center")
                    .font(.title2.weight(.semibold))
                Text("Update actuals, variance, and earned value as of the current status date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(StatusTaskFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            TextField("Search Tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            DatePicker("Status Date", selection: statusDateBinding, displayedComponents: .date)
                .labelsHidden()
                .help("Sets the control date used by earned value and variance calculations.")

            Button("Today") {
                statusDateBinding.wrappedValue = Calendar.current.startOfDay(for: Date())
            }
            .help("Move the status date to today.")

            Button("Apply Status Defaults") {
                applyStatusDefaults()
            }
            .help("Fill missing actual dates for tasks that have already started or finished by the current status date.")

            Button("Capture Snapshot") {
                captureStatusSnapshot()
            }
            .help("Save the current status date, EVM state, and sprint position as a reporting-period snapshot.")

            FinancialTermsButton()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var metricsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                statusMetricCard(title: "In Progress", value: "\(inProgressCount)", tone: .blue)
                statusMetricCard(title: "Overdue", value: "\(overdueCount)", tone: overdueCount > 0 ? .red : .secondary)
                statusMetricCard(title: "Missing Actuals", value: "\(missingActualCount)", tone: missingActualCount > 0 ? .orange : .secondary)
                statusMetricCard(title: "BAC", value: currencyText(statusMetrics.bac), tone: .primary)
                statusMetricCard(title: "AC", value: currencyText(statusMetrics.ac), tone: .primary)
                statusMetricCard(title: "CPI", value: ratioText(statusMetrics.cpi), tone: statusMetrics.cpi >= 1 ? .green : .orange)
                statusMetricCard(title: "SPI", value: ratioText(statusMetrics.spi), tone: statusMetrics.spi >= 1 ? .green : .orange)
                statusMetricCard(title: "EAC", value: currencyText(statusMetrics.eac), tone: .primary)
                statusMetricCard(title: "VAC", value: currencyText(statusMetrics.vac), tone: statusMetrics.vac >= 0 ? .green : .red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var taskListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Task Status")
                    .font(.headline)
                Text("(\(filteredTasks.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 0) {
                listHeader("Task", width: 220, alignment: .leading)
                listHeader("%", width: 48)
                listHeader("Actual Start", width: 94)
                listHeader("Actual Finish", width: 94)
                listHeader("Cost Δ", width: 82)
                listHeader("Slip", width: 62)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.thinMaterial)

            Divider()

            List(selection: $selectedTaskID) {
                ForEach(filteredTasks, id: \.uniqueID) { task in
                    Button {
                        selectStatusTask(task.uniqueID)
                    } label: {
                        HStack(spacing: 0) {
                            taskCell(task: task)
                            numericCell(task.percentComplete.map { "\(Int($0))%" } ?? "0%", width: 48)
                            numericCell(task.actualStart.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualStart == nil && (task.percentComplete ?? 0) > 0 ? .orange : .secondary)
                            numericCell(task.actualFinish.map(DateFormatting.shortDate) ?? "Missing", width: 94, tint: task.actualFinish == nil && task.isCompleted ? .orange : .secondary)
                            numericCell(costVarianceText(for: task), width: 82, tint: costVarianceColor(for: task))
                            numericCell(slipText(for: task), width: 62, tint: slipColor(for: task))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tag(task.uniqueID)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            .listStyle(.plain)
        }
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let task = selectedProjectTask {
                    taskStatusEditor(task: task)
                    assignmentStatusEditor(task: task)
                } else {
                    Text("Select a task from the left to update status, actuals, and progress.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top)
                }

                varianceDashboard
                snapshotHistoryPanel
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func taskStatusEditor(task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.displayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        if let wbs = task.wbs {
                            Text(wbs)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }

                        statusBadge(for: task)
                    }
                }

                Spacer()
            }

            GroupBox("Task Update") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: actualStartBinding(for: task.uniqueID), displayedComponents: .date)
                                .labelsHidden()
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualStart(for: task.uniqueID, to: task.startDate ?? currentStatusDate)
                                }
                                Button("Clear") {
                                    setActualStart(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Finish")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: actualFinishBinding(for: task.uniqueID), displayedComponents: .date)
                                .labelsHidden()
                            HStack(spacing: 8) {
                                Button("Use Scheduled") {
                                    setActualFinish(for: task.uniqueID, to: task.finishDate ?? currentStatusDate)
                                }
                                Button("Clear") {
                                    setActualFinish(for: task.uniqueID, to: nil)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("% Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0", text: percentCompleteBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 84)
                            Text("Statused progress")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Actual Cost")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            StableDecimalTextField(title: "0", text: actualCostBinding(for: task.uniqueID))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text("Override only if needed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Status Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: notesBinding(for: task.uniqueID))
                            .font(.body)
                            .frame(minHeight: 72)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Variance Snapshot") {
                VStack(alignment: .leading, spacing: 8) {
                    statusFactRow(label: "Baseline", value: baselineRangeText(for: task))
                    statusFactRow(label: "Current", value: currentRangeText(for: task))
                    statusFactRow(label: "Planned Value", value: currencyText(task.bcws ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).pv))
                    statusFactRow(label: "Earned Value", value: currencyText(task.bcwp ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).ev))
                    statusFactRow(label: "Actual Cost", value: currencyText(task.acwp ?? EVMCalculator.compute(for: task, statusDate: currentStatusDate).ac))
                    statusFactRow(label: "Cost Variance", value: costVarianceText(for: task), tint: costVarianceColor(for: task))
                    statusFactRow(label: "Schedule Variance", value: currencyText(EVMCalculator.compute(for: task, statusDate: currentStatusDate).sv), tint: EVMCalculator.compute(for: task, statusDate: currentStatusDate).sv >= 0 ? .green : .red)
                }
                .padding(.top, 4)
            }
        }
    }

    private func assignmentStatusEditor(task: ProjectTask) -> some View {
        GroupBox("Assignment Updates") {
            VStack(alignment: .leading, spacing: 10) {
                if selectedAssignments.isEmpty {
                    Text("No assignments on this task yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedAssignments) { assignment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(resourceName(for: assignment))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Units \(Int(assignment.units))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                assignmentField(title: "Actual (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.actualWorkSeconds))
                                assignmentField(title: "Remaining (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.remainingWorkSeconds))
                                assignmentField(title: "OT (h)", text: assignmentHoursBinding(for: assignment.id, keyPath: \.overtimeWorkSeconds))
                                Spacer()
                                Text(assignmentCostSummary(for: assignment))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var varianceDashboard: some View {
        GroupBox("Control Radar") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Schedule Slips")
                        .font(.headline)
                    if topScheduleSlips.isEmpty {
                        Text("No slipped tasks against the current baseline.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topScheduleSlips, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: slipText(for: task),
                                tint: .red,
                                action: { selectStatusTask(task.uniqueID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Cost Overruns")
                        .font(.headline)
                    if topCostOverruns.isEmpty {
                        Text("No tasks are exceeding baseline cost.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topCostOverruns, id: \.uniqueID) { task in
                            radarRow(
                                title: task.displayName,
                                detail: costVarianceText(for: task),
                                tint: .orange,
                                action: { selectStatusTask(task.uniqueID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overtime Drivers")
                        .font(.headline)
                    if topOvertimeDrivers.isEmpty {
                        Text("No explicit overtime has been statused yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(topOvertimeDrivers.enumerated()), id: \.offset) { _, item in
                            radarRow(
                                title: resourceName(for: item.assignment),
                                detail: hoursText(item.assignment.overtimeWorkSeconds),
                                tint: .purple,
                                action: { selectStatusTask(item.assignment.taskID) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 4)
        }
    }

    private var snapshotHistoryPanel: some View {
        GroupBox("Status History") {
            VStack(alignment: .leading, spacing: 10) {
                if nativeStatusSnapshots.isEmpty {
                    Text("No status snapshots captured yet. Use `Capture Snapshot` to save reporting periods for trend and sprint review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(derivedContent.sortedSnapshots.prefix(8), id: \.id) { snapshot in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snapshot.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Status Date \(DateFormatting.simpleDate(snapshot.statusDate))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Use Date") {
                                    statusDateBinding.wrappedValue = snapshot.statusDate
                                }
                                .buttonStyle(.borderless)
                            }

                            HStack(spacing: 18) {
                                snapshotMetric("BAC", currencyText(snapshot.bac))
                                snapshotMetric("EV", currencyText(snapshot.ev))
                                snapshotMetric("AC", currencyText(snapshot.ac))
                                snapshotMetric("CPI", ratioText(snapshot.cpi))
                                snapshotMetric("SPI", ratioText(snapshot.spi))
                                snapshotMetric("VAC", currencyText(snapshot.vac))
                            }

                            if !snapshot.sprintSnapshots.isEmpty {
                                Text(snapshot.sprintSnapshots.map { "\($0.sprintName): \($0.completedPoints)/\($0.committedPoints) pts" }.joined(separator: "   "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !snapshot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(snapshot.notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func radarRow(title: String, detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func refreshDerivedContent() {
        PerformanceMonitor.measure("StatusCenter.RefreshDerived") {
            derivedContent = StatusCenterDerivedContent.build(
                project: project,
                assignments: nativeAssignments,
                resources: nativeResources,
                statusDate: currentStatusDate,
                snapshots: nativeStatusSnapshots,
                filter: filter,
                searchText: searchText
            )
        }
    }

    private func selectStatusTask(_ taskID: Int?) {
        guard let taskID else { return }
        PerformanceMonitor.mark("StatusCenter.SelectTask", message: "task \(taskID)")
        selectedTaskID = taskID
    }

    private func listHeader(_ title: String, width: CGFloat, alignment: Alignment = .center) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func taskCell(task: ProjectTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(taskStatusColor(for: task))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let wbs = task.wbs {
                        Text(wbs)
                    }
                    Text(statusText(for: task))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
    }

    private func numericCell(_ value: String, width: CGFloat, tint: Color = .secondary) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: width)
    }

    private func statusMetricCard(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(tone)
        }
        .frame(width: 108, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func statusBadge(for task: ProjectTask) -> some View {
        Text(statusText(for: task))
            .font(.caption.weight(.semibold))
            .foregroundStyle(taskStatusColor(for: task))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(taskStatusColor(for: task).opacity(0.14))
            )
    }

    private func statusFactRow(label: String, value: String, tint: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
        }
        .font(.callout)
    }

    private func assignmentField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
        }
    }

    private var statusDateBinding: Binding<Date> {
        Binding(
            get: { planModel.statusDate },
            set: { newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                guard planModel.statusDate != normalized else { return }
                planModel.statusDate = normalized
                persistStatusStoreChanges()
            }
        )
    }

    private func captureStatusSnapshot() {
        PerformanceMonitor.measure("StatusCenter.CaptureSnapshot") {
            var snapshotPlan = planModel.asNativePlan()
            snapshotPlan.captureStatusSnapshot()
            planModel.update(from: snapshotPlan)
            persistStatusStoreChanges(refreshMetrics: true)
        }
    }

    private func percentCompleteBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return "\(Int(task.percentComplete.rounded()))"
            },
            set: { newValue in
                let parsed = Double(newValue.filter { $0.isNumber || $0 == "." }) ?? 0
                withStatusTask(taskID) { task in
                    task.percentComplete = min(max(parsed, 0), 100)
                    if task.percentComplete > 0, task.actualStartDate == nil {
                        task.actualStartDate = min(task.startDate, planModel.statusDate)
                    }
                    if task.percentComplete >= 100, task.actualFinishDate == nil {
                        task.actualFinishDate = min(task.finishDate, planModel.statusDate)
                    }
                }
            }
        )
    }

    private func actualCostBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return task.actualCost.map(decimalText) ?? ""
            },
            set: { newValue in
                withStatusTask(taskID) { task in
                    task.actualCost = parseDecimalInput(newValue)
                }
            }
        )
    }

    private func notesBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return "" }
                return task.notes
            },
            set: { newValue in
                withStatusTask(taskID) { task in
                    task.notes = newValue
                }
            }
        )
    }

    private func actualStartBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return planModel.statusDate }
                return task.actualStartDate ?? task.startDate
            },
            set: { newValue in
                setActualStart(for: taskID, to: newValue)
            }
        )
    }

    private func actualFinishBinding(for taskID: Int) -> Binding<Date> {
        Binding(
            get: {
                guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return planModel.statusDate }
                return task.actualFinishDate ?? task.finishDate
            },
            set: { newValue in
                setActualFinish(for: taskID, to: newValue)
            }
        )
    }

    private func assignmentHoursBinding(for assignmentID: Int, keyPath: WritableKeyPath<NativePlanAssignment, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard let assignment = planModel.tasks
                    .flatMap(\.assignments)
                    .first(where: { $0.legacyID == assignmentID }) else { return "" }
                let native = assignment.asNativeAssignment(taskLegacyID: assignment.taskLegacyID)
                return hoursText(native[keyPath: keyPath])
            },
            set: { newValue in
                withStatusAssignment(assignmentID) { assignment in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let seconds: Int?
                    if trimmed.isEmpty {
                        seconds = nil
                    } else if let value = Double(trimmed) {
                        seconds = max(0, Int(value * 3600))
                    } else {
                        seconds = nil
                    }
                    switch keyPath {
                    case \NativePlanAssignment.actualWorkSeconds:
                        assignment.actualWorkSeconds = seconds
                    case \NativePlanAssignment.remainingWorkSeconds:
                        assignment.remainingWorkSeconds = seconds
                    default:
                        assignment.overtimeWorkSeconds = seconds
                    }
                }
            }
        )
    }

    private func setActualStart(for taskID: Int, to date: Date?) {
        PerformanceMonitor.measure("StatusCenter.SetActualStart") {
            let normalized = date.map { Calendar.current.startOfDay(for: $0) }
            withStatusTask(taskID) { task in
                task.actualStartDate = normalized
                if let normalized, let finish = task.actualFinishDate, finish < normalized {
                    task.actualFinishDate = normalized
                }
            }
        }
    }

    private func setActualFinish(for taskID: Int, to date: Date?) {
        PerformanceMonitor.measure("StatusCenter.SetActualFinish") {
            let normalized = date.map { Calendar.current.startOfDay(for: $0) }
            withStatusTask(taskID) { task in
                if let normalized, let start = task.actualStartDate, normalized < start {
                    task.actualFinishDate = start
                } else {
                    task.actualFinishDate = normalized
                }
                if task.actualFinishDate != nil, task.percentComplete < 100 {
                    task.percentComplete = 100
                }
            }
        }
    }

    private func applyStatusDefaults() {
        PerformanceMonitor.measure("StatusCenter.ApplyDefaults") {
            let statusDate = Calendar.current.startOfDay(for: planModel.statusDate)
            var didChange = false
            for task in planModel.tasks {
                if task.percentComplete > 0, task.actualStartDate == nil {
                    task.actualStartDate = min(task.startDate, statusDate)
                    didChange = true
                }

                if task.percentComplete >= 100, task.actualFinishDate == nil {
                    task.actualFinishDate = min(task.finishDate, statusDate)
                    didChange = true
                }

                if let actualStart = task.actualStartDate, actualStart > statusDate {
                    task.actualStartDate = statusDate
                    didChange = true
                }

                if let actualFinish = task.actualFinishDate, actualFinish > statusDate {
                    task.actualFinishDate = statusDate
                    didChange = true
                }
            }

            guard didChange else { return }
            persistStatusStoreChanges()
        }
    }

    private func taskStatusNeedsAttention(_ task: ProjectTask) -> Bool {
        isOverdue(task)
            || task.finishVarianceDays ?? 0 > 0
            || costVarianceValue(for: task) > 0
            || ((task.percentComplete ?? 0) > 0 && task.actualStart == nil)
            || (task.isCompleted && task.actualFinish == nil)
    }

    private func costVarianceValue(for task: ProjectTask) -> Double {
        (task.actualCost ?? 0) - (task.baselineCost ?? task.cost ?? 0)
    }

    private func costVarianceText(for task: ProjectTask) -> String {
        let variance = costVarianceValue(for: task)
        guard variance != 0 else { return "On plan" }
        return currencyText(variance)
    }

    private func costVarianceColor(for task: ProjectTask) -> Color {
        let variance = costVarianceValue(for: task)
        if variance > 0 { return .red }
        if variance < 0 { return .green }
        return .secondary
    }

    private func slipText(for task: ProjectTask) -> String {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days == 0 { return "On time" }
        return "\(days > 0 ? "+" : "")\(days)d"
    }

    private func slipColor(for task: ProjectTask) -> Color {
        let days = task.finishVarianceDays ?? task.startVarianceDays ?? 0
        if days > 0 { return .red }
        if days < 0 { return .green }
        return .secondary
    }

    private func baselineRangeText(for task: ProjectTask) -> String {
        let start = task.baselineStartDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.baselineFinishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func currentRangeText(for task: ProjectTask) -> String {
        let start = task.startDate.map(DateFormatting.simpleDate) ?? "?"
        let finish = task.finishDate.map(DateFormatting.simpleDate) ?? "?"
        return "\(start) -> \(finish)"
    }

    private func statusText(for task: ProjectTask) -> String {
        if task.isCompleted { return "Complete" }
        if isOverdue(task) { return "Overdue" }
        if task.isInProgress { return "In Progress" }
        return "Not Started"
    }

    private func taskStatusColor(for task: ProjectTask) -> Color {
        if task.isCompleted { return .green }
        if isOverdue(task) { return .red }
        if task.isInProgress { return .blue }
        return .secondary
    }

    private func isOverdue(_ task: ProjectTask) -> Bool {
        guard !task.isCompleted, let finishDate = task.finishDate else { return false }
        return finishDate < planModel.statusDate
    }

    private func resourceName(for assignment: NativePlanAssignment) -> String {
        if let resourceID = assignment.resourceID {
            if let name = planModel.resources.first(where: { $0.legacyID == resourceID })?.name,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return "Unassigned"
    }

    private func assignmentCostSummary(for assignment: NativePlanAssignment) -> String {
        guard let projectAssignment = project.assignments.first(where: { $0.uniqueID == assignment.id }) else {
            return "No rolled cost"
        }
        return projectAssignment.cost.map(currencyText) ?? "No rolled cost"
    }

    private func hoursText(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = Double(seconds) / 3600
        return abs(hours.rounded() - hours) < 0.01 ? "\(Int(hours.rounded()))" : String(format: "%.1f", hours)
    }

    private func decimalText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func parseDecimalInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized)
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(
            from: value,
            currencyCode: project.properties.currencyCode ?? "USD",
            currencySymbol: project.properties.currencySymbol ?? "$",
            maximumFractionDigits: 0,
            minimumFractionDigits: 0
        )
    }

    private func ratioText(_ value: Double) -> String {
        value == 0 ? "0.00" : String(format: "%.2f", value)
    }

    private func snapshotMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

enum StatusTaskFilter: String, CaseIterable, Identifiable {
    case attention = "Needs Attention"
    case all = "All"
    case inProgress = "In Progress"
    case overdue = "Overdue"
    case missingActuals = "Missing Actuals"

    var id: String { rawValue }
}

private enum AgileBoardTab: String, CaseIterable, Identifiable {
    case board = "Board"
    case sprints = "Sprint Planner"
    case reports = "Reports"

    var id: String { rawValue }
}

private enum AgileBoardSprintScope: Hashable {
    case all
    case backlogOnly
    case sprint(Int)
}

private enum AgileBoardSwimlaneMode: String, CaseIterable, Identifiable {
    case none = "None"
    case sprint = "Sprint"
    case epic = "Epic"
    case parent = "Parent"
    case assignee = "Assignee"
    case team = "Team"

    var id: String { rawValue }
}

private struct AgileBoardTaskRefreshSignature: Equatable {
    let id: Int
    let name: String
    let agileType: String
    let boardStatus: String
    let sprintID: Int?
    let storyPoints: Int?
    let percentComplete: Double
    let epicName: String
    let outlineLevel: Int
}

private struct AgileBoardAssignmentRefreshSignature: Equatable {
    let taskID: Int
    let resourceID: Int?
}

private struct AgileBoardResourceRefreshSignature: Equatable {
    let id: Int
    let name: String
    let group: String
}

private struct AgileBoardRefreshSignature: Equatable {
    let boardColumns: [String]
    let tasks: [AgileBoardTaskRefreshSignature]
    let assignments: [AgileBoardAssignmentRefreshSignature]
    let resources: [AgileBoardResourceRefreshSignature]
    let sprintIDs: [Int]
    let sprintNames: [String]
    let snapshotIDs: [UUID]
}

private enum AgileWorkflowDesignerScope: Hashable, Identifiable {
    case shared
    case itemType(String)

    var id: String {
        switch self {
        case .shared:
            return "shared"
        case .itemType(let itemType):
            return "type-\(itemType.lowercased())"
        }
    }

    var title: String {
        switch self {
        case .shared:
            return "Shared Workflow"
        case .itemType(let itemType):
            return itemType
        }
    }
}

struct AgileBoardView: View {
    @Environment(\.modelContext) private var modelContext

    let planModel: PortfolioProjectPlan
    @Binding var isFocusMode: Bool
    @Binding var splitViewVisibility: NavigationSplitViewVisibility

    @State private var derivedContent: AgileBoardDerivedContent
    @State private var derivedRefreshWorkItem: DispatchWorkItem?
    @State private var selectedTab: AgileBoardTab = .board
    @State private var selectedTaskID: Int?
    @State private var selectedSprintID: Int?
    @State private var boardSprintScope: AgileBoardSprintScope = .all
    @State private var boardSwimlaneMode: AgileBoardSwimlaneMode = .none
    @State private var inspectorTaskDraft: NativePlanTask?
    @State private var inspectorTaskDraftWorkItem: DispatchWorkItem?
    @State private var inspectorTaskDraftIsDirty = false
    @State private var backlogSectionExpanded = true
    @State private var sprintScopeSectionExpanded = true
    @State private var showsInspector = false
    @State private var isPresentingAddBucketSheet = false
    @State private var newBucketName = ""
    @State private var draggingTaskID: Int?
    @State private var dropTargetLane: String?
    @State private var dropTargetParentGroupKey: String?
    @State private var showsDetailedBoardCards = true
    @State private var collapsedSwimlaneKeys: Set<String> = []
    @State private var boardInteractionMessage: String?
    @State private var boardInteractionMessageWorkItem: DispatchWorkItem?
    @State private var isPresentingWorkflowDesigner = false
    @State private var workflowDraft: [NativeBoardWorkflowColumn] = []
    @State private var workflowDesignerScope: AgileWorkflowDesignerScope = .shared

    private let workflowItemTypes = ["Epic", "Feature", "Story", "Bug", "Task", "Milestone"]

    private var agileTasks: [NativePlanTask] {
        derivedContent.agileTasks
    }

    private var backlogTasks: [NativePlanTask] {
        derivedContent.backlogTasks
    }

    private var boardColumns: [String] {
        derivedContent.boardColumns
    }

    private var nativeTasks: [NativePlanTask] {
        planModel.nativeTasksForUI
    }

    private var nativeAssignments: [NativePlanAssignment] {
        planModel.nativeAssignmentsForUI
    }

    private var nativeResources: [NativePlanResource] {
        planModel.nativeResourcesForUI
    }

    private var nativeSprints: [NativePlanSprint] {
        planModel.nativeSprintsForUI
    }

    private var nativeStatusSnapshots: [NativeStatusSnapshot] {
        planModel.nativeStatusSnapshotsForUI
    }

    private var workflowColumns: [NativeBoardWorkflowColumn] {
        if planModel.workflowColumns.isEmpty {
            return NativeProjectPlan.defaultWorkflowColumns(for: boardColumns)
        }
        return NativeProjectPlan.synchronizedWorkflowColumns(
            boardColumns: boardColumns,
            workflowColumns: planModel.nativeWorkflowColumnsForUI
        )
    }

    private var typeWorkflowOverrides: [NativeBoardTypeWorkflow] {
        NativeProjectPlan.synchronizedTypeWorkflowOverrides(
            boardColumns: boardColumns,
            overrides: planModel.nativeTypeWorkflowOverridesForUI
        )
    }

    private var refreshSignature: AgileBoardRefreshSignature {
        AgileBoardRefreshSignature(
            boardColumns: planModel.boardColumns,
            tasks: nativeTasks.map {
                AgileBoardTaskRefreshSignature(
                    id: $0.id,
                    name: $0.name,
                    agileType: $0.agileType,
                    boardStatus: $0.boardStatus,
                    sprintID: $0.sprintID,
                    storyPoints: $0.storyPoints,
                    percentComplete: $0.percentComplete,
                    epicName: $0.epicName,
                    outlineLevel: $0.outlineLevel
                )
            },
            assignments: nativeAssignments.map {
                AgileBoardAssignmentRefreshSignature(taskID: $0.taskID, resourceID: $0.resourceID)
            },
            resources: nativeResources.map {
                AgileBoardResourceRefreshSignature(id: $0.id, name: $0.name, group: $0.group)
            },
            sprintIDs: nativeSprints.map(\.id),
            sprintNames: nativeSprints.map(\.name),
            snapshotIDs: nativeStatusSnapshots.map(\.id)
        )
    }

    private var tasksByLane: [AgileLaneTasks] {
        derivedContent.tasksByLane
    }

    private var filteredTasksByLane: [AgileLaneTasks] {
        tasksByLane.map { laneGroup in
            AgileLaneTasks(
                lane: laneGroup.lane,
                tasks: filterTasksForBoardScope(laneGroup.tasks),
                id: laneGroup.id
            )
        }
    }

    private var selectedSprintTasks: [NativePlanTask] {
        guard let selectedSprintID else { return [] }
        return agileTasks
            .filter { $0.sprintID == selectedSprintID }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.id < rhs.id
                }
                return lhs.startDate < rhs.startDate
            }
    }

    private var boardSprintScopeTitle: String {
        switch boardSprintScope {
        case .all:
            return "All Work"
        case .backlogOnly:
            return "Backlog Only"
        case .sprint(let sprintID):
            return nativeSprints.first(where: { $0.id == sprintID })?.name ?? "Sprint"
        }
    }

    private var boardSwimlaneTitle: String {
        switch boardSwimlaneMode {
        case .none:
            return "No Swimlanes"
        case .sprint:
            return "By Sprint"
        case .epic:
            return "By Epic"
        case .parent:
            return "By Parent"
        case .assignee:
            return "By Assignee"
        case .team:
            return "By Team"
        }
    }

    private var latestSnapshot: NativeStatusSnapshot? {
        derivedContent.latestSnapshot
    }

    init(
        planModel: PortfolioProjectPlan,
        isFocusMode: Binding<Bool>,
        splitViewVisibility: Binding<NavigationSplitViewVisibility>
    ) {
        self.planModel = planModel
        self._isFocusMode = isFocusMode
        self._splitViewVisibility = splitViewVisibility
        self._derivedContent = State(
            initialValue: AgileBoardDerivedContent.build(
                tasks: planModel.nativeTasksForUI,
                assignments: planModel.nativeAssignmentsForUI,
                resources: planModel.nativeResourcesForUI,
                sprints: planModel.nativeSprintsForUI,
                boardColumns: planModel.boardColumns,
                workflowColumns: planModel.nativeWorkflowColumnsForUI,
                typeWorkflowOverrides: planModel.nativeTypeWorkflowOverridesForUI,
                statusSnapshots: planModel.nativeStatusSnapshotsForUI
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFocusMode {
                header
                Divider()
            }

            Group {
                switch selectedTab {
                case .board:
                    boardView
                case .sprints:
                    sprintPlannerView
                case .reports:
                    reportsView
                }
            }
        }
        .onAppear {
            showsInspector = false
            refreshDerivedContent()
            if selectedTaskID == nil {
                selectedTaskID = agileTasks.first?.id
            }
            if selectedSprintID == nil {
                selectedSprintID = nativeSprints.first?.id
            }
            syncAgileInspectorDraft(force: true)
        }
        .onChange(of: planModel.tasks.map(\.legacyID)) { _, ids in
            guard let selectedTaskID else {
                self.selectedTaskID = ids.first
                syncAgileInspectorDraft(force: true)
                return
            }
            if !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.first
            }
            syncAgileInspectorDraft(force: true)
        }
        .onChange(of: planModel.sprints.map(\.legacyID)) { _, ids in
            guard let selectedSprintID else {
                self.selectedSprintID = ids.first
                if case .sprint = boardSprintScope, let firstID = ids.first {
                    boardSprintScope = .sprint(firstID)
                } else if ids.isEmpty, case .sprint = boardSprintScope {
                    boardSprintScope = .all
                }
                return
            }
            if !ids.contains(selectedSprintID) {
                self.selectedSprintID = ids.first
            }
            if case .sprint(let sprintID) = boardSprintScope, !ids.contains(sprintID) {
                boardSprintScope = .all
            }
        }
        .onChange(of: boardSwimlaneMode) { _, mode in
            if mode == .parent {
                collapsedSwimlaneKeys.removeAll()
            }
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshDerivedContent()
            syncAgileInspectorDraft(force: true)
        }
        .onChange(of: refreshSignature) { _, _ in
            scheduleDerivedContentRefresh()
            syncAgileInspectorDraft()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue != .board, isFocusMode else { return }
            toggleFocusMode()
        }
        .onChange(of: selectedTaskID) { _, _ in
            commitAgileInspectorDraft()
            syncAgileInspectorDraft(force: true)
        }
        .onAppear {
            showsInspector = false
            if selectedTab != .board, isFocusMode {
                toggleFocusMode()
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func persistAgileStoreChanges(refreshMetrics: Bool = true) {
        planModel.updatedAt = Date()
        if refreshMetrics {
            planModel.refreshPortfolioMetrics()
        }
        try? modelContext.save()
    }

    private func withAgileTask(_ taskID: Int, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return }
        update(task)
        persistAgileStoreChanges()
        refreshDerivedContent()
    }

    private func withAgileSprint(_ sprintID: Int, _ update: (PortfolioPlanSprint) -> Void) {
        guard let sprint = planModel.sprints.first(where: { $0.legacyID == sprintID }) else { return }
        update(sprint)
        persistAgileStoreChanges()
        refreshDerivedContent()
    }

    private func fullSyncAgilePlan(_ update: (inout NativeProjectPlan) -> Void) {
        var snapshot = planModel.asNativePlan()
        update(&snapshot)
        planModel.update(from: snapshot)
        persistAgileStoreChanges(refreshMetrics: true)
        refreshDerivedContent()
        syncAgileInspectorDraft(force: true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agile Board")
                        .font(.title2.weight(.semibold))
                    Text("Hybrid backlog, sprint planning, and delivery flow on top of the same native schedule, resources, and finance model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let boardInteractionMessage, !boardInteractionMessage.isEmpty {
                        Label(boardInteractionMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 18)

                Picker("View", selection: $selectedTab) {
                    ForEach(AgileBoardTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
            }

            HStack(spacing: 10) {
                agileHeaderMetric(title: "Backlog", value: "\(backlogTasks.count)", tone: .secondary)
                agileHeaderMetric(title: "Sprints", value: "\(nativeSprints.count)", tone: .blue)
                agileHeaderMetric(title: "Points", value: "\(derivedContent.totalStoryPoints)", tone: .primary)
                agileHeaderMetric(title: "Done", value: "\(derivedContent.doneCount)", tone: .green)
                agileHeaderMetric(title: "Ready", value: "\(derivedContent.readyCount)", tone: .blue)
                agileHeaderMetric(title: "In Progress", value: "\(derivedContent.inProgressCount)", tone: .orange)
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Button {
                        addStory()
                    } label: {
                        Label("Add Story", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        addSprint()
                    } label: {
                        Label("Add Sprint", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                    .frame(height: 26)

                if selectedTab == .board {
                    boardCommandBar
                } else if selectedTab == .sprints {
                    sprintCommandBar
                } else {
                    reportsCommandBar
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .padding(18)
        .sheet(isPresented: $isPresentingAddBucketSheet) {
            addBucketSheet
        }
        .sheet(isPresented: $isPresentingWorkflowDesigner) {
            workflowDesignerSheet
        }
    }

    private var boardCommandBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All Work") {
                    boardSprintScope = .all
                }
                Button("Backlog Only") {
                    boardSprintScope = .backlogOnly
                }
                if !nativeSprints.isEmpty {
                    Divider()
                    ForEach(nativeSprints) { sprint in
                        Button(sprint.name) {
                            boardSprintScope = .sprint(sprint.id)
                        }
                    }
                }
            } label: {
                headerControlLabel(title: "Scope", value: boardSprintScopeTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.plain)
            .help("Focus the board on all work, backlog-only items, or a single sprint.")

            Menu {
                ForEach(AgileBoardSwimlaneMode.allCases) { mode in
                    Button(mode.rawValue) {
                        boardSwimlaneMode = mode
                    }
                }
            } label: {
                headerControlLabel(title: "Swimlanes", value: boardSwimlaneTitle, systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.plain)
            .help("Group the board by sprint, epic, or parent work item.")

            if boardSwimlaneMode != .none {
                Button("Expand All") {
                    collapsedSwimlaneKeys.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Collapse All") {
                    collapsedSwimlaneKeys = Set(filteredTasksByLane.flatMap { laneGroup in
                        swimlaneGroups(for: laneGroup.tasks, lane: laneGroup.lane).map(\.key)
                    })
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                newBucketName = ""
                isPresentingAddBucketSheet = true
            } label: {
                Label("Add Bucket", systemImage: "rectangle.badge.plus")
            }
            .buttonStyle(.bordered)

            Button {
                workflowDesignerScope = .shared
                workflowDraft = workflowColumns
                isPresentingWorkflowDesigner = true
            } label: {
                Label("Workflow", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            Button {
                showsInspector.toggle()
            } label: {
                Label(showsInspector ? "Hide Details" : "Show Details", systemImage: "sidebar.right")
            }
            .buttonStyle(.bordered)

            Toggle("Detailed Cards", isOn: $showsDetailedBoardCards)
                .toggleStyle(.switch)
                .fixedSize()
        }
    }

    private var sprintCommandBar: some View {
        HStack(spacing: 10) {
            headerStatusPill(
                title: selectedSprintID.flatMap { id in nativeSprints.first(where: { $0.id == id })?.name } ?? "No Sprint Selected",
                subtitle: selectedSprintID == nil ? "Choose a sprint to inspect capacity and timeline." : "Sprint capacity, scope, and timeline."
            )
        }
    }

    private var reportsCommandBar: some View {
        HStack(spacing: 10) {
            headerStatusPill(
                title: latestSnapshot?.name ?? "No Snapshots Yet",
                subtitle: latestSnapshot.map { "Latest reporting period: \(DateFormatting.simpleDate($0.statusDate))" } ?? "Capture snapshots in Status Center to unlock trend reporting."
            )
        }
    }

    private var boardView: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(filteredTasksByLane) { laneGroup in
                        laneColumn(laneGroup.lane, tasks: laneGroup.tasks)
                    }
                }
                .padding()
            }
            .transaction { transaction in
                transaction.animation = nil
            }

            if showsInspector {
                Divider()

                agileInspector
                    .frame(width: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var addBucketSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Bucket")
                .font(.title3.weight(.semibold))
            Text("Create a new board column for custom workflow stages.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Bucket Name", text: $newBucketName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresentingAddBucketSheet = false
                }
                Button("Add") {
                    createBucket()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var workflowDesignerSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Workflow Designer")
                .font(.title3.weight(.semibold))
            Text("Edit the shared board workflow or switch to a specific item type to override its allowed moves. Bucket order is still controlled from the board itself.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("Scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu {
                    Button("Shared Workflow") {
                        updateWorkflowDesignerScope(.shared)
                    }
                    Divider()
                    ForEach(workflowItemTypes, id: \.self) { itemType in
                        Button(itemType) {
                            updateWorkflowDesignerScope(.itemType(itemType))
                        }
                    }
                } label: {
                    Label(workflowDesignerScope.title, systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)

                Spacer()

                if case .itemType(let itemType) = workflowDesignerScope,
                   hasTypeWorkflowOverride(for: itemType) {
                    Button("Use Shared Rules") {
                        resetTypeWorkflowOverride(itemType: itemType)
                    }
                    .buttonStyle(.bordered)
                    .help("Remove the override for this item type and fall back to the shared workflow.")
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(workflowDraft.indices), id: \.self) { index in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .bottom, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Bucket")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if workflowDesignerAllowsRename {
                                            TextField("Column Name", text: workflowDraftNameBinding(index))
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            Text(workflowDraft[index].name)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color(nsColor: .controlBackgroundColor))
                                                )
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("WIP Limit")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("None", text: workflowDraftWIPTextBinding(index))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 76)
                                    }

                                    Spacer()
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Allowed Moves")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                                        ForEach(Array(workflowDraft.enumerated()), id: \.offset) { targetIndex, targetColumn in
                                            if targetIndex != index {
                                                Toggle(
                                                    targetColumn.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Bucket" : targetColumn.name,
                                                    isOn: workflowTransitionBinding(index, targetIndex: targetIndex)
                                                )
                                                .toggleStyle(.checkbox)
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(workflowDraft[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Bucket \(index + 1)" : workflowDraft[index].name)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresentingWorkflowDesigner = false
                }
                Button("Save Workflow") {
                    saveWorkflowDesigner()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }

    private func laneColumn(_ lane: String, tasks laneTasks: [NativePlanTask]) -> some View {
        let tint = laneColor(for: lane)
        let laneIndex = boardColumns.firstIndex(of: lane)
        let activeTaskCount = laneTasks.filter { ($0.percentComplete < 100) && normalizedBoardStatus(for: $0).compare("Done", options: .caseInsensitive) != .orderedSame }.count
        let laneWIP = wipLimit(for: lane)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane)
                        .font(.headline)
                    Text(laneWIP.map { "\(activeTaskCount) / \($0) active" } ?? "\(laneTasks.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                HStack(spacing: 4) {
                    Button {
                        moveBucket(lane, direction: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(laneIndex == nil || laneIndex == 0)
                    .help("Move this bucket left.")

                    Button {
                        moveBucket(lane, direction: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(laneIndex == nil || laneIndex == boardColumns.count - 1)
                    .help("Move this bucket right.")

                    Button(role: .destructive) {
                        deleteBucket(lane)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(boardColumns.count <= 1)
                    .help("Delete this bucket and move its tasks to a neighboring lane.")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(swimlaneGroups(for: laneTasks, lane: lane)) { group in
                        swimlaneGroupView(group, tint: tint)
                    }
                }
            }
        }
        .frame(width: 250, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(dropTargetLane == lane ? tint.opacity(0.72) : draggingTaskID != nil ? tint.opacity(0.22) : .clear, lineWidth: dropTargetLane == lane ? 2 : 1)
        }
        .onDrop(of: [UTType.plainText], delegate: AgileBoardDropDelegate(
            lane: lane,
            draggingTaskID: $draggingTaskID,
            dropTargetLane: $dropTargetLane,
            moveTask: moveTaskToLane(taskID:lane:)
        ))
    }

    private func swimlaneGroupView(_ group: AgileSwimlaneGroup, tint: Color) -> some View {
        let isCollapsed = collapsedSwimlaneKeys.contains(group.key)
        let rootTask = parentRootTask(for: group)
        let childTasks = childTasks(for: group)

        return VStack(alignment: .leading, spacing: 8) {
            if boardSwimlaneMode != .none {
                Button {
                    toggleSwimlaneGroup(group.key)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: isCollapsed ? "chevron.right.circle.fill" : "chevron.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tint.opacity(0.9))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(groupHeaderTitle(for: group))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(groupHeaderSubtitle(for: group))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Text(groupCountText(for: group))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(tint.opacity(0.14)))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(boardSwimlaneMode == .parent ? tint.opacity(0.10) : Color.primary.opacity(0.04))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(boardSwimlaneMode == .parent ? tint.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help(isCollapsed ? "Expand this group to show its child cards." : "Collapse this group.")
            }

            if !isCollapsed {
                if boardSwimlaneMode == .parent, let rootTask {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Parent", systemImage: "arrow.triangle.branch")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(tint.opacity(0.95))
                            Spacer()
                            if childTasks.isEmpty {
                                Text("No children")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        boardTaskCard(rootTask, tint: tint)

                        if !childTasks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Children")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(childTasks) { task in
                                    boardTaskCard(task, tint: tint)
                                        .padding(.leading, groupHierarchyIndent(for: task, in: group))
                                }
                            }
                            .padding(.leading, 10)
                        }
                    }
                } else {
                    ForEach(group.tasks) { task in
                        boardTaskCard(task, tint: tint)
                            .padding(.leading, hierarchyIndent(for: task))
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(boardSwimlaneMode == .none ? 0 : 0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    dropTargetParentGroupKey == group.key ? tint.opacity(0.75) : .clear,
                    lineWidth: 2
                )
        }
        .onDrop(
            of: boardSwimlaneMode == .parent ? [UTType.plainText] : [],
            delegate: AgileParentGroupDropDelegate(
                groupKey: group.key,
                parentTaskID: group.parentTaskID,
                lane: group.lane,
                draggingTaskID: $draggingTaskID,
                dropTargetParentGroupKey: $dropTargetParentGroupKey,
                reparentTask: reparentTask(taskID:parentTaskID:lane:)
            )
        )
    }

    private func boardTaskCard(_ task: NativePlanTask, tint: Color) -> some View {
        let epicName = task.epicName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDone = task.percentComplete >= 100 || task.boardStatus == "Done"
        let isOverdue = !isDone && task.finishDate < planModel.statusDate

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(task.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let points = task.storyPoints {
                    Text("\(points) pt")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.16)))
                }
            }

            if !epicName.isEmpty {
                Text(epicName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                miniChip(task.agileType, tint: .secondary)
                if let sprintID = task.sprintID, let sprintName = derivedContent.sprintNamesByID[sprintID] {
                    miniChip(sprintName, tint: .blue)
                } else {
                    miniChip("Backlog", tint: .secondary)
                }
                if isOverdue {
                    miniChip("Overdue", tint: .red)
                } else if isDone {
                    miniChip("Done", tint: .green)
                }
            }

            if showsDetailedBoardCards {
                HStack(alignment: .center, spacing: 8) {
                    Label(boardTaskDateSummary(task), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let assignmentSummary = boardTaskAssignmentSummary(task) {
                        Label(assignmentSummary, systemImage: "person.2")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let parentName = derivedContent.parentTaskNameByTaskID[task.id], !parentName.isEmpty {
                    Label(parentName, systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !task.tags.isEmpty {
                Text(task.tags.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selectedTaskID == task.id ? tint.opacity(0.95) : Color.primary.opacity(0.08),
                    lineWidth: selectedTaskID == task.id ? 2 : 1
                )
        }
        .shadow(color: Color.black.opacity(selectedTaskID == task.id ? 0.08 : 0.03), radius: selectedTaskID == task.id ? 8 : 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            selectBoardTask(task.id)
        }
        .onDrag {
            draggingTaskID = task.id
            return NSItemProvider(object: String(task.id) as NSString)
        }
            .contextMenu {
                Menu("Add Child") {
                    Button("Child Story") {
                        addChildAgileTask(parentID: task.id, type: "Story")
                    }
                    Button("Child Task") {
                        addChildAgileTask(parentID: task.id, type: "Task")
                    }
                }
                Menu("Move To") {
                    ForEach(Array(boardColumns.enumerated()), id: \.offset) { _, lane in
                        Button(lane) {
                            setBoardStatus(taskID: task.id, to: lane)
                        }
                        .disabled(!canMoveTask(task, to: lane))
                    }
                }
            Menu("Assign Sprint") {
                Button("Backlog") {
                    setSprint(taskID: task.id, sprintID: nil)
                }
                ForEach(nativeSprints) { sprint in
                    Button(sprint.name) {
                        setSprint(taskID: task.id, sprintID: sprint.id)
                    }
                }
            }
        }
    }

    private var agileInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if inspectorTaskDraft != nil {
                    GroupBox("Task") {
                        VStack(alignment: .leading, spacing: 10) {
                            StableDraftTextField(title: "Task Name", text: agileTaskDraftBinding(\.name))
                                .textFieldStyle(.roundedBorder)

                            Picker("Type", selection: agileTaskDraftBinding(\.agileType)) {
                                ForEach(["Epic", "Feature", "Story", "Bug", "Task", "Milestone"], id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Board Status", selection: agileTaskDraftBinding(\.boardStatus)) {
                                ForEach(Array(boardColumns.enumerated()), id: \.offset) { _, lane in
                                    Text(lane).tag(lane)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Sprint", selection: agileTaskDraftOptionalIntBinding(\.sprintID)) {
                                Text("Backlog").tag(Int?.none)
                                ForEach(nativeSprints) { sprint in
                                    Text(sprint.name).tag(Optional(sprint.id))
                                }
                            }
                            .pickerStyle(.menu)

                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Story Points")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDraftTextField(title: "Optional", text: agileTaskDraftStoryPointsBinding())
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("% Complete")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDraftTextField(title: "0", text: agileTaskDraftPercentBinding())
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            StableDraftTextField(title: "Epic / Theme", text: agileTaskDraftBinding(\.epicName))
                                .textFieldStyle(.roundedBorder)
                            StableDraftTextField(title: "Tags", text: agileTaskDraftTagsBinding())
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Spacer()
                                Button(role: .destructive) {
                                    deleteSelectedAgileTask()
                                } label: {
                                    Label("Delete Story", systemImage: "trash")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    ContentUnavailableView(
                        "No Agile Item Selected",
                        systemImage: "rectangle.3.group.bubble.left",
                        description: Text("Select a backlog or board card to edit its agile metadata.")
                    )
                }

                GroupBox("Backlog Health") {
                    VStack(alignment: .leading, spacing: 8) {
                        inspectorFact("Unassigned to Sprint", value: "\(backlogTasks.count)")
                        inspectorFact("Ready For Delivery", value: "\(derivedContent.readyCount)")
                        inspectorFact("In Progress", value: "\(derivedContent.inProgressCount)")
                        inspectorFact("Completed", value: "\(derivedContent.completedCount)")
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var sprintPlannerView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sprints")
                        .font(.headline)
                    Spacer()
                }
                .padding()

                Divider()

                List(selection: $selectedSprintID) {
                    ForEach(nativeSprints) { sprint in
                        Button {
                            selectedSprintID = sprint.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sprint.name)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundStyle(.primary)
                                    Text("\(committedPoints(for: sprint.id)) / \(max(0, sprint.capacityPoints)) pts")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(sprint.state)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            }
                        }
                        .buttonStyle(.plain)
                        .tag(sprint.id)
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: 280)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selectedSprintID,
                       let sprint = nativeSprints.first(where: { $0.id == selectedSprintID }) {
                        GroupBox("Sprint Details") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Sprint Name", text: sprintStringBinding(sprintID: selectedSprintID, keyPath: \.name))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Goal", text: sprintStringBinding(sprintID: selectedSprintID, keyPath: \.goal))
                                    .textFieldStyle(.roundedBorder)
                                TextField("Team", text: sprintStringBinding(sprintID: selectedSprintID, keyPath: \.teamName))
                                    .textFieldStyle(.roundedBorder)

                                HStack(spacing: 12) {
                                    DatePicker("Start", selection: sprintDateBinding(sprintID: selectedSprintID, keyPath: \.startDate), displayedComponents: .date)
                                    DatePicker("Finish", selection: sprintDateBinding(sprintID: selectedSprintID, keyPath: \.endDate), displayedComponents: .date)
                                }

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Capacity Points")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("0", value: sprintIntBinding(sprintID: selectedSprintID, keyPath: \.capacityPoints), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 92)
                                    }

                                    Picker("State", selection: sprintStringBinding(sprintID: selectedSprintID, keyPath: \.state)) {
                                        Text("Planning").tag("Planning")
                                        Text("Active").tag("Active")
                                        Text("Complete").tag("Complete")
                                    }
                                    .pickerStyle(.menu)
                                }

                                HStack(spacing: 16) {
                                    inspectorFact("Committed", value: "\(committedPoints(for: sprint.id)) pts")
                                    inspectorFact("Completed", value: "\(completedPoints(for: sprint.id)) pts")
                                    inspectorFact("Remaining", value: "\(max(0, committedPoints(for: sprint.id) - completedPoints(for: sprint.id))) pts")
                                }

                                HStack {
                                    Spacer()
                                    Button(role: .destructive) {
                                        deleteSelectedSprint()
                                    } label: {
                                        Label("Delete Sprint", systemImage: "trash")
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Sprint Selected",
                            systemImage: "calendar",
                            description: Text("Create or select a sprint to edit dates, capacity, and assigned work.")
                        )
                    }

                    GroupBox {
                        collapsibleSprintSection(
                            title: "Backlog",
                            isExpanded: $backlogSectionExpanded
                        ) {
                            sprintTaskList(title: "Not Yet Assigned To Sprint", tasks: backlogTasks)
                        }
                    }

                    if let selectedSprintID {
                        GroupBox {
                            collapsibleSprintSection(
                                title: "Sprint Scope",
                                isExpanded: $sprintScopeSectionExpanded
                            ) {
                                sprintTaskList(title: "Tasks In Selected Sprint", tasks: agileTasks.filter { $0.sprintID == selectedSprintID })
                            }
                        }

                        GroupBox("Sprint Timeline") {
                            sprintTimelineView(tasks: selectedSprintTasks)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func collapsibleSprintSection<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func sprintTaskList(title: String, tasks: [NativePlanTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if tasks.isEmpty {
                Text("No tasks in this set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.name)
                            HStack(spacing: 8) {
                                miniChip(task.boardStatus, tint: laneColor(for: task.boardStatus))
                                if let points = task.storyPoints {
                                    miniChip("\(points) pt", tint: .secondary)
                                }
                            }
                        }

                        Spacer()

                        Picker("", selection: sprintPickerBinding(for: task.id)) {
                            Text("Backlog").tag(Int?.none)
                            ForEach(nativeSprints) { sprint in
                                Text(sprint.name).tag(Optional(sprint.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 190)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func sprintTimelineView(tasks: [NativePlanTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if tasks.isEmpty {
                Text("No scheduled tasks in this sprint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let range = sprintTimelineRange(for: tasks)
                HStack {
                    Text(DateFormatting.simpleDate(range.start))
                    Spacer()
                    Text(DateFormatting.simpleDate(range.end))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(tasks) { task in
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let offset = sprintTimelineOffset(for: task.startDate, range: range, width: width)
                        let barWidth = sprintTimelineBarWidth(start: task.startDate, finish: task.normalizedFinishDate, range: range, width: width)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(task.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(task.boardStatus)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(height: 10)

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(laneColor(for: normalizedBoardStatus(for: task)).opacity(0.85))
                                    .frame(width: barWidth, height: 10)
                                    .offset(x: offset)
                            }

                            HStack {
                                Text(DateFormatting.simpleDate(task.startDate))
                                Spacer()
                                Text(DateFormatting.simpleDate(task.normalizedFinishDate))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 48)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var reportsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                reportSection(title: "Overview", subtitle: "Current delivery posture across backlog, sprint load, and earned status snapshots.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        agileReportCard(
                            title: latestSnapshot?.name ?? "No Snapshot",
                            subtitle: latestSnapshot.map { DateFormatting.simpleDate($0.statusDate) } ?? "Status Center",
                            value: latestSnapshot.map { ratioText($0.cpi) } ?? "--",
                            footnote: "Latest CPI",
                            tone: (latestSnapshot?.cpi ?? 1) >= 1 ? .green : .orange
                        )
                        agileReportCard(
                            title: "Delivery Flow",
                            subtitle: "Board movement",
                            value: "\(derivedContent.doneCount)",
                            footnote: "Done items",
                            tone: .green
                        )
                        agileReportCard(
                            title: "Ready Queue",
                            subtitle: "Near-term work",
                            value: "\(derivedContent.readyCount)",
                            footnote: "Ready items",
                            tone: .blue
                        )
                        agileReportCard(
                            title: "Sprint Capacity",
                            subtitle: nativeSprints.isEmpty ? "No sprints" : "\(nativeSprints.count) active definitions",
                            value: "\(nativeSprints.reduce(0) { $0 + max(0, $1.capacityPoints) })",
                            footnote: "Capacity points",
                            tone: .purple
                        )
                    }
                }

                reportSection(title: "Snapshot Trend", subtitle: "Recent reporting periods with value, cost, and control signals.") {
                    if nativeStatusSnapshots.isEmpty {
                        Text("No status snapshots captured yet. Use Status Center to capture reporting periods.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nativeStatusSnapshots.suffix(6).reversed(), id: \.id) { snapshot in
                            snapshotTrendRow(snapshot)
                        }
                    }
                }

                reportSection(title: "Sprint Radar", subtitle: "Committed vs completed work, remaining load, and capacity pressure by sprint.") {
                    if nativeSprints.isEmpty {
                        Text("No sprints defined yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(nativeSprints) { sprint in
                            sprintRadarRow(sprint)
                        }
                    }
                }

                reportSection(title: "Backlog Composition", subtitle: "Work mix by agile type plus delivery pressure indicators.") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(["Epic", "Feature", "Story", "Bug", "Task", "Milestone"], id: \.self) { type in
                            agileDistributionRow(
                                title: type,
                                count: agileTasks.filter { $0.agileType == type }.count,
                                total: max(agileTasks.count, 1),
                                tint: distributionTint(for: type)
                            )
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            compactReportFact(title: "Backlog Only", value: "\(backlogTasks.count)")
                            compactReportFact(title: "Ready", value: "\(derivedContent.readyCount)")
                            compactReportFact(title: "In Progress", value: "\(derivedContent.inProgressCount)")
                            compactReportFact(title: "Done", value: "\(derivedContent.doneCount)")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func reportSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func agileReportCard(title: String, subtitle: String, value: String, footnote: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tone.opacity(0.14), lineWidth: 1)
        }
    }

    private func snapshotTrendRow(_ snapshot: NativeStatusSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(snapshot.cpi >= 1 && snapshot.spi >= 1 ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.name)
                            .font(.subheadline.weight(.semibold))
                        Text(DateFormatting.simpleDate(snapshot.statusDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 14) {
                        miniMetric("BAC", currencyText(snapshot.bac))
                        miniMetric("EV", currencyText(snapshot.ev))
                        miniMetric("AC", currencyText(snapshot.ac))
                        miniMetric("CPI", ratioText(snapshot.cpi))
                        miniMetric("SPI", ratioText(snapshot.spi))
                        miniMetric("VAC", currencyText(snapshot.vac))
                    }
                }

                if !snapshot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(snapshot.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func sprintRadarRow(_ sprint: NativePlanSprint) -> some View {
        let committed = committedPoints(for: sprint.id)
        let completed = completedPoints(for: sprint.id)
        let remaining = max(0, committed - completed)
        let fillRatio = min(max(capacityFillRatio(for: sprint.id), 0), 1)
        let doneRatio = committed == 0 ? 0 : Double(completed) / Double(committed)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sprint.name)
                        .font(.subheadline.weight(.semibold))
                    Text(sprint.state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                miniMetric("Committed", "\(committed)")
                miniMetric("Done", "\(completed)")
                miniMetric("Remaining", "\(remaining)")
                miniMetric("Capacity", "\(max(0, sprint.capacityPoints))")
            }

            VStack(alignment: .leading, spacing: 8) {
                reportBar(title: "Capacity Fill", value: ratioText(fillRatio), ratio: fillRatio, tint: fillRatio >= 1 ? .orange : .blue)
                reportBar(title: "Completion", value: ratioText(doneRatio), ratio: doneRatio, tint: doneRatio >= 1 ? .green : .mint)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func agileDistributionRow(title: String, count: Int, total: Int, tint: Color) -> some View {
        let ratio = total == 0 ? 0 : Double(count) / Double(total)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text("\(count)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.8))
                        .frame(width: width * ratio)
                }
            }
            .frame(height: 8)
        }
    }

    private func reportBar(title: String, value: String, ratio: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: width * min(max(ratio, 0), 1))
                }
            }
            .frame(height: 8)
        }
    }

    private func compactReportFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func agileHeaderMetric(title: String, value: String, tone: Color) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func headerControlLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func headerStatusPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func distributionTint(for type: String) -> Color {
        switch type.lowercased() {
        case "epic": return .purple
        case "feature": return .indigo
        case "story": return .blue
        case "bug": return .red
        case "task": return .orange
        case "milestone": return .green
        default: return .secondary
        }
    }

    private func toggleFocusMode() {
        let nextValue = !isFocusMode
        isFocusMode = nextValue
        splitViewVisibility = nextValue ? .detailOnly : .all
    }

    private func addStory() {
        commitAgileInspectorDraft()
        fullSyncAgilePlan { workingPlan in
            var task = workingPlan.makeTask(name: "New Story")
            task.agileType = "Story"
            task.boardStatus = boardColumns.first ?? "Backlog"
            workingPlan.tasks.append(task)
            workingPlan.reschedule()
            selectedTaskID = task.id
        }
    }

    private func addSprint() {
        fullSyncAgilePlan { workingPlan in
            let sprint = workingPlan.makeSprint()
            workingPlan.sprints.append(sprint)
            selectedSprintID = sprint.id
        }
    }

    private func addChildAgileTask(parentID: Int, type: String) {
        commitAgileInspectorDraft()

        fullSyncAgilePlan { workingPlan in
            guard let parentIndex = workingPlan.tasks.firstIndex(where: { $0.id == parentID }) else { return }
            let parent = workingPlan.tasks[parentIndex]

            var child = workingPlan.makeTask(name: "New \(type)")
            child.agileType = type
            child.outlineLevel = parent.outlineLevel + 1
            child.boardStatus = normalizedBoardStatus(for: parent)
            child.sprintID = parent.sprintID
            child.startDate = parent.startDate
            child.finishDate = parent.finishDate
            child.durationDays = parent.durationDays
            child.priority = parent.priority
            child.epicName = parent.agileType.compare("Epic", options: .caseInsensitive) == .orderedSame
                ? parent.name
                : parent.epicName

            var insertionIndex = parentIndex + 1
            while insertionIndex < workingPlan.tasks.count, workingPlan.tasks[insertionIndex].outlineLevel > parent.outlineLevel {
                insertionIndex += 1
            }

            workingPlan.tasks.insert(child, at: insertionIndex)
            selectedTaskID = child.id
        }
    }

    private func syncAgileInspectorDraft(force: Bool = false) {
        guard let selectedTaskID,
              let liveTask = nativeTasks.first(where: { $0.id == selectedTaskID }) else {
            inspectorTaskDraft = nil
            inspectorTaskDraftIsDirty = false
            return
        }

        if force || !inspectorTaskDraftIsDirty || inspectorTaskDraft?.id != liveTask.id {
            inspectorTaskDraft = liveTask
            inspectorTaskDraftIsDirty = false
        }
    }

    private func scheduleAgileInspectorDraftCommit() {
        inspectorTaskDraftWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            commitAgileInspectorDraft()
        }
        inspectorTaskDraftWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func commitAgileInspectorDraft() {
        inspectorTaskDraftWorkItem?.cancel()
        inspectorTaskDraftWorkItem = nil

        guard inspectorTaskDraftIsDirty,
              let draft = inspectorTaskDraft,
              let task = planModel.tasks.first(where: { $0.legacyID == draft.id }) else {
            return
        }

        PerformanceMonitor.measure("AgileBoard.CommitInspectorDraft") {
            inspectorTaskDraftIsDirty = false
            task.update(from: draft, orderIndex: task.orderIndex)
            persistAgileStoreChanges()
            refreshDerivedContent()
        }
    }

    private func mutateAgileInspectorDraft(_ update: (inout NativePlanTask) -> Void) {
        guard var draft = inspectorTaskDraft else { return }
        update(&draft)
        inspectorTaskDraft = draft
        inspectorTaskDraftIsDirty = true
        scheduleAgileInspectorDraftCommit()
    }

    private func agileTaskDraftBinding(_ keyPath: WritableKeyPath<NativePlanTask, String>) -> Binding<String> {
        Binding(
            get: { inspectorTaskDraft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                mutateAgileInspectorDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func agileTaskDraftOptionalIntBinding(_ keyPath: WritableKeyPath<NativePlanTask, Int?>) -> Binding<Int?> {
        Binding(
            get: { inspectorTaskDraft?[keyPath: keyPath] },
            set: { newValue in
                mutateAgileInspectorDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func agileTaskDraftStoryPointsBinding() -> Binding<String> {
        Binding(
            get: {
                guard let points = inspectorTaskDraft?.storyPoints else { return "" }
                return String(points)
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                mutateAgileInspectorDraft {
                    $0.storyPoints = digits.isEmpty ? nil : max(0, Int(digits) ?? 0)
                }
            }
        )
    }

    private func agileTaskDraftPercentBinding() -> Binding<String> {
        Binding(
            get: {
                guard let percent = inspectorTaskDraft?.percentComplete else { return "0" }
                return String(Int(percent.rounded()))
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                let parsed = Double(digits) ?? 0
                mutateAgileInspectorDraft {
                    $0.percentComplete = min(100, max(0, parsed))
                }
            }
        )
    }

    private func agileTaskDraftTagsBinding() -> Binding<String> {
        Binding(
            get: { inspectorTaskDraft?.tags.joined(separator: ", ") ?? "" },
            set: { newValue in
                mutateAgileInspectorDraft {
                    $0.tags = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        )
    }

    private func deleteSelectedSprint() {
        guard let selectedSprintID else { return }
        fullSyncAgilePlan { workingPlan in
            workingPlan.sprints.removeAll { $0.id == selectedSprintID }
            for index in workingPlan.tasks.indices where workingPlan.tasks[index].sprintID == selectedSprintID {
                workingPlan.tasks[index].sprintID = nil
            }
            self.selectedSprintID = workingPlan.sprints.first?.id
        }
    }

    private func deleteSelectedAgileTask() {
        commitAgileInspectorDraft()
        guard let selectedTaskID else { return }

        fullSyncAgilePlan { workingPlan in
            guard let index = workingPlan.tasks.firstIndex(where: { $0.id == selectedTaskID }) else { return }

            workingPlan.tasks.remove(at: index)
            workingPlan.assignments.removeAll { $0.taskID == selectedTaskID }
            for taskIndex in workingPlan.tasks.indices {
                workingPlan.tasks[taskIndex].predecessorTaskIDs.removeAll { $0 == selectedTaskID }
            }

            self.selectedTaskID = agileTasks.first(where: { $0.id != selectedTaskID })?.id ?? workingPlan.tasks.first?.id
        }
    }

    private func setBoardStatus(taskID: Int, to status: String) {
        guard let currentTask = nativeTasks.first(where: { $0.id == taskID }) else { return }
        guard normalizedBoardStatus(for: currentTask) != status else { return }
        guard canMoveTask(currentTask, to: status) else {
            presentBoardInteractionMessage(boardMoveRejectionReason(for: currentTask, to: status) ?? "This move is blocked by the current workflow.")
            return
        }
        withAgileTask(taskID) { task in
            task.boardStatus = status
        }
        if inspectorTaskDraft?.id == taskID {
            inspectorTaskDraft?.boardStatus = status
        }
    }

    private func moveTaskToLane(taskID: Int, lane: String) {
        PerformanceMonitor.measure("AgileBoard.MoveTaskToLane") {
            setBoardStatus(taskID: taskID, to: lane)
            refreshDerivedContent()
            selectedTaskID = taskID
            draggingTaskID = nil
            dropTargetLane = nil
        }
    }

    private func reparentTask(taskID: Int, parentTaskID: Int?, lane: String) {
        PerformanceMonitor.measure("AgileBoard.ReparentTask") {
            fullSyncAgilePlan { workingPlan in
                guard let movingIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                let movingRoot = workingPlan.tasks[movingIndex]

                var subtreeEnd = movingIndex + 1
                while subtreeEnd < workingPlan.tasks.count, workingPlan.tasks[subtreeEnd].outlineLevel > movingRoot.outlineLevel {
                    subtreeEnd += 1
                }

                if let parentTaskID,
                   let parentIndex = workingPlan.tasks.firstIndex(where: { $0.id == parentTaskID }),
                   (movingIndex..<subtreeEnd).contains(parentIndex) {
                    return
                }

                let movingSubtree = Array(workingPlan.tasks[movingIndex..<subtreeEnd])
                workingPlan.tasks.removeSubrange(movingIndex..<subtreeEnd)

                let targetOutlineLevel: Int
                let insertionIndex: Int

                if let parentTaskID,
                   let parentIndex = workingPlan.tasks.firstIndex(where: { $0.id == parentTaskID }) {
                    let parent = workingPlan.tasks[parentIndex]
                    targetOutlineLevel = parent.outlineLevel + 1
                    var insertAfter = parentIndex + 1
                    while insertAfter < workingPlan.tasks.count, workingPlan.tasks[insertAfter].outlineLevel > parent.outlineLevel {
                        insertAfter += 1
                    }
                    insertionIndex = insertAfter
                } else {
                    targetOutlineLevel = 1
                    insertionIndex = workingPlan.tasks.indices.contains(movingIndex) ? movingIndex : workingPlan.tasks.count
                }

                let levelDelta = targetOutlineLevel - movingRoot.outlineLevel
                let adjustedSubtree = movingSubtree.map { task in
                    var updated = task
                    updated.outlineLevel = max(1, task.outlineLevel + levelDelta)
                    updated.boardStatus = lane
                    return updated
                }

                workingPlan.tasks.insert(contentsOf: adjustedSubtree, at: insertionIndex)
                selectedTaskID = taskID
                dropTargetParentGroupKey = nil
            }
        }
    }

    private func createBucket() {
        let name = newBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let exists = boardColumns.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
        if !exists {
            fullSyncAgilePlan { workingPlan in
                var nextWorkflow = workflowColumns
                if let previousName = nextWorkflow.last?.name {
                    if let lastIndex = nextWorkflow.indices.last,
                       !nextWorkflow[lastIndex].allowedTransitions.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                        nextWorkflow[lastIndex].allowedTransitions.append(name)
                    }
                    nextWorkflow.append(NativeBoardWorkflowColumn(name: name, wipLimit: nil, allowedTransitions: [previousName]))
                } else {
                    nextWorkflow = [NativeBoardWorkflowColumn(name: name, wipLimit: nil, allowedTransitions: [])]
                }
                workingPlan.workflowColumns = NativeProjectPlan.synchronizedWorkflowColumns(
                    boardColumns: nextWorkflow.map(\.name),
                    workflowColumns: nextWorkflow
                )
                workingPlan.boardColumns = workingPlan.workflowColumns.map(\.name)
                workingPlan.typeWorkflowOverrides = NativeProjectPlan.synchronizedTypeWorkflowOverrides(
                    boardColumns: workingPlan.boardColumns,
                    overrides: workingPlan.typeWorkflowOverrides
                )
            }
        }
        newBucketName = ""
        isPresentingAddBucketSheet = false
    }

    private func moveBucket(_ lane: String, direction: Int) {
        fullSyncAgilePlan { workingPlan in
            var ordered = workflowColumns
            guard let currentIndex = ordered.firstIndex(where: { $0.name == lane }) else { return }
            let destinationIndex = currentIndex + direction
            guard ordered.indices.contains(destinationIndex) else { return }
            guard currentIndex != destinationIndex else { return }
            ordered.swapAt(currentIndex, destinationIndex)
            workingPlan.workflowColumns = NativeProjectPlan.synchronizedWorkflowColumns(
                boardColumns: ordered.map(\.name),
                workflowColumns: ordered
            )
            workingPlan.boardColumns = workingPlan.workflowColumns.map(\.name)
            workingPlan.typeWorkflowOverrides = NativeProjectPlan.synchronizedTypeWorkflowOverrides(
                boardColumns: workingPlan.boardColumns,
                overrides: workingPlan.typeWorkflowOverrides
            )
        }
    }

    private func deleteBucket(_ lane: String) {
        let ordered = boardColumns
        guard ordered.count > 1, let currentIndex = ordered.firstIndex(of: lane) else { return }

        var nextColumns = ordered
        nextColumns.removeAll { $0 == lane }
        let fallbackIndex = min(currentIndex, max(0, nextColumns.count - 1))
        let fallbackLane = nextColumns[fallbackIndex]

        fullSyncAgilePlan { workingPlan in
            for index in workingPlan.tasks.indices where normalizedBoardStatus(for: workingPlan.tasks[index]) == lane {
                workingPlan.tasks[index].boardStatus = fallbackLane
            }

            let nextWorkflow = workflowColumns
                .filter { $0.name.compare(lane, options: .caseInsensitive) != .orderedSame }
                .map { column in
                    var updated = column
                    updated.allowedTransitions.removeAll { $0.compare(lane, options: .caseInsensitive) == .orderedSame }
                    return updated
                }

            workingPlan.workflowColumns = NativeProjectPlan.synchronizedWorkflowColumns(
                boardColumns: nextColumns,
                workflowColumns: nextWorkflow
            )
            workingPlan.boardColumns = workingPlan.workflowColumns.map(\.name)
            workingPlan.typeWorkflowOverrides = NativeProjectPlan.synchronizedTypeWorkflowOverrides(
                boardColumns: workingPlan.boardColumns,
                overrides: workingPlan.typeWorkflowOverrides
            )
            if dropTargetLane == lane {
                dropTargetLane = nil
            }
        }
    }

    private func selectBoardTask(_ taskID: Int) {
        PerformanceMonitor.mark("AgileBoard.SelectTask", message: "task \(taskID)")
        commitAgileInspectorDraft()
        selectedTaskID = taskID
        if !showsInspector {
            showsInspector = true
        }
    }

    private func setSprint(taskID: Int, sprintID: Int?) {
        guard let currentTask = nativeTasks.first(where: { $0.id == taskID }) else { return }
        guard currentTask.sprintID != sprintID else { return }
        withAgileTask(taskID) { task in
            task.sprintID = sprintID
        }
        if inspectorTaskDraft?.id == taskID {
            inspectorTaskDraft?.sprintID = sprintID
        }
    }

    private func sprintPickerBinding(for taskID: Int) -> Binding<Int?> {
        Binding(
            get: {
                nativeTasks.first(where: { $0.id == taskID })?.sprintID
            },
            set: { newValue in
                setSprint(taskID: taskID, sprintID: newValue)
            }
        )
    }

    private func sprintStringBinding(sprintID: Int, keyPath: WritableKeyPath<NativePlanSprint, String>) -> Binding<String> {
        Binding(
            get: {
                guard let sprint = planModel.sprints.first(where: { $0.legacyID == sprintID }) else { return "" }
                return sprint.asNativeSprint()[keyPath: keyPath]
            },
            set: { newValue in
                withAgileSprint(sprintID) { sprint in
                    var nativeSprint = sprint.asNativeSprint()
                    nativeSprint[keyPath: keyPath] = newValue
                    sprint.update(from: nativeSprint)
                }
            }
        )
    }

    private func sprintDateBinding(sprintID: Int, keyPath: WritableKeyPath<NativePlanSprint, Date>) -> Binding<Date> {
        Binding(
            get: {
                guard let sprint = planModel.sprints.first(where: { $0.legacyID == sprintID }) else { return planModel.statusDate }
                return sprint.asNativeSprint()[keyPath: keyPath]
            },
            set: { newValue in
                withAgileSprint(sprintID) { sprint in
                    var nativeSprint = sprint.asNativeSprint()
                    nativeSprint[keyPath: keyPath] = Calendar.current.startOfDay(for: newValue)
                    sprint.update(from: nativeSprint)
                }
            }
        )
    }

    private func sprintIntBinding(sprintID: Int, keyPath: WritableKeyPath<NativePlanSprint, Int>) -> Binding<Int> {
        Binding(
            get: {
                guard let sprint = planModel.sprints.first(where: { $0.legacyID == sprintID }) else { return 0 }
                return sprint.asNativeSprint()[keyPath: keyPath]
            },
            set: { newValue in
                withAgileSprint(sprintID) { sprint in
                    var nativeSprint = sprint.asNativeSprint()
                    nativeSprint[keyPath: keyPath] = max(0, newValue)
                    sprint.update(from: nativeSprint)
                }
            }
        )
    }

    private func normalizedBoardStatus(for task: NativePlanTask) -> String {
        let normalized = task.boardStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return boardColumns.first(where: { $0.compare(normalized, options: .caseInsensitive) == .orderedSame }) ?? boardColumns.first ?? "Backlog"
    }

    private func canMoveTask(_ task: NativePlanTask, to lane: String) -> Bool {
        boardMoveRejectionReason(for: task, to: lane) == nil
    }

    private func boardMoveRejectionReason(for task: NativePlanTask, to lane: String) -> String? {
        let currentLane = normalizedBoardStatus(for: task)
        if currentLane == lane {
            return nil
        }

        let allowed = allowedBoardTransitions(for: task)
        if !allowed.contains(lane) {
            return "\(task.agileType) items cannot move from \(currentLane) to \(lane) directly."
        }

        if let wipLimit = wipLimit(for: lane, itemType: task.agileType), currentLane != lane {
            let hasTypeSpecificLimit = hasTypeSpecificWIPLimit(for: lane, itemType: task.agileType)
            let currentCount = tasksByLane.first(where: { $0.lane == lane })?.tasks.filter {
                $0.id != task.id &&
                ($0.percentComplete < 100) &&
                (!hasTypeSpecificLimit || $0.agileType.compare(task.agileType, options: .caseInsensitive) == .orderedSame)
            }.count ?? 0
            if currentCount >= wipLimit {
                return "\(lane) reached its WIP limit of \(wipLimit)."
            }
        }

        return nil
    }

    private func allowedBoardTransitions(for task: NativePlanTask) -> Set<String> {
        let current = normalizedBoardStatus(for: task)
        let activeWorkflow = workflowColumns(for: task.agileType)
        guard let workflowColumn = activeWorkflow.first(where: { $0.name.compare(current, options: .caseInsensitive) == .orderedSame }) else {
            return Set(boardColumns)
        }
        var allowed: Set<String> = [workflowColumn.name]
        for target in workflowColumn.allowedTransitions {
            if let canonical = boardColumns.first(where: { $0.compare(target, options: .caseInsensitive) == .orderedSame }) {
                allowed.insert(canonical)
            }
        }
        return allowed
    }

    private func wipLimit(for lane: String) -> Int? {
        workflowColumns.first(where: { $0.name.compare(lane, options: .caseInsensitive) == .orderedSame })?.wipLimit
    }

    private func wipLimit(for lane: String, itemType: String) -> Int? {
        workflowColumns(for: itemType).first(where: { $0.name.compare(lane, options: .caseInsensitive) == .orderedSame })?.wipLimit
            ?? wipLimit(for: lane)
    }

    private func workflowColumns(for itemType: String) -> [NativeBoardWorkflowColumn] {
        typeWorkflowOverrides.first(where: { $0.itemType.compare(itemType, options: .caseInsensitive) == .orderedSame })?.columns
            ?? workflowColumns
    }

    private func hasTypeWorkflowOverride(for itemType: String) -> Bool {
        typeWorkflowOverrides.contains { $0.itemType.compare(itemType, options: .caseInsensitive) == .orderedSame }
    }

    private func hasTypeSpecificWIPLimit(for lane: String, itemType: String) -> Bool {
        guard let override = typeWorkflowOverrides.first(where: { $0.itemType.compare(itemType, options: .caseInsensitive) == .orderedSame }) else {
            return false
        }
        return override.columns.first(where: { $0.name.compare(lane, options: .caseInsensitive) == .orderedSame })?.wipLimit != nil
    }

    private func workflowDraftNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { workflowDraft.indices.contains(index) ? workflowDraft[index].name : "" },
            set: { newValue in
                guard workflowDraft.indices.contains(index) else { return }
                workflowDraft[index].name = newValue
            }
        )
    }

    private func workflowDraftWIPTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard workflowDraft.indices.contains(index), let value = workflowDraft[index].wipLimit else { return "" }
                return String(value)
            },
            set: { newValue in
                guard workflowDraft.indices.contains(index) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    workflowDraft[index].wipLimit = nil
                } else {
                    workflowDraft[index].wipLimit = max(1, Int(trimmed.filter(\.isNumber)) ?? 0)
                }
            }
        )
    }

    private func workflowTransitionBinding(_ sourceIndex: Int, targetIndex: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard workflowDraft.indices.contains(sourceIndex), workflowDraft.indices.contains(targetIndex) else { return false }
                let targetName = workflowDraft[targetIndex].name
                return workflowDraft[sourceIndex].allowedTransitions.contains(where: { $0.compare(targetName, options: .caseInsensitive) == .orderedSame })
            },
            set: { isEnabled in
                guard workflowDraft.indices.contains(sourceIndex), workflowDraft.indices.contains(targetIndex) else { return }
                let targetName = workflowDraft[targetIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !targetName.isEmpty else { return }
                if isEnabled {
                    if !workflowDraft[sourceIndex].allowedTransitions.contains(where: { $0.compare(targetName, options: .caseInsensitive) == .orderedSame }) {
                        workflowDraft[sourceIndex].allowedTransitions.append(targetName)
                    }
                } else {
                    workflowDraft[sourceIndex].allowedTransitions.removeAll { $0.compare(targetName, options: .caseInsensitive) == .orderedSame }
                }
            }
        )
    }

    private func saveWorkflowDesigner() {
        let previousWorkflow = workflowColumns
        var previousNamesByID: [UUID: String] = [:]
        for column in previousWorkflow {
            if previousNamesByID[column.id] == nil {
                previousNamesByID[column.id] = column.name
            }
        }
        var usedNames: Set<String> = []
        var normalizedDraft: [NativeBoardWorkflowColumn] = []

        for (index, column) in workflowDraft.enumerated() {
            let trimmed = column.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var candidate = trimmed.isEmpty ? "Bucket \(index + 1)" : trimmed
            if usedNames.contains(candidate.lowercased()) {
                var suffix = 2
                while usedNames.contains("\(candidate) \(suffix)".lowercased()) {
                    suffix += 1
                }
                candidate = "\(candidate) \(suffix)"
            }
            usedNames.insert(candidate.lowercased())

            normalizedDraft.append(
                NativeBoardWorkflowColumn(
                    id: column.id,
                    name: candidate,
                    wipLimit: column.wipLimit,
                    allowedTransitions: column.allowedTransitions
                )
            )
        }

        var renameMap: [String: String] = [:]
        for draft in normalizedDraft {
            let legacyName = previousNamesByID[draft.id] ?? draft.name
            let key = legacyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !renameMap.keys.contains(key) {
                renameMap[key] = draft.name
            }
        }
        let validNames = normalizedDraft.map(\.name)

        let savedWorkflow = normalizedDraft.map { column in
            let transitions = column.allowedTransitions.compactMap { rawTransition -> String? in
                let key = rawTransition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let renamed = renameMap[key], renamed.compare(column.name, options: .caseInsensitive) != .orderedSame {
                    return renamed
                }
                if let canonical = validNames.first(where: { $0.compare(rawTransition, options: .caseInsensitive) == .orderedSame }),
                   canonical.compare(column.name, options: .caseInsensitive) != .orderedSame {
                    return canonical
                }
                return nil
            }

            return NativeBoardWorkflowColumn(
                id: column.id,
                name: column.name,
                wipLimit: column.wipLimit,
                allowedTransitions: transitions
            )
        }

        fullSyncAgilePlan { workingPlan in
            if workflowDesignerAllowsRename {
                for index in workingPlan.tasks.indices {
                    let statusKey = workingPlan.tasks[index].boardStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let renamed = renameMap[statusKey] {
                        workingPlan.tasks[index].boardStatus = renamed
                    }
                }

                workingPlan.workflowColumns = NativeProjectPlan.synchronizedWorkflowColumns(
                    boardColumns: savedWorkflow.map(\.name),
                    workflowColumns: savedWorkflow
                )
                workingPlan.boardColumns = workingPlan.workflowColumns.map(\.name)

                let renamedOverrides = typeWorkflowOverrides.map { override in
                    NativeBoardTypeWorkflow(
                        id: override.id,
                        itemType: override.itemType,
                        columns: override.columns.map { column in
                            let renamedName = renameMap[column.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? column.name
                            let renamedTransitions = column.allowedTransitions.compactMap { transition in
                                renameMap[transition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? transition
                            }
                            return NativeBoardWorkflowColumn(
                                id: column.id,
                                name: renamedName,
                                wipLimit: column.wipLimit,
                                allowedTransitions: renamedTransitions
                            )
                        }
                    )
                }
                workingPlan.typeWorkflowOverrides = NativeProjectPlan.synchronizedTypeWorkflowOverrides(
                    boardColumns: workingPlan.boardColumns,
                    overrides: renamedOverrides
                )
            } else if case .itemType(let itemType) = workflowDesignerScope {
                var nextOverrides = typeWorkflowOverrides.filter { $0.itemType.compare(itemType, options: .caseInsensitive) != .orderedSame }
                nextOverrides.append(
                    NativeBoardTypeWorkflow(
                        itemType: itemType,
                        columns: NativeProjectPlan.synchronizedWorkflowColumns(
                            boardColumns: boardColumns,
                            workflowColumns: savedWorkflow
                        )
                    )
                )
                workingPlan.typeWorkflowOverrides = NativeProjectPlan.synchronizedTypeWorkflowOverrides(
                    boardColumns: boardColumns,
                    overrides: nextOverrides
                )
            }
        }
        isPresentingWorkflowDesigner = false
    }

    private var workflowDesignerAllowsRename: Bool {
        if case .shared = workflowDesignerScope {
            return true
        }
        return false
    }

    private func updateWorkflowDesignerScope(_ scope: AgileWorkflowDesignerScope) {
        workflowDesignerScope = scope
        switch scope {
        case .shared:
            workflowDraft = workflowColumns
        case .itemType(let itemType):
            workflowDraft = workflowColumns(for: itemType)
        }
    }

    private func resetTypeWorkflowOverride(itemType: String) {
        fullSyncAgilePlan { workingPlan in
            workingPlan.typeWorkflowOverrides.removeAll { $0.itemType.compare(itemType, options: .caseInsensitive) == .orderedSame }
        }
        updateWorkflowDesignerScope(.itemType(itemType))
    }

    private func presentBoardInteractionMessage(_ message: String) {
        boardInteractionMessageWorkItem?.cancel()
        boardInteractionMessage = message
        let workItem = DispatchWorkItem {
            boardInteractionMessage = nil
        }
        boardInteractionMessageWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }

    private func filterTasksForBoardScope(_ tasks: [NativePlanTask]) -> [NativePlanTask] {
        switch boardSprintScope {
        case .all:
            return tasks
        case .backlogOnly:
            return tasks.filter { $0.sprintID == nil }
        case .sprint(let sprintID):
            return tasks.filter { $0.sprintID == sprintID }
        }
    }

    private func committedPoints(for sprintID: Int) -> Int {
        agileTasks
            .filter { $0.sprintID == sprintID }
            .reduce(0) { $0 + max(0, $1.storyPoints ?? 0) }
    }

    private func completedPoints(for sprintID: Int) -> Int {
        agileTasks
            .filter { $0.sprintID == sprintID && (normalizedBoardStatus(for: $0) == "Done" || $0.percentComplete >= 100) }
            .reduce(0) { $0 + max(0, $1.storyPoints ?? 0) }
    }

    private func capacityFillRatio(for sprintID: Int) -> Double {
        guard let sprint = nativeSprints.first(where: { $0.id == sprintID }), sprint.capacityPoints > 0 else { return 0 }
        return Double(committedPoints(for: sprintID)) / Double(sprint.capacityPoints)
    }

    private func sprintTimelineRange(for tasks: [NativePlanTask]) -> (start: Date, end: Date) {
        let starts = tasks.map(\.startDate)
        let finishes = tasks.map(\.normalizedFinishDate)
        let start = starts.min() ?? planModel.statusDate
        let finish = finishes.max() ?? start
        return (start, max(start, finish))
    }

    private func sprintTimelineOffset(for date: Date, range: (start: Date, end: Date), width: CGFloat) -> CGFloat {
        let total = max(range.end.timeIntervalSince(range.start), 60 * 60 * 24)
        let progress = min(max(date.timeIntervalSince(range.start) / total, 0), 1)
        return width * progress
    }

    private func sprintTimelineBarWidth(start: Date, finish: Date, range: (start: Date, end: Date), width: CGFloat) -> CGFloat {
        let total = max(range.end.timeIntervalSince(range.start), 60 * 60 * 24)
        let duration = max(finish.timeIntervalSince(start), 60 * 60 * 12)
        return max(10, width * CGFloat(duration / total))
    }

    private func laneColor(for status: String) -> Color {
        switch status.lowercased() {
        case "backlog": return .secondary
        case "ready": return .blue
        case "in progress": return .orange
        case "review": return .purple
        case "done": return .green
        default:
            let palette: [Color] = [.teal, .mint, .indigo, .pink, .cyan, .brown]
            let hash = abs(status.lowercased().hashValue)
            return palette[hash % palette.count]
        }
    }

    private func agileMetric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func boardTaskDateSummary(_ task: NativePlanTask) -> String {
        "\(DateFormatting.simpleDate(task.startDate)) - \(DateFormatting.simpleDate(task.normalizedFinishDate))"
    }

    private func swimlaneGroups(for tasks: [NativePlanTask], lane: String) -> [AgileSwimlaneGroup] {
        let sortedTasks = tasks.sorted { lhs, rhs in
            let lhsOrder = derivedContent.taskOrderByID[lhs.id] ?? .max
            let rhsOrder = derivedContent.taskOrderByID[rhs.id] ?? .max
            return lhsOrder < rhsOrder
        }

        switch boardSwimlaneMode {
        case .none:
            return [AgileSwimlaneGroup(key: "\(lane)|all", title: "All", tasks: sortedTasks, lane: lane, parentTaskID: nil, representsHierarchyRoot: false)]
        case .sprint:
            return groupedSwimlanes(from: sortedTasks, lane: lane) { task in
                if let sprintID = task.sprintID, let sprintName = derivedContent.sprintNamesByID[sprintID] {
                    return (key: "sprint-\(sprintID)", title: sprintName)
                }
                return (key: "backlog", title: "Backlog")
            }
        case .epic:
            return groupedSwimlanes(from: sortedTasks, lane: lane) { task in
                if task.agileType.compare("Epic", options: .caseInsensitive) == .orderedSame {
                    return (key: "epic-\(task.id)", title: task.name)
                }
                let epic = task.epicName.trimmingCharacters(in: .whitespacesAndNewlines)
                if epic.isEmpty {
                    return (key: "no-epic", title: "No Epic")
                }
                return (key: "epic-\(epic.lowercased())", title: epic)
            }
        case .parent:
            return groupedParentSwimlanes(from: sortedTasks, lane: lane)
        case .assignee:
            return groupedSwimlanes(from: sortedTasks, lane: lane) { task in
                if let assignee = primaryAssigneeName(for: task) {
                    return (key: "assignee-\(assignee.lowercased())", title: assignee)
                }
                return (key: "unassigned", title: "Unassigned")
            }
        case .team:
            return groupedSwimlanes(from: sortedTasks, lane: lane) { task in
                let team = teamSwimlaneTitle(for: task)
                return (key: "team-\(team.lowercased())", title: team)
            }
        }
    }

    private func groupedParentSwimlanes(from tasks: [NativePlanTask], lane: String) -> [AgileSwimlaneGroup] {
        var orderedKeys: [String] = []
        var titlesByKey: [String: String] = [:]
        var parentIDByKey: [String: Int?] = [:]
        var tasksByKey: [String: [NativePlanTask]] = [:]

        for task in tasks {
            let descriptor: (key: String, title: String, parentID: Int?)
            if let rootID = derivedContent.rootParentTaskIDByTaskID[task.id],
               let rootTask = derivedContent.taskByID[rootID] {
                descriptor = (key: "parent-\(rootID)", title: rootTask.name, parentID: rootID)
            } else {
                descriptor = (key: "task-\(task.id)", title: task.name, parentID: task.id)
            }

            if titlesByKey[descriptor.key] == nil {
                orderedKeys.append(descriptor.key)
                titlesByKey[descriptor.key] = descriptor.title
                parentIDByKey[descriptor.key] = descriptor.parentID
            }
            tasksByKey[descriptor.key, default: []].append(task)
        }

        return orderedKeys.map { key in
            AgileSwimlaneGroup(
                key: "\(lane)|\(key)",
                title: titlesByKey[key] ?? key,
                tasks: tasksByKey[key] ?? [],
                lane: lane,
                parentTaskID: parentIDByKey[key] ?? nil,
                representsHierarchyRoot: true
            )
        }
    }

    private func groupedSwimlanes(
        from tasks: [NativePlanTask],
        lane: String,
        keyForTask: (NativePlanTask) -> (key: String, title: String)
    ) -> [AgileSwimlaneGroup] {
        var orderedKeys: [String] = []
        var titlesByKey: [String: String] = [:]
        var tasksByKey: [String: [NativePlanTask]] = [:]

        for task in tasks {
            let descriptor = keyForTask(task)
            if titlesByKey[descriptor.key] == nil {
                orderedKeys.append(descriptor.key)
                titlesByKey[descriptor.key] = descriptor.title
            }
            tasksByKey[descriptor.key, default: []].append(task)
        }

        return orderedKeys.map { key in
            AgileSwimlaneGroup(key: "\(lane)|\(key)", title: titlesByKey[key] ?? key, tasks: tasksByKey[key] ?? [], lane: lane, parentTaskID: nil, representsHierarchyRoot: false)
        }
    }

    private func hierarchyIndent(for task: NativePlanTask) -> CGFloat {
        let depth = derivedContent.hierarchyDepthByTaskID[task.id] ?? 0
        return CGFloat(min(depth, 3)) * 14
    }

    private func parentRootTask(for group: AgileSwimlaneGroup) -> NativePlanTask? {
        guard boardSwimlaneMode == .parent, let parentTaskID = group.parentTaskID else { return nil }
        return group.tasks.first(where: { $0.id == parentTaskID }) ?? derivedContent.taskByID[parentTaskID]
    }

    private func childTasks(for group: AgileSwimlaneGroup) -> [NativePlanTask] {
        guard let parentTaskID = group.parentTaskID else { return group.tasks }
        return group.tasks.filter { $0.id != parentTaskID }
    }

    private func groupHierarchyIndent(for task: NativePlanTask, in group: AgileSwimlaneGroup) -> CGFloat {
        let taskDepth = derivedContent.hierarchyDepthByTaskID[task.id] ?? 0
        let rootDepth = group.parentTaskID.flatMap { derivedContent.hierarchyDepthByTaskID[$0] } ?? 0
        let relativeDepth = max(0, taskDepth - rootDepth - 1)
        return CGFloat(relativeDepth) * 14
    }

    private func groupHeaderTitle(for group: AgileSwimlaneGroup) -> String {
        switch boardSwimlaneMode {
        case .parent:
            return group.title
        case .none, .sprint, .epic, .assignee, .team:
            return group.title
        }
    }

    private func groupHeaderSubtitle(for group: AgileSwimlaneGroup) -> String {
        switch boardSwimlaneMode {
        case .parent:
            let childCount = max(0, group.tasks.count - (group.tasks.contains { $0.id == group.parentTaskID } ? 1 : 0))
            if childCount == 0 {
                return "Standalone work item"
            }
            return childCount == 1 ? "1 child item" : "\(childCount) child items"
        case .sprint:
            return group.tasks.count == 1 ? "1 item in sprint" : "\(group.tasks.count) items in sprint"
        case .epic:
            return group.tasks.count == 1 ? "1 item in epic" : "\(group.tasks.count) items in epic"
        case .assignee:
            return group.tasks.count == 1 ? "1 assigned item" : "\(group.tasks.count) assigned items"
        case .team:
            return group.tasks.count == 1 ? "1 team item" : "\(group.tasks.count) team items"
        case .none:
            return group.tasks.count == 1 ? "1 item" : "\(group.tasks.count) items"
        }
    }

    private func groupCountText(for group: AgileSwimlaneGroup) -> String {
        if boardSwimlaneMode == .parent {
            let childCount = max(0, group.tasks.count - (group.tasks.contains { $0.id == group.parentTaskID } ? 1 : 0))
            return childCount == 1 ? "1 child" : "\(childCount) children"
        }
        return "\(group.tasks.count)"
    }

    private func toggleSwimlaneGroup(_ key: String) {
        if collapsedSwimlaneKeys.contains(key) {
            collapsedSwimlaneKeys.remove(key)
        } else {
            collapsedSwimlaneKeys.insert(key)
        }
    }

    private func primaryAssignedResource(for task: NativePlanTask) -> NativePlanResource? {
        guard let resourceID = nativeAssignments.first(where: { $0.taskID == task.id })?.resourceID else {
            return nil
        }
        return nativeResources.first(where: { $0.id == resourceID })
    }

    private func primaryAssigneeName(for task: NativePlanTask) -> String? {
        guard let name = primaryAssignedResource(for: task)?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func teamSwimlaneTitle(for task: NativePlanTask) -> String {
        if let group = primaryAssignedResource(for: task)?.group.trimmingCharacters(in: .whitespacesAndNewlines),
           !group.isEmpty {
            return group
        }
        if let sprintID = task.sprintID,
           let sprintTeam = nativeSprints.first(where: { $0.id == sprintID })?.teamName.trimmingCharacters(in: .whitespacesAndNewlines),
           !sprintTeam.isEmpty {
            return sprintTeam
        }
        return "No Team"
    }

    private func boardTaskAssignmentSummary(_ task: NativePlanTask) -> String? {
        let resourceIDs = nativeAssignments
            .filter { $0.taskID == task.id }
            .compactMap(\.resourceID)

        guard !resourceIDs.isEmpty else { return nil }

        let names = resourceIDs.compactMap { resourceID in
            nativeResources.first(where: { $0.id == resourceID })?.name
        }

        guard let first = names.first else { return nil }
        return names.count == 1 ? first : "\(first) +\(names.count - 1)"
    }
    private func miniMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func miniChip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
    }

    private func inspectorFact(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(
            from: value,
            currencyCode: "USD",
            currencySymbol: "$",
            maximumFractionDigits: 0,
            minimumFractionDigits: 0
        )
    }

    private func ratioText(_ value: Double) -> String {
        guard value.isFinite else { return "0.00" }
        return String(format: "%.2f", value)
    }

    private func refreshDerivedContent() {
        PerformanceMonitor.measure("AgileBoard.RefreshDerived") {
            derivedContent = AgileBoardDerivedContent.build(
                tasks: nativeTasks,
                assignments: nativeAssignments,
                resources: nativeResources,
                sprints: nativeSprints,
                boardColumns: planModel.boardColumns,
                workflowColumns: workflowColumns,
                typeWorkflowOverrides: typeWorkflowOverrides,
                statusSnapshots: nativeStatusSnapshots
            )
        }
    }

    private func scheduleDerivedContentRefresh() {
        derivedRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshDerivedContent()
        }
        derivedRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }
}

private struct AgileBoardDropDelegate: DropDelegate {
    let lane: String
    @Binding var draggingTaskID: Int?
    @Binding var dropTargetLane: String?
    let moveTask: (Int, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [UTType.plainText]) else { return }
        guard dropTargetLane != lane else { return }
        dropTargetLane = lane
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingTaskID else { return false }
        moveTask(draggingTaskID, lane)
        dropTargetLane = nil
        return true
    }

    func dropExited(info: DropInfo) {
        guard dropTargetLane == lane else { return }
        dropTargetLane = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct AgileParentGroupDropDelegate: DropDelegate {
    let groupKey: String
    let parentTaskID: Int?
    let lane: String
    @Binding var draggingTaskID: Int?
    @Binding var dropTargetParentGroupKey: String?
    let reparentTask: (Int, Int?, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard info.hasItemsConforming(to: [UTType.plainText]) else { return }
        guard dropTargetParentGroupKey != groupKey else { return }
        dropTargetParentGroupKey = groupKey
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingTaskID else { return false }
        reparentTask(draggingTaskID, parentTaskID, lane)
        dropTargetParentGroupKey = nil
        return true
    }

    func dropExited(info: DropInfo) {
        guard dropTargetParentGroupKey == groupKey else { return }
        dropTargetParentGroupKey = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct PortfolioDashboardView: View {
    private enum RegistryScope: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case archived = "Archived"

        var id: String { rawValue }
    }

    private struct TaskSnapshot: Identifiable, Hashable {
        let id: String
        let planID: UUID
        let planTitle: String
        let name: String
        let boardStatus: String
        let finishDate: Date
        let isActive: Bool
        let percentComplete: Double
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PortfolioProjectPlan.updatedAt, order: .reverse)])
    private var plans: [PortfolioProjectPlan]
    @Binding var activePortfolioID: UUID?

    @State private var selectedPlanID: UUID?
    @State private var registryScope: RegistryScope = .active
    @State private var searchText = ""
    @State private var showImportPicker = false
    @State private var importStatusMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImporting = false

    private var visiblePlans: [PortfolioProjectPlan] {
        plans.filter { plan in
            scopeMatches(plan) && searchMatches(plan)
        }
    }

    private var archivedCount: Int {
        plans.filter(\.isArchivedValue).count
    }

    private var activeCount: Int {
        plans.count - archivedCount
    }

    private var totalPortfolioBudget: Double {
        visiblePlans.reduce(0) { $0 + $1.portfolioBudget }
    }

    private var totalPortfolioActualCost: Double {
        visiblePlans.reduce(0) { $0 + $1.portfolioActualCost }
    }

    private var budgetVariance: Double {
        totalPortfolioBudget - totalPortfolioActualCost
    }

    private var overdueTaskCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return activeTasks.filter { Calendar.current.startOfDay(for: $0.finishDate) < today }.count
    }

    private var activeTasks: [TaskSnapshot] {
        visiblePlans
            .flatMap(taskSnapshots(for:))
            .filter { $0.isActive && $0.percentComplete < 100 }
            .sorted {
                if $0.finishDate != $1.finishDate {
                    return $0.finishDate < $1.finishDate
                }
                return $0.id < $1.id
            }
    }

    private var selectedPlan: PortfolioProjectPlan? {
        if let selectedPlanID, let plan = plans.first(where: { $0.portfolioID == selectedPlanID }) {
            return plan
        }
        if let activePortfolioID, let plan = plans.first(where: { $0.portfolioID == activePortfolioID }) {
            return plan
        }
        return visiblePlans.first ?? plans.first
    }

    private var selectedPlanTitle: String {
        trimmedOrFallback(selectedPlan?.title ?? "", fallback: "No plan selected")
    }

    private var workspacePlan: PortfolioProjectPlan? {
        guard let activePortfolioID else { return nil }
        return plans.first(where: { $0.portfolioID == activePortfolioID })
    }

    private var watchlistTasks: [TaskSnapshot] {
        activeTasks
    }

    private var selectedPlanTasks: [TaskSnapshot] {
        guard let selectedPlan else { return [] }
        return taskSnapshots(for: selectedPlan)
    }

    private var selectedActiveTasks: [TaskSnapshot] {
        selectedPlanTasks
            .filter { $0.isActive && $0.percentComplete < 100 }
            .sorted {
                if $0.finishDate != $1.finishDate {
                    return $0.finishDate < $1.finishDate
                }
                return $0.id < $1.id
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    HStack(spacing: 12) {
                        metricCard(title: "Visible", value: "\(visiblePlans.count)", tint: .blue)
                        metricCard(title: "Active", value: "\(activeCount)", tint: .teal)
                        metricCard(title: "Archived", value: "\(archivedCount)", tint: .secondary)
                        metricCard(title: "Portfolio Budget", value: CurrencyFormatting.string(from: totalPortfolioBudget), tint: .green)
                        metricCard(title: "Actual Cost", value: CurrencyFormatting.string(from: totalPortfolioActualCost), tint: .orange)
                        metricCard(title: "Budget Remaining", value: CurrencyFormatting.string(from: budgetVariance), tint: budgetVariance >= 0 ? .green : .red)
                        metricCard(title: "Overdue Work", value: "\(overdueTaskCount)", tint: .red)
                    }

                    GroupBox("Registry") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                TextField("Search registry", text: $searchText)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 260)

                                Picker("Scope", selection: $registryScope) {
                                    ForEach(RegistryScope.allCases) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 280)

                                Button {
                                    showImportPicker = true
                                } label: {
                                    Label("Import Plan(s)", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    createBlankPortfolioPlan()
                                } label: {
                                    Label("New Blank Plan", systemImage: "doc.badge.plus")
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }

                            if visiblePlans.isEmpty {
                                ContentUnavailableView(
                                    "No Matching Projects",
                                    systemImage: "tray",
                                    description: Text("Import `.mpp` or `.mppplan` files, create a blank plan, or change the registry scope.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 220)
                            } else {
                                LazyVStack(spacing: 12) {
                                    ForEach(visiblePlans) { plan in
                                        portfolioRow(for: plan)
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Cross-Portfolio Watchlist") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(watchlistTasks.prefix(12)) { task in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.name)
                                            .font(.body.weight(.medium))
                                        Text(task.planTitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(task.finishDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Calendar.current.startOfDay(for: task.finishDate) < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                                }
                                Divider()
                            }
                            if watchlistTasks.isEmpty {
                                Text("No active work in the current registry scope.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 560, idealWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            detailPane
                .frame(minWidth: 420, idealWidth: 540, maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.mpp, .mppplan],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await importPortfolioPlans(from: urls)
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .onAppear {
            syncSelectedPlan()
            normalizeArchiveFlags()
        }
        .onChange(of: plans.map(\.portfolioID)) { _, _ in
            syncSelectedPlan()
        }
        .onChange(of: registryScope) { _, _ in
            syncSelectedPlan()
        }
        .onChange(of: searchText) { _, _ in
            syncSelectedPlan()
        }
        .onChange(of: activePortfolioID) { _, newValue in
            if selectedPlanID != newValue {
                selectedPlanID = newValue
            }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "Unknown error")
        }
        .overlay(alignment: .bottomLeading) {
            if let importStatusMessage {
                Text(importStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.leading, 20)
                    .padding(.bottom, 18)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio Workspace")
                    .font(.largeTitle.bold())
                Text("Register multiple projects, open one into the live workspace, archive or remove inactive work, and inspect portfolio health from one place.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedPlanTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let workspacePlan {
                    Label(workspacePlan.isArchivedValue ? "Archived" : "Active", systemImage: workspacePlan.isArchivedValue ? "archivebox" : "checkmark.seal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(workspacePlan.isArchivedValue ? Color.secondary : Color.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selected = selectedPlan {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(trimmedOrFallback(selected.title, fallback: "Untitled Plan"))
                        .font(.title2.bold())

                    HStack(spacing: 8) {
                        Label(selected.isArchivedValue ? "Archived" : "Active", systemImage: selected.isArchivedValue ? "archivebox" : "checkmark.seal")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold))
                        Label("Updated \(selected.updatedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        metricCard(title: "Tasks", value: "\(selected.taskCount)", tint: .blue)
                        metricCard(title: "BAC", value: CurrencyFormatting.string(from: selected.portfolioBudget), tint: .green)
                        metricCard(title: "Actual", value: CurrencyFormatting.string(from: selected.portfolioActualCost), tint: .orange)
                        metricCard(title: "Variance", value: CurrencyFormatting.string(from: selected.portfolioBudget - selected.portfolioActualCost), tint: selected.portfolioBudget >= selected.portfolioActualCost ? .green : .red)
                    }

                    GroupBox("Plan Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow(label: "Owner", value: trimmedOrFallback(selected.manager, fallback: "Unassigned"))
                            detailRow(label: "Company", value: trimmedOrFallback(selected.company, fallback: "No company"))
                            detailRow(label: "Status Date", value: selected.statusDate.formatted(date: .abbreviated, time: .omitted))
                            detailRow(label: "Resources", value: "\(selected.resources.count)")
                            detailRow(label: "Calendars", value: "\(selected.calendars.count)")
                            detailRow(label: "Sprints", value: "\(selected.sprints.count)")
                            detailRow(label: "Snapshots", value: "\(selected.statusSnapshots.count)")
                            detailRow(label: "Workflow Columns", value: "\(selected.workflowColumns.count)")
                            detailRow(label: "Type Workflows", value: "\(selected.typeWorkflowOverrides.count)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Actions") {
                        HStack(spacing: 10) {
                            Button {
                                openPlanInWorkspace(selected)
                            } label: {
                                Label("Open In Workspace", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(activePortfolioID == selected.portfolioID)

                            Button(selected.isArchivedValue ? "Restore" : "Archive") {
                                toggleArchive(for: selected)
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                deletePortfolioPlan(selected)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Spacer()
                        }
                    }

                    GroupBox("Active Work") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selectedActiveTasks.prefix(12)) { task in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.name)
                                            .font(.body.weight(.medium))
                                        Text(task.boardStatus)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(task.finishDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Calendar.current.startOfDay(for: task.finishDate) < Calendar.current.startOfDay(for: Date()) ? .red : .secondary)
                                }
                                Divider()
                            }
                            if selectedPlanTasks.isEmpty {
                                Text("No tasks stored in this project yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView(
                "No Plan Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Select a project from the portfolio registry to inspect or open it in the workspace.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func portfolioRow(for plan: PortfolioProjectPlan) -> some View {
        let selected = selectedPlanID == plan.portfolioID
        let planTaskSnapshots = taskSnapshots(for: plan)
        let activeTaskCount = planTaskSnapshots.filter { $0.isActive && $0.percentComplete < 100 }.count
        let overdueTaskCount = planTaskSnapshots.filter {
            $0.isActive
                && $0.percentComplete < 100
                && Calendar.current.startOfDay(for: $0.finishDate) < Calendar.current.startOfDay(for: Date())
        }.count
        let budgetVariance = plan.portfolioBudget - plan.portfolioActualCost

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(trimmedOrFallback(plan.title, fallback: "Untitled Plan"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if plan.isArchivedValue {
                            Text("Archived")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                        if activePortfolioID == plan.portfolioID {
                            Text("Workspace")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(trimmedOrFallback(plan.company, fallback: trimmedOrFallback(plan.manager, fallback: "No owner")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Updated \(plan.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button {
                            openPlanInWorkspace(plan)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(activePortfolioID == plan.portfolioID)

                        Button {
                            toggleArchive(for: plan)
                        } label: {
                            Label(plan.isArchivedValue ? "Restore" : "Archive", systemImage: plan.isArchivedValue ? "archivebox.badge.plus" : "archivebox")
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            deletePortfolioPlan(plan)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack(spacing: 10) {
                Label("\(plan.taskCount) tasks", systemImage: "list.bullet")
                Label("\(activeTaskCount) active", systemImage: "play.circle")
                Label("\(overdueTaskCount) overdue", systemImage: "exclamationmark.triangle")
                Label(CurrencyFormatting.string(from: plan.portfolioBudget), systemImage: "dollarsign.circle")
                Label(CurrencyFormatting.string(from: plan.portfolioActualCost), systemImage: "chart.line.uptrend.xyaxis")
                Label(CurrencyFormatting.string(from: budgetVariance), systemImage: budgetVariance >= 0 ? "arrow.down.right.circle" : "arrow.up.right.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            HStack(spacing: 10) {
                detailChip("Resources", "\(plan.resources.count)")
                detailChip("Calendars", "\(plan.calendars.count)")
                detailChip("Sprints", "\(plan.sprints.count)")
                detailChip("Snapshots", "\(plan.statusSnapshots.count)")
                detailChip("Workflows", "\(plan.workflowColumns.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlanID = plan.portfolioID
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func detailChip(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }

    private func scopeMatches(_ plan: PortfolioProjectPlan) -> Bool {
        switch registryScope {
        case .all:
            return true
        case .active:
            return !plan.isArchivedValue
        case .archived:
            return plan.isArchivedValue
        }
    }

    private func normalizeArchiveFlags() {
        for plan in plans where plan.isArchived == nil {
            plan.isArchived = false
        }
        try? modelContext.save()
    }

    private func searchMatches(_ plan: PortfolioProjectPlan) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        let haystack = [
            plan.title,
            plan.company,
            plan.manager,
            plan.boardColumns.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        return haystack.contains(query)
    }

    private func syncSelectedPlan() {
        if let activePortfolioID, plans.contains(where: { $0.portfolioID == activePortfolioID }) {
            selectedPlanID = activePortfolioID
            return
        }

        if let selectedPlanID, plans.contains(where: { $0.portfolioID == selectedPlanID }) {
            return
        }

        selectedPlanID = visiblePlans.first?.portfolioID ?? plans.first?.portfolioID
    }

    private func openPlanInWorkspace(_ plan: PortfolioProjectPlan) {
        activePortfolioID = plan.portfolioID
        selectedPlanID = plan.portfolioID
    }

    private func toggleArchive(for plan: PortfolioProjectPlan) {
        plan.isArchived = !(plan.isArchivedValue)
        plan.updatedAt = Date()
        try? modelContext.save()
        if plan.isArchivedValue, activePortfolioID == plan.portfolioID {
            activePortfolioID = visiblePlans.first?.portfolioID
        }
        syncSelectedPlan()
    }

    private func deletePortfolioPlan(_ plan: PortfolioProjectPlan) {
        let deletedID = plan.portfolioID
        modelContext.delete(plan)
        try? modelContext.save()
        if activePortfolioID == deletedID {
            activePortfolioID = visiblePlans.first(where: { $0.portfolioID != deletedID })?.portfolioID
        }
        selectedPlanID = visiblePlans.first?.portfolioID
    }

    private func createBlankPortfolioPlan() {
        let nativePlan = NativeProjectPlan.empty()
        do {
            try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: modelContext)
            activePortfolioID = nativePlan.portfolioID
            selectedPlanID = nativePlan.portfolioID
            importStatusMessage = "Created new portfolio plan."
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func importPortfolioPlans(from urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await MainActor.run {
            isImporting = true
            importErrorMessage = nil
            importStatusMessage = "Importing \(urls.count) plan(s)..."
        }

        let converter = MPPConverterService()
        var importedTitles: [String] = []
        var failedNames: [String] = []

        for url in urls {
            do {
                let nativePlan = try await loadNativePlan(from: url, converter: converter)
                try await MainActor.run {
                    try PortfolioProjectSynchronizer.upsert(nativePlan: nativePlan, in: modelContext)
                    activePortfolioID = nativePlan.portfolioID
                    selectedPlanID = nativePlan.portfolioID
                    importedTitles.append(trimmedOrFallback(nativePlan.title, fallback: url.lastPathComponent))
                }
            } catch {
                failedNames.append(url.lastPathComponent)
            }
        }

        await MainActor.run {
            isImporting = false
            if !failedNames.isEmpty {
                importErrorMessage = "Some files failed to import: \(failedNames.joined(separator: ", "))"
            } else if importedTitles.isEmpty {
                importErrorMessage = "No plans were imported."
            } else {
                importStatusMessage = "Imported \(importedTitles.count) plan(s): \(importedTitles.joined(separator: ", "))"
            }
        }
    }

    private func loadNativePlan(from url: URL, converter: MPPConverterService) async throws -> NativeProjectPlan {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let extensionLower = url.pathExtension.lowercased()
        if extensionLower == "mppplan" || extensionLower == "json" || extensionLower == "nativeplan" {
            do {
                let data = try Data(contentsOf: url)
                return try NativeProjectPlan.decode(from: data)
            } catch {
                // If this file is actually an MPP file with one of these extensions,
                // fall through to converter path.
            }
        }

        let data = try await converter.convert(mppFileURL: url)
        let projectModel = try await JSONProjectParser.parseDetached(jsonData: data)
        return NativeProjectPlan(projectModel: projectModel)
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func taskSnapshots(for plan: PortfolioProjectPlan) -> [TaskSnapshot] {
        let planTitle = trimmedOrFallback(plan.title, fallback: "Untitled Plan")
        return plan.nativeTasksForUI.map { task in
            TaskSnapshot(
                id: "\(plan.portfolioID.uuidString)-\(task.id)",
                planID: plan.portfolioID,
                planTitle: planTitle,
                name: trimmedOrFallback(task.name, fallback: "Untitled Task"),
                boardStatus: task.boardStatus,
                finishDate: task.normalizedFinishDate,
                isActive: task.isActive,
                percentComplete: task.percentComplete
            )
        }
    }
}
