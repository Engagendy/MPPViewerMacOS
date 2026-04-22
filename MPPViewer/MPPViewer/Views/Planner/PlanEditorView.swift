import SwiftUI
import AppKit

struct PlanEditorView: View {
    @Binding var plan: NativeProjectPlan
    @State private var analysis: NativePlanAnalysis
    @State private var analysisRefreshWorkItem: DispatchWorkItem?

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
    private let milestoneColumnWidth: CGFloat = 44
    private let predecessorsColumnWidth: CGFloat = 91
    private let resourceColumnWidth: CGFloat = 122
    private let assignmentUnitsColumnWidth: CGFloat = 62
    private let dividerWidth: CGFloat = 10
    private let minimumGridWidth: CGFloat = 420
    private let minimumInspectorWidth: CGFloat = 260
    private let supportedConstraintTypes = ["ASAP", "SNET", "FNET", "MSO", "MFO"]

    private var selectedTaskIndex: Int? {
        guard let selectedTaskID else { return nil }
        return plan.tasks.firstIndex(where: { $0.id == selectedTaskID })
    }

    private var milestoneCount: Int {
        plan.tasks.filter(\.isMilestone).count
    }

    private var dependencyCount: Int {
        plan.tasks.reduce(0) { $0 + $1.predecessorTaskIDs.count }
    }

    private var baselineCount: Int {
        plan.tasks.filter { $0.baselineStartDate != nil || $0.baselineFinishDate != nil || $0.baselineDurationDays != nil }.count
    }

    private var currentProject: ProjectModel {
        analysis.project
    }

    private var currentProjectEVM: EVMMetrics {
        analysis.evm
    }

    private var totalPlannedCost: Double {
        currentProject.tasks
            .filter { $0.summary != true }
            .compactMap(\.cost)
            .reduce(0, +)
    }

    private var validationIssues: [ProjectValidationIssue] {
        analysis.validationIssues
    }

    private var diagnosticItems: [ProjectDiagnosticItem] {
        analysis.diagnosticItems
    }

    init(plan: Binding<NativeProjectPlan>) {
        self._plan = plan
        self._analysis = State(initialValue: NativePlanAnalysis.build(from: plan.wrappedValue))
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
        .sheet(item: $taskImportSession) { session in
            TaskCSVImportMappingSheet(
                session: session,
                onImport: { mappedSession in
                    if let result = CSVExporter.applyTaskImport(mappedSession, into: plan) {
                        plan = result.plan
                        selectedTaskID = plan.tasks.last?.id
                        lastTaskImportSession = mappedSession
                        importReport = result.report
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
                    }
                    baselineImportSession = nil
                },
                onCancel: {
                    baselineImportSession = nil
                }
            )
        }
        .sheet(item: $importReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastTaskImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenTaskImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: fixTaskImportIssue,
                onClose: {
                importReport = nil
                }
            )
        }
        .sheet(item: $dependencyImportReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastDependencyImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenDependencyImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil,
                onClose: {
                    dependencyImportReport = nil
                }
            )
        }
        .sheet(item: $constraintImportReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastConstraintImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenConstraintImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil,
                onClose: {
                    constraintImportReport = nil
                }
            )
        }
        .sheet(item: $baselineImportReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastBaselineImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenBaselineImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil,
                onClose: {
                    baselineImportReport = nil
                }
            )
        }
        .sheet(item: $assignmentImportReport) { report in
            CSVImportReportSheet(
                report: report,
                secondaryActionTitle: lastAssignmentImportSession == nil ? nil : "Adjust Mapping",
                onSecondaryAction: reopenAssignmentImportMapping,
                onSelectIssue: selectImportedTaskIssue,
                onFixIssue: nil,
                onClose: {
                    assignmentImportReport = nil
                }
            )
        }
        .onAppear {
            reschedulePlan()
            if selectedTaskID == nil {
                selectedTaskID = plan.tasks.first?.id
            }
        }
        .onChange(of: plan) { _, newPlan in
            scheduleAnalysisRefresh(for: newPlan)
        }
        .onChange(of: plan.tasks.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                return
            }

            if let selectedTaskID, ids.contains(selectedTaskID) {
                return
            }

            selectedTaskID = ids.first
        }
    }

    private func reopenTaskImportMapping() {
        guard let session = lastTaskImportSession else { return }
        importReport = nil
        DispatchQueue.main.async {
            taskImportSession = session
        }
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
        guard let targetID = issue.targetID, plan.tasks.contains(where: { $0.id == targetID }) else { return }
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
            if let taskIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) {
                plan.tasks[taskIndex].calendarUniqueID = calendarID
                selectedTaskID = taskID
                plan.reschedule()
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
        return calendar.id
    }

    private func removeIssueFromReport(_ issueID: UUID) {
        guard let report = importReport else { return }
        let remaining = report.issues.filter { $0.id != issueID }
        importReport = CSVImportReport(title: report.title, summaryLines: report.summaryLines, issues: remaining)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan Builder")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create and save native project plans, then use the existing analysis views to review them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                FinancialTermsButton()

                Spacer()

                HStack(spacing: 18) {
                    summaryMetric(value: "\(plan.tasks.count)", label: "Tasks")
                    summaryMetric(value: "\(milestoneCount)", label: "Milestones")
                    summaryMetric(value: "\(dependencyCount)", label: "Dependencies")
                    summaryMetric(value: "\(baselineCount)", label: "Baselined")
                    summaryMetric(value: currencyText(totalPlannedCost), label: "Planned Cost")
                    summaryMetric(value: currencyText(currentProjectEVM.bac), label: "BAC")
                    summaryMetric(value: currencyText(currentProjectEVM.ac), label: "Actual Cost")
                    summaryMetric(value: safeRatioText(currentProjectEVM.cpi), label: "CPI")
                    summaryMetric(value: safeRatioText(currentProjectEVM.spi), label: "SPI")
                    summaryMetric(value: currencyText(currentProjectEVM.eac), label: "EAC")
                }
            }

            HStack(spacing: 10) {
                plannerSignalChip(
                    title: "Errors",
                    count: validationIssues.filter { $0.severity == .error }.count,
                    color: .red
                )
                plannerSignalChip(
                    title: "Warnings",
                    count: validationIssues.filter { $0.severity == .warning }.count,
                    color: .orange
                )
                plannerSignalChip(
                    title: "Info",
                    count: validationIssues.filter { $0.severity == .info }.count,
                    color: .blue
                )
                plannerSignalChip(
                    title: "Diagnostics",
                    count: diagnosticItems.count,
                    color: .purple
                )
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 12) {
                TextField("Project Title", text: $plan.title)
                    .textFieldStyle(.roundedBorder)

                TextField("Manager", text: $plan.manager)
                    .textFieldStyle(.roundedBorder)

                TextField("Company", text: $plan.company)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PlannerDateField(date: $plan.statusDate)
                        .frame(width: 150)
                }
            }
        }
        .padding(16)
    }

    private func taskListPane() -> some View {
        GeometryReader { geometry in
            let contentWidth = geometry.size.width
            let layout = gridLayout(for: contentWidth)

            VStack(spacing: 0) {
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
                            Button {
                                taskImportSession = CSVExporter.selectTaskImportSession()
                            } label: {
                                wrappedToolbarLabel("Import CSV/Excel", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .help("Import tasks from CSV or Excel-compatible spreadsheet")

                            Button {
                                assignmentImportSession = CSVExporter.selectAssignmentImportSession()
                            } label: {
                                wrappedToolbarLabel("Import Assignments", systemImage: "person.crop.rectangle.stack.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .help("Import task-resource assignments from CSV or Excel-compatible spreadsheet")

                            Button {
                                dependencyImportSession = CSVExporter.selectDependencyImportSession()
                            } label: {
                                wrappedToolbarLabel("Import Dependencies", systemImage: "arrow.triangle.branch", width: 138)
                            }
                            .buttonStyle(.bordered)
                            .help("Import predecessor links from CSV or Excel-compatible spreadsheet")

                            Button {
                                constraintImportSession = CSVExporter.selectConstraintImportSession()
                            } label: {
                                wrappedToolbarLabel("Import Constraints", systemImage: "calendar.badge.exclamationmark")
                            }
                            .buttonStyle(.bordered)
                            .help("Import scheduling constraints from CSV or Excel-compatible spreadsheet")

                            Button {
                                baselineImportSession = CSVExporter.selectBaselineImportSession()
                            } label: {
                                wrappedToolbarLabel("Import Baseline", systemImage: "flag.pattern.checkered")
                            }
                            .buttonStyle(.bordered)
                            .help("Import task baseline dates or durations from CSV or Excel-compatible spreadsheet")
                        }

                        HStack(spacing: 8) {
                            Menu {
                                Button("Task CSV Template") {
                                    CSVExporter.exportTaskImportTemplateCSV()
                                }
                                Button("Task Excel Example") {
                                    CSVExporter.exportTaskImportTemplateExcel()
                                }
                                Divider()
                                Button("Assignment CSV Template") {
                                    CSVExporter.exportAssignmentImportTemplateCSV()
                                }
                                Button("Assignment Excel Example") {
                                    CSVExporter.exportAssignmentImportTemplateExcel()
                                }
                                Divider()
                                Button("Dependency CSV Template") {
                                    CSVExporter.exportDependencyImportTemplateCSV()
                                }
                                Button("Dependency Excel Example") {
                                    CSVExporter.exportDependencyImportTemplateExcel()
                                }
                                Divider()
                                Button("Constraint CSV Template") {
                                    CSVExporter.exportConstraintImportTemplateCSV()
                                }
                                Button("Constraint Excel Example") {
                                    CSVExporter.exportConstraintImportTemplateExcel()
                                }
                                Divider()
                                Button("Baseline CSV Template") {
                                    CSVExporter.exportBaselineImportTemplateCSV()
                                }
                                Button("Baseline Excel Example") {
                                    CSVExporter.exportBaselineImportTemplateExcel()
                                }
                            } label: {
                                wrappedToolbarLabel("Templates", systemImage: "tablecells.badge.ellipsis")
                            }
                            .menuStyle(.borderlessButton)
                            .help("Export ready-made task, assignment, dependency, constraint, and baseline import templates")

                            Button {
                                plan.captureBaseline()
                            } label: {
                                wrappedToolbarLabel("Capture Baseline", systemImage: "camera.macro")
                            }
                            .buttonStyle(.bordered)
                            .disabled(plan.tasks.isEmpty)
                            .help("Store the current scheduled dates as the working baseline")

                            Button {
                                addTask(focus: .name)
                            } label: {
                                wrappedToolbarLabel("Add Task", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: [.command])
                            .help("Add task below selected row (Command-Return)")

                            Button {
                                indentSelectedTask()
                            } label: {
                                Image(systemName: "increase.indent")
                            }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("]", modifiers: [.command])
                            .disabled(!canIndentSelectedTask())
                            .help("Make selected task a child of the previous task (Command-])")

                            Button {
                                outdentSelectedTask()
                            } label: {
                                Image(systemName: "decrease.indent")
                            }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("[", modifiers: [.command])
                            .disabled(!canOutdentSelectedTask())
                            .help("Promote selected task one level (Command-[)")

                            Button {
                                duplicateSelectedTask()
                            } label: {
                                Image(systemName: "plus.square.on.square")
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedTaskIndex == nil)
                            .help("Duplicate selected task")

                            Button {
                                moveSelectedTaskUp()
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canMoveSelectedTaskUp())
                            .help("Move selected task block up")

                            Button {
                                moveSelectedTaskDown()
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canMoveSelectedTaskDown())
                            .help("Move selected task block down")

                            Button(role: .destructive) {
                                deleteSelectedTask()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(selectedTaskIndex == nil)
                            .help("Delete selected task")

                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.bar)

                HStack(spacing: 12) {
                    taskShortcutHint("Tab", description: "Next cell")
                    taskShortcutHint("Shift+Tab", description: "Previous cell")
                    taskShortcutHint("Enter", description: "Down same column")
                    taskShortcutHint("Cmd+Return", description: "New row")
                    taskShortcutHint("Cmd+[ / ]", description: "Outdent / indent")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                if plan.tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks Yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Start by adding the first task for this plan.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        VStack(spacing: 0) {
                            taskGridHeader(layout: layout)

                            LazyVStack(spacing: 0) {
                                ForEach($plan.tasks) { $task in
                                    taskGridRow(task: $task, layout: layout)
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
        .help("Drag to resize the task details pane")
    }

    private func taskGridHeader(layout: PlannerGridLayout) -> some View {
        HStack(spacing: 0) {
            taskHeaderCell("ID", width: layout.id, alignment: .leading)
            taskHeaderCell("Task Name", width: layout.name, alignment: .leading)
            taskHeaderCell("Start", width: layout.start, alignment: .leading)
            taskHeaderCell("Finish", width: layout.finish, alignment: .leading)
            taskHeaderCell("Dur", width: layout.duration, alignment: .center)
            taskHeaderCell("%", width: layout.percent, alignment: .center)
            taskHeaderCell("MS", width: layout.milestone, alignment: .center)
            taskHeaderCell("Preds", width: layout.predecessors, alignment: .leading)
            taskHeaderCell("Resource", width: layout.resource, alignment: .leading)
            taskHeaderCell("Units", width: layout.assignmentUnits, alignment: .center)
        }
        .frame(height: 30)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func taskGridRow(task: Binding<NativePlanTask>, layout: PlannerGridLayout) -> some View {
        let isSelected = selectedTaskID == task.wrappedValue.id
        let isLastRow = plan.tasks.last?.id == task.wrappedValue.id
        let taskIndex = plan.tasks.firstIndex(where: { $0.id == task.wrappedValue.id })
        let isSummary = taskIndex.map(taskHasChildren(at:)) ?? false
        let indentWidth = CGFloat(max(0, task.wrappedValue.outlineLevel - 1)) * 16

        return HStack(spacing: 0) {
            taskValueCell(width: layout.id, alignment: .leading) {
                Text("#\(task.wrappedValue.id)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            taskValueCell(width: layout.name, alignment: .leading) {
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: indentWidth, height: 1)

                    if isSummary {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    PlannerGridTextField(
                        text: task.name,
                        placeholder: "Task Name",
                        shouldBecomeFirstResponder: shouldFocus(taskID: task.wrappedValue.id, column: .name),
                        onReturn: {
                            moveDownInGrid(fromTaskID: task.wrappedValue.id, column: .name)
                        },
                        onFocused: {
                            selectedTaskID = task.wrappedValue.id
                            clearPendingFocusIfNeeded(taskID: task.wrappedValue.id, column: .name)
                        },
                        fontWeight: isSummary ? .semibold : .regular
                    )
                }
            }

            taskValueCell(width: layout.start, alignment: .leading) {
                PlannerDateField(date: startDateBinding(for: task))
            }

            taskValueCell(width: layout.finish, alignment: .leading) {
                PlannerDateField(date: finishDateBinding(for: task))
            }

            taskValueCell(width: layout.duration, alignment: .center) {
                PlannerGridTextField(
                    text: durationDaysTextBinding(for: task),
                    placeholder: task.wrappedValue.isMilestone ? "0" : "1",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocus(taskID: task.wrappedValue.id, column: .duration),
                    onReturn: {
                        moveDownInGrid(fromTaskID: task.wrappedValue.id, column: .duration)
                    },
                    onFocused: {
                        selectedTaskID = task.wrappedValue.id
                        clearPendingFocusIfNeeded(taskID: task.wrappedValue.id, column: .duration)
                    }
                )
            }

            taskValueCell(width: layout.percent, alignment: .center) {
                PlannerGridTextField(
                    text: percentTextBinding(for: task),
                    placeholder: "0",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocus(taskID: task.wrappedValue.id, column: .percent),
                    onReturn: {
                        moveDownInGrid(fromTaskID: task.wrappedValue.id, column: .percent)
                    },
                    onFocused: {
                        selectedTaskID = task.wrappedValue.id
                        clearPendingFocusIfNeeded(taskID: task.wrappedValue.id, column: .percent)
                    }
                )
            }

            taskValueCell(width: layout.milestone, alignment: .center) {
                Toggle("", isOn: milestoneBinding(for: task))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }

            taskValueCell(width: layout.predecessors, alignment: .leading) {
                PlannerGridTextField(
                    text: predecessorsBinding(for: task),
                    placeholder: "1, 3",
                    shouldBecomeFirstResponder: shouldFocus(taskID: task.wrappedValue.id, column: .predecessors),
                    onReturn: {
                        moveDownInGrid(fromTaskID: task.wrappedValue.id, column: .predecessors)
                    },
                    onFocused: {
                        selectedTaskID = task.wrappedValue.id
                        clearPendingFocusIfNeeded(taskID: task.wrappedValue.id, column: .predecessors)
                    }
                )
            }

            taskValueCell(width: layout.resource, alignment: .leading) {
                if plan.resources.isEmpty {
                    Text("No resources")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "",
                        selection: primaryAssignmentResourceBinding(for: task.wrappedValue.id)
                    ) {
                        Text("None").tag(Int?.none)
                        ForEach(plan.resources) { resource in
                            Text(resource.name).tag(Optional(resource.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onTapGesture {
                        selectedTaskID = task.wrappedValue.id
                    }
                }
            }

            taskValueCell(width: layout.assignmentUnits, alignment: .center) {
                PlannerGridTextField(
                    text: primaryAssignmentUnitsTextBinding(for: task.wrappedValue.id),
                    placeholder: "--",
                    alignment: .center,
                    shouldBecomeFirstResponder: shouldFocus(taskID: task.wrappedValue.id, column: .assignmentUnits),
                    onTab: isLastRow ? {
                        addTask(after: task.wrappedValue.id, focus: .name)
                    } : nil,
                    onReturn: {
                        moveDownInGrid(fromTaskID: task.wrappedValue.id, column: .assignmentUnits)
                    },
                    onFocused: {
                        selectedTaskID = task.wrappedValue.id
                        clearPendingFocusIfNeeded(taskID: task.wrappedValue.id, column: .assignmentUnits)
                    }
                )
            }
        }
        .frame(height: 34)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTaskID = task.wrappedValue.id
        }
    }

    private var inspectorPane: some View {
        Group {
            if let taskBinding = selectedTaskBinding() {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        GroupBox("Task Basics") {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Task Name", text: taskBinding.name)
                                    .textFieldStyle(.roundedBorder)

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Start")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PlannerDateField(date: startDateBinding(for: taskBinding))
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Finish")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    PlannerDateField(date: finishDateBinding(for: taskBinding))
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        outdentSelectedTask()
                                    } label: {
                                        Label("Left", systemImage: "decrease.indent")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!canOutdentSelectedTask())

                                    Button {
                                        indentSelectedTask()
                                    } label: {
                                        Label("Right", systemImage: "increase.indent")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!canIndentSelectedTask())
                                }

                                HStack(spacing: 12) {
                                    Toggle("Milestone", isOn: milestoneBinding(for: taskBinding))
                                    Toggle("Active", isOn: taskBinding.isActive)
                                }

                                Toggle("Manual Scheduling", isOn: manualSchedulingBinding(for: taskBinding))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Duration (working days)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("1", text: durationDaysTextBinding(for: taskBinding))
                                        .textFieldStyle(.roundedBorder)
                                }

                                if !plan.calendars.isEmpty {
                                    Picker("Task Calendar", selection: taskCalendarBinding(for: taskBinding)) {
                                        Text("Project Default").tag(Int?.none)
                                        ForEach(plan.calendars) { calendar in
                                            Text(calendar.name).tag(Optional(calendar.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }

                                Picker("Constraint", selection: constraintTypeBinding(for: taskBinding)) {
                                    ForEach(supportedConstraintTypes, id: \.self) { type in
                                        Text(type).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                if constraintTypeBinding(for: taskBinding).wrappedValue != "ASAP" {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Constraint Date")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        PlannerDateField(date: constraintDateBinding(for: taskBinding))
                                    }
                                }

                                Text(taskBinding.wrappedValue.manuallyScheduled
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
                                    Slider(value: taskBinding.percentComplete, in: 0 ... 100, step: 5)
                                    Text("\(Int(taskBinding.wrappedValue.percentComplete))%")
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .monospacedDigit()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Priority")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Stepper(value: taskBinding.priority, in: 0 ... 1000, step: 50) {
                                        Text("\(taskBinding.wrappedValue.priority)")
                                            .monospacedDigit()
                                    }
                                }

                                Divider()

                                actualDateEditor(
                                    title: "Actual Start",
                                    date: taskBinding.wrappedValue.actualStartDate,
                                    setCurrent: { taskBinding.wrappedValue.actualStartDate = Calendar.current.startOfDay(for: taskBinding.wrappedValue.startDate)
                                        if taskBinding.wrappedValue.percentComplete == 0 {
                                            taskBinding.wrappedValue.percentComplete = 1
                                        }
                                    },
                                    clear: { taskBinding.wrappedValue.actualStartDate = nil },
                                    binding: actualStartDateBinding(for: taskBinding)
                                )

                                actualDateEditor(
                                    title: "Actual Finish",
                                    date: taskBinding.wrappedValue.actualFinishDate,
                                    setCurrent: {
                                        taskBinding.wrappedValue.actualStartDate = taskBinding.wrappedValue.actualStartDate ?? Calendar.current.startOfDay(for: taskBinding.wrappedValue.startDate)
                                        taskBinding.wrappedValue.actualFinishDate = Calendar.current.startOfDay(for: taskBinding.wrappedValue.finishDate)
                                        taskBinding.wrappedValue.percentComplete = 100
                                    },
                                    clear: { taskBinding.wrappedValue.actualFinishDate = nil },
                                    binding: actualFinishDateBinding(for: taskBinding)
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Dependencies") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Predecessor IDs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Example: 1, 3, 7", text: predecessorsBinding(for: taskBinding))
                                    .textFieldStyle(.roundedBorder)
                                Text("Only finish-to-start links are supported in this first planning slice.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Baseline") {
                            VStack(alignment: .leading, spacing: 10) {
                                if taskBinding.wrappedValue.baselineStartDate == nil,
                                   taskBinding.wrappedValue.baselineFinishDate == nil,
                                   taskBinding.wrappedValue.baselineDurationDays == nil {
                                    Text("No baseline stored for this task yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    baselineField(title: "Baseline Start", value: baselineDateText(taskBinding.wrappedValue.baselineStartDate))
                                    baselineField(title: "Baseline Finish", value: baselineDateText(taskBinding.wrappedValue.baselineFinishDate))
                                    baselineField(title: "Baseline Duration", value: baselineDurationText(for: taskBinding.wrappedValue))
                                    baselineField(title: "Start Variance", value: varianceText(current: taskBinding.wrappedValue.startDate, baseline: taskBinding.wrappedValue.baselineStartDate))
                                    baselineField(title: "Finish Variance", value: varianceText(current: taskBinding.wrappedValue.finishDate, baseline: taskBinding.wrappedValue.baselineFinishDate))
                                }

                                Button("Capture Current Plan as Baseline") {
                                    plan.captureBaseline()
                                }
                                .buttonStyle(.bordered)
                                .disabled(plan.tasks.isEmpty)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Financials") {
                            VStack(alignment: .leading, spacing: 12) {
                                let summary = financialSummary(for: taskBinding.wrappedValue.id)
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
                                    StableDecimalTextField(title: "0", text: fixedCostTextBinding(for: taskBinding))
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isSummaryTask)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Baseline Cost Override")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDecimalTextField(title: "Auto from current plan", text: baselineCostTextBinding(for: taskBinding))
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(isSummaryTask)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Actual Cost Override")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    StableDecimalTextField(title: "Auto from progress and actual work", text: actualCostTextBinding(for: taskBinding))
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
                                    let assignmentIndices = taskAssignmentIndices(for: taskBinding.wrappedValue.id)

                                    if assignmentIndices.isEmpty {
                                        Text("No resources assigned yet.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(assignmentIndices, id: \.self) { assignmentIndex in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Picker(
                                                    "Resource",
                                                    selection: assignmentResourceBinding(for: assignmentIndex)
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
                                                            value: assignmentUnitsBinding(for: assignmentIndex),
                                                            in: 0 ... 300,
                                                            step: 25
                                                        )
                                                    }

                                                    Text("\(Int(plan.assignments[assignmentIndex].units))%")
                                                        .monospacedDigit()
                                                        .frame(width: 52, alignment: .trailing)
                                                }

                                                TextField("Assignment Notes", text: $plan.assignments[assignmentIndex].notes)
                                                    .textFieldStyle(.roundedBorder)

                                                HStack(spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Work (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField("Auto", text: assignmentWorkHoursTextBinding(for: assignmentIndex))
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Actual (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField("Auto", text: assignmentActualWorkHoursTextBinding(for: assignmentIndex))
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Remaining (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField("Auto", text: assignmentRemainingWorkHoursTextBinding(for: assignmentIndex))
                                                            .textFieldStyle(.roundedBorder)
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text("Overtime (h)")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                        TextField("0", text: assignmentOvertimeWorkHoursTextBinding(for: assignmentIndex))
                                                            .textFieldStyle(.roundedBorder)
                                                    }
                                                }

                                                if let assignmentCost = primaryAssignmentCost(for: plan.assignments[assignmentIndex].id) {
                                                    Text("Planned Cost: \(currencyText(assignmentCost))")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }

                                                HStack {
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        plan.assignments.remove(at: assignmentIndex)
                                                    } label: {
                                                        Label("Remove", systemImage: "trash")
                                                    }
                                                    .buttonStyle(.borderless)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }

                                    Button {
                                        addAssignment(to: taskBinding.wrappedValue.id)
                                    } label: {
                                        Label("Add Assignment", systemImage: "plus")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GroupBox("Notes") {
                            TextEditor(text: taskBinding.notes)
                                .frame(minHeight: 160)
                                .font(.body)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func selectedTaskBinding() -> Binding<NativePlanTask>? {
        guard let selectedTaskIndex else { return nil }
        return $plan.tasks[selectedTaskIndex]
    }

    private func addTask(after taskID: Int? = nil, focus: PlannerGridColumn? = nil) {
        let insertionAnchorIndex: Int?
        if let taskID {
            insertionAnchorIndex = plan.tasks.firstIndex(where: { $0.id == taskID })
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
        guard let selectedTaskIndex else { return }
        var duplicate = plan.tasks[selectedTaskIndex]
        duplicate.id = plan.nextTaskID()
        duplicate.name += " Copy"
        duplicate.predecessorTaskIDs = duplicate.predecessorTaskIDs.filter { $0 != duplicate.id }
        let insertionIndex = subtreeRange(for: selectedTaskIndex).upperBound
        plan.tasks.insert(duplicate, at: insertionIndex)
        reschedulePlan()
        selectedTaskID = duplicate.id
    }

    private func deleteSelectedTask() {
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
        let newLevel = plan.tasks[selectedTaskIndex - 1].outlineLevel + 1
        let delta = newLevel - plan.tasks[selectedTaskIndex].outlineLevel
        adjustSelectedSubtreeOutlineLevel(by: delta)
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
        guard let selectedTaskIndex else { return }
        let range = subtreeRange(for: selectedTaskIndex)
        for index in range {
            plan.tasks[index].outlineLevel = max(1, plan.tasks[index].outlineLevel + delta)
        }
        reschedulePlan()
    }

    private func canMoveSelectedTaskUp() -> Bool {
        previousSiblingRootIndex(for: selectedTaskIndex)
            .map { _ in true } ?? false
    }

    private func moveSelectedTaskUp() {
        guard let selectedTaskIndex,
              let previousSiblingIndex = previousSiblingRootIndex(for: selectedTaskIndex) else { return }

        let selectedRange = subtreeRange(for: selectedTaskIndex)
        let movingTasks = Array(plan.tasks[selectedRange])
        plan.tasks.removeSubrange(selectedRange)
        plan.tasks.insert(contentsOf: movingTasks, at: previousSiblingIndex)
        reschedulePlan()
        selectedTaskID = movingTasks.first?.id
    }

    private func canMoveSelectedTaskDown() -> Bool {
        nextSiblingRootIndex(for: selectedTaskIndex)
            .map { _ in true } ?? false
    }

    private func moveSelectedTaskDown() {
        guard let selectedTaskIndex,
              let nextSiblingIndex = nextSiblingRootIndex(for: selectedTaskIndex) else { return }

        let selectedRange = subtreeRange(for: selectedTaskIndex)
        let movingTasks = Array(plan.tasks[selectedRange])
        let nextSiblingRange = subtreeRange(for: nextSiblingIndex)
        plan.tasks.removeSubrange(selectedRange)
        let insertionIndex = nextSiblingRange.upperBound - selectedRange.count
        plan.tasks.insert(contentsOf: movingTasks, at: insertionIndex)
        reschedulePlan()
        selectedTaskID = movingTasks.first?.id
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

    private func taskHasChildren(at index: Int) -> Bool {
        guard plan.tasks.indices.contains(index + 1) else { return false }
        return plan.tasks[index + 1].outlineLevel > plan.tasks[index].outlineLevel
    }

    private func moveDownInGrid(fromTaskID taskID: Int, column: PlannerGridColumn) {
        guard let currentIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        if plan.tasks.indices.contains(currentIndex + 1) {
            let nextTaskID = plan.tasks[currentIndex + 1].id
            selectedTaskID = nextTaskID
            pendingGridFocusTarget = PlannerGridFocusTarget(taskID: nextTaskID, column: column)
            return
        }

        addTask(after: taskID, focus: column)
    }

    private func shouldFocus(taskID: Int, column: PlannerGridColumn) -> Bool {
        pendingGridFocusTarget == PlannerGridFocusTarget(taskID: taskID, column: column)
    }

    private func clearPendingFocusIfNeeded(taskID: Int, column: PlannerGridColumn) {
        if pendingGridFocusTarget == PlannerGridFocusTarget(taskID: taskID, column: column) {
            pendingGridFocusTarget = nil
        }
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
                reschedulePlan()
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

                reschedulePlan()
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
                reschedulePlan()
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
                reschedulePlan()
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
                reschedulePlan()
            }
        )
    }

    private func constraintDateBinding(for task: Binding<NativePlanTask>) -> Binding<Date> {
        Binding(
            get: { task.wrappedValue.constraintDate ?? task.wrappedValue.startDate },
            set: { newValue in
                task.wrappedValue.constraintDate = Calendar.current.startOfDay(for: newValue)
                reschedulePlan()
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

                reschedulePlan()
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
        plan.assignments.indices.filter { plan.assignments[$0].taskID == taskID }
    }

    private func primaryAssignmentIndex(for taskID: Int) -> Int? {
        taskAssignmentIndices(for: taskID).first
    }

    private func addAssignment(to taskID: Int) {
        let defaultResourceID = plan.resources.first?.id
        plan.assignments.append(plan.makeAssignment(taskID: taskID, resourceID: defaultResourceID))
    }

    private func primaryAssignmentResourceBinding(for taskID: Int) -> Binding<Int?> {
        Binding(
            get: {
                primaryAssignmentIndex(for: taskID).flatMap { plan.assignments[$0].resourceID }
            },
            set: { newValue in
                if let index = primaryAssignmentIndex(for: taskID) {
                    if let newValue {
                        plan.assignments[index].resourceID = newValue
                    } else {
                        plan.assignments.remove(at: index)
                    }
                } else if let newValue {
                    plan.assignments.append(plan.makeAssignment(taskID: taskID, resourceID: newValue))
                }
            }
        )
    }

    private func primaryAssignmentUnitsTextBinding(for taskID: Int) -> Binding<String> {
        Binding(
            get: {
                guard let index = primaryAssignmentIndex(for: taskID) else { return "" }
                return String(Int(plan.assignments[index].units))
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)

                guard !digits.isEmpty else {
                    if let index = primaryAssignmentIndex(for: taskID) {
                        plan.assignments[index].units = 0
                    }
                    return
                }

                let parsed = min(300.0, max(0.0, Double(digits) ?? 0))
                if let index = primaryAssignmentIndex(for: taskID) {
                    plan.assignments[index].units = parsed
                } else {
                    var assignment = plan.makeAssignment(taskID: taskID, resourceID: plan.resources.first?.id)
                    assignment.units = parsed
                    plan.assignments.append(assignment)
                }
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

    private func reschedulePlan() {
        let selectedTaskID = selectedTaskID
        plan.reschedule()
        refreshAnalysis(for: plan)
        self.selectedTaskID = selectedTaskID ?? plan.tasks.first?.id
    }

    private func refreshAnalysis(for plan: NativeProjectPlan) {
        analysisRefreshWorkItem?.cancel()
        analysis = NativePlanAnalysis.build(from: plan)
    }

    private func scheduleAnalysisRefresh(for plan: NativeProjectPlan) {
        analysisRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            analysis = NativePlanAnalysis.build(from: plan)
        }
        analysisRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
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

        let calendarsByID = Dictionary(uniqueKeysWithValues: plan.calendars.map { ($0.id, $0.asProjectCalendar()) })
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

    private func summaryMetric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func taskShortcutHint(_ shortcut: String, description: String) -> some View {
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

    private func wrappedToolbarLabel(_ title: String, systemImage: String, width: CGFloat = 120) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
        .frame(width: width, alignment: .leading)
    }

    private func plannerSignalChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
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
                        .buttonStyle(.borderless)
                }
            } else {
                HStack(spacing: 8) {
                    Text("Not set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Use Scheduled", action: setCurrent)
                        .buttonStyle(.bordered)
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
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

    private var fixedGridColumnsWidth: CGFloat {
        idColumnWidth +
        startColumnWidth +
        finishColumnWidth +
        durationColumnWidth +
        percentColumnWidth +
        milestoneColumnWidth +
        predecessorsColumnWidth +
        resourceColumnWidth +
        assignmentUnitsColumnWidth
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
            start: startColumnWidth * scale,
            finish: finishColumnWidth * scale,
            duration: durationColumnWidth * scale,
            percent: percentColumnWidth * scale,
            milestone: milestoneColumnWidth * scale,
            predecessors: predecessorsColumnWidth * scale,
            resource: resourceColumnWidth * scale,
            assignmentUnits: assignmentUnitsColumnWidth * scale
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

private struct PlannerGridLayout {
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
        DatePicker("", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlannerGridTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var alignment: NSTextAlignment = .left
    var shouldBecomeFirstResponder = false
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
        if nsView.stringValue != text {
            nsView.stringValue = text
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

        init(_ parent: PlannerGridTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocused?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)),
               let onTab = parent.onTab {
                onTab()
                return true
            }

            if commandSelector == #selector(NSResponder.insertBacktab(_:)),
               let onBackTab = parent.onBackTab {
                onBackTab()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               let onReturn = parent.onReturn {
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
}
