import SwiftUI
import AppKit
import SwiftData

/// Clipboard payload for copying plan-builder rows within the app. Carries the
/// full task subtree plus its assignments so paste can recreate them faithfully.
struct PlannerClipboardPayload: Codable {
    static let pasteboardType = NSPasteboard.PasteboardType("com.planroom.plantasks")
    var tasks: [NativePlanTask]
    var assignments: [NativePlanAssignment]
}

struct PlanEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    let planModel: PortfolioProjectPlan
    @State private var plan: NativeProjectPlan
    @State private var suppressUndoRegistration = false
    @State private var analysis: NativePlanAnalysis
    @State private var isInitializing = true
    @State private var hasInitialized = false
    @State private var analysisRefreshWorkItem: DispatchWorkItem?
    @State private var persistenceWorkItem: DispatchWorkItem?
    @State private var dirtyTaskIDs: Set<Int> = []
    @State private var metadataNeedsFullSync = false
    @State private var inspectorTaskDraft: NativePlanTask?
    @State private var newCustomFieldName = ""
    @State private var pendingCustomFieldRemoval: String?
    @AppStorage("plannerGridHiddenColumns") private var plannerGridHiddenColumnsRaw = ""
    @AppStorage("plannerGridCustomColumns") private var plannerGridCustomColumnsRaw = ""
    @AppStorage("plannerGridExtraColumns") private var plannerGridExtraColumnsRaw = ""
    @State private var showGridColumnPicker = false
    @State private var inspectorTaskDraftWorkItem: DispatchWorkItem?
    @State private var inspectorTaskDraftNeedsReschedule = false
    @State private var inspectorTaskDraftIsDirty = false
    @State private var inspectorAssignmentDrafts: [NativePlanAssignment] = []
    @State private var inspectorAssignmentDraftWorkItem: DispatchWorkItem?
    @State private var inspectorAssignmentDraftsAreDirty = false
    @State private var gridRowModels: [PlannerGridRowModel] = []
    @State private var gridResourceOptions: [PlannerGridResourceOption] = []
    @State private var gridTextDrafts: [PlannerGridCellKey: String] = [:]
    @State private var gridAssignmentDrafts: [Int: PlannerGridAssignmentDraft] = [:]
    @State private var gridDraftCommitWorkItem: DispatchWorkItem?
    @State private var collapsedGridTaskIDs: Set<Int> = []
    @State private var refreshCounter = 0
    @State private var lastObservedPlanHash = 0
    @State private var planSummaryMetrics: PlannerSummaryMetrics = .empty
    @State private var planSignalCounts: PlannerSignalCounts = .empty
    @State private var taskIndexByID: [Int: Int] = [:]
    @State private var validTaskIDs: Set<Int> = []
    @State private var assignmentIndicesByTaskID: [Int: [Int]] = [:]
    @State private var pendingGridRefresh = false
    @State private var pendingAnalysisRefresh = false
    @State private var pendingFullGridRefresh = false
    @State private var pendingChangedGridTaskIDs: Set<Int> = []
    @State private var gridRowModelCache: [Int: PlannerGridRowModel] = [:]
    @State private var latestRescheduleGeneration = 0

    @State private var selectedTaskID: Int?
    @State private var pendingGridFocusTarget: PlannerGridFocusTarget?
    @State private var inspectorWidth: CGFloat = 320
    @State private var inspectorDragStartWidth: CGFloat?
    @State private var taskImportSession: CSVTaskImportSession?
    @State private var lastTaskImportSession: CSVTaskImportSession?
    @State private var assignmentImportSession: CSVAssignmentImportSession?
    @State private var lastAssignmentImportSession: CSVAssignmentImportSession?
    @State private var dependencyImportSession: CSVDependencyImportSession?
    @State private var lastDependencyImportSession: CSVDependencyImportSession?
    @State private var constraintImportSession: CSVConstraintImportSession?
    @State private var lastConstraintImportSession: CSVConstraintImportSession?
    @State private var baselineImportSession: CSVBaselineImportSession?
    @State private var lastBaselineImportSession: CSVBaselineImportSession?
    @State private var importReport: CSVImportReport?
    @State private var assignmentImportReport: CSVImportReport?
    @State private var dependencyImportReport: CSVImportReport?
    @State private var constraintImportReport: CSVImportReport?
    @State private var baselineImportReport: CSVImportReport?

    private let minimumTaskNameColumnWidth: CGFloat = 104
    private let idColumnWidth: CGFloat = 46
    private let startColumnWidth: CGFloat = 110
    private let finishColumnWidth: CGFloat = 110
    private let durationColumnWidth: CGFloat = 51
    private let percentColumnWidth: CGFloat = 51
    private let milestoneColumnWidth: CGFloat = 76
    private let predecessorsColumnWidth: CGFloat = 91
    private let resourceColumnWidth: CGFloat = 122
    private let assignmentUnitsColumnWidth: CGFloat = 62
    private let dividerWidth: CGFloat = 10
    private let minimumGridWidth: CGFloat = 420
    private let minimumInspectorWidth: CGFloat = 260
    private let supportedConstraintTypes = ["ASAP", "SNET", "FNET", "MSO", "MFO"]
    private let agileTypes = ["Epic", "Feature", "Story", "Bug", "Task", "Milestone"]
    private let boardStatuses = ["Backlog", "Ready", "In Progress", "Review", "Done"]

    private var selectedTaskIndex: Int? {
        guard let selectedTaskID else { return nil }
        return taskIndex(for: selectedTaskID)
    }

    private var visibleGridRowModels: [PlannerGridRowModel] {
        var visibleRows: [PlannerGridRowModel] = []
        var collapsedOutlineLevel: Int?

        for row in gridRowModels {
            if let hiddenLevel = collapsedOutlineLevel {
                if row.outlineLevel > hiddenLevel {
                    continue
                }
                collapsedOutlineLevel = nil
            }

            visibleRows.append(row)

            if row.isSummary && collapsedGridTaskIDs.contains(row.id) {
                collapsedOutlineLevel = row.outlineLevel
            }
        }

        return visibleRows
    }

    private var canExpandGridTasks: Bool {
        !collapsedGridTaskIDs.isEmpty
    }

    private var canCollapseGridTasks: Bool {
        gridRowModels.contains { $0.isSummary && !collapsedGridTaskIDs.contains($0.id) }
    }

    private var currentProject: ProjectModel {
        analysis.project
    }

    private var currentProjectEVM: EVMMetrics {
        analysis.evm
    }

    private var validationIssues: [ProjectValidationIssue] {
        analysis.validationIssues
    }

    private var diagnosticItems: [ProjectDiagnosticItem] {
        analysis.diagnosticItems
    }

    init(planModel: PortfolioProjectPlan, initialPlan: NativeProjectPlan? = nil) {
        let initialPlan = initialPlan ?? planModel.editorSnapshotForUI()
        self.planModel = planModel
        self._plan = State(initialValue: initialPlan)
        self._analysis = State(initialValue: NativePlanAnalysis.placeholder)
        self._planSummaryMetrics = State(initialValue: PlannerSummaryMetrics.build(from: initialPlan))
        self._taskIndexByID = State(initialValue: PlannerPlanLookup.taskIndexByID(in: initialPlan.tasks))
        self._validTaskIDs = State(initialValue: PlannerPlanLookup.taskIDs(in: initialPlan.tasks))
        self._assignmentIndicesByTaskID = State(initialValue: PlannerPlanLookup.assignmentIndicesByTaskID(in: initialPlan.assignments))
    }

    private var selectedTaskValidationIssues: [ProjectValidationIssue] {
        guard let selectedTaskID else { return [] }
        return validationIssues.filter { $0.taskUniqueID == selectedTaskID }
    }

    private var selectedTaskDiagnosticItems: [ProjectDiagnosticItem] {
        guard let selectedTaskID else { return [] }
        return diagnosticItems.filter { $0.taskUniqueID == selectedTaskID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isInitializing {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparing plan data...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let totalWidth = max(geometry.size.width, 1)
                    let currentInspectorWidth = clampedInspectorWidth(for: totalWidth)
                    let gridWidth = max(minimumGridWidth, totalWidth - currentInspectorWidth - dividerWidth)

                    HStack(spacing: 0) {
                        taskListPane()
                            .frame(width: gridWidth)

                        splitHandle(totalWidth: totalWidth)

                        inspectorPane
                            .frame(width: currentInspectorWidth)
                    }
                    .frame(width: totalWidth, height: geometry.size.height, alignment: .topLeading)
                }
            }
        }
        .sheet(item: $taskImportSession) { session in
            TaskCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyTaskImport(mappedSession, into: plan) {
                        plan = result.plan
                        selectedTaskID = plan.tasks.last?.id
                        lastTaskImportSession = mappedSession
                        importReport = result.report
                        notePlanMutation(needsGrid: true, needsAnalysis: true)
                    }
                    taskImportSession = nil
                },
                onCancel: {
                    taskImportSession = nil
                }
            )
        }
        .sheet(item: $assignmentImportSession) { session in
            AssignmentCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyAssignmentImport(mappedSession, into: plan) {
                        plan = result.plan
                        lastAssignmentImportSession = mappedSession
                        assignmentImportReport = result.report
                        notePlanMutation(needsGrid: true, needsAnalysis: true)
                    }
                    assignmentImportSession = nil
                },
                onCancel: {
                    assignmentImportSession = nil
                }
            )
        }
        .sheet(item: $dependencyImportSession) { session in
            DependencyCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyDependencyImport(mappedSession, into: plan) {
                        plan = result.plan
                        lastDependencyImportSession = mappedSession
                        dependencyImportReport = result.report
                        notePlanMutation(needsGrid: true, needsAnalysis: true)
                    }
                    dependencyImportSession = nil
                },
                onCancel: {
                    dependencyImportSession = nil
                }
            )
        }
        .sheet(item: $constraintImportSession) { session in
            ConstraintCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyConstraintImport(mappedSession, into: plan) {
                        plan = result.plan
                        lastConstraintImportSession = mappedSession
                        constraintImportReport = result.report
                        notePlanMutation(needsGrid: true, needsAnalysis: true)
                    }
                    constraintImportSession = nil
                },
                onCancel: {
                    constraintImportSession = nil
                }
            )
        }
        .sheet(item: $baselineImportSession) { session in
            BaselineCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyBaselineImport(mappedSession, into: plan) {
                        plan = result.plan
                        lastBaselineImportSession = mappedSession
                        baselineImportReport = result.report
                        notePlanMutation(needsGrid: true, needsAnalysis: true)
                    }
                    baselineImportSession = nil
                },
                onCancel: {
                    baselineImportSession = nil
                }
            )
        }
        .sheet(item: $importReport) { report in
            importReportSheet(
                report: report,
                secondaryActionTitle: lastTaskImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenTaskImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: fixTaskImportIssue
            ) {
                importReport = nil
            }
        }
        .sheet(item: $dependencyImportReport) { report in
            importReportSheet(
                report: report,
                secondaryActionTitle: lastDependencyImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenDependencyImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil
            ) {
                    dependencyImportReport = nil
                }
        }
        .sheet(item: $constraintImportReport) { report in
            importReportSheet(
                report: report,
                secondaryActionTitle: lastConstraintImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenConstraintImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil
            ) {
                    constraintImportReport = nil
                }
        }
        .sheet(item: $baselineImportReport) { report in
            importReportSheet(
                report: report,
                secondaryActionTitle: lastBaselineImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenBaselineImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil
            ) {
                    baselineImportReport = nil
                }
        }
        .sheet(item: $assignmentImportReport) { report in
            importReportSheet(
                report: report,
                secondaryActionTitle: lastAssignmentImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenAssignmentImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil
            ) {
                    assignmentImportReport = nil
                }
        }
        .task {
            await initializePlanEditorIfNeeded()
        }
        .onChange(of: refreshCounter) { _, _ in
            handleRefreshCounterChange()
        }
        .onChange(of: selectedTaskID) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if hasPendingInspectorChanges(for: oldValue) {
                Task { @MainActor in
                    commitInspectorEdits()
                }
            }
            syncInspectorTaskDraft(force: true)
            syncInspectorAssignmentDrafts(force: true)
        }
        .onChange(of: plan.title) { _, _ in
            markMetadataDirty()
            schedulePlanPersistence()
        }
        .onChange(of: plan.manager) { _, _ in
            markMetadataDirty()
            schedulePlanPersistence()
        }
        .onChange(of: plan.company) { _, _ in
            markMetadataDirty()
            schedulePlanPersistence()
        }
        .onChange(of: plan.statusDate) { _, _ in
            markMetadataDirty()
            schedulePlanPersistence()
            notePlanMutation(needsGrid: true, needsAnalysis: true)
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            syncPlanFromModelIfNeeded()
        }
        .onChange(of: plan) { oldPlan, _ in
            registerPlanUndo(from: oldPlan)
        }
        .onDisappear {
            commitInspectorEdits()
            persistPlanImmediately()
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func reopenTaskImportMapping() {
        guard let session = lastTaskImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            taskImportSession = session
        }
    }

    private func importReportSheet(
        report: CSVImportReport,
        secondaryActionTitle: String?,
        onSecondaryAction: (() -> Void)?,
        onSelectIssue: ((CSVImportIssue) -> Void)?,
        onFixIssue: ((CSVImportIssue) -> Void)?,
        onClose: @escaping () -> Void
    ) -> some View {
        CSVImportReportSheet(
            report: report,
            secondaryActionTitle: secondaryActionTitle,
            onSecondaryAction: onSecondaryAction,
            onSelectIssue: onSelectIssue,
            onFixIssue: onFixIssue,
            onClose: onClose
        )
    }

    private func reopenAssignmentImportMapping() {
        guard let session = lastAssignmentImportSession else { return }
        assignmentImportReport = nil
        DispatchQueue.main.async {
            assignmentImportSession = session
        }
    }

    private func reopenDependencyImportMapping() {
        guard let session = lastDependencyImportSession else { return }
        dependencyImportReport = nil
        DispatchQueue.main.async {
            dependencyImportSession = session
        }
    }

    private func reopenConstraintImportMapping() {
        guard let session = lastConstraintImportSession else { return }
        constraintImportReport = nil
        DispatchQueue.main.async {
            constraintImportSession = session
        }
    }

    private func reopenBaselineImportMapping() {
        guard let session = lastBaselineImportSession else { return }
        baselineImportReport = nil
        DispatchQueue.main.async {
            baselineImportSession = session
        }
    }

    private func selectImportedTaskIssue(_ issue: CSVImportIssue) {
        guard let targetID = issue.targetID, taskIndex(for: targetID) != nil else { return }
        PerformanceMonitor.mark("PlanEditor.SelectImportIssue", message: "task \(targetID)")
        selectedTaskID = targetID
        importReport = nil
        assignmentImportReport = nil
        dependencyImportReport = nil
        constraintImportReport = nil
        baselineImportReport = nil
    }

    private func fixTaskImportIssue(_ issue: CSVImportIssue) {
        guard let fixAction = issue.fixAction else { return }

        switch fixAction {
        case let .createTaskCalendar(name, taskID):
            let calendarID = ensureCalendar(named: name)
            if let taskIndex = taskIndex(for: taskID) {
                plan.tasks[taskIndex].calendarUniqueID = calendarID
                selectedTaskID = taskID
                reschedulePlan(changedTaskIDs: [taskID])
                removeIssueFromReport(issue.id)
            }
        default:
            break
        }
    }

    private func ensureCalendar(named name: String) -> Int {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = plan.calendars.first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }) {
            return existing.id
        }

        let calendar = plan.makeCalendar(name: name)
        plan.calendars.append(calendar)
        notePlanMutation(needsGrid: true, needsAnalysis: true)
        return calendar.id
    }

    private func removeIssueFromReport(_ issueID: UUID) {
        guard let report = importReport else { return }
        let remaining = report.issues.filter { $0.id != issueID }
        importReport = CSVImportReport(title: report.title, summaryLines: report.summaryLines, issues: remaining)
    }

    private var header: some View {
        PlannerHeaderView(
            title: $plan.title,
            manager: $plan.manager,
            company: $plan.company,
            statusDate: $plan.statusDate,
            metrics: [
                .init(value: "\(planSummaryMetrics.taskCount)", label: "Tasks"),
                .init(value: "\(planSummaryMetrics.sprintCount)", label: "Sprints"),
                .init(value: "\(planSummaryMetrics.totalStoryPoints)", label: "Points"),
                .init(value: "\(planSummaryMetrics.milestoneCount)", label: "Milestones"),
                .init(value: "\(planSummaryMetrics.dependencyCount)", label: "Dependencies"),
                .init(value: "\(planSummaryMetrics.baselineCount)", label: "Baselined"),
                .init(value: currencyText(analysis.headerMetrics.plannedCost), label: "Planned Cost"),
                .init(value: currencyText(analysis.headerMetrics.bac), label: "BAC"),
                .init(value: currencyText(analysis.headerMetrics.actualCost), label: "Actual Cost"),
                .init(value: safeRatioText(analysis.headerMetrics.cpi), label: "CPI"),
                .init(value: safeRatioText(analysis.headerMetrics.spi), label: "SPI"),
                .init(value: currencyText(analysis.headerMetrics.eac), label: "EAC")
            ],
            signalChips: [
                .init(title: "Errors", count: planSignalCounts.errorCount, color: .red),
                .init(title: "Warnings", count: planSignalCounts.warningCount, color: .orange),
                .init(title: "Info", count: planSignalCounts.infoCount, color: .blue),
                .init(title: "Diagnostics", count: planSignalCounts.diagnosticCount, color: .purple)
            ]
        )
    }

    private func taskListPane() -> some View {
        PlannerTaskListPane(
            tasksEmpty: plan.tasks.isEmpty,
            resources: plan.resources,
            selectedTaskAvailable: selectedTaskIndex != nil,
            canIndent: canIndentSelectedTask(),
            canOutdent: canOutdentSelectedTask(),
            canMoveUp: canMoveSelectedTaskUp(),
            canMoveDown: canMoveSelectedTaskDown(),
            canExpandTasks: canExpandGridTasks,
            canCollapseTasks: canCollapseGridTasks,
            rowModels: visibleGridRowModels,
            gridLayoutForWidth: gridLayout(for:),
            onImportTasks: { taskImportSession = CSVExporter.selectTaskImportSession() },
            onImportAssignments: { assignmentImportSession = CSVExporter.selectAssignmentImportSession() },
            onImportDependencies: { dependencyImportSession = CSVExporter.selectDependencyImportSession() },
            onImportConstraints: { constraintImportSession = CSVExporter.selectConstraintImportSession() },
            onImportBaseline: { baselineImportSession = CSVExporter.selectBaselineImportSession() },
            onExportTaskTemplateCSV: CSVExporter.exportTaskImportTemplateCSV,
            onExportTaskTemplateExcel: CSVExporter.exportTaskImportTemplateExcel,
            onExportAssignmentTemplateCSV: CSVExporter.exportAssignmentImportTemplateCSV,
            onExportAssignmentTemplateExcel: CSVExporter.exportAssignmentImportTemplateExcel,
            onExportDependencyTemplateCSV: CSVExporter.exportDependencyImportTemplateCSV,
            onExportDependencyTemplateExcel: CSVExporter.exportDependencyImportTemplateExcel,
            onExportConstraintTemplateCSV: CSVExporter.exportConstraintImportTemplateCSV,
            onExportConstraintTemplateExcel: CSVExporter.exportConstraintImportTemplateExcel,
            onExportBaselineTemplateCSV: CSVExporter.exportBaselineImportTemplateCSV,
            onExportBaselineTemplateExcel: CSVExporter.exportBaselineImportTemplateExcel,
            onCaptureBaseline: {
                plan.captureBaseline()
                notePlanMutation(needsGrid: true, needsAnalysis: true)
            },
            onExportMSPDI: { MSPDIExporter.exportWithSavePanel(plan: plan) },
            onAddTask: { addTask(focus: .name) },
            onIndent: indentSelectedTask,
            onOutdent: outdentSelectedTask,
            onDuplicate: duplicateSelectedTask,
            onMoveUp: moveSelectedTaskUp,
            onMoveDown: moveSelectedTaskDown,
            onDelete: deleteSelectedTask,
            onExpandTasks: expandAllGridTasks,
            onCollapseTasks: collapseAllGridTasks,
            onInsertAbove: insertRowAboveSelection,
            onInsertBelow: insertRowBelowSelection,
            onCopyRows: copySelectedRows,
            onPasteRows: pasteRows,
            makeHeader: taskGridHeader(layout:),
            makeRow: taskGridRow(row:layout:)
        )
    }

    private func splitHandle(totalWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)

            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 4, height: 36)
        }
        .frame(width: dividerWidth)
        .cursor(.resizeLeftRight)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let startingWidth = inspectorDragStartWidth ?? clampedInspectorWidth(for: totalWidth)
                    if inspectorDragStartWidth == nil {
                        inspectorDragStartWidth = startingWidth
                    }
                    inspectorWidth = clampedInspectorWidth(startingWidth - value.translation.width, totalWidth: totalWidth)
                }
                .onEnded { _ in
                    inspectorDragStartWidth = nil
                }
        )
        // Double-click the divider to reset the details pane to a sensible
        // default, matching native HSplitView behavior.
        .onTapGesture(count: 2) {
            withAnimation(.easeOut(duration: 0.15)) {
                inspectorWidth = clampedInspectorWidth(380, totalWidth: totalWidth)
            }
        }
        .help("Drag to resize · double-click to reset the details pane")
    }

    private func taskGridHeader(layout: PlannerGridLayout) -> some View {
        HStack(spacing: 0) {
            taskHeaderCell("ID", width: layout.id, alignment: .leading)
            taskHeaderCell("Task Name", width: layout.name, alignment: .leading)
            if layout.start > 0 { taskHeaderCell("Start", width: layout.start, alignment: .leading) }
            if layout.finish > 0 { taskHeaderCell("Finish", width: layout.finish, alignment: .leading) }
            if layout.duration > 0 { taskHeaderCell("Dur", width: layout.duration, alignment: .center) }
            if layout.percent > 0 { taskHeaderCell("%", width: layout.percent, alignment: .center) }
            if layout.milestone > 0 { taskHeaderCell("Milestone", width: layout.milestone, alignment: .center) }
            if layout.predecessors > 0 { taskHeaderCell("Preds", width: layout.predecessors, alignment: .leading) }
            if layout.resource > 0 { taskHeaderCell("Resource", width: layout.resource, alignment: .leading) }
            if layout.assignmentUnits > 0 { taskHeaderCell("Units", width: layout.assignmentUnits, alignment: .center) }
            ForEach(Array(layout.extraColumns.enumerated()), id: \.offset) { index, name in
                taskHeaderCell(name, width: layout.extraWidths[index], alignment: .leading)
            }
            ForEach(layout.customColumns, id: \.self) { name in
                taskHeaderCell(name, width: layout.custom, alignment: .leading)
            }
        }
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            gridColumnPickerButton
                .padding(.trailing, 4)
        }
    }

    private var gridColumnPickerButton: some View {
        Button {
            showGridColumnPicker.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Choose which columns are visible in the grid")
        .popover(isPresented: $showGridColumnPicker) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grid Columns")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.bottom, 4)
                ForEach(Self.hideableGridColumns, id: \.key) { column in
                    Toggle(column.title, isOn: Binding(
                        get: { !hiddenGridColumns.contains(column.key) },
                        set: { setGridColumn(column.key, hidden: !$0) }
                    ))
                    .font(.caption)
                }

                Text("More Columns")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ForEach(Self.optionalGridColumns, id: \.key) { column in
                    Toggle(column.key, isOn: Binding(
                        get: { visibleExtraGridColumns.contains(column.key) },
                        set: { setGridExtraColumn(column.key, visible: $0) }
                    ))
                    .font(.caption)
                }

                if !planCustomFieldNames.isEmpty {
                    Text("Custom Fields")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    ForEach(planCustomFieldNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { visibleGridCustomColumns.contains(name) },
                            set: { setGridCustomColumn(name, visible: $0) }
                        ))
                        .font(.caption)
                    }
                }
            }
            .padding()
            .frame(minWidth: 170)
        }
    }

    private func taskGridRow(row: PlannerGridRowModel, layout: PlannerGridLayout) -> some View {
        let liveTaskIndex = taskIndex(for: row.id)
        let liveTask = liveTaskIndex.flatMap { plan.tasks.indices.contains($0) ? plan.tasks[$0] : nil }
        return PlannerGridRowView(
            row: row,
            layout: layout,
            isSelected: selectedTaskID == row.id,
            isCollapsed: collapsedGridTaskIDs.contains(row.id),
            resourceOptions: gridResourceOptions,
            nameValue: gridTextDrafts[PlannerGridCellKey(taskID: row.id, column: .name)] ?? row.name,
            startDateValue: liveTask?.startDate ?? row.startDate,
            finishDateValue: liveTask?.normalizedFinishDate ?? row.finishDate,
            durationValue: gridTextDrafts[PlannerGridCellKey(taskID: row.id, column: .duration)] ?? row.durationText,
            percentValue: gridTextDrafts[PlannerGridCellKey(taskID: row.id, column: .percent)] ?? row.percentText,
            milestoneValue: liveTask?.isMilestone ?? row.isMilestone,
            predecessorsValue: gridTextDrafts[PlannerGridCellKey(taskID: row.id, column: .predecessors)] ?? row.predecessorText,
            primaryAssignmentResourceIDValue: gridAssignmentDrafts[row.id].map(\.resourceID) ?? row.primaryAssignmentResourceID,
            primaryAssignmentUnitsValue: {
                if let draft = gridAssignmentDrafts[row.id] {
                    return draft.resourceID == nil ? "" : String(Int(draft.units))
                }
                return row.primaryAssignmentUnitsText
            }(),
            nameText: gridTextBinding(taskID: row.id, column: .name, fallback: row.name),
            startDate: startDateBinding(for: row.id, fallback: row.startDate),
            finishDate: finishDateBinding(for: row.id, fallback: row.finishDate),
            durationText: gridTextBinding(taskID: row.id, column: .duration, fallback: row.durationText),
            percentText: gridTextBinding(taskID: row.id, column: .percent, fallback: row.percentText),
            milestone: milestoneBinding(for: row.id, fallback: row.isMilestone),
            predecessorsText: gridTextBinding(taskID: row.id, column: .predecessors, fallback: row.predecessorText),
            primaryAssignmentResourceID: primaryAssignmentResourceBinding(for: row.id, fallback: row.primaryAssignmentResourceID),
            primaryAssignmentUnitsText: primaryAssignmentUnitsTextBinding(for: row.id, fallback: row.primaryAssignmentUnitsText),
            customValues: layout.customColumns.map { liveTask?.customFields[$0] ?? "" },
            onCommitCustomField: { fieldName, value in
                updateTaskCustomField(taskID: row.id, fieldName: fieldName, value: value)
            },
            extraValues: layout.extraColumns.map { extraGridColumnValue($0, task: liveTask) },
            onCommitExtraColumn: { columnName, value in
                updateTaskExtraColumn(taskID: row.id, columnName: columnName, value: value)
            },
            shouldFocusName: shouldFocus(taskID: row.id, column: .name),
            shouldFocusDuration: shouldFocus(taskID: row.id, column: .duration),
            shouldFocusPercent: shouldFocus(taskID: row.id, column: .percent),
            shouldFocusPredecessors: shouldFocus(taskID: row.id, column: .predecessors),
            shouldFocusAssignmentUnits: shouldFocus(taskID: row.id, column: .assignmentUnits),
            onCommitName: { commitGridDrafts() },
            onCommitDuration: { commitGridDrafts(reschedule: true) },
            onCommitPercent: { commitGridDrafts() },
            onCommitPredecessors: { commitGridDrafts(reschedule: true) },
            onCommitAssignmentUnits: { commitGridDrafts() },
            onReturnFromName: { moveDownInGrid(fromTaskID: row.id, column: .name) },
            onReturnFromDuration: { moveDownInGrid(fromTaskID: row.id, column: .duration) },
            onReturnFromPercent: { moveDownInGrid(fromTaskID: row.id, column: .percent) },
            onReturnFromPredecessors: { moveDownInGrid(fromTaskID: row.id, column: .predecessors) },
            onReturnFromAssignmentUnits: { moveDownInGrid(fromTaskID: row.id, column: .assignmentUnits) },
            onTabFromAssignmentUnits: row.isLastRow ? { addTask(after: row.id, focus: .name) } : nil,
            onFocusName: {
                focusGridTask(row.id)
                clearPendingFocusIfNeeded(taskID: row.id, column: .name)
            },
            onFocusDuration: {
                focusGridTask(row.id)
                clearPendingFocusIfNeeded(taskID: row.id, column: .duration)
            },
            onFocusPercent: {
                focusGridTask(row.id)
                clearPendingFocusIfNeeded(taskID: row.id, column: .percent)
            },
            onFocusPredecessors: {
                focusGridTask(row.id)
                clearPendingFocusIfNeeded(taskID: row.id, column: .predecessors)
            },
            onFocusAssignmentUnits: {
                focusGridTask(row.id)
                clearPendingFocusIfNeeded(taskID: row.id, column: .assignmentUnits)
            },
            onToggleCollapse: {
                toggleGridTaskCollapse(row.id)
            },
            onTap: {
                selectedTaskID = row.id
            }
        )
        .equatable()
    }

    private var inspectorPane: some View {
        Group {
            if let taskDraft = inspectorTaskDraft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Task Basics") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField(
                                    "Task Name",
                                    text: inspectorTaskDraftBinding(
                                        defaultValue: "",
                                        get: { $0.name },
                                        set: { $0.name = $1 }
                                    )
                                )
                                    .textFieldStyle(.roundedBorder)

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Start")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PlannerDateField(
                                        date: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.startDate,
                                            get: { $0.startDate },
                                            set: { task, newValue in
                                                let normalized = Calendar.current.startOfDay(for: newValue)
                                                task.startDate = normalized

                                                if task.isMilestone {
                                                    task.finishDate = normalized
                                                } else if task.manuallyScheduled {
                                                    task.finishDate = finishDateForDuration(
                                                        task: task,
                                                        startDate: normalized,
                                                        durationDays: task.durationDays
                                                    )
                                                } else if task.finishDate < normalized {
                                                    task.finishDate = normalized
                                                }
                                            },
                                            reschedule: true
                                        )
                                    )
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Finish")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PlannerDateField(
                                        date: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.normalizedFinishDate,
                                            get: { $0.normalizedFinishDate },
                                            set: { task, newValue in
                                                let normalized = max(Calendar.current.startOfDay(for: newValue), task.startDate)
                                                if task.isMilestone {
                                                    task.finishDate = task.startDate
                                                } else {
                                                    task.finishDate = normalized
                                                    task.durationDays = max(1, durationDaysFromDates(for: task, finishDate: normalized))
                                                }
                                            },
                                            reschedule: true
                                        )
                                    )
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        outdentSelectedTask()
                                    } label: {
                                        Label("Left", systemImage: "decrease.indent")
                                    }
                                    .buttonStyle(.bordered)
                                    .hoverHighlight()
                                    .disabled(!canOutdentSelectedTask())

                                    Button {
                                        indentSelectedTask()
                                    } label: {
                                        Label("Right", systemImage: "increase.indent")
                                    }
                                    .buttonStyle(.bordered)
                                    .hoverHighlight()
                                    .disabled(!canIndentSelectedTask())
                                }

                                HStack(spacing: 12) {
                                    Toggle(
                                        "Milestone",
                                        isOn: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.isMilestone,
                                            get: { $0.isMilestone },
                                            set: { task, isMilestone in
                                                task.isMilestone = isMilestone
                                                if isMilestone {
                                                    task.finishDate = task.startDate
                                                    task.durationDays = 1
                                                }
                                            },
                                            reschedule: true
                                        )
                                    )
                                    Toggle(
                                        "Active",
                                        isOn: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.isActive,
                                            get: { $0.isActive },
                                            set: { $0.isActive = $1 }
                                        )
                                    )
                                }

                                Toggle(
                                    "Manual Scheduling",
                                    isOn: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.manuallyScheduled,
                                        get: { $0.manuallyScheduled },
                                        set: { task, isManual in
                                            task.manuallyScheduled = isManual
                                            task.durationDays = durationDaysFromDates(for: task)
                                            if task.isMilestone {
                                                task.finishDate = task.startDate
                                            }
                                        },
                                        reschedule: true
                                    )
                                )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Duration (working days)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "1",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.isMilestone ? "0" : String(max(1, taskDraft.durationDays)),
                                            get: { $0.isMilestone ? "0" : String(max(1, $0.durationDays)) },
                                            set: { task, newValue in
                                                let digits = newValue.filter(\.isNumber)
                                                let parsed = Int(digits) ?? (task.isMilestone ? 0 : 1)
                                                task.durationDays = max(1, parsed)

                                                if task.isMilestone {
                                                    task.finishDate = task.startDate
                                                } else if task.manuallyScheduled {
                                                    task.finishDate = finishDateForDuration(
                                                        task: task,
                                                        startDate: task.startDate,
                                                        durationDays: task.durationDays
                                                    )
                                                }
                                            },
                                            reschedule: true
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                if !plan.calendars.isEmpty {
                                    Picker(
                                        "Task Calendar",
                                        selection: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.calendarUniqueID,
                                            get: { $0.calendarUniqueID },
                                            set: { task, newValue in
                                                task.calendarUniqueID = newValue
                                                if task.manuallyScheduled {
                                                    task.durationDays = durationDaysFromDates(for: task)
                                                }
                                            },
                                            reschedule: true
                                        )
                                    ) {
                                        Text("Project Default").tag(Int?.none)
                                        ForEach(plan.calendars) { calendar in
                                            Text(calendar.name).tag(Optional(calendar.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                Picker(
                                    "Constraint",
                                    selection: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.constraintType ?? "ASAP",
                                        get: { $0.constraintType ?? "ASAP" },
                                        set: { task, newValue in
                                            let normalized = newValue == "ASAP" ? nil : newValue
                                            task.constraintType = normalized
                                            if normalized == nil {
                                                task.constraintDate = nil
                                            } else if task.constraintDate == nil {
                                                task.constraintDate = task.startDate
                                            }
                                        },
                                        reschedule: true
                                    )
                                ) {
                                    ForEach(supportedConstraintTypes, id: \.self) { type in
                                        Text(type).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                if (inspectorTaskDraft?.constraintType ?? "ASAP") != "ASAP" {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Constraint Date")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        PlannerDateField(
                                            date: inspectorTaskDraftBinding(
                                                defaultValue: taskDraft.constraintDate ?? taskDraft.startDate,
                                                get: { $0.constraintDate ?? $0.startDate },
                                                set: { task, newValue in
                                                    task.constraintDate = Calendar.current.startOfDay(for: newValue)
                                                },
                                                reschedule: true
                                            )
                                        )
                                    }
                                }

                                Text(taskDraft.manuallyScheduled
                                     ? "Manual tasks keep the entered dates until you change them."
                                     : "Auto-scheduled tasks move when predecessors, duration, or calendars change.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Progress & Priority") {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Complete")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.percentComplete,
                                            get: { $0.percentComplete },
                                            set: { $0.percentComplete = $1 }
                                        ),
                                        in: 0 ... 100,
                                        step: 5
                                    )
                                    Text("\(Int(inspectorTaskDraft?.percentComplete ?? 0))%")
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .monospacedDigit()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Priority")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Stepper(
                                        value: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.priority,
                                            get: { $0.priority },
                                            set: { $0.priority = $1 }
                                        ),
                                        in: 0 ... 1000,
                                        step: 50
                                    ) {
                                        Text("\(inspectorTaskDraft?.priority ?? 0)")
                                            .monospacedDigit()
                                    }
                                }

                                Divider()

                                actualDateEditor(
                                    title: "Actual Start",
                                    date: taskDraft.actualStartDate,
                                    setCurrent: {
                                        mutateInspectorTaskDraft {
                                            $0.actualStartDate = Calendar.current.startOfDay(for: $0.startDate)
                                            if $0.percentComplete == 0 {
                                                $0.percentComplete = 1
                                            }
                                        }
                                    },
                                    clear: {
                                        mutateInspectorTaskDraft {
                                            $0.actualStartDate = nil
                                        }
                                    },
                                    binding: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.actualStartDate ?? taskDraft.startDate,
                                        get: { $0.actualStartDate ?? $0.startDate },
                                        set: { task, newValue in
                                            task.actualStartDate = Calendar.current.startOfDay(for: newValue)
                                            if task.percentComplete == 0 {
                                                task.percentComplete = 1
                                            }
                                        }
                                    )
                                )

                                actualDateEditor(
                                    title: "Actual Finish",
                                    date: taskDraft.actualFinishDate,
                                    setCurrent: {
                                        mutateInspectorTaskDraft {
                                            $0.actualStartDate = $0.actualStartDate ?? Calendar.current.startOfDay(for: $0.startDate)
                                            $0.actualFinishDate = Calendar.current.startOfDay(for: $0.finishDate)
                                            $0.percentComplete = 100
                                        }
                                    },
                                    clear: {
                                        mutateInspectorTaskDraft {
                                            $0.actualFinishDate = nil
                                        }
                                    },
                                    binding: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.actualFinishDate ?? taskDraft.finishDate,
                                        get: { $0.actualFinishDate ?? $0.finishDate },
                                        set: { task, newValue in
                                            let normalized = Calendar.current.startOfDay(for: newValue)
                                            task.actualStartDate = task.actualStartDate ?? task.startDate
                                            task.actualFinishDate = max(task.actualStartDate ?? normalized, normalized)
                                            task.percentComplete = 100
                                        }
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Dependencies") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Predecessor IDs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Example: 1, 3, 7",
                                    text: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.predecessorTaskIDs.sorted().map(String.init).joined(separator: ", "),
                                        get: { $0.predecessorTaskIDs.sorted().map(String.init).joined(separator: ", ") },
                                        set: { task, newValue in
                                            let validIDs = Set(plan.tasks.map(\.id))
                                            let parsed = newValue
                                                .split(separator: ",")
                                                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                                                .filter { $0 != task.id && validIDs.contains($0) }
                                            task.predecessorTaskIDs = Array(Set(parsed)).sorted()
                                        },
                                        reschedule: true
                                    )
                                )
                                    .textFieldStyle(.roundedBorder)
                                Text("Only finish-to-start links are supported in this first planning slice.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Agile") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker(
                                    "Agile Type",
                                    selection: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.agileType,
                                        get: { $0.agileType },
                                        set: { $0.agileType = $1 }
                                    )
                                ) {
                                    ForEach(agileTypes, id: \.self) { type in
                                        Text(type).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker(
                                    "Board Status",
                                    selection: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.boardStatus,
                                        get: { $0.boardStatus },
                                        set: { $0.boardStatus = $1 }
                                    )
                                ) {
                                    ForEach(boardStatuses, id: \.self) { status in
                                        Text(status).tag(status)
                                    }
                                }
                                .pickerStyle(.menu)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Story Points")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "Optional",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.storyPoints.map(String.init) ?? "",
                                            get: { $0.storyPoints.map(String.init) ?? "" },
                                            set: { task, newValue in
                                                let digits = newValue.filter(\.isNumber)
                                                task.storyPoints = digits.isEmpty ? nil : max(0, Int(digits) ?? 0)
                                            }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                Picker(
                                    "Sprint",
                                    selection: inspectorTaskDraftBinding(
                                        defaultValue: taskDraft.sprintID,
                                        get: { $0.sprintID },
                                        set: { $0.sprintID = $1 }
                                    )
                                ) {
                                    Text("Backlog / None").tag(Int?.none)
                                    ForEach(plan.sprints) { sprint in
                                        Text(sprint.name).tag(Optional(sprint.id))
                                    }
                                }
                                .pickerStyle(.menu)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Epic / Theme")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "Example: Customer Experience",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.epicName,
                                            get: { $0.epicName },
                                            set: { $0.epicName = $1 }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Tags")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField(
                                        "Comma separated",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.tags.joined(separator: ", "),
                                            get: { $0.tags.joined(separator: ", ") },
                                            set: { task, newValue in
                                                task.tags = newValue
                                                    .split(separator: ",")
                                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                    .filter { !$0.isEmpty }
                                            }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                }

                                Text("Use agile metadata for backlog, sprint, and board workflows without leaving the native schedule model.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Baseline") {
                            VStack(alignment: .leading, spacing: 10) {
                                if taskDraft.baselineStartDate == nil,
                                   taskDraft.baselineFinishDate == nil,
                                   taskDraft.baselineDurationDays == nil {
                                    Text("No baseline stored for this task yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    baselineField(title: "Baseline Start", value: baselineDateText(taskDraft.baselineStartDate))
                                    baselineField(title: "Baseline Finish", value: baselineDateText(taskDraft.baselineFinishDate))
                                    baselineField(title: "Baseline Duration", value: baselineDurationText(for: taskDraft))
                                    baselineField(title: "Start Variance", value: varianceText(current: taskDraft.startDate, baseline: taskDraft.baselineStartDate))
                                    baselineField(title: "Finish Variance", value: varianceText(current: taskDraft.finishDate, baseline: taskDraft.baselineFinishDate))
                                }

                                Button("Capture Current Plan as Baseline") {
                                    commitInspectorTaskDraft()
                                    plan.captureBaseline()
                                    notePlanMutation(needsGrid: true, needsAnalysis: true)
                                    syncInspectorTaskDraft(force: true)
                                }
                                .buttonStyle(.bordered)
                                .hoverHighlight()
                                .disabled(plan.tasks.isEmpty)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Financials") {
                            VStack(alignment: .leading, spacing: 12) {
                                let summary = financialSummary(for: taskDraft.id)
                                let isSummaryTask = summary.isSummary

                                if isSummaryTask {
                                    Text("Summary task financials roll up from child tasks and assignments.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Fixed Cost")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDecimalTextField(
                                        title: "0",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: decimalText(taskDraft.fixedCost),
                                            get: { decimalText($0.fixedCost) },
                                            set: { task, newValue in
                                                task.fixedCost = max(0, parseDecimalInput(newValue) ?? 0)
                                            }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isSummaryTask)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Baseline Cost Override")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDecimalTextField(
                                        title: "Auto from current plan",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: optionalDecimalText(taskDraft.baselineCost),
                                            get: { optionalDecimalText($0.baselineCost) },
                                            set: { task, newValue in
                                                task.baselineCost = parseDecimalInput(newValue)
                                            }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isSummaryTask)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Actual Cost Override")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDecimalTextField(
                                        title: "Auto from progress and actual work",
                                        text: inspectorTaskDraftBinding(
                                            defaultValue: optionalDecimalText(taskDraft.actualCost),
                                            get: { optionalDecimalText($0.actualCost) },
                                            set: { task, newValue in
                                                task.actualCost = parseDecimalInput(newValue)
                                            }
                                        )
                                    )
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isSummaryTask)
                                }

                                Divider()

                                baselineField(title: "Planned Cost", value: currencyText(summary.plannedCost))
                                baselineField(title: "BAC", value: currencyText(summary.budgetAtCompletion))
                                baselineField(title: "PV", value: currencyText(summary.plannedValue))
                                baselineField(title: "EV", value: currencyText(summary.earnedValue))
                                baselineField(title: "Actual Cost", value: currencyText(summary.actualCost))
                                baselineField(title: "CV", value: currencyText(summary.costVariance))
                                baselineField(title: "SV", value: currencyText(summary.scheduleVariance))
                                baselineField(title: "CPI", value: summary.cpiText)
                                baselineField(title: "SPI", value: summary.spiText)
                                baselineField(title: "EAC", value: currencyText(summary.estimateAtCompletion))
                                baselineField(title: "ETC", value: currencyText(summary.estimateToComplete))
                                baselineField(title: "VAC", value: currencyText(summary.varianceAtCompletion))
                                baselineField(title: "TCPI", value: summary.tcpiText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Planner Signals") {
                            VStack(alignment: .leading, spacing: 12) {
                                if selectedTaskValidationIssues.isEmpty && selectedTaskDiagnosticItems.isEmpty {
                                    Text("No active validation or diagnostic signals for the selected task.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(selectedTaskValidationIssues) { issue in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label(issue.rule, systemImage: issue.severity.icon)
                                                .foregroundStyle(issue.severity.color)
                                            Text(issue.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    ForEach(selectedTaskDiagnosticItems) { item in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label(item.title, systemImage: item.category.icon)
                                                .foregroundStyle(item.category.color)
                                            Text(item.message)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Assignments") {
                            VStack(alignment: .leading, spacing: 12) {
                                if plan.resources.isEmpty {
                                    Text("Add resources in the Resources screen before assigning work to tasks.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    let assignmentDrafts = inspectorAssignmentDrafts

                                    if assignmentDrafts.isEmpty {
                                        Text("No resources assigned yet.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(assignmentDrafts.indices, id: \.self) { assignmentDraftIndex in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Picker(
                                                    "Resource",
                                                    selection: inspectorAssignmentDraftBinding(
                                                        at: assignmentDraftIndex,
                                                        defaultValue: assignmentDrafts[assignmentDraftIndex].resourceID,
                                                        get: { $0.resourceID },
                                                        set: { $0.resourceID = $1 }
                                                    )
                                                ) {
                                                    Text("Unassigned").tag(Int?.none)
                                                    ForEach(plan.resources) { resource in
                                                        Text(resource.name).tag(Optional(resource.id))
                                                    }
                                                }
                                                .pickerStyle(.menu)

                                                HStack(spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Units")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        Slider(
                                                            value: inspectorAssignmentDraftBinding(
                                                                at: assignmentDraftIndex,
                                                                defaultValue: assignmentDrafts[assignmentDraftIndex].units,
                                                                get: { $0.units },
                                                                set: { $0.units = max(0, $1) }
                                                            ),
                                                            in: 0 ... 300,
                                                            step: 25
                                                        )
                                                    }

                                                    Text("\(Int(assignmentDrafts[assignmentDraftIndex].units))%")
                                                        .monospacedDigit()
                                                        .frame(width: 52, alignment: .trailing)
                                                }

                                                TextField(
                                                    "Assignment Notes",
                                                    text: inspectorAssignmentDraftBinding(
                                                        at: assignmentDraftIndex,
                                                        defaultValue: assignmentDrafts[assignmentDraftIndex].notes,
                                                        get: { $0.notes },
                                                        set: { $0.notes = $1 }
                                                    )
                                                )
                                                    .textFieldStyle(.roundedBorder)

                                                HStack(spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Work (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField(
                                                            "Auto",
                                                            text: inspectorAssignmentDraftBinding(
                                                                at: assignmentDraftIndex,
                                                                defaultValue: hoursText(from: assignmentDrafts[assignmentDraftIndex].workSeconds),
                                                                get: { hoursText(from: $0.workSeconds) },
                                                                set: { $0.workSeconds = parseHoursInput($1) }
                                                            )
                                                        )
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Actual (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField(
                                                            "Auto",
                                                            text: inspectorAssignmentDraftBinding(
                                                                at: assignmentDraftIndex,
                                                                defaultValue: hoursText(from: assignmentDrafts[assignmentDraftIndex].actualWorkSeconds),
                                                                get: { hoursText(from: $0.actualWorkSeconds) },
                                                                set: { $0.actualWorkSeconds = parseHoursInput($1) }
                                                            )
                                                        )
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Remaining (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField(
                                                            "Auto",
                                                            text: inspectorAssignmentDraftBinding(
                                                                at: assignmentDraftIndex,
                                                                defaultValue: hoursText(from: assignmentDrafts[assignmentDraftIndex].remainingWorkSeconds),
                                                                get: { hoursText(from: $0.remainingWorkSeconds) },
                                                                set: { $0.remainingWorkSeconds = parseHoursInput($1) }
                                                            )
                                                        )
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Overtime (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField(
                                                            "0",
                                                            text: inspectorAssignmentDraftBinding(
                                                                at: assignmentDraftIndex,
                                                                defaultValue: hoursText(from: assignmentDrafts[assignmentDraftIndex].overtimeWorkSeconds),
                                                                get: { hoursText(from: $0.overtimeWorkSeconds) },
                                                                set: { $0.overtimeWorkSeconds = parseHoursInput($1) }
                                                            )
                                                        )
                                                            .textFieldStyle(.roundedBorder)
                                                    }
                                                }

                                                if let assignmentCost = primaryAssignmentCost(for: assignmentDrafts[assignmentDraftIndex].id) {
                                                    Text("Planned Cost: \(currencyText(assignmentCost))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                HStack {
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        removeInspectorAssignmentDraft(at: assignmentDraftIndex)
                                                    } label: {
                                                        Label("Remove", systemImage: "trash")
                                                    }
                                                    .buttonStyle(.accessoryBar)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }

                                    Button {
                                        addInspectorAssignmentDraft(to: taskDraft.id)
                                    } label: {
                                        Label("Add Assignment", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .hoverHighlight()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Notes") {
                            TextEditor(
                                text: inspectorTaskDraftBinding(
                                    defaultValue: taskDraft.notes,
                                    get: { $0.notes },
                                    set: { $0.notes = $1 }
                                )
                            )
                                .frame(minHeight: 160)
                                .font(.body)
                        }

                        GroupBox("Gantt Bar Color") {
                            HStack(spacing: 10) {
                                ColorPicker(
                                    "Bar Color",
                                    selection: inspectorTaskDraftBinding(
                                        defaultValue: Color(hex: taskDraft.barColorHex ?? "") ?? .accentColor,
                                        get: { Color(hex: $0.barColorHex ?? "") ?? .accentColor },
                                        set: { $0.barColorHex = $1.hexString }
                                    ),
                                    supportsOpacity: false
                                )
                                .labelsHidden()

                                Text((inspectorTaskDraft?.barColorHex ?? taskDraft.barColorHex) == nil ? "Default (accent / critical)" : "Custom color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button("Reset") {
                                    mutateInspectorTaskDraft { $0.barColorHex = nil }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled((inspectorTaskDraft?.barColorHex ?? taskDraft.barColorHex) == nil)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Custom Fields") {
                            VStack(alignment: .leading, spacing: 8) {
                                let fieldNames = planCustomFieldNames

                                if fieldNames.isEmpty {
                                    Text("Add your own attributes, like Domain or Workstream. A field is added to every task in the plan, appears as an optional column in the Tasks view, and is searchable.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                ForEach(fieldNames, id: \.self) { fieldName in
                                    HStack(spacing: 8) {
                                        Text(fieldName)
                                            .font(.caption)
                                            .frame(width: 110, alignment: .leading)
                                            .lineLimit(1)
                                            .help(fieldName)

                                        TextField("Value", text: inspectorTaskDraftBinding(
                                            defaultValue: taskDraft.customFields[fieldName] ?? "",
                                            get: { $0.customFields[fieldName] ?? "" },
                                            set: { $0.customFields[fieldName] = $1 }
                                        ))
                                        .textFieldStyle(.roundedBorder)

                                        Button {
                                            pendingCustomFieldRemoval = fieldName
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Remove this field from all tasks")
                                    }
                                }

                                HStack(spacing: 8) {
                                    TextField("Field name (e.g. Domain)", text: $newCustomFieldName)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 160)
                                        .onSubmit(addCustomFieldToAllTasks)

                                    Button {
                                        addCustomFieldToAllTasks()
                                    } label: {
                                        Label("Add Field", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)
                                    .hoverHighlight()
                                    .disabled(trimmedNewCustomFieldName.isEmpty)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .confirmationDialog(
                            "Remove `\(pendingCustomFieldRemoval ?? "")` from all tasks?",
                            isPresented: Binding(
                                get: { pendingCustomFieldRemoval != nil },
                                set: { if !$0 { pendingCustomFieldRemoval = nil } }
                            ),
                            titleVisibility: .visible
                        ) {
                            Button("Remove Field", role: .destructive) {
                                if let fieldName = pendingCustomFieldRemoval {
                                    removeCustomFieldFromAllTasks(fieldName)
                                }
                                pendingCustomFieldRemoval = nil
                            }
                            Button("Cancel", role: .cancel) {
                                pendingCustomFieldRemoval = nil
                            }
                        } message: {
                            Text("The field and every task's value for it will be deleted. This can be undone with Cmd+Z.")
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "square.and.pencil",
                    description: Text("Select a task to edit its schedule, progress, dependencies, and notes.")
                )
                .topAlignedEmptyState()
            }
        }
    }

    private func selectedTaskBinding() -> Binding<NativePlanTask>? {
        guard let selectedTaskIndex else { return nil }
        return $plan.tasks[selectedTaskIndex]
    }

    private func hasPendingInspectorChanges(for previousTaskID: Int?) -> Bool {
        guard let previousTaskID else { return false }
        let taskDraftDirty = inspectorTaskDraftIsDirty && inspectorTaskDraft?.id == previousTaskID
        let assignmentDraftDirty = inspectorAssignmentDraftsAreDirty
            && (inspectorAssignmentDrafts.isEmpty || inspectorAssignmentDrafts.contains(where: { $0.taskID == previousTaskID }))
        return taskDraftDirty || assignmentDraftDirty
    }

    private func commitInspectorEdits() {
        commitGridDrafts()
        commitInspectorTaskDraft()
        commitInspectorAssignmentDrafts()
    }

    private func syncInspectorTaskDraft(force: Bool = false) {
        guard let selectedTaskIndex else {
            inspectorTaskDraft = nil
            inspectorTaskDraftIsDirty = false
            return
        }

        let liveTask = plan.tasks[selectedTaskIndex]
        if force || inspectorTaskDraftWorkItem == nil || inspectorTaskDraft?.id != liveTask.id {
            inspectorTaskDraft = liveTask
            inspectorTaskDraftIsDirty = false
        }
    }

    private func syncInspectorAssignmentDrafts(force: Bool = false) {
        guard let selectedTaskID else {
            inspectorAssignmentDrafts = []
            inspectorAssignmentDraftsAreDirty = false
            return
        }

        let liveAssignments = taskAssignmentIndices(for: selectedTaskID).map { plan.assignments[$0] }
        if force || inspectorAssignmentDraftWorkItem == nil {
            inspectorAssignmentDrafts = liveAssignments
            inspectorAssignmentDraftsAreDirty = false
            return
        }

        let draftIDs = inspectorAssignmentDrafts.map(\.id)
        let liveIDs = liveAssignments.map(\.id)
        if draftIDs != liveIDs {
            inspectorAssignmentDrafts = liveAssignments
            inspectorAssignmentDraftsAreDirty = false
        }
    }

    private var trimmedNewCustomFieldName: String {
        newCustomFieldName.trimmingCharacters(in: .whitespaces)
    }

    private var planCustomFieldNames: [String] {
        var names = Set<String>()
        for task in plan.tasks {
            names.formUnion(task.customFields.keys)
        }
        if let draft = inspectorTaskDraft {
            names.formUnion(draft.customFields.keys)
        }
        return names.sorted()
    }

    private func addCustomFieldToAllTasks() {
        let fieldName = trimmedNewCustomFieldName
        guard !fieldName.isEmpty else { return }
        for index in plan.tasks.indices where plan.tasks[index].customFields[fieldName] == nil {
            plan.tasks[index].customFields[fieldName] = ""
        }
        mutateInspectorTaskDraft { task in
            if task.customFields[fieldName] == nil {
                task.customFields[fieldName] = ""
            }
        }
        notePlanMutation(needsGrid: false, needsAnalysis: true)
        newCustomFieldName = ""
    }

    private func updateTaskCustomField(taskID: Int, fieldName: String, value: String) {
        guard let index = taskIndex(for: taskID), plan.tasks.indices.contains(index) else { return }
        guard (plan.tasks[index].customFields[fieldName] ?? "") != value else { return }
        plan.tasks[index].customFields[fieldName] = value
        if inspectorTaskDraft?.id == taskID {
            mutateInspectorTaskDraft { task in
                task.customFields[fieldName] = value
            }
        }
        notePlanMutation(needsGrid: true, needsAnalysis: false, changedTaskIDs: [taskID])
    }

    private func extraGridColumnValue(_ columnName: String, task: NativePlanTask?) -> String {
        guard let task else { return "" }
        switch columnName {
        case "Notes":
            return task.notes
        case "Priority":
            return String(task.priority)
        case "Fixed Cost":
            return task.fixedCost == 0 ? "" : decimalText(task.fixedCost)
        default:
            return ""
        }
    }

    private func updateTaskExtraColumn(taskID: Int, columnName: String, value: String) {
        guard let index = taskIndex(for: taskID), plan.tasks.indices.contains(index) else { return }
        guard extraGridColumnValue(columnName, task: plan.tasks[index]) != value else { return }

        var needsAnalysis = false
        switch columnName {
        case "Notes":
            plan.tasks[index].notes = value
        case "Priority":
            guard let priority = Int(value.trimmingCharacters(in: .whitespaces)) else { return }
            plan.tasks[index].priority = min(1000, max(0, priority))
        case "Fixed Cost":
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            let cost = trimmed.isEmpty ? 0 : parseDecimalInput(trimmed)
            guard let cost else { return }
            plan.tasks[index].fixedCost = max(0, cost)
            needsAnalysis = true
        default:
            return
        }

        if inspectorTaskDraft?.id == taskID {
            let updatedTask = plan.tasks[index]
            mutateInspectorTaskDraft { task in
                task.notes = updatedTask.notes
                task.priority = updatedTask.priority
                task.fixedCost = updatedTask.fixedCost
            }
        }
        notePlanMutation(needsGrid: true, needsAnalysis: needsAnalysis, changedTaskIDs: [taskID])
    }

    private func removeCustomFieldFromAllTasks(_ fieldName: String) {
        for index in plan.tasks.indices {
            plan.tasks[index].customFields.removeValue(forKey: fieldName)
        }
        mutateInspectorTaskDraft { task in
            task.customFields.removeValue(forKey: fieldName)
        }
        notePlanMutation(needsGrid: false, needsAnalysis: true)
    }

    private func mutateInspectorTaskDraft(reschedule: Bool = false, _ update: (inout NativePlanTask) -> Void) {
        guard var draft = inspectorTaskDraft else { return }
        update(&draft)
        inspectorTaskDraft = draft
        inspectorTaskDraftIsDirty = true
        scheduleInspectorTaskDraftCommit(reschedule: reschedule)
    }

    private func inspectorTaskDraftBinding<Value>(
        defaultValue: @autoclosure @escaping () -> Value,
        get: @escaping (NativePlanTask) -> Value,
        set: @escaping (inout NativePlanTask, Value) -> Void,
        reschedule: Bool = false
    ) -> Binding<Value> {
        Binding(
            get: { inspectorTaskDraft.map(get) ?? defaultValue() },
            set: { newValue in
                mutateInspectorTaskDraft(reschedule: reschedule) { task in
                    set(&task, newValue)
                }
            }
        )
    }

    private func scheduleInspectorTaskDraftCommit(reschedule: Bool) {
        inspectorTaskDraftNeedsReschedule = inspectorTaskDraftNeedsReschedule || reschedule
        inspectorTaskDraftWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            commitInspectorTaskDraft()
        }
        inspectorTaskDraftWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func inspectorAssignmentDraftBinding<Value>(
        at index: Int,
        defaultValue: @autoclosure @escaping () -> Value,
        get: @escaping (NativePlanAssignment) -> Value,
        set: @escaping (inout NativePlanAssignment, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: {
                guard inspectorAssignmentDrafts.indices.contains(index) else { return defaultValue() }
                return get(inspectorAssignmentDrafts[index])
            },
            set: { newValue in
                guard inspectorAssignmentDrafts.indices.contains(index) else { return }
                set(&inspectorAssignmentDrafts[index], newValue)
                inspectorAssignmentDraftsAreDirty = true
                scheduleInspectorAssignmentDraftCommit()
            }
        )
    }

    private func scheduleInspectorAssignmentDraftCommit() {
        inspectorAssignmentDraftWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            commitInspectorAssignmentDrafts()
        }
        inspectorAssignmentDraftWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func initializePlanEditorIfNeeded() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        isInitializing = true

        if selectedTaskID == nil {
            selectedTaskID = plan.tasks.first?.id
        }

        gridResourceOptions = plan.resources.map { PlannerGridResourceOption(id: $0.id, name: $0.name) }
        refreshPlanLookupCaches()

        let snapshot = plan
        let builtAnalysis = await planModel.buildAnalysisForUIAsync()

        guard hasInitialized else { return }

        analysis = builtAnalysis
        planSignalCounts = PlannerSignalCounts.build(from: builtAnalysis)
        lastObservedPlanHash = planRefreshHash(for: snapshot)
        pendingGridRefresh = true
        pendingFullGridRefresh = true
        pendingChangedGridTaskIDs = Set(snapshot.tasks.map(\.id))
        pendingAnalysisRefresh = false
        refreshCounter += 1
        isInitializing = false
    }

    private func planRefreshHash(for plan: NativeProjectPlan) -> Int {
        var hasher = Hasher()
        hasher.combine(plan.title)
        hasher.combine(plan.statusDate.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(plan.tasks.count)
        hasher.combine(plan.assignments.count)
        hasher.combine(plan.resources.count)
        hasher.combine(plan.calendars.count)

        for task in plan.tasks {
            hasher.combine(task.id)
            hasher.combine(task.name)
            hasher.combine(task.outlineLevel)
            hasher.combine(task.startDate.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(task.finishDate.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(task.durationDays)
            hasher.combine(Int(task.percentComplete))
            hasher.combine(task.isMilestone)
            hasher.combine(task.predecessorTaskIDs.count)
        }

        for assignment in plan.assignments {
            hasher.combine(assignment.id)
            hasher.combine(assignment.taskID)
            hasher.combine(assignment.resourceID)
            hasher.combine(Int(assignment.units))
        }

        return hasher.finalize()
    }

    private func notePlanMutation(needsGrid: Bool, needsAnalysis: Bool, changedTaskIDs: Set<Int> = []) {
        let updatedHash = planRefreshHash(for: plan)
        guard updatedHash != lastObservedPlanHash || needsGrid || needsAnalysis else { return }
        lastObservedPlanHash = updatedHash
        refreshPlanLookupCaches()
        if changedTaskIDs.isEmpty {
            metadataNeedsFullSync = true
        } else {
            dirtyTaskIDs.formUnion(changedTaskIDs)
        }
        schedulePlanPersistence()
        pendingGridRefresh = pendingGridRefresh || needsGrid
        pendingAnalysisRefresh = pendingAnalysisRefresh || needsAnalysis
        if needsGrid {
            if changedTaskIDs.isEmpty {
                pendingFullGridRefresh = true
                pendingChangedGridTaskIDs.removeAll()
            } else if !pendingFullGridRefresh {
                pendingChangedGridTaskIDs.formUnion(changedTaskIDs)
            }
        }
        refreshCounter += 1
    }

    private func markMetadataDirty() {
        metadataNeedsFullSync = true
    }

    private func schedulePlanPersistence() {
        persistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            Task { @MainActor in
                persistPlanChanges()
            }
        }
        persistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func persistPlanImmediately() {
        persistenceWorkItem?.cancel()
        persistenceWorkItem = nil
        persistPlanChanges()
    }

    private func persistPlanChanges() {
        guard metadataNeedsFullSync || !dirtyTaskIDs.isEmpty else { return }

        if metadataNeedsFullSync {
            planModel.update(from: plan, in: modelContext)
        } else {
            let tasksByLegacyID = Dictionary(nonThrowingUniquePairs: planModel.tasks.map { ($0.legacyID, $0) })
            let resourcesByLegacyID = Dictionary(nonThrowingUniquePairs: planModel.resources.map { ($0.legacyID, $0) })
            let assignmentsByTaskID = Dictionary(grouping: plan.assignments, by: \.taskID)
            let taskSnapshotsByID = Dictionary(nonThrowingUniquePairs: plan.tasks.enumerated().map { ($1.id, ($0, $1)) })

            for taskID in dirtyTaskIDs {
                guard let (orderIndex, nativeTask) = taskSnapshotsByID[taskID] else { continue }
                let taskModel: PortfolioPlanTask
                if let existing = tasksByLegacyID[taskID] {
                    taskModel = existing
                    existing.update(from: nativeTask, orderIndex: orderIndex)
                } else {
                    let created = PortfolioPlanTask(nativeTask: nativeTask, orderIndex: orderIndex)
                    created.plan = planModel
                    planModel.tasks.append(created)
                    taskModel = created
                }

                let nativeAssignments = assignmentsByTaskID[taskID] ?? []
                taskModel.syncAssignments(from: nativeAssignments, resourcesByLegacyID: resourcesByLegacyID, in: modelContext)
            }

            planModel.updatedAt = Date()
            planModel.refreshPortfolioMetrics(from: plan)
        }

        modelContext.saveReportingFailures()
        dirtyTaskIDs.removeAll()
        metadataNeedsFullSync = false
    }

    private func hasPendingPlanPersistence() -> Bool {
        metadataNeedsFullSync
            || !dirtyTaskIDs.isEmpty
            || persistenceWorkItem != nil
            || inspectorTaskDraftIsDirty
            || inspectorAssignmentDraftsAreDirty
            || !gridTextDrafts.isEmpty
            || !gridAssignmentDrafts.isEmpty
    }

    private func registerPlanUndo(from previousPlan: NativeProjectPlan) {
        if suppressUndoRegistration {
            suppressUndoRegistration = false
            return
        }
        guard hasInitialized else { return }
        undoManager?.registerUndo(withTarget: planModel) { _ in
            restorePlanSnapshot(previousPlan)
        }
        undoManager?.setActionName("Plan Edit")
    }

    private func restorePlanSnapshot(_ snapshot: NativeProjectPlan) {
        let current = plan
        undoManager?.registerUndo(withTarget: planModel) { _ in
            restorePlanSnapshot(current)
        }
        undoManager?.setActionName("Plan Edit")

        // Discard in-flight drafts so they cannot overwrite the restored state.
        inspectorTaskDraftWorkItem?.cancel()
        inspectorTaskDraftIsDirty = false
        inspectorAssignmentDraftWorkItem?.cancel()
        inspectorAssignmentDraftsAreDirty = false
        gridDraftCommitWorkItem?.cancel()
        gridTextDrafts.removeAll()
        gridAssignmentDrafts.removeAll()

        suppressUndoRegistration = true
        plan = snapshot
        lastObservedPlanHash = planRefreshHash(for: snapshot)
        refreshPlanLookupCaches()
        metadataNeedsFullSync = true
        schedulePlanPersistence()
        pendingGridRefresh = true
        pendingFullGridRefresh = true
        pendingChangedGridTaskIDs.removeAll()
        pendingAnalysisRefresh = true
        refreshCounter += 1
    }

    private func syncPlanFromModelIfNeeded() {
        guard !hasPendingPlanPersistence() else { return }
        guard let modelSnapshot = try? planModel.asNativePlan(in: modelContext) else { return }
        let snapshotHash = planRefreshHash(for: modelSnapshot)
        guard snapshotHash != lastObservedPlanHash else { return }
        // External refresh, not a user edit — keep it off the undo stack.
        suppressUndoRegistration = true
        plan = modelSnapshot
        refreshPlanLookupCaches()
        lastObservedPlanHash = snapshotHash
        pendingGridRefresh = true
        pendingFullGridRefresh = true
        pendingChangedGridTaskIDs = Set(modelSnapshot.tasks.map(\.id))
        pendingAnalysisRefresh = true
        refreshCounter += 1
    }

    private func handleRefreshCounterChange() {
        refreshPlanLookupCaches()

        if selectedTaskID == nil || selectedTaskID.flatMap(taskIndex(for:)) == nil {
            selectedTaskID = plan.tasks.first?.id
        }

        if pendingGridRefresh {
            let changedTaskIDs = pendingFullGridRefresh ? nil : pendingChangedGridTaskIDs
            refreshGridRowModels(changedTaskIDs: changedTaskIDs)
            syncGridAssignmentDrafts()
            gridResourceOptions = plan.resources.map { PlannerGridResourceOption(id: $0.id, name: $0.name) }
            pendingGridRefresh = false
            pendingFullGridRefresh = false
            pendingChangedGridTaskIDs.removeAll()
        }

        if let selectedTaskID,
           let liveTaskIndex = taskIndex(for: selectedTaskID),
           !inspectorTaskDraftIsDirty {
            inspectorTaskDraft = plan.tasks[liveTaskIndex]
        } else if selectedTaskID == nil {
            inspectorTaskDraft = nil
        }

        if let selectedTaskID,
           !inspectorAssignmentDraftsAreDirty {
            inspectorAssignmentDrafts = taskAssignmentIndices(for: selectedTaskID).map { plan.assignments[$0] }
        } else if selectedTaskID == nil {
            inspectorAssignmentDrafts = []
        }

        guard pendingAnalysisRefresh else { return }
        pendingAnalysisRefresh = false
        scheduleAnalysisRefresh(for: plan)
    }

    private func refreshPlanLookupCaches() {
        taskIndexByID = PlannerPlanLookup.taskIndexByID(in: plan.tasks)
        validTaskIDs = PlannerPlanLookup.taskIDs(in: plan.tasks)
        assignmentIndicesByTaskID = PlannerPlanLookup.assignmentIndicesByTaskID(in: plan.assignments)
        planSummaryMetrics = PlannerSummaryMetrics.build(from: plan)
    }

    private func commitInspectorAssignmentDrafts() {
        inspectorAssignmentDraftWorkItem?.cancel()
        inspectorAssignmentDraftWorkItem = nil

        guard let selectedTaskID else {
            inspectorAssignmentDrafts = []
            inspectorAssignmentDraftsAreDirty = false
            return
        }

        guard inspectorAssignmentDraftsAreDirty else { return }

        plan.assignments.removeAll { $0.taskID == selectedTaskID }
        plan.assignments.append(contentsOf: inspectorAssignmentDrafts)
        inspectorAssignmentDraftsAreDirty = false
        notePlanMutation(needsGrid: true, needsAnalysis: true, changedTaskIDs: [selectedTaskID])
    }

    private func addInspectorAssignmentDraft(to taskID: Int) {
        commitInspectorTaskDraft()
        if selectedTaskID != taskID {
            commitInspectorAssignmentDrafts()
            selectedTaskID = taskID
            syncInspectorAssignmentDrafts(force: true)
        }
        let defaultResourceID = plan.resources.first?.id
        inspectorAssignmentDrafts.append(plan.makeAssignment(taskID: taskID, resourceID: defaultResourceID))
        inspectorAssignmentDraftsAreDirty = true
        scheduleInspectorAssignmentDraftCommit()
    }

    private func removeInspectorAssignmentDraft(at index: Int) {
        guard inspectorAssignmentDrafts.indices.contains(index) else { return }
        inspectorAssignmentDrafts.remove(at: index)
        inspectorAssignmentDraftsAreDirty = true
        scheduleInspectorAssignmentDraftCommit()
    }

    private func commitInspectorTaskDraft() {
        inspectorTaskDraftWorkItem?.cancel()
        inspectorTaskDraftWorkItem = nil

        guard let draft = inspectorTaskDraft,
              let taskIndex = taskIndex(for: draft.id) else {
            inspectorTaskDraftNeedsReschedule = false
            inspectorTaskDraftIsDirty = false
            return
        }

        guard inspectorTaskDraftIsDirty || inspectorTaskDraftNeedsReschedule else { return }

        PerformanceMonitor.measure("PlanEditor.CommitInspectorDraft") {
            let needsReschedule = inspectorTaskDraftNeedsReschedule
            inspectorTaskDraftNeedsReschedule = false
            inspectorTaskDraftIsDirty = false
            plan.tasks[taskIndex] = draft

            if needsReschedule {
                reschedulePlan(changedTaskIDs: [draft.id])
            } else {
                notePlanMutation(needsGrid: true, needsAnalysis: true, changedTaskIDs: [draft.id])
            }
        }
    }

    private func addTask(after taskID: Int? = nil, focus: PlannerGridColumn? = nil) {
        commitInspectorEdits()

        let insertionAnchorIndex: Int?
        if let taskID {
            insertionAnchorIndex = taskIndex(for: taskID)
        } else {
            insertionAnchorIndex = selectedTaskIndex
        }

        let insertionIndex: Int
        let anchorDate: Date
        let outlineLevel: Int

        if let insertionAnchorIndex {
            let range = subtreeRange(for: insertionAnchorIndex)
            let anchorTask = plan.tasks[insertionAnchorIndex]
            insertionIndex = range.upperBound
            anchorDate = anchorTask.normalizedFinishDate
            outlineLevel = anchorTask.outlineLevel
        } else {
            insertionIndex = plan.tasks.endIndex
            anchorDate = plan.statusDate
            outlineLevel = 1
        }

        var newTask = plan.makeTask(anchoredTo: anchorDate)
        newTask.outlineLevel = outlineLevel
        plan.tasks.insert(newTask, at: insertionIndex)
        reschedulePlan()
        selectedTaskID = newTask.id

        if let focus {
            pendingGridFocusTarget = PlannerGridFocusTarget(taskID: newTask.id, column: focus)
        }
    }

    private func duplicateSelectedTask() {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }
        let range = subtreeRange(for: selectedTaskIndex)
        let block = Array(plan.tasks[range])
        let blockIDs = Set(block.map(\.id))
        let blockAssignments = plan.assignments.filter { blockIDs.contains($0.taskID) }

        var cloned = cloneTaskBlock(block, sourceAssignments: blockAssignments)
        // Timing is preserved: the clone keeps each row's stored start date and
        // any still-valid external predecessors, so the scheduler places it on
        // the same dates as the original. Only rename the root for clarity.
        if !cloned.tasks.isEmpty {
            cloned.tasks[0].name += " Copy"
        }

        plan.tasks.insert(contentsOf: cloned.tasks, at: range.upperBound)
        plan.assignments.append(contentsOf: cloned.assignments)
        reschedulePlan()
        selectedTaskID = cloned.tasks.first?.id
    }

    /// Clones a contiguous block of tasks with fresh task/assignment identities.
    /// Predecessors pointing *inside* the block are remapped to the clones;
    /// predecessors pointing to rows that still exist in the plan are kept (so
    /// duplicated timing matches the source); dangling links are dropped.
    private func cloneTaskBlock(
        _ block: [NativePlanTask],
        sourceAssignments: [NativePlanAssignment]
    ) -> (tasks: [NativePlanTask], assignments: [NativePlanAssignment]) {
        var nextTaskID = plan.nextTaskID()
        var idRemap: [Int: Int] = [:]
        for task in block {
            idRemap[task.id] = nextTaskID
            nextTaskID += 1
        }

        let existingIDs = Set(plan.tasks.map(\.id))
        var nextAssignmentID = plan.nextAssignmentID()
        var newTasks: [NativePlanTask] = []
        var newAssignments: [NativePlanAssignment] = []

        for task in block {
            var copy = task
            copy.uniqueID = UUID()
            copy.id = idRemap[task.id] ?? task.id
            copy.predecessorTaskIDs = task.predecessorTaskIDs.compactMap { predID in
                idRemap[predID] ?? (existingIDs.contains(predID) ? predID : nil)
            }
            newTasks.append(copy)

            for assignment in sourceAssignments where assignment.taskID == task.id {
                var clone = assignment
                clone.uniqueID = UUID()
                clone.id = nextAssignmentID
                nextAssignmentID += 1
                clone.taskID = copy.id
                newAssignments.append(clone)
            }
        }

        return (newTasks, newAssignments)
    }

    private func addTask(before taskID: Int, focus: PlannerGridColumn? = nil) {
        commitInspectorEdits()
        guard let anchorIndex = taskIndex(for: taskID) else { return }
        let anchorTask = plan.tasks[anchorIndex]
        var newTask = plan.makeTask(anchoredTo: anchorTask.startDate)
        newTask.outlineLevel = anchorTask.outlineLevel
        // Insert at the anchor's own row so it lands directly above it without
        // disturbing the neighbor's dates.
        plan.tasks.insert(newTask, at: anchorIndex)
        reschedulePlan()
        selectedTaskID = newTask.id
        if let focus {
            pendingGridFocusTarget = PlannerGridFocusTarget(taskID: newTask.id, column: focus)
        }
    }

    private func insertRowAboveSelection() {
        if let selectedTaskID {
            addTask(before: selectedTaskID, focus: .name)
        } else {
            addTask(focus: .name)
        }
    }

    private func insertRowBelowSelection() {
        addTask(after: selectedTaskID, focus: .name)
    }

    // MARK: Row copy / paste

    private func copySelectedRows() {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }
        let range = subtreeRange(for: selectedTaskIndex)
        let block = Array(plan.tasks[range])
        let blockIDs = Set(block.map(\.id))
        let blockAssignments = plan.assignments.filter { blockIDs.contains($0.taskID) }
        let payload = PlannerClipboardPayload(tasks: block, assignments: blockAssignments)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = try? JSONEncoder().encode(payload) {
            pasteboard.setData(data, forType: PlannerClipboardPayload.pasteboardType)
        }
        // Also expose a tab-separated fallback so rows can paste into Excel.
        let tsv = block.map { task in
            [task.name, String(task.durationDays), DateFormatting.simpleDate(task.startDate)]
                .joined(separator: "\t")
        }.joined(separator: "\n")
        pasteboard.setString(tsv, forType: .string)
    }

    private func pasteRows() {
        commitInspectorEdits()
        let pasteboard = NSPasteboard.general

        if let data = pasteboard.data(forType: PlannerClipboardPayload.pasteboardType),
           let payload = try? JSONDecoder().decode(PlannerClipboardPayload.self, from: data) {
            insertClonedBlock(tasks: payload.tasks, assignments: payload.assignments)
            return
        }

        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pasteSpreadsheetRows(text)
        }
    }

    private func insertClonedBlock(tasks: [NativePlanTask], assignments: [NativePlanAssignment]) {
        guard !tasks.isEmpty else { return }
        let cloned = cloneTaskBlock(tasks, sourceAssignments: assignments)
        var newTasks = cloned.tasks

        // Re-level the pasted block so its root sits at the selection's level.
        let targetLevel = selectedTaskIndex.map { plan.tasks[$0].outlineLevel } ?? 1
        let rootLevel = newTasks.first?.outlineLevel ?? 1
        let levelDelta = targetLevel - rootLevel
        if levelDelta != 0 {
            for index in newTasks.indices {
                newTasks[index].outlineLevel = max(1, newTasks[index].outlineLevel + levelDelta)
            }
        }

        let insertionIndex = selectedTaskIndex.map { subtreeRange(for: $0).upperBound } ?? plan.tasks.endIndex
        plan.tasks.insert(contentsOf: newTasks, at: insertionIndex)
        plan.assignments.append(contentsOf: cloned.assignments)
        reschedulePlan()
        selectedTaskID = newTasks.first?.id
    }

    /// Parses tab/newline-separated text pasted from Excel/Sheets into new tasks.
    /// Columns: Name, Duration (days), Start date, % Complete — all but Name
    /// optional. Extra columns are ignored.
    private func pasteSpreadsheetRows(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline)
        let targetLevel = selectedTaskIndex.map { plan.tasks[$0].outlineLevel } ?? 1
        var nextID = plan.nextTaskID()
        var created: [NativePlanTask] = []

        for line in lines {
            let columns = line.components(separatedBy: "\t")
            let name = columns[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            var task = plan.makeTask(name: name, anchoredTo: plan.statusDate)
            task.uniqueID = UUID()
            task.id = nextID
            nextID += 1
            task.outlineLevel = targetLevel

            if columns.count > 1 {
                let digits = columns[1].filter { $0.isNumber }
                if let duration = Int(digits), duration > 0 {
                    task.durationDays = duration
                }
            }
            if columns.count > 2, let date = parsePastedDate(columns[2]) {
                task.startDate = Calendar.current.startOfDay(for: date)
                task.manuallyScheduled = true
            }
            if columns.count > 3 {
                let digits = columns[3].filter { $0.isNumber }
                if let percent = Double(digits) {
                    task.percentComplete = min(100, max(0, percent))
                }
            }

            created.append(task)
        }

        guard !created.isEmpty else { return }
        let insertionIndex = selectedTaskIndex.map { subtreeRange(for: $0).upperBound } ?? plan.tasks.endIndex
        plan.tasks.insert(contentsOf: created, at: insertionIndex)
        reschedulePlan()
        selectedTaskID = created.first?.id
    }

    private func parsePastedDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        for format in ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "M/d/yyyy", "dd-MM-yyyy", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func deleteSelectedTask() {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }
        let range = subtreeRange(for: selectedTaskIndex)
        let removedIDs = Set(plan.tasks[range].map(\.id))
        let nextSelectionIndex = range.lowerBound < plan.tasks.count - range.count ? range.lowerBound : max(0, range.lowerBound - 1)

        plan.tasks.removeSubrange(range)

        for index in plan.tasks.indices {
            plan.tasks[index].predecessorTaskIDs.removeAll { removedIDs.contains($0) }
        }

        plan.assignments.removeAll { assignment in
            removedIDs.contains(assignment.taskID)
        }

        reschedulePlan()
        selectedTaskID = plan.tasks.indices.contains(nextSelectionIndex) ? plan.tasks[nextSelectionIndex].id : nil
    }

    private func canIndentSelectedTask() -> Bool {
        guard let selectedTaskIndex, selectedTaskIndex > 0 else { return false }
        let currentLevel = plan.tasks[selectedTaskIndex].outlineLevel
        let previousLevel = plan.tasks[selectedTaskIndex - 1].outlineLevel
        return previousLevel + 1 > currentLevel
    }

    private func indentSelectedTask() {
        guard let selectedTaskIndex, canIndentSelectedTask() else { return }
        let currentLevel = plan.tasks[selectedTaskIndex].outlineLevel
        let previousLevel = plan.tasks[selectedTaskIndex - 1].outlineLevel
        // Demote by exactly one level, but never deeper than one below the row
        // above. This keeps a single indent a single step: indenting a level-1
        // row under a level-2 sibling makes it that sibling's peer (level 2),
        // not its child (level 3).
        let newLevel = min(currentLevel + 1, previousLevel + 1)
        adjustSelectedSubtreeOutlineLevel(by: newLevel - currentLevel)
    }

    private func canOutdentSelectedTask() -> Bool {
        guard let selectedTaskIndex else { return false }
        return plan.tasks[selectedTaskIndex].outlineLevel > 1
    }

    private func outdentSelectedTask() {
        guard canOutdentSelectedTask() else { return }
        adjustSelectedSubtreeOutlineLevel(by: -1)
    }

    private func adjustSelectedSubtreeOutlineLevel(by delta: Int) {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }
        let range = subtreeRange(for: selectedTaskIndex)
        for index in range {
            plan.tasks[index].outlineLevel = max(1, plan.tasks[index].outlineLevel + delta)
        }
        reschedulePlan()
    }

    private func parentRowIndex(for index: Int) -> Int? {
        let level = plan.tasks[index].outlineLevel
        var candidate = index - 1
        while candidate >= 0 {
            if plan.tasks[candidate].outlineLevel < level {
                return candidate
            }
            candidate -= 1
        }
        return nil
    }

    private func canMoveSelectedTaskUp() -> Bool {
        guard let selectedTaskIndex else { return false }
        if previousSiblingRootIndex(for: selectedTaskIndex) != nil { return true }
        // First child: can still leave the parent when the parent has a
        // previous sibling to join.
        guard let parentIndex = parentRowIndex(for: selectedTaskIndex) else { return false }
        return previousSiblingRootIndex(for: parentIndex) != nil
    }

    private func moveSelectedTaskUp() {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }

        if let previousSiblingIndex = previousSiblingRootIndex(for: selectedTaskIndex) {
            let selectedRange = subtreeRange(for: selectedTaskIndex)
            let movingTasks = Array(plan.tasks[selectedRange])
            plan.tasks.removeSubrange(selectedRange)
            plan.tasks.insert(contentsOf: movingTasks, at: previousSiblingIndex)
            reschedulePlan()
            selectedTaskID = movingTasks.first?.id
            return
        }

        // At the top of this parent: hop into the previous sibling of the
        // parent (e.g. from the start of Phase 3 to the end of Phase 2).
        guard let parentIndex = parentRowIndex(for: selectedTaskIndex),
              let auntIndex = previousSiblingRootIndex(for: parentIndex) else { return }
        let auntRange = subtreeRange(for: auntIndex)
        let anchorTaskID = plan.tasks[auntRange.upperBound - 1].id
        let taskID = plan.tasks[selectedTaskIndex].id
        if plan.relocateTaskSubtree(taskID: taskID, anchorTaskID: anchorTaskID, placeAfterAnchor: true) {
            reschedulePlan()
            selectedTaskID = taskID
        }
    }

    private func canMoveSelectedTaskDown() -> Bool {
        guard let selectedTaskIndex else { return false }
        if nextSiblingRootIndex(for: selectedTaskIndex) != nil { return true }
        guard let parentIndex = parentRowIndex(for: selectedTaskIndex) else { return false }
        return nextSiblingRootIndex(for: parentIndex) != nil
    }

    private func moveSelectedTaskDown() {
        commitInspectorEdits()
        guard let selectedTaskIndex else { return }

        if let nextSiblingIndex = nextSiblingRootIndex(for: selectedTaskIndex) {
            let selectedRange = subtreeRange(for: selectedTaskIndex)
            let movingTasks = Array(plan.tasks[selectedRange])
            let nextSiblingRange = subtreeRange(for: nextSiblingIndex)
            plan.tasks.removeSubrange(selectedRange)
            let insertionIndex = nextSiblingRange.upperBound - selectedRange.count
            plan.tasks.insert(contentsOf: movingTasks, at: insertionIndex)
            reschedulePlan()
            selectedTaskID = movingTasks.first?.id
            return
        }

        // At the bottom of this parent: hop into the next sibling of the
        // parent (e.g. from the end of Phase 2 to the start of Phase 3).
        guard let parentIndex = parentRowIndex(for: selectedTaskIndex),
              let auntIndex = nextSiblingRootIndex(for: parentIndex) else { return }
        let anchorTaskID = plan.tasks[auntIndex].id
        let taskID = plan.tasks[selectedTaskIndex].id
        if plan.relocateTaskSubtree(taskID: taskID, anchorTaskID: anchorTaskID, placeAfterAnchor: true) {
            reschedulePlan()
            selectedTaskID = taskID
        }
    }

    private func toggleGridTaskCollapse(_ taskID: Int) {
        guard gridRowModelCache[taskID]?.isSummary == true || gridRowModels.contains(where: { $0.id == taskID && $0.isSummary }) else {
            selectedTaskID = taskID
            return
        }

        if collapsedGridTaskIDs.contains(taskID) {
            collapsedGridTaskIDs.remove(taskID)
        } else {
            collapsedGridTaskIDs.insert(taskID)
        }

        selectedTaskID = taskID
    }

    private func expandAllGridTasks() {
        collapsedGridTaskIDs.removeAll()
    }

    private func collapseAllGridTasks() {
        collapsedGridTaskIDs = Set(gridRowModels.filter(\.isSummary).map(\.id))
        reconcileSelectedTaskAfterCollapse()
    }

    private func reconcileSelectedTaskAfterCollapse() {
        guard let selectedTaskID else {
            self.selectedTaskID = visibleGridRowModels.first?.id
            return
        }

        self.selectedTaskID = visibleTaskID(for: selectedTaskID)
    }

    private func visibleTaskID(for taskID: Int) -> Int? {
        guard let index = taskIndex(for: taskID),
              plan.tasks.indices.contains(index) else {
            return visibleGridRowModels.first?.id
        }

        var level = plan.tasks[index].outlineLevel
        var candidate = index - 1
        var collapsedAncestorID: Int?

        while candidate >= 0 {
            let candidateTask = plan.tasks[candidate]
            if candidateTask.outlineLevel < level {
                if collapsedGridTaskIDs.contains(candidateTask.id) {
                    collapsedAncestorID = candidateTask.id
                }
                level = candidateTask.outlineLevel
            }
            candidate -= 1
        }

        return collapsedAncestorID ?? taskID
    }

    private func subtreeRange(for index: Int) -> Range<Int> {
        let baseLevel = plan.tasks[index].outlineLevel
        var endIndex = index + 1

        while plan.tasks.indices.contains(endIndex), plan.tasks[endIndex].outlineLevel > baseLevel {
            endIndex += 1
        }

        return index ..< endIndex
    }

    private func previousSiblingRootIndex(for index: Int?) -> Int? {
        guard let index, plan.tasks.indices.contains(index) else { return nil }
        let level = plan.tasks[index].outlineLevel
        guard index > 0 else { return nil }

        var candidate = index - 1
        while candidate >= 0 {
            let candidateLevel = plan.tasks[candidate].outlineLevel
            if candidateLevel == level {
                return candidate
            }
            if candidateLevel < level {
                return nil
            }
            candidate -= 1
        }

        return nil
    }

    private func nextSiblingRootIndex(for index: Int?) -> Int? {
        guard let index, plan.tasks.indices.contains(index) else { return nil }
        let level = plan.tasks[index].outlineLevel
        let range = subtreeRange(for: index)
        var candidate = range.upperBound

        while plan.tasks.indices.contains(candidate) {
            let candidateLevel = plan.tasks[candidate].outlineLevel
            if candidateLevel == level {
                return candidate
            }
            if candidateLevel < level {
                return nil
            }
            candidate += 1
        }

        return nil
    }

    private func moveDownInGrid(fromTaskID taskID: Int, column: PlannerGridColumn) {
        guard let currentIndex = taskIndex(for: taskID) else { return }

        if plan.tasks.indices.contains(currentIndex + 1) {
            let nextTaskID = plan.tasks[currentIndex + 1].id
            selectedTaskID = nextTaskID
            pendingGridFocusTarget = PlannerGridFocusTarget(taskID: nextTaskID, column: column)
            return
        }

        addTask(after: taskID, focus: column)
    }

    private func focusGridTask(_ taskID: Int) {
        guard selectedTaskID != taskID else { return }
        selectedTaskID = taskID
    }

    private func shouldFocus(taskID: Int, column: PlannerGridColumn) -> Bool {
        pendingGridFocusTarget == PlannerGridFocusTarget(taskID: taskID, column: column)
    }

    private func clearPendingFocusIfNeeded(taskID: Int, column: PlannerGridColumn) {
        if pendingGridFocusTarget == PlannerGridFocusTarget(taskID: taskID, column: column) {
            pendingGridFocusTarget = nil
        }
    }

    private func refreshGridRowModels(changedTaskIDs: Set<Int>? = nil) {
        let summaryParentTaskIDs = analysis.summaryParentTaskIDs.isEmpty
            ? plan.summaryParentTaskIDs()
            : analysis.summaryParentTaskIDs
        let shouldRefreshAll = changedTaskIDs == nil || gridRowModelCache.isEmpty
        let changedIDs = changedTaskIDs ?? Set(plan.tasks.map(\.id))
        let validTaskIDs = Set(plan.tasks.map(\.id))
        var primaryAssignmentsByTaskID: [Int: NativePlanAssignment] = [:]
        let resourceNamesByID = Dictionary(nonThrowingUniquePairs: plan.resources.map { ($0.id, $0.name) })

        collapsedGridTaskIDs.formIntersection(validTaskIDs)

        for assignment in plan.assignments where primaryAssignmentsByTaskID[assignment.taskID] == nil {
            primaryAssignmentsByTaskID[assignment.taskID] = assignment
        }

        gridRowModelCache = gridRowModelCache.filter { validTaskIDs.contains($0.key) }

        for (index, task) in plan.tasks.enumerated() {
            guard shouldRefreshAll || changedIDs.contains(task.id) || gridRowModelCache[task.id] == nil else { continue }
            let primaryAssignment = primaryAssignmentsByTaskID[task.id]
            gridRowModelCache[task.id] = PlannerGridRowModel(
                id: task.id,
                name: task.name,
                outlineLevel: task.outlineLevel,
                isSummary: summaryParentTaskIDs.contains(task.id),
                isMilestone: task.isMilestone,
                isLastRow: index == plan.tasks.indices.last,
                startDate: task.startDate,
                finishDate: task.normalizedFinishDate,
                durationText: task.isMilestone ? "0" : String(max(1, task.durationDays)),
                percentText: String(Int(task.percentComplete)),
                predecessorText: task.predecessorTaskIDs.sorted().map(String.init).joined(separator: ", "),
                primaryAssignmentResourceID: primaryAssignment?.resourceID,
                primaryAssignmentResourceName: primaryAssignment?.resourceID.flatMap { resourceNamesByID[$0] } ?? "",
                primaryAssignmentUnitsText: primaryAssignment.map { String(Int($0.units)) } ?? ""
            )
        }

        gridRowModels = plan.tasks.compactMap { gridRowModelCache[$0.id] }
    }

    private func syncGridAssignmentDrafts() {
        let validTaskIDs = Set(plan.tasks.map(\.id))
        gridAssignmentDrafts = gridAssignmentDrafts.filter { validTaskIDs.contains($0.key) }
    }

    private func taskIndex(for taskID: Int) -> Int? {
        if let index = taskIndexByID[taskID],
           plan.tasks.indices.contains(index),
           plan.tasks[index].id == taskID {
           return index
        }

        return plan.tasks.firstIndex(where: { $0.id == taskID })
    }

    private func gridTextBinding(
        taskID: Int,
        column: PlannerGridColumn,
        fallback: String
    ) -> Binding<String> {
        let key = PlannerGridCellKey(taskID: taskID, column: column)
        return Binding(
            get: {
                gridTextDrafts[key] ?? fallback
            },
            set: { newValue in
                gridTextDrafts[key] = newValue
                syncSelectedInspectorFromGridDrafts(taskID: taskID)
                scheduleGridDraftCommit(reschedule: column.requiresReschedule)
            }
        )
    }

    private func syncSelectedInspectorFromGridDrafts(taskID: Int) {
        guard selectedTaskID == taskID,
              !inspectorTaskDraftIsDirty,
              let index = taskIndex(for: taskID),
              plan.tasks.indices.contains(index) else { return }

        var draft = plan.tasks[index]
        let validIDs = validTaskIDs.isEmpty ? Set(plan.tasks.map(\.id)) : validTaskIDs
        for (key, value) in gridTextDrafts where key.taskID == taskID {
            _ = applyGridTextDraft(value, column: key.column, to: &draft, validTaskIDs: validIDs)
        }
        inspectorTaskDraft = draft
    }

    private func syncSelectedInspectorFromLiveTask(taskID: Int) {
        guard selectedTaskID == taskID,
              !inspectorTaskDraftIsDirty,
              let index = taskIndex(for: taskID),
              plan.tasks.indices.contains(index) else { return }

        inspectorTaskDraft = plan.tasks[index]
    }

    @discardableResult
    private func applyGridTextDraft(
        _ draftValue: String,
        column: PlannerGridColumn,
        to task: inout NativePlanTask,
        validTaskIDs: Set<Int>
    ) -> Bool {
        switch column {
        case .name:
            task.name = draftValue
            return false
        case .duration:
            let digits = draftValue.filter(\.isNumber)
            let parsed = Int(digits) ?? (task.isMilestone ? 0 : 1)
            task.durationDays = max(1, parsed)
            if task.isMilestone {
                task.finishDate = task.startDate
            } else if task.manuallyScheduled {
                task.finishDate = finishDateForDuration(
                    task: task,
                    startDate: task.startDate,
                    durationDays: task.durationDays
                )
            }
            return true
        case .percent:
            let digits = draftValue.filter(\.isNumber)
            let parsed = Double(digits) ?? 0
            task.percentComplete = min(100, max(0, parsed))
            return false
        case .predecessors:
            let parsed = draftValue
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { $0 != task.id && validTaskIDs.contains($0) }
            task.predecessorTaskIDs = Array(Set(parsed)).sorted()
            return true
        case .assignmentUnits:
            return false
        }
    }

    private func scheduleGridDraftCommit(reschedule: Bool) {
        gridDraftCommitWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            commitGridDrafts(reschedule: reschedule)
        }
        gridDraftCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func commitGridDrafts(reschedule: Bool = false) {
        gridDraftCommitWorkItem?.cancel()
        gridDraftCommitWorkItem = nil

        let hadTextDrafts = !gridTextDrafts.isEmpty
        let hadAssignmentDrafts = !gridAssignmentDrafts.isEmpty
        guard hadTextDrafts || hadAssignmentDrafts else { return }

        refreshPlanLookupCaches()

        var shouldReschedule = reschedule
        var changedTaskIDs = Set<Int>()
        let validIDs = validTaskIDs

        if hadTextDrafts {
            let textDrafts = gridTextDrafts
            gridTextDrafts.removeAll()

            for (key, draftValue) in textDrafts {
                guard let index = taskIndex(for: key.taskID) else { continue }
                changedTaskIDs.insert(key.taskID)
                if applyGridTextDraft(draftValue, column: key.column, to: &plan.tasks[index], validTaskIDs: validIDs) {
                    shouldReschedule = true
                }
            }
        }

        if hadAssignmentDrafts {
            let assignmentDrafts = gridAssignmentDrafts
            gridAssignmentDrafts.removeAll()

            for (taskID, draft) in assignmentDrafts {
                changedTaskIDs.insert(taskID)
                if let index = primaryAssignmentIndex(for: taskID) {
                    if let resourceID = draft.resourceID {
                        plan.assignments[index].resourceID = resourceID
                        plan.assignments[index].units = draft.units
                    } else {
                        plan.assignments.remove(at: index)
                    }
                } else if let resourceID = draft.resourceID {
                    var assignment = plan.makeAssignment(taskID: taskID, resourceID: resourceID)
                    assignment.units = draft.units
                    plan.assignments.append(assignment)
                }
            }
        }

        guard shouldReschedule else {
            notePlanMutation(needsGrid: true, needsAnalysis: true, changedTaskIDs: changedTaskIDs)
            return
        }

        reschedulePlan(changedTaskIDs: changedTaskIDs)
    }

    private func startDateBinding(for taskID: Int, fallback: Date) -> Binding<Date> {
        Binding(
            get: {
                guard let index = taskIndex(for: taskID) else { return fallback }
                return plan.tasks[index].startDate
            },
            set: { newValue in
                guard let index = taskIndex(for: taskID) else { return }
                let normalized = Calendar.current.startOfDay(for: newValue)
                plan.tasks[index].startDate = normalized

                if plan.tasks[index].isMilestone {
                    plan.tasks[index].finishDate = normalized
                } else if plan.tasks[index].manuallyScheduled {
                    plan.tasks[index].finishDate = finishDateForDuration(
                        task: plan.tasks[index],
                        startDate: normalized,
                        durationDays: plan.tasks[index].durationDays
                    )
                } else if plan.tasks[index].finishDate < normalized {
                    plan.tasks[index].finishDate = normalized
                }

                syncSelectedInspectorFromLiveTask(taskID: taskID)
                reschedulePlan(changedTaskIDs: [taskID])
            }
        )
    }

    private func finishDateBinding(for taskID: Int, fallback: Date) -> Binding<Date> {
        Binding(
            get: {
                guard let index = taskIndex(for: taskID) else { return fallback }
                return plan.tasks[index].normalizedFinishDate
            },
            set: { newValue in
                guard let index = taskIndex(for: taskID) else { return }
                let normalized = max(Calendar.current.startOfDay(for: newValue), plan.tasks[index].startDate)
                if plan.tasks[index].isMilestone {
                    plan.tasks[index].finishDate = plan.tasks[index].startDate
                } else {
                    plan.tasks[index].finishDate = normalized
                    plan.tasks[index].durationDays = max(1, durationDaysFromDates(for: plan.tasks[index], finishDate: normalized))
                }
                syncSelectedInspectorFromLiveTask(taskID: taskID)
                reschedulePlan(changedTaskIDs: [taskID])
            }
        )
    }

    private func milestoneBinding(for taskID: Int, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: {
                guard let index = taskIndex(for: taskID) else { return fallback }
                return plan.tasks[index].isMilestone
            },
            set: { isMilestone in
                guard let index = taskIndex(for: taskID) else { return }
                plan.tasks[index].isMilestone = isMilestone
                if isMilestone {
                    plan.tasks[index].finishDate = plan.tasks[index].startDate
                    plan.tasks[index].durationDays = 1
                }
                syncSelectedInspectorFromLiveTask(taskID: taskID)
                reschedulePlan(changedTaskIDs: [taskID])
            }
        )
    }

    private func predecessorsBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: {
                task.wrappedValue.predecessorTaskIDs
                    .sorted()
                    .map(String.init)
                    .joined(separator: ", ")
            },
            set: { newValue in
                let validIDs = Set(plan.tasks.map(\.id))
                let parsed = newValue
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { $0 != task.wrappedValue.id && validIDs.contains($0) }
                task.wrappedValue.predecessorTaskIDs = Array(Set(parsed)).sorted()
                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func agileTypeBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { task.wrappedValue.agileType },
            set: { task.wrappedValue.agileType = $0 }
        )
    }

    private func boardStatusBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { task.wrappedValue.boardStatus },
            set: { task.wrappedValue.boardStatus = $0 }
        )
    }

    private func storyPointsTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: {
                guard let points = task.wrappedValue.storyPoints else { return "" }
                return String(points)
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                task.wrappedValue.storyPoints = digits.isEmpty ? nil : max(0, Int(digits) ?? 0)
            }
        )
    }

    private func sprintIDBinding(for task: Binding<NativePlanTask>) -> Binding<Int?> {
        Binding(
            get: { task.wrappedValue.sprintID },
            set: { task.wrappedValue.sprintID = $0 }
        )
    }

    private func epicNameBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { task.wrappedValue.epicName },
            set: { task.wrappedValue.epicName = $0 }
        )
    }

    private func tagsTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { task.wrappedValue.tags.joined(separator: ", ") },
            set: { newValue in
                task.wrappedValue.tags = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func percentTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { String(Int(task.wrappedValue.percentComplete)) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                let parsed = Double(digits) ?? 0
                task.wrappedValue.percentComplete = min(100, max(0, parsed))
            }
        )
    }

    private func durationDaysTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: {
                task.wrappedValue.isMilestone ? "0" : String(max(1, task.wrappedValue.durationDays))
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                let parsed = Int(digits) ?? (task.wrappedValue.isMilestone ? 0 : 1)
                task.wrappedValue.durationDays = max(1, parsed)

                if task.wrappedValue.isMilestone {
                    task.wrappedValue.finishDate = task.wrappedValue.startDate
                } else if task.wrappedValue.manuallyScheduled {
                    task.wrappedValue.finishDate = finishDateForDuration(
                        task: task.wrappedValue,
                        startDate: task.wrappedValue.startDate,
                        durationDays: task.wrappedValue.durationDays
                    )
                }

                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func manualSchedulingBinding(for task: Binding<NativePlanTask>) -> Binding<Bool> {
        Binding(
            get: { task.wrappedValue.manuallyScheduled },
            set: { isManual in
                task.wrappedValue.manuallyScheduled = isManual
                task.wrappedValue.durationDays = durationDaysFromDates(for: task.wrappedValue)
                if task.wrappedValue.isMilestone {
                    task.wrappedValue.finishDate = task.wrappedValue.startDate
                }
                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func taskCalendarBinding(for task: Binding<NativePlanTask>) -> Binding<Int?> {
        Binding(
            get: { task.wrappedValue.calendarUniqueID },
            set: { newValue in
                task.wrappedValue.calendarUniqueID = newValue
                if task.wrappedValue.manuallyScheduled {
                    task.wrappedValue.durationDays = durationDaysFromDates(for: task.wrappedValue)
                }
                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func constraintTypeBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { task.wrappedValue.constraintType ?? "ASAP" },
            set: { newValue in
                let normalized = newValue == "ASAP" ? nil : newValue
                task.wrappedValue.constraintType = normalized
                if normalized == nil {
                    task.wrappedValue.constraintDate = nil
                } else if task.wrappedValue.constraintDate == nil {
                    task.wrappedValue.constraintDate = task.wrappedValue.startDate
                }
                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func constraintDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.constraintDate ?? task.wrappedValue.startDate },
            set: { newValue in
                task.wrappedValue.constraintDate = Calendar.current.startOfDay(for: newValue)
                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func startDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.startDate },
            set: { newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                task.wrappedValue.startDate = normalized

                if task.wrappedValue.isMilestone {
                    task.wrappedValue.finishDate = normalized
                } else if task.wrappedValue.manuallyScheduled {
                    task.wrappedValue.finishDate = finishDateForDuration(
                        task: task.wrappedValue,
                        startDate: normalized,
                        durationDays: task.wrappedValue.durationDays
                    )
                } else if task.wrappedValue.finishDate < normalized {
                    task.wrappedValue.finishDate = normalized
                }

                reschedulePlan(changedTaskIDs: [task.wrappedValue.id])
            }
        )
    }

    private func finishDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.normalizedFinishDate },
            set: { newValue in
                let normalized = max(Calendar.current.startOfDay(for: newValue), task.wrappedValue.startDate)
                if task.wrappedValue.isMilestone {
                    task.wrappedValue.finishDate = task.wrappedValue.startDate
                } else {
                    task.wrappedValue.finishDate = normalized
                    task.wrappedValue.durationDays = max(1, durationDaysFromDates(for: task.wrappedValue, finishDate: normalized))
                }
                reschedulePlan()
            }
        )
    }

    private func milestoneBinding(for task: Binding<NativePlanTask>) -> Binding<Bool> {
        Binding(
            get: { task.wrappedValue.isMilestone },
            set: { isMilestone in
                task.wrappedValue.isMilestone = isMilestone
                if isMilestone {
                    task.wrappedValue.finishDate = task.wrappedValue.startDate
                    task.wrappedValue.durationDays = 1
                }
                reschedulePlan()
            }
        )
    }

    private func durationLabel(for task: NativePlanTask) -> String {
        return task.isMilestone ? "0d" : "\(max(1, task.durationDays))d"
    }

    private func taskAssignmentIndices(for taskID: Int) -> [Int] {
        if let cachedIndices = assignmentIndicesByTaskID[taskID] {
            let validCachedIndices = cachedIndices.filter { index in
                plan.assignments.indices.contains(index) && plan.assignments[index].taskID == taskID
            }
            if validCachedIndices.count == cachedIndices.count {
                return validCachedIndices
            }
        }

        return plan.assignments.indices.filter { plan.assignments[$0].taskID == taskID }
    }

    private func primaryAssignmentIndex(for taskID: Int) -> Int? {
        taskAssignmentIndices(for: taskID).first
    }

    private func addAssignment(to taskID: Int) {
        commitInspectorEdits()
        let defaultResourceID = plan.resources.first?.id
        plan.assignments.append(plan.makeAssignment(taskID: taskID, resourceID: defaultResourceID))
    }

    private func primaryAssignmentResourceBinding(for taskID: Int, fallback: Int?) -> Binding<Int?> {
        Binding(
            get: {
                // A draft is authoritative even when its resourceID is nil
                // (the user explicitly chose "Unassigned"), so use `.map` to keep
                // nil from falling through to the previous resource.
                if let draft = gridAssignmentDrafts[taskID] {
                    return draft.resourceID
                }
                return primaryAssignmentIndex(for: taskID).flatMap { plan.assignments[$0].resourceID } ?? fallback
            },
            set: { newValue in
                let baseUnits = gridAssignmentDrafts[taskID]?.units
                    ?? primaryAssignmentIndex(for: taskID).map { plan.assignments[$0].units }
                    ?? 100
                gridAssignmentDrafts[taskID] = PlannerGridAssignmentDraft(resourceID: newValue, units: baseUnits)
                // Resource changes are discrete — apply on the next tick so the
                // change (including unassigning) sticks without a debounce window,
                // while avoiding a re-entrant mutation during the view update.
                gridDraftCommitWorkItem?.cancel()
                let workItem = DispatchWorkItem { commitGridDrafts(reschedule: false) }
                gridDraftCommitWorkItem = workItem
                DispatchQueue.main.async(execute: workItem)
            }
        )
    }

    private func primaryAssignmentUnitsTextBinding(for taskID: Int, fallback: String) -> Binding<String> {
        Binding(
            get: {
                if let draft = gridAssignmentDrafts[taskID] {
                    return draft.resourceID == nil ? "" : String(Int(draft.units))
                }
                guard let index = primaryAssignmentIndex(for: taskID) else { return fallback }
                return String(Int(plan.assignments[index].units))
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                let parsed = digits.isEmpty ? 0 : min(300.0, max(0.0, Double(digits) ?? 0))
                let baseResourceID = gridAssignmentDrafts[taskID]?.resourceID
                    ?? primaryAssignmentIndex(for: taskID).flatMap { plan.assignments[$0].resourceID }
                    ?? plan.resources.first?.id
                gridAssignmentDrafts[taskID] = PlannerGridAssignmentDraft(resourceID: baseResourceID, units: parsed)
                scheduleGridDraftCommit(reschedule: false)
            }
        )
    }

    private func assignmentResourceBinding(for index: Int) -> Binding<Int?> {
        Binding(
            get: { plan.assignments[index].resourceID },
            set: { plan.assignments[index].resourceID = $0 }
        )
    }

    private func assignmentUnitsBinding(for index: Int) -> Binding<Double> {
        Binding(
            get: { plan.assignments[index].units },
            set: { plan.assignments[index].units = max(0, $0) }
        )
    }

    private func assignmentWorkHoursTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { hoursText(from: plan.assignments[index].workSeconds) },
            set: { newValue in
                plan.assignments[index].workSeconds = parseHoursInput(newValue)
            }
        )
    }

    private func assignmentActualWorkHoursTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { hoursText(from: plan.assignments[index].actualWorkSeconds) },
            set: { newValue in
                plan.assignments[index].actualWorkSeconds = parseHoursInput(newValue)
            }
        )
    }

    private func assignmentRemainingWorkHoursTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { hoursText(from: plan.assignments[index].remainingWorkSeconds) },
            set: { newValue in
                plan.assignments[index].remainingWorkSeconds = parseHoursInput(newValue)
            }
        )
    }

    private func assignmentOvertimeWorkHoursTextBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { hoursText(from: plan.assignments[index].overtimeWorkSeconds) },
            set: { newValue in
                plan.assignments[index].overtimeWorkSeconds = parseHoursInput(newValue)
            }
        )
    }

    private func fixedCostTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { decimalText(task.wrappedValue.fixedCost) },
            set: { newValue in
                task.wrappedValue.fixedCost = max(0, parseDecimalInput(newValue) ?? 0)
            }
        )
    }

    private func baselineCostTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { optionalDecimalText(task.wrappedValue.baselineCost) },
            set: { newValue in
                task.wrappedValue.baselineCost = parseDecimalInput(newValue)
            }
        )
    }

    private func actualCostTextBinding(for task: Binding<NativePlanTask>) -> Binding<String> {
        Binding(
            get: { optionalDecimalText(task.wrappedValue.actualCost) },
            set: { newValue in
                task.wrappedValue.actualCost = parseDecimalInput(newValue)
            }
        )
    }

    private func actualStartDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.actualStartDate ?? task.wrappedValue.startDate },
            set: { newValue in
                task.wrappedValue.actualStartDate = Calendar.current.startOfDay(for: newValue)
                if task.wrappedValue.percentComplete == 0 {
                    task.wrappedValue.percentComplete = 1
                }
            }
        )
    }

    private func actualFinishDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.actualFinishDate ?? task.wrappedValue.finishDate },
            set: { newValue in
                let normalized = Calendar.current.startOfDay(for: newValue)
                task.wrappedValue.actualStartDate = task.wrappedValue.actualStartDate ?? task.wrappedValue.startDate
                task.wrappedValue.actualFinishDate = max(task.wrappedValue.actualStartDate ?? normalized, normalized)
                task.wrappedValue.percentComplete = 100
            }
        )
    }

    private func reschedulePlan(changedTaskIDs: Set<Int> = []) {
        let changedCount = changedTaskIDs.count
        PerformanceMonitor.mark("PlanEditor.ReschedulePlan", message: "changed \(changedCount)")
        let selectionSnapshot = selectedTaskID
        let planSnapshot = plan
        latestRescheduleGeneration += 1
        let generation = latestRescheduleGeneration

        Task(priority: .userInitiated) {
            var scheduledPlan = planSnapshot
            // Cell-level edits reschedule incrementally (changed + downstream +
            // ancestors); structural changes pass an empty set → full pass.
            await scheduledPlan.reschedule(changedTaskIDs: changedTaskIDs)
            let scheduledTasks = scheduledPlan.tasks

            await MainActor.run {
                guard generation == latestRescheduleGeneration else { return }
                let actualChangedTaskIDs: Set<Int>
                if changedTaskIDs.isEmpty {
                    actualChangedTaskIDs = []
                } else {
            let originalTasksByID = Dictionary(nonThrowingUniquePairs: planSnapshot.tasks.map { ($0.id, $0) })
                    let scheduleChangedTaskIDs = Set(scheduledTasks.compactMap { task in
                        guard let original = originalTasksByID[task.id] else { return task.id }
                        return original == task ? nil : task.id
                    })
                    actualChangedTaskIDs = changedTaskIDs.union(scheduleChangedTaskIDs)
                }
                plan.tasks = scheduledTasks
                self.selectedTaskID = selectionSnapshot ?? plan.tasks.first?.id
                notePlanMutation(
                    needsGrid: true,
                    needsAnalysis: true,
                    changedTaskIDs: actualChangedTaskIDs
                )
            }
        }
    }

    private func scheduleAnalysisRefresh(for plan: NativeProjectPlan) {
        analysisRefreshWorkItem?.cancel()
        let snapshot = plan
        var workItem: DispatchWorkItem!
        workItem = DispatchWorkItem {
            Task {
                let builtAnalysis = await NativePlanAnalysis.buildAsync(from: snapshot)
                guard !workItem.isCancelled else { return }
                await MainActor.run {
                    guard !workItem.isCancelled else { return }
                    analysis = builtAnalysis
                    planSignalCounts = PlannerSignalCounts.build(from: builtAnalysis)
                }
            }
        }
        analysisRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !(workItem?.isCancelled ?? true) else { return }
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }

    private func effectiveCalendar(for task: NativePlanTask) -> ProjectCalendar? {
        let calendarID = task.calendarUniqueID ?? plan.defaultCalendarUniqueID
        guard let calendarID else { return nil }
        return plan.calendars.first(where: { $0.id == calendarID })?.asProjectCalendar()
    }

    private func isWorkingDate(_ date: Date, task: NativePlanTask) -> Bool {
        let calendar = Calendar.current
        let projectCalendar = effectiveCalendar(for: task)
        let day = calendar.startOfDay(for: date)
        if let exceptions = projectCalendar?.exceptions {
            for exception in exceptions {
                guard let from = exception.fromDate, let to = exception.toDate else { continue }
                let rangeStart = calendar.startOfDay(for: from)
                let rangeEnd = calendar.startOfDay(for: to)
                if day >= rangeStart && day <= rangeEnd {
                    return exception.isWorking
                }
            }
        }

        let calendarsByID = Dictionary(nonThrowingUniquePairs: plan.calendars.map { ($0.id, $0.asProjectCalendar()) })
        let weekday = calendar.component(.weekday, from: day)
        if let projectCalendar {
            return projectCalendar.resolvedIsWorkingDay(weekday: weekday, calendarsByID: calendarsByID)
        }
        return weekday >= 2 && weekday <= 6
    }

    private func nextWorkingDay(onOrAfter date: Date, task: NativePlanTask) -> Date {
        let calendar = Calendar.current
        var current = calendar.startOfDay(for: date)
        while !isWorkingDate(current, task: task) {
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return current
    }

    private func shiftWorkingDays(from date: Date, by delta: Int, task: NativePlanTask) -> Date {
        let calendar = Calendar.current
        var current = nextWorkingDay(onOrAfter: date, task: task)
        if delta == 0 {
            return current
        }

        var remaining = abs(delta)
        while remaining > 0 {
            current = calendar.date(byAdding: .day, value: delta > 0 ? 1 : -1, to: current) ?? current
            if isWorkingDate(current, task: task) {
                remaining -= 1
            }
        }
        return current
    }

    private func finishDateForDuration(task: NativePlanTask, startDate: Date, durationDays: Int) -> Date {
        let normalizedStart = nextWorkingDay(onOrAfter: startDate, task: task)
        guard durationDays > 1 else { return normalizedStart }
        return shiftWorkingDays(from: normalizedStart, by: durationDays - 1, task: task)
    }

    private func durationDaysFromDates(for task: NativePlanTask, finishDate: Date? = nil) -> Int {
        if task.isMilestone {
            return 1
        }

        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: task.startDate)
        let normalizedFinish = calendar.startOfDay(for: finishDate ?? task.finishDate)
        var current = min(normalizedStart, normalizedFinish)
        let end = max(normalizedStart, normalizedFinish)
        var count = 0

        while current <= end {
            if isWorkingDate(current, task: task) {
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? end
        }

        return max(1, count)
    }

    private func baselineField(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }

    private func baselineDateText(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return DateFormatting.simpleDate(date)
    }

    private func baselineDurationText(for task: NativePlanTask) -> String {
        guard let baselineDurationDays = task.baselineDurationDays else { return "Not set" }
        return baselineDurationDays == 0 ? "0d" : "\(baselineDurationDays)d"
    }

    private func varianceText(current: Date, baseline: Date?) -> String {
        guard let baseline else { return "No baseline" }
        let calendar = Calendar.current
        let delta = calendar.dateComponents([.day], from: calendar.startOfDay(for: baseline), to: calendar.startOfDay(for: current)).day ?? 0
        if delta == 0 {
            return "On baseline"
        }
        if delta > 0 {
            return "+\(delta)d later"
        }
        return "\(delta)d earlier"
    }

    private func actualDateEditor(
        title: String,
        date: Date?,
        setCurrent: @escaping () -> Void,
        clear: @escaping () -> Void,
        binding: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if date != nil {
                HStack(spacing: 8) {
                    PlannerDateField(date: binding)
                    Button("Clear", role: .destructive, action: clear)
                        .buttonStyle(.accessoryBar)
                }
            } else {
                HStack(spacing: 8) {
                    Text("Not set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use Scheduled", action: setCurrent)
                        .buttonStyle(.bordered)
                        .hoverHighlight()
                }
            }
        }
    }

    private func financialSummary(for taskID: Int) -> PlannerFinancialSummary {
        guard let task = currentProject.tasksByID[taskID] else { return .zero }

        if task.summary == true {
            let leafTasks = flattenedLeafTasks(from: task)
            let metrics = leafTasks.reduce(EVMMetrics.zero) { partial, task in
                let metrics = EVMCalculator.compute(for: task, statusDate: plan.statusDate)
                return EVMMetrics(
                    bac: partial.bac + metrics.bac,
                    pv: partial.pv + metrics.pv,
                    ev: partial.ev + metrics.ev,
                    ac: partial.ac + metrics.ac
                )
            }

            return PlannerFinancialSummary(
                isSummary: true,
                plannedCost: leafTasks.compactMap(\.cost).reduce(0, +),
                budgetAtCompletion: metrics.bac,
                plannedValue: metrics.pv,
                earnedValue: metrics.ev,
                actualCost: metrics.ac
            )
        }

        let metrics = EVMCalculator.compute(for: task, statusDate: plan.statusDate)
        return PlannerFinancialSummary(
            isSummary: false,
            plannedCost: task.cost ?? 0,
            budgetAtCompletion: metrics.bac,
            plannedValue: metrics.pv,
            earnedValue: metrics.ev,
            actualCost: metrics.ac
        )
    }

    private func flattenedLeafTasks(from task: ProjectTask) -> [ProjectTask] {
        if task.children.isEmpty {
            return [task]
        }
        return task.children.flatMap(flattenedLeafTasks)
    }

    private func primaryAssignmentCost(for assignmentID: Int) -> Double? {
        currentProject.assignments.first(where: { $0.uniqueID == assignmentID })?.cost
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(
            from: value,
            maximumFractionDigits: value.rounded() == value ? 0 : 2,
            minimumFractionDigits: 0
        )
    }

    private func safeRatioText(_ value: Double) -> String {
        guard value > 0 else { return "N/A" }
        return String(format: "%.2f", value)
    }

    private func decimalText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func optionalDecimalText(_ value: Double?) -> String {
        guard let value else { return "" }
        return decimalText(value)
    }

    private func parseDecimalInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber || $0 == "." }
        return Double(normalized)
    }

    private func hoursText(from seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = Double(seconds) / 3600.0
        return decimalText(hours)
    }

    private func parseHoursInput(_ text: String) -> Int? {
        guard let hours = parseDecimalInput(text) else { return nil }
        return max(0, Int((hours * 3600).rounded()))
    }

    private static let hideableGridColumns: [(key: String, title: String)] = [
        ("Start", "Start"),
        ("Finish", "Finish"),
        ("Duration", "Duration"),
        ("Percent", "% Complete"),
        ("Milestone", "Milestone"),
        ("Predecessors", "Predecessors"),
        ("Resource", "Resource"),
        ("Units", "Units")
    ]

    private let customGridColumnWidth: CGFloat = 110

    private static let optionalGridColumns: [(key: String, width: CGFloat)] = [
        ("Notes", 170),
        ("Priority", 62),
        ("Fixed Cost", 84)
    ]

    private var visibleExtraGridColumns: [String] {
        let visible = Set(plannerGridExtraColumnsRaw.split(separator: "|").map(String.init))
        return Self.optionalGridColumns.map(\.key).filter { visible.contains($0) }
    }

    private func setGridExtraColumn(_ name: String, visible: Bool) {
        var visibleColumns = Set(plannerGridExtraColumnsRaw.split(separator: "|").map(String.init))
        if visible {
            visibleColumns.insert(name)
        } else {
            visibleColumns.remove(name)
        }
        plannerGridExtraColumnsRaw = visibleColumns.sorted().joined(separator: "|")
    }

    private func extraGridColumnWidth(_ name: String) -> CGFloat {
        Self.optionalGridColumns.first(where: { $0.key == name })?.width ?? 110
    }

    private var hiddenGridColumns: Set<String> {
        Set(plannerGridHiddenColumnsRaw.split(separator: "|").map(String.init))
    }

    private func setGridColumn(_ key: String, hidden: Bool) {
        var columns = hiddenGridColumns
        if hidden {
            columns.insert(key)
        } else {
            columns.remove(key)
        }
        plannerGridHiddenColumnsRaw = columns.sorted().joined(separator: "|")
    }

    private var visibleGridCustomColumns: [String] {
        let visible = Set(plannerGridCustomColumnsRaw.split(separator: "|").map(String.init))
        return planCustomFieldNames.filter { visible.contains($0) }
    }

    private func setGridCustomColumn(_ name: String, visible: Bool) {
        var visibleColumns = Set(plannerGridCustomColumnsRaw.split(separator: "|").map(String.init))
        if visible {
            visibleColumns.insert(name)
        } else {
            visibleColumns.remove(name)
        }
        plannerGridCustomColumnsRaw = visibleColumns.sorted().joined(separator: "|")
    }

    private func gridBaseWidth(_ key: String, _ width: CGFloat) -> CGFloat {
        hiddenGridColumns.contains(key) ? 0 : width
    }

    private var fixedGridColumnsWidth: CGFloat {
        idColumnWidth +
        gridBaseWidth("Start", startColumnWidth) +
        gridBaseWidth("Finish", finishColumnWidth) +
        gridBaseWidth("Duration", durationColumnWidth) +
        gridBaseWidth("Percent", percentColumnWidth) +
        gridBaseWidth("Milestone", milestoneColumnWidth) +
        gridBaseWidth("Predecessors", predecessorsColumnWidth) +
        gridBaseWidth("Resource", resourceColumnWidth) +
        gridBaseWidth("Units", assignmentUnitsColumnWidth) +
        CGFloat(visibleGridCustomColumns.count) * customGridColumnWidth +
        visibleExtraGridColumns.reduce(0) { $0 + extraGridColumnWidth($1) }
    }

    private func gridLayout(for totalWidth: CGFloat) -> PlannerGridLayout {
        let preferredNameWidth = max(minimumTaskNameColumnWidth, totalWidth - fixedGridColumnsWidth)
        let preferredTotalWidth = fixedGridColumnsWidth + preferredNameWidth
        let scale = min(1, totalWidth / max(preferredTotalWidth, 1))

        let scaledFixedWidth = fixedGridColumnsWidth * scale
        let remainingNameWidth = max(72, totalWidth - scaledFixedWidth)

        return PlannerGridLayout(
            id: idColumnWidth * scale,
            name: remainingNameWidth,
            start: gridBaseWidth("Start", startColumnWidth) * scale,
            finish: gridBaseWidth("Finish", finishColumnWidth) * scale,
            duration: gridBaseWidth("Duration", durationColumnWidth) * scale,
            percent: gridBaseWidth("Percent", percentColumnWidth) * scale,
            milestone: gridBaseWidth("Milestone", milestoneColumnWidth) * scale,
            predecessors: gridBaseWidth("Predecessors", predecessorsColumnWidth) * scale,
            resource: gridBaseWidth("Resource", resourceColumnWidth) * scale,
            assignmentUnits: gridBaseWidth("Units", assignmentUnitsColumnWidth) * scale,
            customColumns: visibleGridCustomColumns,
            custom: customGridColumnWidth * scale,
            extraColumns: visibleExtraGridColumns,
            extraWidths: visibleExtraGridColumns.map { extraGridColumnWidth($0) * scale }
        )
    }

    private func clampedInspectorWidth(for totalWidth: CGFloat) -> CGFloat {
        clampedInspectorWidth(inspectorWidth, totalWidth: totalWidth)
    }

    private func clampedInspectorWidth(_ proposedWidth: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let maximumInspectorWidth = max(
            minimumInspectorWidth,
            min(totalWidth * 0.45, totalWidth - minimumGridWidth - dividerWidth)
        )
        return min(max(proposedWidth, minimumInspectorWidth), maximumInspectorWidth)
    }

    private func taskHeaderCell(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity, alignment: alignment)
            .overlay(alignment: .trailing) {
                Divider()
            }
    }

    private func taskValueCell<Content: View>(width: CGFloat, alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity, alignment: alignment)
            .overlay(alignment: .trailing) {
                Divider()
            }
    }
}

private struct PlannerSummaryMetrics: Equatable {
    let taskCount: Int
    let sprintCount: Int
    let totalStoryPoints: Int
    let milestoneCount: Int
    let dependencyCount: Int
    let baselineCount: Int

    static let empty = PlannerSummaryMetrics(
        taskCount: 0,
        sprintCount: 0,
        totalStoryPoints: 0,
        milestoneCount: 0,
        dependencyCount: 0,
        baselineCount: 0
    )

    static func build(from plan: NativeProjectPlan) -> PlannerSummaryMetrics {
        var totalStoryPoints = 0
        var milestoneCount = 0
        var dependencyCount = 0
        var baselineCount = 0

        for task in plan.tasks {
            totalStoryPoints += max(0, task.storyPoints ?? 0)
            if task.isMilestone {
                milestoneCount += 1
            }
            dependencyCount += task.predecessorTaskIDs.count
            if task.baselineStartDate != nil || task.baselineFinishDate != nil || task.baselineDurationDays != nil {
                baselineCount += 1
            }
        }

        return PlannerSummaryMetrics(
            taskCount: plan.tasks.count,
            sprintCount: plan.sprints.count,
            totalStoryPoints: totalStoryPoints,
            milestoneCount: milestoneCount,
            dependencyCount: dependencyCount,
            baselineCount: baselineCount
        )
    }
}

private struct PlannerSignalCounts: Equatable {
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
    let diagnosticCount: Int

    static let empty = PlannerSignalCounts(errorCount: 0, warningCount: 0, infoCount: 0, diagnosticCount: 0)

    static func build(from analysis: NativePlanAnalysis) -> PlannerSignalCounts {
        var errorCount = 0
        var warningCount = 0
        var infoCount = 0

        for issue in analysis.validationIssues {
            switch issue.severity {
            case .error:
                errorCount += 1
            case .warning:
                warningCount += 1
            case .info:
                infoCount += 1
            }
        }

        return PlannerSignalCounts(
            errorCount: errorCount,
            warningCount: warningCount,
            infoCount: infoCount,
            diagnosticCount: analysis.diagnosticItems.count
        )
    }
}

private enum PlannerPlanLookup {
    static func taskIndexByID(in tasks: [NativePlanTask]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        result.reserveCapacity(tasks.count)
        for (index, task) in tasks.enumerated() {
            result[task.id] = index
        }
        return result
    }

    static func taskIDs(in tasks: [NativePlanTask]) -> Set<Int> {
        Set(tasks.map(\.id))
    }

    static func assignmentIndicesByTaskID(in assignments: [NativePlanAssignment]) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        result.reserveCapacity(assignments.count)
        for index in assignments.indices {
            result[assignments[index].taskID, default: []].append(index)
        }
        return result
    }
}

private struct PlannerHeaderMetric: Identifiable {
    let id = UUID()
    let value: String
    let label: String
}

private struct PlannerSignalChipModel: Identifiable {
    let id = UUID()
    let title: String
    let count: Int
    let color: Color
}

private struct PlannerHeaderView: View {
    @Binding var title: String
    @Binding var manager: String
    @Binding var company: String
    @Binding var statusDate: Date
    let metrics: [PlannerHeaderMetric]
    let signalChips: [PlannerSignalChipModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan Builder")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .fixedSize()
                    Text("Create and save native project plans, then use the existing analysis views to review them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                FinancialTermsButton()
                    .fixedSize()
            }

            // Metrics reflow as whole cells on narrow windows instead of
            // squeezing into hyphenated columns.
            FlowLayout(spacing: 18, lineSpacing: 10) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.value)
                            .font(.headline)
                            .monospacedDigit()
                        Text(metric.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(spacing: 10, lineSpacing: 6) {
                ForEach(signalChips) { chip in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(chip.color)
                            .frame(width: 8, height: 8)
                        Text("\(chip.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(chip.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(chip.color.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(spacing: 12, lineSpacing: 10) {
                TextField("Project Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                TextField("Manager", text: $manager)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                TextField("Company", text: $company)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                HStack(spacing: 6) {
                    Text("Status Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    PlannerDateField(date: $statusDate)
                        .frame(width: 150)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

private struct PlannerTaskListPane<RowContent: View, HeaderContent: View>: View {
    let tasksEmpty: Bool
    let resources: [NativePlanResource]
    let selectedTaskAvailable: Bool
    let canIndent: Bool
    let canOutdent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canExpandTasks: Bool
    let canCollapseTasks: Bool
    let rowModels: [PlannerGridRowModel]
    let gridLayoutForWidth: (CGFloat) -> PlannerGridLayout
    let onImportTasks: () -> Void
    let onImportAssignments: () -> Void
    let onImportDependencies: () -> Void
    let onImportConstraints: () -> Void
    let onImportBaseline: () -> Void
    let onExportTaskTemplateCSV: () -> Void
    let onExportTaskTemplateExcel: () -> Void
    let onExportAssignmentTemplateCSV: () -> Void
    let onExportAssignmentTemplateExcel: () -> Void
    let onExportDependencyTemplateCSV: () -> Void
    let onExportDependencyTemplateExcel: () -> Void
    let onExportConstraintTemplateCSV: () -> Void
    let onExportConstraintTemplateExcel: () -> Void
    let onExportBaselineTemplateCSV: () -> Void
    let onExportBaselineTemplateExcel: () -> Void
    let onCaptureBaseline: () -> Void
    let onExportMSPDI: () -> Void
    let onAddTask: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onDuplicate: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let onExpandTasks: () -> Void
    let onCollapseTasks: () -> Void
    let onInsertAbove: () -> Void
    let onInsertBelow: () -> Void
    let onCopyRows: () -> Void
    let onPasteRows: () -> Void
    let makeHeader: (PlannerGridLayout) -> HeaderContent
    let makeRow: (PlannerGridRowModel, PlannerGridLayout) -> RowContent

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width
            let layout = gridLayoutForWidth(contentWidth)

            VStack(spacing: 0) {
                toolbar
                shortcuts
                Divider()

                if tasksEmpty {
                    ContentUnavailableView(
                        "No Tasks Yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Start by adding the first task for this plan.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            makeHeader(layout)

                            LazyVStack(spacing: 0) {
                                ForEach(rowModels) { row in
                                    makeRow(row, layout)
                                }
                            }
                        }
                        .frame(minWidth: contentWidth, alignment: .topLeading)
                        .frame(minHeight: geometry.size.height - 1, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks")
                        .font(.headline)
                    Text("Grid entry for fast planning, inspector for detail editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    toolbarButton("Import CSV/Excel", systemImage: "square.and.arrow.down", action: onImportTasks)
                        .help("Import tasks from CSV or Excel-compatible spreadsheet")
                    toolbarButton("Import Assignments", systemImage: "person.2.badge.plus", action: onImportAssignments)
                        .help("Import task-resource assignments from CSV or Excel-compatible spreadsheet")
                    toolbarButton("Import Dependencies", systemImage: "arrow.triangle.branch", action: onImportDependencies)
                        .help("Import predecessor links from CSV or Excel-compatible spreadsheet")
                    toolbarButton("Import Constraints", systemImage: "calendar.badge.exclamationmark", action: onImportConstraints)
                        .help("Import scheduling constraints from CSV or Excel-compatible spreadsheet")
                    toolbarButton("Import Baseline", systemImage: "flag.pattern.checkered", action: onImportBaseline)
                        .help("Import task baseline dates or durations from CSV or Excel-compatible spreadsheet")
                }

                HStack(spacing: 8) {
                    Menu {
                        Button("Task CSV Template", action: onExportTaskTemplateCSV)
                        Button("Task Excel Example", action: onExportTaskTemplateExcel)
                        Divider()
                        Button("Assignment CSV Template", action: onExportAssignmentTemplateCSV)
                        Button("Assignment Excel Example", action: onExportAssignmentTemplateExcel)
                        Divider()
                        Button("Dependency CSV Template", action: onExportDependencyTemplateCSV)
                        Button("Dependency Excel Example", action: onExportDependencyTemplateExcel)
                        Divider()
                        Button("Constraint CSV Template", action: onExportConstraintTemplateCSV)
                        Button("Constraint Excel Example", action: onExportConstraintTemplateExcel)
                        Divider()
                        Button("Baseline CSV Template", action: onExportBaselineTemplateCSV)
                        Button("Baseline Excel Example", action: onExportBaselineTemplateExcel)
                    } label: {
                        wrappedToolbarLabel("Templates", systemImage: "tablecells.badge.ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .fixedSize()
                    .help("Export ready-made task, assignment, dependency, constraint, and baseline import templates")

                    Button(action: onCaptureBaseline) {
                        wrappedToolbarLabel("Capture Baseline", systemImage: "camera.macro")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(tasksEmpty)
                    .help("Store the current scheduled dates as the working baseline")

                    Button(action: onExportMSPDI) {
                        wrappedToolbarLabel("Export MS Project XML", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(tasksEmpty)
                    .help("Export this plan as MSPDI XML that Microsoft Project can open")

                    Divider()
                        .frame(height: 16)

                    Button(action: onAddTask) {
                        wrappedToolbarLabel("Add Task", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverHighlight()
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Add task below selected row (Command-Return)")

                    Button(action: onExpandTasks) {
                        Image(systemName: "chevron.down.square")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!canExpandTasks)
                    .help("Expand all task groups")

                    Button(action: onCollapseTasks) {
                        Image(systemName: "chevron.right.square")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!canCollapseTasks)
                    .help("Collapse task groups")

                    Divider()
                        .frame(height: 16)

                    Button(action: onIndent) {
                        Image(systemName: "increase.indent")
                    }
                    .buttonStyle(.accessoryBar)
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!canIndent)
                    .help("Make selected task a child of the previous task (Command-])")

                    Button(action: onOutdent) {
                        Image(systemName: "decrease.indent")
                    }
                    .buttonStyle(.accessoryBar)
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!canOutdent)
                    .help("Promote selected task one level (Command-[)")

                    Button(action: onDuplicate) {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!selectedTaskAvailable)
                    .help("Duplicate selected task (keeps timing and resources)")

                    Menu {
                        Button(action: onInsertAbove) {
                            Label("Insert Row Above", systemImage: "arrow.up.to.line")
                        }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        Button(action: onInsertBelow) {
                            Label("Insert Row Below", systemImage: "arrow.down.to.line")
                        }
                        Divider()
                        Button(action: onCopyRows) {
                            Label("Copy Row(s)", systemImage: "doc.on.doc")
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .disabled(!selectedTaskAvailable)
                        Button(action: onPasteRows) {
                            Label("Paste Row(s)", systemImage: "doc.on.clipboard")
                        }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.accessoryBar)
                    .fixedSize()
                    .help("Insert, copy, and paste rows. Paste also accepts tab-separated rows from Excel/Sheets. (⇧⌘C copy · ⇧⌘V paste · ⇧⌘↩ insert above)")

                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!canMoveUp)
                    .help("Move selected task block up")

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!canMoveDown)
                    .help("Move selected task block down")

                    Divider()
                        .frame(height: 16)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(!selectedTaskAvailable)
                    .help("Delete selected task")

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var shortcuts: some View {
        HStack(spacing: 12) {
            shortcutHint("Tab", description: "Next cell")
            shortcutHint("Shift+Tab", description: "Previous cell")
            shortcutHint("Enter", description: "Down same column")
            shortcutHint("Cmd+Return", description: "New row")
            shortcutHint("Cmd+[ / ]", description: "Outdent / indent")
            shortcutHint("⇧Cmd+C / V", description: "Copy / paste rows")
            shortcutHint("⇧Cmd+Return", description: "Insert above")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            wrappedToolbarLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .hoverHighlight()
    }

    private func shortcutHint(_ shortcut: String, description: String) -> some View {
        HStack(spacing: 6) {
            Text(shortcut)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func wrappedToolbarLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .fixedSize()
    }
}

private struct PlannerGridLayout: Equatable {
    let id: CGFloat
    let name: CGFloat
    let start: CGFloat
    let finish: CGFloat
    let duration: CGFloat
    let percent: CGFloat
    let milestone: CGFloat
    let predecessors: CGFloat
    let resource: CGFloat
    let assignmentUnits: CGFloat
    let customColumns: [String]
    let custom: CGFloat
    let extraColumns: [String]
    let extraWidths: [CGFloat]
}

private struct PlannerGridResourceOption: Identifiable, Equatable {
    let id: Int
    let name: String
}

private struct PlannerGridRowModel: Identifiable, Equatable {
    let id: Int
    let name: String
    let outlineLevel: Int
    let isSummary: Bool
    let isMilestone: Bool
    let isLastRow: Bool
    let startDate: Date
    let finishDate: Date
    let durationText: String
    let percentText: String
    let predecessorText: String
    let primaryAssignmentResourceID: Int?
    let primaryAssignmentResourceName: String
    let primaryAssignmentUnitsText: String
}

private struct PlannerGridRowView: View, Equatable {
    let row: PlannerGridRowModel
    let layout: PlannerGridLayout
    let isSelected: Bool
    let isCollapsed: Bool
    let resourceOptions: [PlannerGridResourceOption]
    let nameValue: String
    let startDateValue: Date
    let finishDateValue: Date
    let durationValue: String
    let percentValue: String
    let milestoneValue: Bool
    let predecessorsValue: String
    let primaryAssignmentResourceIDValue: Int?
    let primaryAssignmentUnitsValue: String
    @Binding var nameText: String
    @Binding var startDate: Date
    @Binding var finishDate: Date
    @Binding var durationText: String
    @Binding var percentText: String
    @Binding var milestone: Bool
    @Binding var predecessorsText: String
    @Binding var primaryAssignmentResourceID: Int?
    @Binding var primaryAssignmentUnitsText: String
    let customValues: [String]
    let onCommitCustomField: (String, String) -> Void
    let extraValues: [String]
    let onCommitExtraColumn: (String, String) -> Void
    let shouldFocusName: Bool
    let shouldFocusDuration: Bool
    let shouldFocusPercent: Bool
    let shouldFocusPredecessors: Bool
    let shouldFocusAssignmentUnits: Bool
    let onCommitName: () -> Void
    let onCommitDuration: () -> Void
    let onCommitPercent: () -> Void
    let onCommitPredecessors: () -> Void
    let onCommitAssignmentUnits: () -> Void
    let onReturnFromName: () -> Void
    let onReturnFromDuration: () -> Void
    let onReturnFromPercent: () -> Void
    let onReturnFromPredecessors: () -> Void
    let onReturnFromAssignmentUnits: () -> Void
    let onTabFromAssignmentUnits: (() -> Void)?
    let onFocusName: () -> Void
    let onFocusDuration: () -> Void
    let onFocusPercent: () -> Void
    let onFocusPredecessors: () -> Void
    let onFocusAssignmentUnits: () -> Void
    let onToggleCollapse: () -> Void
    let onTap: () -> Void

    static func == (lhs: PlannerGridRowView, rhs: PlannerGridRowView) -> Bool {
        let resourceOptionsEquivalent = (!lhs.isSelected && !rhs.isSelected) || lhs.resourceOptions == rhs.resourceOptions

        return lhs.row == rhs.row &&
        lhs.layout == rhs.layout &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isCollapsed == rhs.isCollapsed &&
        resourceOptionsEquivalent &&
        lhs.nameValue == rhs.nameValue &&
        lhs.startDateValue == rhs.startDateValue &&
        lhs.finishDateValue == rhs.finishDateValue &&
        lhs.durationValue == rhs.durationValue &&
        lhs.percentValue == rhs.percentValue &&
        lhs.milestoneValue == rhs.milestoneValue &&
        lhs.predecessorsValue == rhs.predecessorsValue &&
        lhs.primaryAssignmentResourceIDValue == rhs.primaryAssignmentResourceIDValue &&
        lhs.primaryAssignmentUnitsValue == rhs.primaryAssignmentUnitsValue &&
        lhs.customValues == rhs.customValues &&
        lhs.extraValues == rhs.extraValues &&
        lhs.shouldFocusName == rhs.shouldFocusName &&
        lhs.shouldFocusDuration == rhs.shouldFocusDuration &&
        lhs.shouldFocusPercent == rhs.shouldFocusPercent &&
        lhs.shouldFocusPredecessors == rhs.shouldFocusPredecessors &&
        lhs.shouldFocusAssignmentUnits == rhs.shouldFocusAssignmentUnits
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(width: layout.id, alignment: .leading) {
                Text("\(row.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            cell(width: layout.name, alignment: .leading) {
                HStack(spacing: 4) {
                    Color.clear
                        .frame(width: CGFloat(max(0, row.outlineLevel - 1)) * 14, height: 1)

                    if row.isSummary {
                        Button(action: onToggleCollapse) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(isCollapsed ? "Expand task group" : "Collapse task group")
                    } else {
                        Color.clear
                            .frame(width: 14, height: 1)
                    }

                    PlannerGridTextField(
                        text: $nameText,
                        placeholder: "Task Name",
                        shouldBecomeFirstResponder: shouldFocusName,
                        onCommitNow: onCommitName,
                        onReturn: onReturnFromName,
                        onFocused: onFocusName,
                        fontWeight: row.isSummary ? .semibold : .regular
                    )
                }
            }

            if layout.start > 0 {
                cell(width: layout.start, alignment: .leading) {
                    if isSelected {
                        PlannerDateField(date: $startDate)
                    } else {
                        dateText(startDateValue)
                    }
                }
            }

            if layout.finish > 0 {
                cell(width: layout.finish, alignment: .leading) {
                    if isSelected {
                        PlannerDateField(date: $finishDate)
                    } else {
                        dateText(finishDateValue)
                    }
                }
            }

            if layout.duration > 0 {
            cell(width: layout.duration, alignment: .center) {
                PlannerGridTextField(
                    text: $durationText,
                    placeholder: "1",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocusDuration,
                    onCommitNow: onCommitDuration,
                    onReturn: onReturnFromDuration,
                    onFocused: onFocusDuration
                )
            }
            }

            if layout.percent > 0 {
            cell(width: layout.percent, alignment: .center) {
                PlannerGridTextField(
                    text: $percentText,
                    placeholder: "0",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocusPercent,
                    onCommitNow: onCommitPercent,
                    onReturn: onReturnFromPercent,
                    onFocused: onFocusPercent
                )
            }
            }

            if layout.milestone > 0 {
                cell(width: layout.milestone, alignment: .center) {
                    Toggle("", isOn: $milestone)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }

            if layout.predecessors > 0 {
            cell(width: layout.predecessors, alignment: .leading) {
                PlannerGridTextField(
                    text: $predecessorsText,
                    placeholder: "1, 2",
                    shouldBecomeFirstResponder: shouldFocusPredecessors,
                    onCommitNow: onCommitPredecessors,
                    onReturn: onReturnFromPredecessors,
                    onFocused: onFocusPredecessors
                )
            }
            }

            if layout.resource > 0 {
            cell(width: layout.resource, alignment: .leading) {
                if isSelected {
                    Picker("", selection: $primaryAssignmentResourceID) {
                        Text("Unassigned").tag(Int?.none)
                        ForEach(resourceOptions) { option in
                            Text(option.name).tag(Optional(option.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } else {
                    Text(row.primaryAssignmentResourceName.isEmpty ? "Unassigned" : row.primaryAssignmentResourceName)
                        .lineLimit(1)
                        .foregroundStyle(row.primaryAssignmentResourceName.isEmpty ? .secondary : .primary)
                }
            }
            }

            if layout.assignmentUnits > 0 {
            cell(width: layout.assignmentUnits, alignment: .center) {
                PlannerGridTextField(
                    text: $primaryAssignmentUnitsText,
                    placeholder: "0",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocusAssignmentUnits,
                    onCommitNow: onCommitAssignmentUnits,
                    onTab: onTabFromAssignmentUnits,
                    onReturn: onReturnFromAssignmentUnits,
                    onFocused: onFocusAssignmentUnits
                )
            }
            }

            ForEach(Array(layout.extraColumns.enumerated()), id: \.offset) { index, columnName in
                cell(width: layout.extraWidths[index], alignment: .leading) {
                    PlannerGridCustomFieldCell(
                        value: index < extraValues.count ? extraValues[index] : ""
                    ) { newValue in
                        onCommitExtraColumn(columnName, newValue)
                    }
                }
            }

            ForEach(Array(layout.customColumns.enumerated()), id: \.offset) { index, fieldName in
                cell(width: layout.custom, alignment: .leading) {
                    PlannerGridCustomFieldCell(
                        value: index < customValues.count ? customValues[index] : ""
                    ) { newValue in
                        onCommitCustomField(fieldName, newValue)
                    }
                }
            }
        }
        .frame(height: 32)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func dateText(_ date: Date) -> some View {
        Text(DateFormatting.shortDate(date))
            .font(.caption)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }

    private func cell<Content: View>(width: CGFloat, alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .frame(width: width, alignment: alignment)
            .frame(maxHeight: .infinity, alignment: alignment)
            .overlay(alignment: .trailing) {
                Divider()
            }
    }
}

private struct PlannerGridCustomFieldCell: View {
    let value: String
    let onCommit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.caption)
            .focused($isFocused)
            .onAppear { text = value }
            .onChange(of: value) { _, newValue in
                if !isFocused {
                    text = newValue
                }
            }
            .onSubmit { onCommit(text) }
            .onChange(of: isFocused) { _, focused in
                if !focused, text != value {
                    onCommit(text)
                }
            }
    }
}

private struct PlannerGridAssignmentDraft {
    var resourceID: Int?
    var units: Double
}

private struct PlannerGridCellKey: Hashable {
    let taskID: Int
    let column: PlannerGridColumn
}

private struct PlannerFinancialSummary {
    let isSummary: Bool
    let plannedCost: Double
    let budgetAtCompletion: Double
    let plannedValue: Double
    let earnedValue: Double
    let actualCost: Double

    static let zero = PlannerFinancialSummary(
        isSummary: false,
        plannedCost: 0,
        budgetAtCompletion: 0,
        plannedValue: 0,
        earnedValue: 0,
        actualCost: 0
    )

    var cpiText: String {
        guard actualCost > 0 else { return "N/A" }
        return String(format: "%.2f", earnedValue / actualCost)
    }

    var spiText: String {
        guard plannedValue > 0 else { return "N/A" }
        return String(format: "%.2f", earnedValue / plannedValue)
    }

    var costVariance: Double { earnedValue - actualCost }
    var scheduleVariance: Double { earnedValue - plannedValue }
    var estimateAtCompletion: Double {
        guard actualCost > 0, earnedValue > 0 else { return budgetAtCompletion }
        let cpi = earnedValue / actualCost
        return cpi > 0 ? budgetAtCompletion / cpi : budgetAtCompletion
    }
    var estimateToComplete: Double { max(0, estimateAtCompletion - actualCost) }
    var varianceAtCompletion: Double { budgetAtCompletion - estimateAtCompletion }
    var tcpiText: String {
        let remaining = budgetAtCompletion - earnedValue
        let budgetRemaining = budgetAtCompletion - actualCost
        guard budgetRemaining > 0 else { return "N/A" }
        return String(format: "%.2f", remaining / budgetRemaining)
    }
}

private struct PlannerDateField: View {
    @Binding var date: Date

    var body: some View {
        CalendarDatePicker(date: $date, isCompact: true)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlannerGridTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var alignment: NSTextAlignment = .left
    var shouldBecomeFirstResponder = false
    var onCommitNow: (() -> Void)? = nil
    var onTab: (() -> Void)? = nil
    var onBackTab: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil
    var onFocused: (() -> Void)? = nil
    var fontWeight: Font.Weight = .regular

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PlannerTabInterceptingTextField {
        let textField = PlannerTabInterceptingTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ nsView: PlannerTabInterceptingTextField, context: Context) {
        if !context.coordinator.isEditing, nsView.stringValue != text {
            nsView.stringValue = text
            context.coordinator.draftText = text
        }

        nsView.placeholderString = placeholder
        nsView.alignment = alignment
        nsView.onTab = onTab
        nsView.onBackTab = onBackTab
        nsView.onReturn = onReturn
        nsView.onFocused = onFocused
        nsView.font = fontWeight == .semibold
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)

        if shouldBecomeFirstResponder {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                if window.firstResponder !== nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                    nsView.currentEditor()?.selectedRange = NSRange(location: 0, length: nsView.stringValue.count)
                    onFocused?()
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlannerGridTextField
        var draftText: String
        var isEditing = false
        var pendingCommitWorkItem: DispatchWorkItem?

        init(_ parent: PlannerGridTextField) {
            self.parent = parent
            self.draftText = parent.text
        }

        func updateDraft(from field: NSTextField) {
            draftText = field.stringValue
        }

        func scheduleCommit() {
            pendingCommitWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.commitDraft()
            }
            pendingCommitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
        }

        func commitDraft() {
            pendingCommitWorkItem?.cancel()
            pendingCommitWorkItem = nil

            guard draftText != parent.text else { return }
            parent.text = draftText
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            updateDraft(from: field)
            if draftText != parent.text {
                parent.text = draftText
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            if let field = obj.object as? NSTextField {
                updateDraft(from: field)
            }
            parent.onFocused?()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                updateDraft(from: field)
            }
            isEditing = false
            commitDraft()
            parent.onCommitNow?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)),
               let onTab = parent.onTab {
                commitDraft()
                parent.onCommitNow?()
                onTab()
                return true
            }

            if commandSelector == #selector(NSResponder.insertBacktab(_:)),
               let onBackTab = parent.onBackTab {
                commitDraft()
                parent.onCommitNow?()
                onBackTab()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               let onReturn = parent.onReturn {
                commitDraft()
                parent.onCommitNow?()
                onReturn()
                return true
            }

            return false
        }
    }
}

private final class PlannerTabInterceptingTextField: NSTextField {
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onReturn: (() -> Void)?
    var onFocused: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onFocused?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocused?()
        }
        return didBecomeFirstResponder
    }
}

private struct PlannerGridFocusTarget: Equatable {
    let taskID: Int
    let column: PlannerGridColumn
}

private enum PlannerGridColumn: Equatable {
    case name
    case duration
    case percent
    case predecessors
    case assignmentUnits

    var requiresReschedule: Bool {
        switch self {
        case .duration, .predecessors:
            return true
        case .name, .percent, .assignmentUnits:
            return false
        }
    }
}
