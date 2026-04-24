import SwiftUI
import SwiftData

private enum GanttInteractionMode: String, CaseIterable, Identifiable {
    case view = "View"
    case edit = "Edit"

    var id: String { rawValue }
}

private struct GanttFinancialSummary {
    let plannedCost: Double
    let budgetAtCompletion: Double
    let plannedValue: Double
    let earnedValue: Double
    let actualCost: Double

    static let zero = GanttFinancialSummary(
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

    var estimateAtCompletion: Double {
        guard actualCost > 0, earnedValue > 0 else { return budgetAtCompletion }
        let cpi = earnedValue / actualCost
        return cpi > 0 ? budgetAtCompletion / cpi : budgetAtCompletion
    }

    var varianceAtCompletion: Double {
        budgetAtCompletion - estimateAtCompletion
    }
}

private enum GanttInspectorTab: String, CaseIterable, Identifiable {
    case task = "Task"
    case links = "Links"
    case staffing = "Staffing"
    case finance = "Finance"

    var id: String { rawValue }
}

struct GanttDependencySelection: Equatable, Identifiable {
    let predecessorID: Int
    let successorID: Int

    var id: String { "\(predecessorID)->\(successorID)" }
}

private struct GanttDerivedContent {
    let flatTasks: [ProjectTask]
    let taskIDs: [Int]
    let rowIndexByTaskID: [Int: Int]
    let dateRange: (start: Date, end: Date)
    let totalDays: Int

    static func build(project: ProjectModel, searchText: String) -> GanttDerivedContent {
        let root = if searchText.isEmpty {
            project.rootTasks
        } else {
            project.tasks.filter { $0.name?.localizedCaseInsensitiveContains(searchText) == true }
        }

        let flatTasks = flattenVisible(root)
        let taskIDs = flatTasks.map(\.uniqueID)
        let rowIndexByTaskID = Dictionary(nonThrowingUniquePairs: flatTasks.enumerated().map { ($1.uniqueID, $0) })
        let dateRange = GanttDateHelpers.dateRange(for: project.tasks)
        return GanttDerivedContent(
            flatTasks: flatTasks,
            taskIDs: taskIDs,
            rowIndexByTaskID: rowIndexByTaskID,
            dateRange: dateRange,
            totalDays: GanttDateHelpers.totalDays(for: dateRange)
        )
    }

    private static func flattenVisible(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        result.reserveCapacity(tasks.count)
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty {
                result.append(contentsOf: flattenVisible(task.children))
            }
        }
        return result
    }
}

private struct GanttTaskSnapshot: Equatable {
    let id: Int
    let name: String
    let start: String
    let finish: String
}

private struct GanttDerivedInput: Equatable {
    let searchText: String
    let statusDate: String
    let tasks: [GanttTaskSnapshot]

    init(project: ProjectModel, searchText: String) {
        self.searchText = searchText
        self.statusDate = project.properties.statusDate ?? ""
        self.tasks = project.tasks.map {
            GanttTaskSnapshot(
                id: $0.uniqueID,
                name: $0.name ?? "",
                start: $0.start ?? "",
                finish: $0.finish ?? ""
            )
        }
    }
}

private struct GanttTimelineViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct GanttChartView: View {
    @Environment(\.modelContext) private var modelContext

    let project: ProjectModel
    let searchText: String
    let planModel: PortfolioProjectPlan?

    @State private var derivedContent: GanttDerivedContent
    @State private var timelineVisibleRect: CGRect = .zero

    @State private var pixelsPerDay: CGFloat = 8
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var timelineViewportHeight: CGFloat = 0
    @State private var shouldAutoFitTimeline = true
    @State private var rowHeight: CGFloat = 24
    @State private var criticalPathOnly: Bool = false
    @State private var showBaseline: Bool = false
    @State private var selectedTaskID: Int?
    @State private var pendingDependencySourceTaskID: Int?
    @State private var selectedDependency: GanttDependencySelection?
    @State private var interactionMode: GanttInteractionMode = .view
    @State private var inspectorTab: GanttInspectorTab = .task
    @GestureState private var magnifyBy: CGFloat = 1.0

    private let exportTaskListWidth: CGFloat = 280
    private let ganttConstraintOptions = ["None", "ASAP", "SNET", "FNET", "MSO", "MFO"]

    private var flatTasks: [ProjectTask] {
        derivedContent.flatTasks
    }

    private var derivedInput: GanttDerivedInput {
        GanttDerivedInput(project: project, searchText: searchText)
    }

    private var dateRange: (start: Date, end: Date) {
        derivedContent.dateRange
    }

    private var totalDays: Int {
        derivedContent.totalDays
    }

    private var isNativeEditablePlan: Bool {
        planModel != nil
    }

    private var nativeTasks: [NativePlanTask] {
        planModel?.nativeTasksForUI ?? []
    }

    private var nativeAssignments: [NativePlanAssignment] {
        planModel?.nativeAssignmentsForUI ?? []
    }

    private var nativeResources: [NativePlanResource] {
        planModel?.nativeResourcesForUI ?? []
    }

    private var isEditingEnabled: Bool {
        isNativeEditablePlan && interactionMode == .edit
    }

    private var showsEditSidebar: Bool {
        isEditingEnabled
    }

    private var editableTaskIDs: Set<Int> {
        guard isEditingEnabled else { return [] }
        let nativeTaskIDs = Set(nativeTasks.map(\.id))
        return Set(derivedContent.taskIDs.filter { nativeTaskIDs.contains($0) && project.tasksByID[$0]?.summary != true })
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    private var selectedProjectTask: ProjectTask? {
        guard let selectedTaskID else { return nil }
        return project.tasksByID[selectedTaskID]
    }

    private var selectedNativeTask: NativePlanTask? {
        guard let selectedTaskID else { return nil }
        return nativeTasks.first(where: { $0.id == selectedTaskID })
    }

    private var selectedTaskFinancialSummary: GanttFinancialSummary {
        guard let projectTask = selectedProjectTask else { return .zero }
        return financialSummary(for: projectTask)
    }

    private var showsDockedSelectionPanel: Bool {
        showsEditSidebar
    }

    private var dockedSelectionPanelHeight: CGFloat {
        124
    }

    init(project: ProjectModel, searchText: String, planModel: PortfolioProjectPlan? = nil) {
        self.project = project
        self.searchText = searchText
        self.planModel = planModel
        self._derivedContent = State(initialValue: GanttDerivedContent.build(project: project, searchText: searchText))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if showsDockedSelectionPanel {
                dockedSelectionPanel
                Divider()
            }

            GanttLegendBar()

            Divider()

            if flatTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "chart.bar.xaxis")
            } else {
                GeometryReader { geometry in
                    let viewportWidth = max(geometry.size.width, 1)
                    let taskListWidth = showsEditSidebar ? preferredTaskListWidth(for: viewportWidth) : 0

                    ScrollView([.horizontal, .vertical]) {
                        ganttContent(taskListWidth: taskListWidth)
                            .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "GanttScrollViewport")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        timelineViewportWidth = viewportWidth
                        timelineViewportHeight = geometry.size.height
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: viewportWidth) { _, newWidth in
                        timelineViewportWidth = newWidth
                        timelineViewportHeight = geometry.size.height
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: totalDays) { _, _ in
                        applyAutoFitIfNeeded()
                    }
                    .onPreferenceChange(GanttTimelineViewportPreferenceKey.self) { rect in
                        timelineVisibleRect = rect
                    }
                }
                .gesture(
                    MagnifyGesture()
                        .updating($magnifyBy) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            shouldAutoFitTimeline = false
                            pixelsPerDay = min(100, max(2, pixelsPerDay * value.magnification))
                        }
                )
            }
        }
        .onAppear {
            refreshDerivedContent()
            interactionMode = .view
            pendingDependencySourceTaskID = nil
            selectedDependency = nil
            if selectedTaskID == nil {
                selectedTaskID = flatTasks.first?.uniqueID
            }
        }
        .onChange(of: derivedInput) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: planModel?.updatedAt) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: interactionMode) { _, mode in
            if mode == .view {
                pendingDependencySourceTaskID = nil
                selectedDependency = nil
            }
        }
        .onChange(of: derivedContent.taskIDs) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                pendingDependencySourceTaskID = nil
                selectedDependency = nil
                return
            }

            if let selectedTaskID, ids.contains(selectedTaskID) {
                return
            }

            self.selectedTaskID = ids.first

            if let selectedDependency,
               (!ids.contains(selectedDependency.predecessorID) || !ids.contains(selectedDependency.successorID)) {
                self.selectedDependency = nil
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func persistGanttStoreChanges(refreshMetrics: Bool = true) {
        guard let planModel else { return }
        planModel.updatedAt = Date()
        if refreshMetrics {
            planModel.refreshPortfolioMetrics()
        }
        try? modelContext.save()
    }

    private func withGanttTask(_ taskID: Int, refreshDerived: Bool = true, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel?.tasks.first(where: { $0.legacyID == taskID }) else { return }
        update(task)
        persistGanttStoreChanges()
        if refreshDerived {
            refreshDerivedContent()
        }
    }

    private func withGanttAssignment(_ assignmentID: Int, refreshDerived: Bool = true, _ update: (PortfolioPlanAssignment) -> Void) {
        guard let assignment = planModel?.tasks.flatMap(\.assignments).first(where: { $0.legacyID == assignmentID }) else { return }
        update(assignment)
        persistGanttStoreChanges()
        if refreshDerived {
            refreshDerivedContent()
        }
    }

    private func fullSyncGanttPlan(_ update: (inout NativeProjectPlan) -> Void) {
        guard let planModel else { return }
        var snapshot = planModel.asNativePlan()
        update(&snapshot)
        planModel.update(from: snapshot)
        persistGanttStoreChanges(refreshMetrics: true)
        refreshDerivedContent()
    }

    private var dockedSelectionPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            selectionPanel
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: dockedSelectionPanelHeight, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Gantt Chart")
                    .font(.headline)
                Text("(\(flatTasks.count) tasks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if isNativeEditablePlan {
                    Picker("Mode", selection: $interactionMode) {
                        ForEach(GanttInteractionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .help("Switch between review mode and direct editing mode for native plans.")
                }

                Button {
                    exportToPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    printGantt()
                } label: {
                    Label("Print", systemImage: "printer")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Toggle(isOn: $criticalPathOnly) {
                    Label("Critical Path", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(criticalPathOnly ? .red : nil)

                Toggle(isOn: $showBaseline) {
                    Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(showBaseline ? .gray : nil)

                Divider().frame(height: 16)

                GanttZoomControls(
                    pixelsPerDay: pixelsPerDay,
                    totalDays: totalDays,
                    onFitAll: {
                        shouldAutoFitTimeline = true
                        applyAutoFitIfNeeded()
                    },
                    onShowWeek: {
                        shouldAutoFitTimeline = false
                        pixelsPerDay = 40
                    },
                    onShowMonth: {
                        shouldAutoFitTimeline = false
                        pixelsPerDay = 10
                    },
                    onZoomOut: {
                        shouldAutoFitTimeline = false
                        pixelsPerDay = max(2, pixelsPerDay / 1.5)
                    },
                    onZoomIn: {
                        shouldAutoFitTimeline = false
                        pixelsPerDay = min(100, pixelsPerDay * 1.5)
                    }
                )
            }

            if isNativeEditablePlan {
                HStack(spacing: 10) {
                    Button {
                        addTaskFromGantt()
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isEditingEnabled)
                    .help("Insert a new task after the selected task or at the end of the plan.")

                    Button {
                        addSubtaskFromGantt()
                    } label: {
                        Label("Add Subtask", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isEditingEnabled || selectedTaskID == nil)
                    .help("Insert a child task under the selected task.")

                    Button {
                        indentSelectedTask()
                    } label: {
                        Label("Indent", systemImage: "arrow.right.to.line")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canIndentSelectedTask)
                    .help("Make the selected task a child of the row above.")

                    Button {
                        outdentSelectedTask()
                    } label: {
                        Label("Outdent", systemImage: "arrow.left.to.line")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canOutdentSelectedTask)
                    .help("Promote the selected task up one outline level.")

                    Button {
                        linkSelectedTaskToNext()
                    } label: {
                        Label("Link Next", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canLinkSelectedTaskToNext)
                    .help("Create a finish-to-start dependency from the selected task to the next visible task.")

                    Button {
                        togglePendingLinkMode()
                    } label: {
                        Label(
                            pendingDependencySourceTaskID == nil ? "Start Linking" : "Cancel Linking",
                            systemImage: pendingDependencySourceTaskID == nil ? "link.badge.plus" : "xmark"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEditingEnabled || selectedTaskID == nil)
                    .help("Start dependency linking for the selected task, then click the target row or bar.")

                    Button(role: .destructive) {
                        removeSelectedDependency()
                    } label: {
                        Label("Remove Link", systemImage: "link.badge.minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canRemoveSelectedDependency)
                    .help("Remove the selected dependency arrow from the plan.")

                    Button(role: .destructive) {
                        deleteSelectedTask()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canDeleteSelectedTask)
                    .help("Delete the selected task and its child tasks from the plan.")

                    Spacer()

                    Text(editStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var selectionPanel: some View {
        if let selectedDependency {
            dependencySelectionPanel(selectedDependency)
        } else if let nativeTask = selectedNativeTask,
                  let projectTask = selectedProjectTask {
            taskSelectionPanel(nativeTask: nativeTask, projectTask: projectTask)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.click")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Selection")
                        .font(.caption.weight(.semibold))
                    Text("Select a task or dependency in Edit mode to review it here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func dependencySelectionPanel(_ dependency: GanttDependencySelection) -> some View {
        let predecessorName = project.tasksByID[dependency.predecessorID]?.displayName ?? "Task \(dependency.predecessorID)"
        let successorName = project.tasksByID[dependency.successorID]?.displayName ?? "Task \(dependency.successorID)"

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dependency")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(predecessorName) -> \(successorName)")
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    compactInspectorChip("Finish-to-Start", tint: .accentColor)
                    compactInspectorChip("Selected", tint: .orange)
                }
            }

            Spacer()

            Button(role: .destructive) {
                removeDependency(
                    predecessorID: dependency.predecessorID,
                    successorID: dependency.successorID
                )
            } label: {
                Label("Remove Link", systemImage: "link.badge.minus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func taskSelectionPanel(nativeTask: NativePlanTask, projectTask: ProjectTask) -> some View {
        let hasConstraint = (selectedNativeTask?.constraintType ?? "").isEmpty == false
        let predecessorsSummary = selectedNativeTask?.predecessorTaskIDs.map(String.init).joined(separator: ", ") ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            Picker("Inspector Tab", selection: $inspectorTab) {
                ForEach(GanttInspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)

            switch inspectorTab {
            case .task:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Name")
                        TextField("Task Name", text: selectedTaskNameBinding())
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(minWidth: 220)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Start")
                        DatePicker("Start", selection: selectedTaskStartBinding(), displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                    }
                    .frame(width: 118)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Finish")
                        DatePicker("Finish", selection: selectedTaskFinishBinding(), displayedComponents: .date)
                            .datePickerStyle(.field)
                            .labelsHidden()
                    }
                    .frame(width: 118)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Duration")
                        Stepper(value: selectedTaskDurationBinding(), in: 1 ... 365) {
                            Text("\(nativeTask.isMilestone ? 0 : nativeTask.durationDays)d")
                                .font(.caption)
                                .frame(width: 54, alignment: .leading)
                        }
                    }
                    .frame(width: 92)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("WBS")
                        Text(projectTask.wbs ?? "None")
                            .font(.caption)
                            .foregroundStyle(projectTask.wbs == nil ? .secondary : .primary)
                            .frame(width: 74, alignment: .leading)
                    }
                    .frame(width: 74)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Constraint")
                        HStack(spacing: 8) {
                            Picker("Constraint", selection: selectedTaskConstraintBinding()) {
                                ForEach(ganttConstraintOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 132)

                            if hasConstraint {
                                DatePicker("Constraint Date", selection: selectedTaskConstraintDateBinding(), displayedComponents: .date)
                                    .datePickerStyle(.field)
                                    .labelsHidden()
                                    .frame(width: 118)
                            } else {
                                Text("No date")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        compactInspectorLabel("Flags")
                        HStack(spacing: 10) {
                            Toggle("Manual", isOn: selectedTaskManualBinding())
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .help("Turn manual scheduling on or off for the selected task.")

                            Toggle("Milestone", isOn: selectedTaskMilestoneBinding())
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .help("Turn the selected task into a milestone or regular task.")
                        }
                        .font(.caption)

                        if nativeTask.isMilestone {
                            compactInspectorChip("Milestone", tint: .orange)
                        }
                    }

                    Spacer(minLength: 0)
                }
            case .links:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Predecessors")
                        TextField("12, 18", text: selectedTaskPredecessorsBinding())
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(minWidth: 180)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Current Links")
                        Text(predecessorsSummary.isEmpty ? "None" : predecessorsSummary)
                            .font(.caption)
                            .foregroundStyle(predecessorsSummary.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 160)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Quick Actions")
                        HStack(spacing: 8) {
                            Button {
                                linkSelectedTaskToNext()
                            } label: {
                                Label("Link Next", systemImage: "link")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canLinkSelectedTaskToNext)

                            Button {
                                togglePendingLinkMode()
                            } label: {
                                Label(
                                    pendingDependencySourceTaskID == nil ? "Start Linking" : "Cancel Linking",
                                    systemImage: pendingDependencySourceTaskID == nil ? "link.badge.plus" : "xmark"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isEditingEnabled || selectedTaskID == nil)
                        }
                    }

                    Spacer(minLength: 0)
                }
            case .staffing:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Assignment")

                        if projectTask.summary == true {
                            Text("Use child tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let resources = nativeResources

                            if resources.isEmpty {
                                Text("No resources")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 8) {
                                    Picker("Resource", selection: selectedTaskPrimaryAssignmentResourceBinding()) {
                                        Text("Unassigned").tag(Int?.none)
                                        ForEach(resources) { resource in
                                            Text(resource.name).tag(Optional(resource.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 180)
                                    .help("Assign the primary resource for the selected task.")

                                    TextField("Units %", text: selectedTaskPrimaryAssignmentUnitsBinding())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 64)
                                        .help("Set primary assignment units as a percentage.")

                                    Text(primaryAssignmentUnitsSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 42, alignment: .leading)

                                    if primaryAssignmentIndex(for: nativeTask.id) == nil {
                                        Button {
                                            addPrimaryAssignmentToSelectedTask()
                                        } label: {
                                            Label("Add", systemImage: "plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .help("Add a primary assignment using the first available resource.")
                                    } else {
                                        Button(role: .destructive) {
                                            clearPrimaryAssignmentFromSelectedTask()
                                        } label: {
                                            Label("Clear", systemImage: "xmark")
                                        }
                                        .buttonStyle(.bordered)
                                        .help("Remove the primary assignment from the selected task.")
                                    }
                                }

                                HStack(spacing: 8) {
                                    TextField("Planned h", text: selectedTaskPrimaryAssignmentWorkBinding())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 78)
                                        .help("Set planned work hours for the primary assignment.")

                                    TextField("Actual h", text: selectedTaskPrimaryAssignmentActualWorkBinding())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 78)
                                        .help("Set actual work hours for the primary assignment.")

                                    TextField("Remain h", text: selectedTaskPrimaryAssignmentRemainingWorkBinding())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 78)
                                        .help("Set remaining work hours for the primary assignment.")

                                    TextField("OT h", text: selectedTaskPrimaryAssignmentOvertimeWorkBinding())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 68)
                                        .help("Set explicit overtime hours for the primary assignment.")
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            case .finance:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Task Costs")
                        if projectTask.summary == true {
                            Text("Summary task values roll up from child tasks.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                StableDecimalTextField(title: "Fixed Cost", text: selectedTaskFixedCostBinding())
                                    .textFieldStyle(.roundedBorder)
                                StableDecimalTextField(title: "Baseline Cost Override", text: selectedTaskBaselineCostBinding())
                                    .textFieldStyle(.roundedBorder)
                                StableDecimalTextField(title: "Actual Cost Override", text: selectedTaskActualCostBinding())
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(width: 170)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Actual Dates")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                DatePicker("Actual Start", selection: selectedTaskActualStartBinding(), displayedComponents: .date)
                                    .datePickerStyle(.field)
                                    .labelsHidden()
                                    .frame(width: 118)
                                Button("Clear", role: .destructive) {
                                    clearSelectedTaskActualStart()
                                }
                                .buttonStyle(.borderless)
                            }

                            HStack(spacing: 8) {
                                DatePicker("Actual Finish", selection: selectedTaskActualFinishBinding(), displayedComponents: .date)
                                    .datePickerStyle(.field)
                                    .labelsHidden()
                                    .frame(width: 118)
                                Button("Clear", role: .destructive) {
                                    clearSelectedTaskActualFinish()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Forecast")
                        VStack(alignment: .leading, spacing: 3) {
                            ganttMetricRow("Planned", value: currencyText(selectedTaskFinancialSummary.plannedCost))
                            ganttMetricRow("BAC", value: currencyText(selectedTaskFinancialSummary.budgetAtCompletion))
                            ganttMetricRow("PV", value: currencyText(selectedTaskFinancialSummary.plannedValue))
                            ganttMetricRow("EV", value: currencyText(selectedTaskFinancialSummary.earnedValue))
                            ganttMetricRow("AC", value: currencyText(selectedTaskFinancialSummary.actualCost))
                            ganttMetricRow("EAC", value: currencyText(selectedTaskFinancialSummary.estimateAtCompletion))
                            ganttMetricRow("VAC", value: currencyText(selectedTaskFinancialSummary.varianceAtCompletion))
                            ganttMetricRow("CPI", value: selectedTaskFinancialSummary.cpiText)
                            ganttMetricRow("SPI", value: selectedTaskFinancialSummary.spiText)
                        }
                        .frame(width: 160)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Glossary")
                        FinancialTermsButton(title: "Terms")
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func compactInspectorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func compactInspectorChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func ganttMetricRow(_ title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }

    private func applyAutoFitIfNeeded() {
        guard shouldAutoFitTimeline, timelineViewportWidth > 0 else { return }
        pixelsPerDay = fittedPixelsPerDay(for: timelineViewportWidth)
    }

    private func fittedPixelsPerDay(for viewportWidth: CGFloat) -> CGFloat {
        max(2, min(100, viewportWidth / CGFloat(max(totalDays, 1))))
    }

    private func exportToPDF() {
        let contentView = ganttContent(taskListWidth: exportTaskListWidth)
        let contentSize = CGSize(
            width: exportTaskListWidth + timelineWidth,
            height: CGFloat(flatTasks.count) * rowHeight + ganttHeaderHeight
        )
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PDFExporter.exportGanttToPDF(
            view: contentView,
            contentSize: contentSize,
            fileName: "\(title) - Gantt \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    private func printGantt() {
        let contentView = ganttContent(taskListWidth: exportTaskListWidth)
        let contentSize = CGSize(
            width: exportTaskListWidth + timelineWidth,
            height: CGFloat(flatTasks.count) * rowHeight + ganttHeaderHeight
        )
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PrintManager.printView(contentView, size: contentSize, title: title)
    }

    private var ganttHeaderHeight: CGFloat {
        pixelsPerDay < 15 ? 64 : 44
    }

    private var editStatusText: String {
        if interactionMode == .view {
            return "Review mode keeps bars read-only."
        }
        if let selectedDependency {
            return "Selected link: \(selectedDependency.predecessorID) -> \(selectedDependency.successorID)."
        }
        if let pendingDependencySourceTaskID,
           let sourceTask = project.tasksByID[pendingDependencySourceTaskID] {
            return "Linking from \(sourceTask.displayName). Click a target row or bar."
        }
        return "Edit mode: select tasks, drag bars, add subtasks, or create links."
    }

    private var canLinkSelectedTaskToNext: Bool {
        isEditingEnabled && nextVisibleTaskID(after: selectedTaskID) != nil
    }

    private var canRemoveSelectedDependency: Bool {
        isEditingEnabled && selectedDependency != nil
    }

    private func preferredTaskListWidth(for viewportWidth: CGFloat) -> CGFloat {
        min(max(230, viewportWidth * 0.28), 340)
    }

    private func ganttContent(taskListWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if showsEditSidebar {
                    taskListHeader(width: taskListWidth)
                }
                GanttHeaderView(
                    dateRange: dateRange,
                    pixelsPerDay: pixelsPerDay,
                    totalWidth: timelineWidth
                )
            }

            HStack(alignment: .top, spacing: 0) {
                if showsEditSidebar {
                    ganttTaskList(width: taskListWidth)
                }
                GanttCanvasView(
                    tasks: flatTasks,
                    allTasks: project.tasksByID,
                    rowIndexByTaskID: derivedContent.rowIndexByTaskID,
                    startDate: dateRange.start,
                    totalDays: totalDays,
                    pixelsPerDay: pixelsPerDay,
                    rowHeight: rowHeight,
                    visibleRect: timelineVisibleRect,
                    criticalPathOnly: criticalPathOnly,
                    showBaseline: showBaseline,
                    editableTaskIDs: editableTaskIDs,
                    selectedTaskID: selectedTaskID,
                    selectedDependency: selectedDependency,
                    pendingLinkSourceTaskID: pendingDependencySourceTaskID,
                    onMoveTask: planModel == nil ? nil : moveNativeTask,
                    onResizeTask: planModel == nil ? nil : resizeNativeTask,
                    onSelectTask: handleTaskSelection,
                    onStartLinkingFromTask: startLinkingFromTask,
                    onSelectDependency: { predecessorID, successorID in
                        selectedDependency = GanttDependencySelection(
                            predecessorID: predecessorID,
                            successorID: successorID
                        )
                        selectedTaskID = successorID
                    },
                    onRemoveDependency: { predecessorID, successorID in
                        removeDependency(predecessorID: predecessorID, successorID: successorID)
                    }
                )
                .frame(width: timelineWidth, height: CGFloat(flatTasks.count) * rowHeight)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: GanttTimelineViewportPreferenceKey.self,
                            value: CGRect(
                                x: max(0, -proxy.frame(in: .named("GanttScrollViewport")).minX),
                                y: max(0, -proxy.frame(in: .named("GanttScrollViewport")).minY),
                                width: timelineViewportWidth,
                                height: timelineViewportHeight
                            )
                        )
                    }
                )
            }
        }
    }

    private func taskListHeader(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text("Tasks")
                .font(.caption.weight(.semibold))
            Spacer()
            if isNativeEditablePlan {
                Text(interactionMode.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: ganttHeaderHeight, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func ganttTaskList(width: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(flatTasks, id: \.uniqueID) { task in
                taskListRow(task, width: width)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .background(taskListBackgroundColor)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func taskListRow(_ task: ProjectTask, width: CGFloat) -> some View {
        let isSelected = selectedTaskID == task.uniqueID
        let isPendingSource = pendingDependencySourceTaskID == task.uniqueID
        let isLinkTarget = pendingDependencySourceTaskID != nil && !isPendingSource
        let rowIndent = CGFloat(max(0, (task.outlineLevel ?? 1) - 1)) * 16

        return HStack(spacing: 8) {
            rowIcon(for: task)

            Text(task.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isPendingSource {
                Text("FROM")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18))
                    .clipShape(Capsule())
            } else if isLinkTarget {
                Text("TARGET")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14))
                    .clipShape(Capsule())
            } else if isSelected && isEditingEnabled {
                HStack(spacing: 4) {
                    rowActionButton("plus", help: "Add task after selection.") {
                        addTask(after: task.uniqueID)
                    }
                    rowActionButton("arrow.turn.down.right", help: "Add child task.") {
                        addSubtask(under: task.uniqueID)
                    }
                    rowActionButton("arrow.right.to.line", help: "Indent task.") {
                        indent(taskID: task.uniqueID)
                    }
                    rowActionButton("arrow.left.to.line", help: "Outdent task.") {
                        outdent(taskID: task.uniqueID)
                    }
                    rowActionButton("link", help: "Start linking from this task.") {
                        selectedTaskID = task.uniqueID
                        pendingDependencySourceTaskID = task.uniqueID
                    }
                    rowActionButton("trash", destructive: true, help: "Delete task and subtasks.") {
                        deleteTask(taskID: task.uniqueID)
                    }
                }
            }
        }
        .padding(.leading, 10 + rowIndent)
        .padding(.trailing, 10)
        .frame(width: width, height: rowHeight, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.accentColor.opacity(0.12))
            } else if isPendingSource {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.orange.opacity(0.08))
            } else if isLinkTarget {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.green.opacity(0.06))
            } else if rowBackgroundShouldAlternate(for: task.uniqueID) {
                Color.gray.opacity(0.03)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTaskSelection(task.uniqueID)
        }
        .contextMenu {
            Button {
                selectedTaskID = task.uniqueID
                addTask(after: task.uniqueID)
            } label: {
                Label("Add Task", systemImage: "plus")
            }

            Button {
                selectedTaskID = task.uniqueID
                addSubtask(under: task.uniqueID)
            } label: {
                Label("Add Subtask", systemImage: "arrow.turn.down.right")
            }

            Divider()

            Button {
                selectedTaskID = task.uniqueID
                indent(taskID: task.uniqueID)
            } label: {
                Label("Indent", systemImage: "arrow.right.to.line")
            }
            .disabled(!canIndent(taskID: task.uniqueID))

            Button {
                selectedTaskID = task.uniqueID
                outdent(taskID: task.uniqueID)
            } label: {
                Label("Outdent", systemImage: "arrow.left.to.line")
            }
            .disabled(!canOutdent(taskID: task.uniqueID))

            Divider()

            Button {
                selectedTaskID = task.uniqueID
                pendingDependencySourceTaskID = task.uniqueID
                interactionMode = .edit
            } label: {
                Label("Link From This Task", systemImage: "link")
            }
            .disabled(!isEditingEnabled)

            Button {
                clearPredecessors(for: task.uniqueID)
            } label: {
                Label("Clear Predecessors", systemImage: "link.badge.minus")
            }
            .disabled(!isEditingEnabled || (task.predecessors?.isEmpty ?? true))

            Divider()

            Button(role: .destructive) {
                deleteTask(taskID: task.uniqueID)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .disabled(!isEditingEnabled)
        }
        .help(taskRowTooltip(for: task))
    }

    private var taskListBackgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
            .opacity(0.96)
    }

    private func rowActionButton(_ systemImage: String, destructive: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(destructive ? Color.red : Color.secondary)
        .help(help)
    }

    @ViewBuilder
    private func rowIcon(for task: ProjectTask) -> some View {
        if task.summary == true {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        } else if task.milestone == true {
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "rectangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(task.critical == true ? .red : .accentColor)
        }
    }

    private func rowBackgroundShouldAlternate(for taskID: Int) -> Bool {
        guard let rowIndex = derivedContent.rowIndexByTaskID[taskID] else { return false }
        return rowIndex.isMultiple(of: 2)
    }

    private func taskRowTooltip(for task: ProjectTask) -> String {
        var lines = [task.displayName]
        if let wbs = task.wbs {
            lines.append("WBS: \(wbs)")
        }
        if let start = task.start {
            lines.append("Start: \(DateFormatting.shortDate(start))")
        }
        if let finish = task.finish {
            lines.append("Finish: \(DateFormatting.shortDate(finish))")
        }
        if !task.durationDisplay.isEmpty {
            lines.append("Duration: \(task.durationDisplay)")
        }
        if let predecessors = task.predecessors, !predecessors.isEmpty {
            let ids = predecessors.map(\.targetTaskUniqueID).map(String.init).joined(separator: ", ")
            lines.append("Predecessors: \(ids)")
        }
        return lines.joined(separator: "\n")
    }

    private func handleTaskSelection(_ taskID: Int) {
        PerformanceMonitor.measure("Gantt.SelectTask") {
            if isEditingEnabled,
               let sourceTaskID = pendingDependencySourceTaskID,
               sourceTaskID != taskID {
                createDependency(predecessorID: sourceTaskID, successorID: taskID)
                pendingDependencySourceTaskID = nil
                selectedTaskID = taskID
                return
            }

            selectedDependency = nil
            selectedTaskID = taskID
        }
    }

    private func startLinkingFromTask(_ taskID: Int) {
        guard isEditingEnabled else { return }
        PerformanceMonitor.mark("Gantt.StartLinking", message: "task \(taskID)")
        selectedDependency = nil
        selectedTaskID = taskID
        pendingDependencySourceTaskID = taskID
    }

    private func togglePendingLinkMode() {
        guard isEditingEnabled else { return }
        if pendingDependencySourceTaskID != nil {
            pendingDependencySourceTaskID = nil
        } else {
            selectedDependency = nil
            pendingDependencySourceTaskID = selectedTaskID
        }
    }

    private func nextVisibleTaskID(after taskID: Int?) -> Int? {
        guard let taskID,
              let index = derivedContent.rowIndexByTaskID[taskID],
              flatTasks.indices.contains(index + 1) else {
            return nil
        }

        return flatTasks[index + 1].uniqueID
    }

    private func linkSelectedTaskToNext() {
        guard let selectedTaskID,
              let successorID = nextVisibleTaskID(after: selectedTaskID) else { return }
        createDependency(predecessorID: selectedTaskID, successorID: successorID)
        self.selectedTaskID = successorID
    }

    private func createDependency(predecessorID: Int, successorID: Int) {
        guard predecessorID != successorID, planModel != nil else { return }

        PerformanceMonitor.measure("Gantt.CreateDependency") {
            fullSyncGanttPlan { workingPlan in
                guard let successorIndex = workingPlan.tasks.firstIndex(where: { $0.id == successorID }) else { return }

                if workingPlan.tasks[successorIndex].predecessorTaskIDs.contains(predecessorID) {
                    return
                }

                guard !createsDependencyCycle(addingDependencyFrom: predecessorID, to: successorID, tasks: workingPlan.tasks) else {
                    return
                }

                workingPlan.tasks[successorIndex].predecessorTaskIDs.append(predecessorID)
                workingPlan.tasks[successorIndex].predecessorTaskIDs = Array(Set(workingPlan.tasks[successorIndex].predecessorTaskIDs)).sorted()
                workingPlan.tasks[successorIndex].manuallyScheduled = false
                workingPlan.reschedule()
                selectedDependency = GanttDependencySelection(predecessorID: predecessorID, successorID: successorID)
            }
        }
    }

    private func removeSelectedDependency() {
        guard let selectedDependency else { return }
        removeDependency(
            predecessorID: selectedDependency.predecessorID,
            successorID: selectedDependency.successorID
        )
    }

    private func removeDependency(predecessorID: Int, successorID: Int) {
        guard planModel != nil else { return }

        PerformanceMonitor.measure("Gantt.RemoveDependency") {
            fullSyncGanttPlan { workingPlan in
                guard let successorIndex = workingPlan.tasks.firstIndex(where: { $0.id == successorID }) else { return }
                let originalCount = workingPlan.tasks[successorIndex].predecessorTaskIDs.count
                workingPlan.tasks[successorIndex].predecessorTaskIDs.removeAll { $0 == predecessorID }
                guard workingPlan.tasks[successorIndex].predecessorTaskIDs.count != originalCount else { return }

                workingPlan.tasks[successorIndex].manuallyScheduled = false
                workingPlan.reschedule()
                selectedDependency = nil
                selectedTaskID = successorID
            }
        }
    }

    private func createsDependencyCycle(addingDependencyFrom predecessorID: Int, to successorID: Int, tasks: [NativePlanTask]) -> Bool {
        var successorMap: [Int: [Int]] = [:]
        for task in tasks {
            for currentPredecessorID in task.predecessorTaskIDs {
                successorMap[currentPredecessorID, default: []].append(task.id)
            }
        }

        var stack = [successorID]
        var visited: Set<Int> = []

        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            if current == predecessorID {
                return true
            }
            stack.append(contentsOf: successorMap[current] ?? [])
        }

        return false
    }

    private func addTaskFromGantt() {
        guard planModel != nil else { return }

        fullSyncGanttPlan { workingPlan in
            let insertionAnchorIndex = selectedNativeTaskIndex(in: workingPlan.tasks)
            let insertionIndex: Int
            let anchorDate: Date
            let outlineLevel: Int

            if let insertionAnchorIndex {
                let range = subtreeRange(for: insertionAnchorIndex, in: workingPlan.tasks)
                let anchorTask = workingPlan.tasks[insertionAnchorIndex]
                insertionIndex = range.upperBound
                anchorDate = anchorTask.normalizedFinishDate
                outlineLevel = anchorTask.outlineLevel
            } else {
                insertionIndex = workingPlan.tasks.endIndex
                anchorDate = workingPlan.statusDate
                outlineLevel = 1
            }

            var newTask = workingPlan.makeTask(anchoredTo: anchorDate)
            newTask.outlineLevel = outlineLevel
            workingPlan.tasks.insert(newTask, at: insertionIndex)
            workingPlan.reschedule()
            selectedTaskID = newTask.id
            interactionMode = .edit
        }
    }

    private func refreshDerivedContent() {
        PerformanceMonitor.measure("Gantt.RefreshDerived") {
            derivedContent = GanttDerivedContent.build(project: project, searchText: searchText)
        }
    }

    private func addSubtaskFromGantt() {
        guard planModel != nil else { return }

        if selectedTaskID == nil {
            addTaskFromGantt()
            return
        }

        guard selectedNativeTaskIndex(in: nativeTasks) != nil else {
            addTaskFromGantt()
            return
        }

        fullSyncGanttPlan { workingPlan in
            guard let selectedIndex = selectedNativeTaskIndex(in: workingPlan.tasks) else { return }
            let range = subtreeRange(for: selectedIndex, in: workingPlan.tasks)
            let parentTask = workingPlan.tasks[selectedIndex]

            var newTask = workingPlan.makeTask(anchoredTo: parentTask.normalizedFinishDate)
            newTask.outlineLevel = parentTask.outlineLevel + 1
            workingPlan.tasks.insert(newTask, at: range.upperBound)
            workingPlan.reschedule()
            selectedTaskID = newTask.id
            interactionMode = .edit
        }
    }

    private var canDeleteSelectedTask: Bool {
        isEditingEnabled && selectedNativeTaskIndex(in: nativeTasks) != nil
    }

    private var canIndentSelectedTask: Bool {
        guard isEditingEnabled, let selectedTaskID else { return false }
        return canIndent(taskID: selectedTaskID)
    }

    private var canOutdentSelectedTask: Bool {
        guard isEditingEnabled, let selectedTaskID else { return false }
        return canOutdent(taskID: selectedTaskID)
    }

    private func addTask(after taskID: Int) {
        guard planModel != nil else { return }
        fullSyncGanttPlan { workingPlan in
            guard let insertionAnchorIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

            let range = subtreeRange(for: insertionAnchorIndex, in: workingPlan.tasks)
            let anchorTask = workingPlan.tasks[insertionAnchorIndex]

            var newTask = workingPlan.makeTask(anchoredTo: anchorTask.normalizedFinishDate)
            newTask.outlineLevel = anchorTask.outlineLevel
            workingPlan.tasks.insert(newTask, at: range.upperBound)
            workingPlan.reschedule()
            selectedTaskID = newTask.id
            interactionMode = .edit
        }
    }

    private func addSubtask(under taskID: Int) {
        guard planModel != nil else { return }
        fullSyncGanttPlan { workingPlan in
            guard let selectedIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

            let range = subtreeRange(for: selectedIndex, in: workingPlan.tasks)
            let parentTask = workingPlan.tasks[selectedIndex]

            var newTask = workingPlan.makeTask(anchoredTo: parentTask.normalizedFinishDate)
            newTask.outlineLevel = parentTask.outlineLevel + 1
            workingPlan.tasks.insert(newTask, at: range.upperBound)
            workingPlan.reschedule()
            selectedTaskID = newTask.id
            interactionMode = .edit
        }
    }

    private func deleteSelectedTask() {
        guard let selectedTaskID else { return }
        deleteTask(taskID: selectedTaskID)
    }

    private func deleteTask(taskID: Int) {
        guard planModel != nil else { return }

        fullSyncGanttPlan { workingPlan in
            guard let selectedIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

            let range = subtreeRange(for: selectedIndex, in: workingPlan.tasks)
            let removedIDs = Set(workingPlan.tasks[range].map(\.id))
            let nextSelectionIndex = range.lowerBound < workingPlan.tasks.count - range.count ? range.lowerBound : max(0, range.lowerBound - 1)

            workingPlan.tasks.removeSubrange(range)
            for index in workingPlan.tasks.indices {
                workingPlan.tasks[index].predecessorTaskIDs.removeAll { removedIDs.contains($0) }
            }
            workingPlan.assignments.removeAll { removedIDs.contains($0.taskID) }
            workingPlan.reschedule()

            if let pendingDependencySourceTaskID, removedIDs.contains(pendingDependencySourceTaskID) {
                self.pendingDependencySourceTaskID = nil
            }
            if let selectedDependency,
               removedIDs.contains(selectedDependency.predecessorID) || removedIDs.contains(selectedDependency.successorID) {
                self.selectedDependency = nil
            }
            selectedTaskID = workingPlan.tasks.indices.contains(nextSelectionIndex) ? workingPlan.tasks[nextSelectionIndex].id : nil
        }
    }

    private func canIndent(taskID: Int) -> Bool {
        guard let selectedIndex = nativeTasks.firstIndex(where: { $0.id == taskID }),
              selectedIndex > 0 else { return false }

        let currentLevel = nativeTasks[selectedIndex].outlineLevel
        let previousLevel = nativeTasks[selectedIndex - 1].outlineLevel
        return previousLevel + 1 > currentLevel
    }

    private func indentSelectedTask() {
        guard let selectedTaskID else { return }
        indent(taskID: selectedTaskID)
    }

    private func indent(taskID: Int) {
        guard canIndent(taskID: taskID), let selectedIndex = nativeTasks.firstIndex(where: { $0.id == taskID }) else { return }

        fullSyncGanttPlan { workingPlan in
            let newLevel = workingPlan.tasks[selectedIndex - 1].outlineLevel + 1
            let delta = newLevel - workingPlan.tasks[selectedIndex].outlineLevel
            adjustSubtreeOutlineLevel(taskID: taskID, by: delta, in: &workingPlan)
            workingPlan.reschedule()
            selectedTaskID = taskID
        }
    }

    private func canOutdent(taskID: Int) -> Bool {
        guard let selectedIndex = nativeTasks.firstIndex(where: { $0.id == taskID }) else { return false }
        return nativeTasks[selectedIndex].outlineLevel > 1
    }

    private func outdentSelectedTask() {
        guard let selectedTaskID else { return }
        outdent(taskID: selectedTaskID)
    }

    private func outdent(taskID: Int) {
        guard canOutdent(taskID: taskID) else { return }
        fullSyncGanttPlan { workingPlan in
            adjustSubtreeOutlineLevel(taskID: taskID, by: -1, in: &workingPlan)
            workingPlan.reschedule()
            selectedTaskID = taskID
        }
    }

    private func adjustSubtreeOutlineLevel(taskID: Int, by delta: Int, in plan: inout NativeProjectPlan) {
        guard let selectedIndex = nativeTasks.firstIndex(where: { $0.id == taskID }) else { return }
        let range = subtreeRange(for: selectedIndex, in: nativeTasks)
        for index in range {
            plan.tasks[index].outlineLevel = max(1, plan.tasks[index].outlineLevel + delta)
        }
    }

    private func clearPredecessors(for taskID: Int) {
        guard planModel != nil else { return }
        fullSyncGanttPlan { workingPlan in
            guard let taskIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
            workingPlan.tasks[taskIndex].predecessorTaskIDs = []
            workingPlan.tasks[taskIndex].manuallyScheduled = false
            workingPlan.reschedule()
            selectedTaskID = taskID
            if pendingDependencySourceTaskID == taskID {
                pendingDependencySourceTaskID = nil
            }
            if let selectedDependency, selectedDependency.successorID == taskID {
                self.selectedDependency = nil
            }
        }
    }

    private func updateSelectedTask(reschedule: Bool = true, _ transform: (inout NativePlanTask) -> Void) {
        guard let selectedTaskID else { return }

        if reschedule {
            fullSyncGanttPlan { workingPlan in
                guard let taskIndex = workingPlan.tasks.firstIndex(where: { $0.id == selectedTaskID }) else { return }
                transform(&workingPlan.tasks[taskIndex])
                workingPlan.reschedule()
            }
        } else {
            guard let task = planModel?.tasks.first(where: { $0.legacyID == selectedTaskID }) else { return }
            var nativeTask = task.asNativeTask()
            transform(&nativeTask)
            task.update(from: nativeTask, orderIndex: task.orderIndex)
            persistGanttStoreChanges()
            refreshDerivedContent()
        }
    }

    private func selectedTaskNameBinding() -> Binding<String> {
        Binding(
            get: { selectedNativeTask?.name ?? "" },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    task.name = newValue
                }
            }
        )
    }

    private func selectedTaskStartBinding() -> Binding<Date> {
        Binding(
            get: { selectedNativeTask?.startDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                updateSelectedTask { task in
                    let normalized = Calendar.current.startOfDay(for: newValue)
                    task.startDate = normalized
                    if task.isMilestone {
                        task.finishDate = normalized
                    } else if task.finishDate < normalized {
                        task.finishDate = normalized
                    }
                    task.manuallyScheduled = true
                }
            }
        )
    }

    private func selectedTaskFinishBinding() -> Binding<Date> {
        Binding(
            get: { selectedNativeTask?.finishDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                updateSelectedTask { task in
                    let normalized = Calendar.current.startOfDay(for: newValue)
                    task.finishDate = task.isMilestone ? task.startDate : max(task.startDate, normalized)
                    task.manuallyScheduled = true
                }
            }
        )
    }

    private func selectedTaskDurationBinding() -> Binding<Int> {
        Binding(
            get: { max(1, selectedNativeTask?.durationDays ?? 1) },
            set: { newValue in
                updateSelectedTask { task in
                    task.durationDays = max(1, newValue)
                    task.manuallyScheduled = false
                }
            }
        )
    }

    private func selectedTaskManualBinding() -> Binding<Bool> {
        Binding(
            get: { selectedNativeTask?.manuallyScheduled ?? false },
            set: { newValue in
                updateSelectedTask { task in
                    task.manuallyScheduled = newValue
                }
            }
        )
    }

    private func selectedTaskMilestoneBinding() -> Binding<Bool> {
        Binding(
            get: { selectedNativeTask?.isMilestone ?? false },
            set: { newValue in
                updateSelectedTask { task in
                    task.isMilestone = newValue
                    if newValue {
                        task.finishDate = task.startDate
                        task.durationDays = 1
                    } else if task.finishDate < task.startDate {
                        task.finishDate = task.startDate
                    }
                }
            }
        )
    }

    private func selectedTaskConstraintBinding() -> Binding<String> {
        Binding(
            get: { selectedNativeTask?.constraintType ?? "None" },
            set: { newValue in
                updateSelectedTask { task in
                    if newValue == "None" {
                        task.constraintType = nil
                        task.constraintDate = nil
                    } else {
                        task.constraintType = newValue
                        if task.constraintDate == nil {
                            let seedDate = newValue == "FNET" || newValue == "MFO" ? task.finishDate : task.startDate
                            task.constraintDate = Calendar.current.startOfDay(for: seedDate)
                        }
                    }
                }
            }
        )
    }

    private func selectedTaskConstraintDateBinding() -> Binding<Date> {
        Binding(
            get: {
                if let date = selectedNativeTask?.constraintDate {
                    return date
                }
                if let task = selectedNativeTask {
                    return Calendar.current.startOfDay(
                        for: (task.constraintType == "FNET" || task.constraintType == "MFO") ? task.finishDate : task.startDate
                    )
                }
                return Calendar.current.startOfDay(for: Date())
            },
            set: { newValue in
                updateSelectedTask { task in
                    task.constraintDate = Calendar.current.startOfDay(for: newValue)
                }
            }
        )
    }

    private func selectedTaskPredecessorsBinding() -> Binding<String> {
        Binding(
            get: {
                selectedNativeTask?.predecessorTaskIDs
                    .sorted()
                    .map(String.init)
                    .joined(separator: ", ") ?? ""
            },
            set: { newValue in
                guard let selectedTaskID else { return }
                let validIDs = Set(nativeTasks.map(\.id))
                let parsed = newValue
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { $0 != selectedTaskID && validIDs.contains($0) }

                updateSelectedTask { task in
                    task.predecessorTaskIDs = Array(Set(parsed)).sorted()
                    task.manuallyScheduled = false
                }
            }
        )
    }

    private func selectedTaskFixedCostBinding() -> Binding<String> {
        Binding(
            get: { selectedNativeTask.map { decimalText($0.fixedCost) } ?? "" },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    task.fixedCost = max(0, parseDecimalInput(newValue) ?? 0)
                }
            }
        )
    }

    private func selectedTaskBaselineCostBinding() -> Binding<String> {
        Binding(
            get: { selectedNativeTask?.baselineCost.map(decimalText) ?? "" },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    task.baselineCost = parseDecimalInput(newValue)
                }
            }
        )
    }

    private func selectedTaskActualCostBinding() -> Binding<String> {
        Binding(
            get: { selectedNativeTask?.actualCost.map(decimalText) ?? "" },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    task.actualCost = parseDecimalInput(newValue)
                }
            }
        )
    }

    private func selectedTaskActualStartBinding() -> Binding<Date> {
        Binding(
            get: { selectedNativeTask?.actualStartDate ?? selectedNativeTask?.startDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    task.actualStartDate = Calendar.current.startOfDay(for: newValue)
                    if task.percentComplete == 0 {
                        task.percentComplete = 1
                    }
                }
            }
        )
    }

    private func selectedTaskActualFinishBinding() -> Binding<Date> {
        Binding(
            get: { selectedNativeTask?.actualFinishDate ?? selectedNativeTask?.finishDate ?? Calendar.current.startOfDay(for: Date()) },
            set: { newValue in
                updateSelectedTask(reschedule: false) { task in
                    let normalized = Calendar.current.startOfDay(for: newValue)
                    task.actualStartDate = task.actualStartDate ?? task.startDate
                    task.actualFinishDate = max(task.actualStartDate ?? normalized, normalized)
                    task.percentComplete = 100
                }
            }
        )
    }

    private func clearSelectedTaskActualStart() {
        updateSelectedTask(reschedule: false) { task in
            task.actualStartDate = nil
        }
    }

    private func clearSelectedTaskActualFinish() {
        updateSelectedTask(reschedule: false) { task in
            task.actualFinishDate = nil
        }
    }

    private func primaryAssignmentIndex(for taskID: Int) -> Int? {
        return nativeAssignments.firstIndex(where: { $0.taskID == taskID })
    }

    private var primaryAssignmentUnitsSummary: String {
        guard let selectedTaskID,
              let index = primaryAssignmentIndex(for: selectedTaskID) else {
            return "0%"
        }

        return "\(Int(nativeAssignments[index].units))%"
    }

    private func addPrimaryAssignmentToSelectedTask() {
        guard planModel != nil, let selectedTaskID else { return }
        guard primaryAssignmentIndex(for: selectedTaskID) == nil else { return }
        let defaultResourceID = nativeResources.first?.id
        guard defaultResourceID != nil else { return }

        fullSyncGanttPlan { workingPlan in
            workingPlan.assignments.append(workingPlan.makeAssignment(taskID: selectedTaskID, resourceID: defaultResourceID))
        }
    }

    private func clearPrimaryAssignmentFromSelectedTask() {
        guard planModel != nil, let selectedTaskID else { return }
        guard let index = primaryAssignmentIndex(for: selectedTaskID) else { return }

        fullSyncGanttPlan { workingPlan in
            workingPlan.assignments.remove(at: index)
        }
    }

    private func selectedTaskPrimaryAssignmentResourceBinding() -> Binding<Int?> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else {
                    return nil
                }

                return nativeAssignments[index].resourceID
            },
            set: { newValue in
                guard let selectedTaskID else { return }

                if let index = nativeAssignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                    let assignmentID = nativeAssignments[index].id
                    if let newValue {
                        withGanttAssignment(assignmentID) { assignment in
                            assignment.resourceLegacyID = newValue
                        }
                    } else {
                        fullSyncGanttPlan { workingPlan in
                            guard let assignmentIndex = workingPlan.assignments.firstIndex(where: { $0.id == assignmentID }) else { return }
                            workingPlan.assignments.remove(at: assignmentIndex)
                        }
                    }
                } else if let newValue {
                    fullSyncGanttPlan { workingPlan in
                        workingPlan.assignments.append(workingPlan.makeAssignment(taskID: selectedTaskID, resourceID: newValue))
                    }
                }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentUnitsBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else {
                    return ""
                }

                return String(Int(nativeAssignments[index].units))
            },
            set: { newValue in
                guard let selectedTaskID else { return }

                let digits = newValue.filter(\.isNumber)

                if digits.isEmpty {
                    if let index = nativeAssignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                        let assignmentID = nativeAssignments[index].id
                        withGanttAssignment(assignmentID) { assignment in
                            assignment.units = 0
                        }
                    }
                    return
                }

                let parsedUnits = min(300.0, max(0.0, Double(digits) ?? 0))
                if let index = nativeAssignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                    let assignmentID = nativeAssignments[index].id
                    withGanttAssignment(assignmentID) { assignment in
                        assignment.units = parsedUnits
                    }
                    return
                } else {
                    fullSyncGanttPlan { workingPlan in
                        var assignment = workingPlan.makeAssignment(
                            taskID: selectedTaskID,
                            resourceID: workingPlan.resources.first?.id
                        )
                        assignment.units = parsedUnits
                        workingPlan.assignments.append(assignment)
                    }
                    return
                }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativeAssignments[index].workSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.workSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentActualWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativeAssignments[index].actualWorkSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.actualWorkSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentRemainingWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativeAssignments[index].remainingWorkSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.remainingWorkSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentOvertimeWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativeAssignments[index].overtimeWorkSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.overtimeWorkSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedNativeTaskIndex(in tasks: [NativePlanTask]) -> Int? {
        guard let selectedTaskID else { return nil }
        return tasks.firstIndex(where: { $0.id == selectedTaskID })
    }

    private func updatePrimaryAssignmentHours(_ transform: (inout NativePlanAssignment) -> Void) {
        guard let selectedTaskID,
              let index = primaryAssignmentIndex(for: selectedTaskID) else { return }
        let assignmentID = nativeAssignments[index].id
        guard let assignment = planModel?.tasks.flatMap(\.assignments).first(where: { $0.legacyID == assignmentID }) else { return }
        var nativeAssignment = assignment.asNativeAssignment()
        transform(&nativeAssignment)
        assignment.update(from: nativeAssignment)
        persistGanttStoreChanges()
        refreshDerivedContent()
    }

    private func financialSummary(for task: ProjectTask) -> GanttFinancialSummary {
        if task.summary == true {
            let leafTasks = flattenedLeafTasks(from: task)
            let metrics = leafTasks.reduce(EVMMetrics.zero) { partial, task in
                let metrics = EVMCalculator.compute(for: task, statusDate: projectStatusDate)
                return EVMMetrics(
                    bac: partial.bac + metrics.bac,
                    pv: partial.pv + metrics.pv,
                    ev: partial.ev + metrics.ev,
                    ac: partial.ac + metrics.ac
                )
            }

            return GanttFinancialSummary(
                plannedCost: leafTasks.compactMap(\.cost).reduce(0, +),
                budgetAtCompletion: metrics.bac,
                plannedValue: metrics.pv,
                earnedValue: metrics.ev,
                actualCost: metrics.ac
            )
        }

        let metrics = EVMCalculator.compute(for: task, statusDate: projectStatusDate)
        return GanttFinancialSummary(
            plannedCost: task.cost ?? 0,
            budgetAtCompletion: metrics.bac,
            plannedValue: metrics.pv,
            earnedValue: metrics.ev,
            actualCost: metrics.ac
        )
    }

    private var projectStatusDate: Date {
        if let raw = project.properties.statusDate, let parsed = DateFormatting.parseMPXJDate(raw) {
            return parsed
        }
        return Date()
    }

    private func flattenedLeafTasks(from task: ProjectTask) -> [ProjectTask] {
        if task.children.isEmpty {
            return [task]
        }
        return task.children.flatMap(flattenedLeafTasks)
    }

    private func currencyText(_ value: Double) -> String {
        CurrencyFormatting.string(
            from: value,
            maximumFractionDigits: value.rounded() == value ? 0 : 2,
            minimumFractionDigits: 0
        )
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

    private func parseHoursInput(_ text: String) -> Int? {
        guard let hours = parseDecimalInput(text) else { return nil }
        return max(0, Int((hours * 3600).rounded()))
    }

    private func hoursText(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let hours = Double(seconds) / 3600.0
        if hours.rounded() == hours {
            return String(Int(hours))
        }
        return String(format: "%.2f", hours)
    }

    private func subtreeRange(for index: Int, in tasks: [NativePlanTask]) -> Range<Int> {
        let baseLevel = tasks[index].outlineLevel
        var endIndex = index + 1

        while tasks.indices.contains(endIndex), tasks[endIndex].outlineLevel > baseLevel {
            endIndex += 1
        }

        return index ..< endIndex
    }

    private func moveNativeTask(_ taskID: Int, dayDelta: Int) {
        guard dayDelta != 0, planModel != nil else { return }

        PerformanceMonitor.measure("Gantt.MoveTask") {
            fullSyncGanttPlan { workingPlan in
                guard let taskIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                var task = workingPlan.tasks[taskIndex]
                let calendar = Calendar.current
                task.startDate = calendar.date(byAdding: .day, value: dayDelta, to: task.startDate) ?? task.startDate
                task.finishDate = calendar.date(byAdding: .day, value: dayDelta, to: task.finishDate) ?? task.finishDate
                task.startDate = calendar.startOfDay(for: task.startDate)
                task.finishDate = task.isMilestone ? task.startDate : calendar.startOfDay(for: task.finishDate)
                task.manuallyScheduled = true
                workingPlan.tasks[taskIndex] = task
                workingPlan.reschedule()
                selectedTaskID = taskID
            }
        }
    }

    private func resizeNativeTask(_ taskID: Int, edge: GanttResizeEdge, dayDelta: Int) {
        guard dayDelta != 0, planModel != nil else { return }

        PerformanceMonitor.measure("Gantt.ResizeTask") {
            fullSyncGanttPlan { workingPlan in
                guard let taskIndex = workingPlan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
                var task = workingPlan.tasks[taskIndex]
                guard !task.isMilestone else { return }

                let calendar = Calendar.current
                switch edge {
                case .leading:
                    let proposedStart = calendar.date(byAdding: .day, value: dayDelta, to: task.startDate) ?? task.startDate
                    task.startDate = calendar.startOfDay(for: min(proposedStart, task.finishDate))
                case .trailing:
                    let proposedFinish = calendar.date(byAdding: .day, value: dayDelta, to: task.finishDate) ?? task.finishDate
                    task.finishDate = calendar.startOfDay(for: max(proposedFinish, task.startDate))
                }

                task.manuallyScheduled = true
                workingPlan.tasks[taskIndex] = task
                workingPlan.reschedule()
                selectedTaskID = taskID
            }
        }
    }
}

// MARK: - Gantt Date Helpers (shared between views)

enum GanttDateHelpers {
    static func dateRange(for tasks: [ProjectTask]) -> (start: Date, end: Date) {
        let allDates = tasks.compactMap { $0.startDate } + tasks.compactMap { $0.finishDate }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            let now = Date()
            return (now, now.addingTimeInterval(86400 * 30))
        }
        let paddedStart = Calendar.current.date(byAdding: .day, value: -3, to: minDate) ?? minDate
        let paddedEnd = Calendar.current.date(byAdding: .day, value: 7, to: maxDate) ?? maxDate
        return (paddedStart, paddedEnd)
    }

    static func totalDays(for dateRange: (start: Date, end: Date)) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 30)
    }

    static func todayDayOffset(from startDate: Date) -> CGFloat? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return CGFloat(days)
    }
}

// MARK: - Legend Bar

struct GanttLegendBar: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .blue, label: "Normal")
            legendItem(color: .red, label: "Critical")
            summaryLegendItem()
            milestoneLegendItem()
            progressLegendItem()
            baselineLegendItem()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.5))
                .frame(width: 16, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(color.opacity(0.6), lineWidth: 0.5)
                )
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func summaryLegendItem() -> some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.primary.opacity(0.6))
                .frame(width: 16, height: 4)
            Text("Summary").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func milestoneLegendItem() -> some View {
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
            Text("Milestone").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func progressLegendItem() -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: 16, height: 8)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 10, height: 8)
            }
            Text("Progress").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func baselineLegendItem() -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 16, height: 6)
            Text("Baseline").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Zoom Controls

struct GanttZoomControls: View {
    let pixelsPerDay: CGFloat
    let totalDays: Int
    let onFitAll: () -> Void
    let onShowWeek: () -> Void
    let onShowMonth: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void

    init(
        pixelsPerDay: CGFloat,
        totalDays: Int,
        onFitAll: @escaping () -> Void,
        onShowWeek: @escaping () -> Void,
        onShowMonth: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void
    ) {
        self.pixelsPerDay = pixelsPerDay
        self.totalDays = totalDays
        self.onFitAll = onFitAll
        self.onShowWeek = onShowWeek
        self.onShowMonth = onShowMonth
        self.onZoomOut = onZoomOut
        self.onZoomIn = onZoomIn
    }

    init(pixelsPerDay: Binding<CGFloat>, totalDays: Int) {
        self.init(
            pixelsPerDay: pixelsPerDay.wrappedValue,
            totalDays: totalDays,
            onFitAll: {
                pixelsPerDay.wrappedValue = max(2, min(100, 900.0 / CGFloat(max(totalDays, 1))))
            },
            onShowWeek: {
                pixelsPerDay.wrappedValue = 40
            },
            onShowMonth: {
                pixelsPerDay.wrappedValue = 10
            },
            onZoomOut: {
                pixelsPerDay.wrappedValue = max(2, pixelsPerDay.wrappedValue / 1.5)
            },
            onZoomIn: {
                pixelsPerDay.wrappedValue = min(100, pixelsPerDay.wrappedValue * 1.5)
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Fit All", action: onFitAll)
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Week", action: onShowWeek)
            .buttonStyle(.borderless)
            .font(.caption)

            Button("Month", action: onShowMonth)
            .buttonStyle(.borderless)
            .font(.caption)

            Divider().frame(height: 16)

            Button(action: onZoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            Text("\(Int(pixelsPerDay)) px/day")
                .monospacedDigit()
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70)
            Button(action: onZoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Single Canvas for Grid + Bars + Dependencies

private struct GanttDependencySegment: Identifiable, Hashable {
    let predecessorID: Int
    let successorID: Int
    let start: CGPoint
    let end: CGPoint
    let midX: CGFloat

    var id: String { "\(predecessorID)->\(successorID)" }
}

private struct GanttTaskGeometry {
    let rowIndex: Int
    let rowRect: CGRect
    let startX: CGFloat?
    let width: CGFloat?
    let barRect: CGRect?
    let baselineStartX: CGFloat?
    let baselineFinishX: CGFloat?
    let baselineBarRect: CGRect?
}

private struct GanttCanvasLayoutInput: Equatable {
    let taskIDs: [Int]
    let taskStarts: [String]
    let taskFinishes: [String]
    let baselineStarts: [String]
    let baselineFinishes: [String]
    let predecessorPairs: [[Int]]
    let startDate: Date
    let totalDays: Int
    let pixelsPerDay: CGFloat
    let rowHeight: CGFloat
    let showBaseline: Bool
}

private struct GanttCanvasLayoutState {
    let timelineContentWidth: CGFloat
    let taskGeometryByID: [Int: GanttTaskGeometry]
    let dependencySegments: [GanttDependencySegment]

    static func build(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        rowIndexByTaskID: [Int: Int],
        startDate: Date,
        totalDays: Int,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        showBaseline: Bool
    ) -> GanttCanvasLayoutState {
        let calendar = Calendar.current
        let timelineContentWidth = CGFloat(totalDays) * pixelsPerDay
        let barInset: CGFloat = 4
        let barHeight = rowHeight - barInset * 2
        let baselineBarHeight = barHeight * 0.5

        let taskGeometryByID = Dictionary(nonThrowingUniquePairs: tasks.enumerated().map { index, task in
            let rowRect = CGRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: timelineContentWidth,
                height: rowHeight
            )

            let startX = task.startDate.map { date -> CGFloat in
                let startDays = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
                return CGFloat(startDays) * pixelsPerDay
            }

            let width: CGFloat? = {
                guard let taskStart = task.startDate, let taskFinish = task.finishDate else { return nil }
                let startDays = calendar.dateComponents([.day], from: startDate, to: taskStart).day ?? 0
                let finishDays = calendar.dateComponents([.day], from: startDate, to: taskFinish).day ?? 0
                return max(4, CGFloat(max(1, finishDays - startDays)) * pixelsPerDay)
            }()

            let barRect: CGRect? = {
                guard let startX else { return nil }
                if task.milestone == true {
                    let diamondSize: CGFloat = barHeight * 0.6
                    return CGRect(
                        x: startX - (diamondSize / 2),
                        y: rowRect.minY + (rowHeight - diamondSize) / 2,
                        width: diamondSize,
                        height: diamondSize
                    )
                }

                guard let width else { return nil }
                return CGRect(x: startX, y: rowRect.minY + barInset, width: width, height: barHeight)
            }()

            let baselineStartX = task.baselineStartDate.map { date -> CGFloat in
                let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
                return CGFloat(days) * pixelsPerDay
            }

            let baselineFinishX = task.baselineFinishDate.map { date -> CGFloat in
                let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
                return CGFloat(days) * pixelsPerDay
            }

            let baselineBarRect: CGRect? = {
                guard showBaseline,
                      task.hasBaseline,
                      task.milestone != true,
                      task.summary != true,
                      let baselineStartX,
                      let baselineFinishX
                else { return nil }

                return CGRect(
                    x: baselineStartX,
                    y: rowRect.minY + barInset + barHeight - baselineBarHeight,
                    width: max(4, baselineFinishX - baselineStartX),
                    height: baselineBarHeight
                )
            }()

            return (
                task.uniqueID,
                GanttTaskGeometry(
                    rowIndex: index,
                    rowRect: rowRect,
                    startX: startX,
                    width: width,
                    barRect: barRect,
                    baselineStartX: baselineStartX,
                    baselineFinishX: baselineFinishX,
                    baselineBarRect: baselineBarRect
                )
            )
        })

        let dependencySegments = tasks.flatMap { task in
            guard let predecessors = task.predecessors,
                  let successorIndex = rowIndexByTaskID[task.uniqueID] else { return [GanttDependencySegment]() }

            return predecessors.compactMap { relation in
                guard let predecessorIndex = rowIndexByTaskID[relation.targetTaskUniqueID],
                      let predecessorTask = allTasks[relation.targetTaskUniqueID] else { return nil }

                let predecessorEnd = dayOffsetX(for: predecessorTask.finishDate, startDate: startDate, pixelsPerDay: pixelsPerDay, calendar: calendar)
                let successorStart = dayOffsetX(for: task.startDate, startDate: startDate, pixelsPerDay: pixelsPerDay, calendar: calendar)
                let predecessorY = CGFloat(predecessorIndex) * rowHeight + rowHeight / 2
                let successorY = CGFloat(successorIndex) * rowHeight + rowHeight / 2

                return GanttDependencySegment(
                    predecessorID: relation.targetTaskUniqueID,
                    successorID: task.uniqueID,
                    start: CGPoint(x: predecessorEnd, y: predecessorY),
                    end: CGPoint(x: successorStart, y: successorY),
                    midX: predecessorEnd + 6
                )
            }
        }

        return GanttCanvasLayoutState(
            timelineContentWidth: timelineContentWidth,
            taskGeometryByID: taskGeometryByID,
            dependencySegments: dependencySegments
        )
    }

    private static func dayOffsetX(for date: Date?, startDate: Date, pixelsPerDay: CGFloat, calendar: Calendar) -> CGFloat {
        guard let date else { return 0 }
        let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
        return CGFloat(days) * pixelsPerDay
    }
}

struct GanttCanvasView: View {
    private let canvasCoordinateSpaceName = "GanttCanvasViewSpace"

    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let rowIndexByTaskID: [Int: Int]
    let startDate: Date
    let totalDays: Int
    let pixelsPerDay: CGFloat
    let rowHeight: CGFloat
    let visibleRect: CGRect
    var criticalPathOnly: Bool = false
    var showBaseline: Bool = false
    var editableTaskIDs: Set<Int> = []
    var selectedTaskID: Int? = nil
    var selectedDependency: GanttDependencySelection? = nil
    var pendingLinkSourceTaskID: Int? = nil
    var onMoveTask: ((Int, Int) -> Void)? = nil
    var onResizeTask: ((Int, GanttResizeEdge, Int) -> Void)? = nil
    var onSelectTask: ((Int) -> Void)? = nil
    var onStartLinkingFromTask: ((Int) -> Void)? = nil
    var onSelectDependency: ((Int, Int) -> Void)? = nil
    var onRemoveDependency: ((Int, Int) -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme
    @State private var layoutState: GanttCanvasLayoutState

    init(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        rowIndexByTaskID: [Int: Int],
        startDate: Date,
        totalDays: Int,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        visibleRect: CGRect = .zero,
        criticalPathOnly: Bool = false,
        showBaseline: Bool = false,
        editableTaskIDs: Set<Int> = [],
        selectedTaskID: Int? = nil,
        selectedDependency: GanttDependencySelection? = nil,
        pendingLinkSourceTaskID: Int? = nil,
        onMoveTask: ((Int, Int) -> Void)? = nil,
        onResizeTask: ((Int, GanttResizeEdge, Int) -> Void)? = nil,
        onSelectTask: ((Int) -> Void)? = nil,
        onStartLinkingFromTask: ((Int) -> Void)? = nil,
        onSelectDependency: ((Int, Int) -> Void)? = nil,
        onRemoveDependency: ((Int, Int) -> Void)? = nil
    ) {
        self.tasks = tasks
        self.allTasks = allTasks
        self.rowIndexByTaskID = rowIndexByTaskID
        self.startDate = startDate
        self.totalDays = totalDays
        self.pixelsPerDay = pixelsPerDay
        self.rowHeight = rowHeight
        self.visibleRect = visibleRect
        self.criticalPathOnly = criticalPathOnly
        self.showBaseline = showBaseline
        self.editableTaskIDs = editableTaskIDs
        self.selectedTaskID = selectedTaskID
        self.selectedDependency = selectedDependency
        self.pendingLinkSourceTaskID = pendingLinkSourceTaskID
        self.onMoveTask = onMoveTask
        self.onResizeTask = onResizeTask
        self.onSelectTask = onSelectTask
        self.onStartLinkingFromTask = onStartLinkingFromTask
        self.onSelectDependency = onSelectDependency
        self.onRemoveDependency = onRemoveDependency
        self._layoutState = State(
            initialValue: GanttCanvasLayoutState.build(
                tasks: tasks,
                allTasks: allTasks,
                rowIndexByTaskID: rowIndexByTaskID,
                startDate: startDate,
                totalDays: totalDays,
                pixelsPerDay: pixelsPerDay,
                rowHeight: rowHeight,
                showBaseline: showBaseline
            )
        )
    }

    private var rowShadingOpacity: Double { colorScheme == .dark ? 0.08 : 0.04 }
    private var gridLineOpacity: Double { colorScheme == .dark ? 0.25 : 0.15 }
    private var weekendOpacity: Double { colorScheme == .dark ? 0.12 : 0.06 }
    private var barBgOpacity: Double { colorScheme == .dark ? 0.35 : 0.25 }
    private var baselineOpacity: Double { colorScheme == .dark ? 0.4 : 0.25 }

    private var timelineContentWidth: CGFloat {
        layoutState.timelineContentWidth
    }

    private var layoutInput: GanttCanvasLayoutInput {
        GanttCanvasLayoutInput(
            taskIDs: tasks.map(\.uniqueID),
            taskStarts: tasks.map { $0.start ?? "" },
            taskFinishes: tasks.map { $0.finish ?? "" },
            baselineStarts: tasks.map { $0.baselineStart ?? "" },
            baselineFinishes: tasks.map { $0.baselineFinish ?? "" },
            predecessorPairs: tasks.map { $0.predecessors?.map(\.targetTaskUniqueID) ?? [] },
            startDate: startDate,
            totalDays: totalDays,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            showBaseline: showBaseline
        )
    }

    private var visibleRowRange: Range<Int> {
        guard !tasks.isEmpty else { return 0..<0 }
        let overscan = 2
        let minY = max(0, visibleRect.minY)
        let maxY = max(minY, visibleRect.maxY > 0 ? visibleRect.maxY : CGFloat(tasks.count) * rowHeight)
        let lower = max(0, Int(floor(minY / rowHeight)) - overscan)
        let upper = min(tasks.count, Int(ceil(maxY / rowHeight)) + overscan)
        return lower..<max(lower, upper)
    }

    private var visibleDayRange: ClosedRange<Int> {
        guard totalDays > 0 else { return 0...0 }
        let overscan = 2
        let minX = max(0, visibleRect.minX)
        let maxX = max(minX, visibleRect.maxX > 0 ? visibleRect.maxX : timelineContentWidth)
        let lower = max(0, Int(floor(minX / max(1, pixelsPerDay))) - overscan)
        let upper = min(totalDays, Int(ceil(maxX / max(1, pixelsPerDay))) + overscan)
        return lower...max(lower, upper)
    }

    private var visibleTaskRows: [(index: Int, task: ProjectTask)] {
        visibleRowRange.compactMap { index in
            guard tasks.indices.contains(index) else { return nil }
            return (index, tasks[index])
        }
    }

    private var editableTaskRows: [(index: Int, task: ProjectTask)] {
        visibleTaskRows.filter { editableTaskIDs.contains($0.task.uniqueID) }
    }

    private var visibleDependencySegments: [GanttDependencySegment] {
        let expandedRect = visibleRect.insetBy(dx: -40, dy: -rowHeight)
        return layoutState.dependencySegments.filter { segment in
            let minX = min(segment.start.x, segment.end.x, segment.midX)
            let maxX = max(segment.start.x, segment.end.x, segment.midX)
            let minY = min(segment.start.y, segment.end.y)
            let maxY = max(segment.start.y, segment.end.y)
            return maxX >= expandedRect.minX &&
                minX <= expandedRect.maxX &&
                maxY >= expandedRect.minY &&
                minY <= expandedRect.maxY
        }
    }

    private var taskGeometryByID: [Int: GanttTaskGeometry] {
        layoutState.taskGeometryByID
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gridCanvas
                .drawingGroup()
            taskBarsCanvas
            dependencyCanvas
            tooltipOverlay
            linkSourceHighlightOverlay
            linkTargetHighlightOverlay
            dependencySelectionOverlay
            editableBarsOverlay
        }
        .coordinateSpace(name: canvasCoordinateSpaceName)
        .onChange(of: layoutInput) { _, _ in
            refreshLayoutState()
        }
    }

    private var editableBarsOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(editableTaskRows, id: \.task.uniqueID) { row in
                GanttBarView(
                    task: row.task,
                    startDate: startDate,
                    pixelsPerDay: pixelsPerDay,
                    rowIndex: row.index,
                    rowHeight: rowHeight,
                    coordinateSpaceName: canvasCoordinateSpaceName,
                    isEditable: true,
                    isSelected: selectedTaskID == row.task.uniqueID,
                    isLinkSource: pendingLinkSourceTaskID == row.task.uniqueID,
                    onMoveTask: { dayDelta in
                        onMoveTask?(row.task.uniqueID, dayDelta)
                    },
                    onResizeTask: { edge, dayDelta in
                        onResizeTask?(row.task.uniqueID, edge, dayDelta)
                    },
                    onSelectTask: {
                        onSelectTask?(row.task.uniqueID)
                    },
                    onStartLinkingFromTask: {
                        onStartLinkingFromTask?(row.task.uniqueID)
                    }
                )
            }
        }
    }

    private var linkTargetHighlightOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let sourceTaskID = pendingLinkSourceTaskID {
                ForEach(visibleTaskRows, id: \.task.uniqueID) { row in
                    let task = row.task
                    if task.uniqueID != sourceTaskID,
                       let geometry = taskGeometryByID[task.uniqueID] {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.06))
                            .frame(width: geometry.rowRect.width, height: geometry.rowRect.height)
                            .position(x: geometry.rowRect.midX, y: geometry.rowRect.midY)
                            .overlay {
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelectTask?(task.uniqueID)
                                    }
                            }

                        if task.summary != true,
                           task.milestone != true,
                           let taskBarRect = geometry.barRect {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.green.opacity(0.45), lineWidth: 1.5)
                                .frame(width: taskBarRect.width + 6, height: taskBarRect.height + 6)
                                .position(x: taskBarRect.midX, y: taskBarRect.midY)
                        }
                    }
                }
            }
        }
    }

    private var linkSourceHighlightOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let sourceTaskID = pendingLinkSourceTaskID,
               let geometry = taskGeometryByID[sourceTaskID] {
                let rowRect = geometry.rowRect

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.08))
                    .frame(width: rowRect.width, height: rowRect.height)
                    .position(x: rowRect.midX, y: rowRect.midY)

                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: rowRect.width - 2, height: rowRect.height - 2)
                    .position(x: rowRect.midX, y: rowRect.midY)

                if let taskBarRect = geometry.barRect {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 8, weight: .bold))
                        Text("FROM")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.97))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.orange.opacity(0.7), lineWidth: 1.2)
                    )
                    .position(
                        x: min(taskBarRect.maxX + 44, rowRect.maxX - 42),
                        y: taskBarRect.midY
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var dependencySelectionOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleDependencySegments) { segment in
                let isSelected = selectedDependency?.predecessorID == segment.predecessorID
                    && selectedDependency?.successorID == segment.successorID

                segmentPath(segment)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.95) : Color.clear,
                        style: StrokeStyle(lineWidth: isSelected ? 2.4 : 1.0)
                    )
                    .overlay {
                        segmentPath(segment)
                            .stroke(Color.clear, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectDependency?(segment.predecessorID, segment.successorID)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    onRemoveDependency?(segment.predecessorID, segment.successorID)
                                } label: {
                                    Label("Remove Link", systemImage: "link.badge.minus")
                                }
                            }
                    }

                if isSelected {
                    arrowHeadPath(segment)
                        .fill(Color.accentColor)
                }
            }
        }
    }

    private var tooltipOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let selectedTaskID,
               let geometry = taskGeometryByID[selectedTaskID],
               let task = allTasks[selectedTaskID] {
                Color.accentColor.opacity(0.08)
                    .frame(width: geometry.rowRect.width, height: geometry.rowRect.height)
                    .position(
                        x: geometry.rowRect.midX,
                        y: geometry.rowRect.midY
                    )
                    .contentShape(Rectangle())
                    .help(tooltipFor(task))
                    .onTapGesture {
                        onSelectTask?(task.uniqueID)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tooltipFor(_ task: ProjectTask) -> String {
        var parts: [String] = [task.displayName]
        if let s = task.start {
            parts.append("Start: \(DateFormatting.shortDate(s))")
        }
        if let f = task.finish {
            parts.append("Finish: \(DateFormatting.shortDate(f))")
        }
        let dur = task.durationDisplay
        if !dur.isEmpty {
            parts.append("Duration: \(dur)")
        }
        if let pct = task.percentComplete {
            parts.append("Complete: \(Int(pct))%")
        }
        if task.critical == true {
            parts.append("Critical Path")
        }
        if task.hasBaseline {
            if let sv = task.startVarianceDays {
                parts.append("Start Variance: \(sv > 0 ? "+" : "")\(sv)d")
            }
            if let fv = task.finishVarianceDays {
                parts.append("Finish Variance: \(fv > 0 ? "+" : "")\(fv)d")
            }
        }
        return parts.joined(separator: "\n")
    }

    private func segmentPath(_ segment: GanttDependencySegment) -> Path {
        var path = Path()
        path.move(to: segment.start)
        path.addLine(to: CGPoint(x: segment.midX, y: segment.start.y))
        path.addLine(to: CGPoint(x: segment.midX, y: segment.end.y))
        path.addLine(to: segment.end)
        return path
    }

    private func arrowHeadPath(_ segment: GanttDependencySegment) -> Path {
        let size: CGFloat = 4
        var head = Path()
        head.move(to: segment.end)
        head.addLine(to: CGPoint(x: segment.end.x - size, y: segment.end.y - size))
        head.addLine(to: CGPoint(x: segment.end.x - size, y: segment.end.y + size))
        head.closeSubpath()
        return head
    }

    private func taskBarRect(for task: ProjectTask, rowIndex: Int) -> CGRect? {
        taskGeometryByID[task.uniqueID]?.barRect
    }

    private var gridCanvas: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            let visibleRows = Array(visibleRowRange)
            let visibleDays = visibleDayRange

            // --- Alternate Row Shading ---
            for row in visibleRows {
                if row % 2 == 0 {
                    let rowRect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                    context.fill(Path(rowRect), with: .color(.gray.opacity(rowShadingOpacity)))
                }
            }

            // --- Grid ---
            let gridRowUpperBound = min(tasks.count, visibleRowRange.upperBound)
            for row in visibleRowRange.lowerBound...gridRowUpperBound {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            for day in visibleDays {
                let x = CGFloat(day) * pixelsPerDay
                let date = Calendar.current.date(byAdding: .day, value: day, to: startDate) ?? startDate
                let weekday = calendar.component(.weekday, from: date)

                if weekday == 1 || weekday == 7 {
                    let rect = CGRect(x: x, y: 0, width: pixelsPerDay, height: size.height)
                    context.fill(Path(rect), with: .color(.gray.opacity(weekendOpacity)))
                }

                if weekday == 2 || pixelsPerDay >= 30 {
                    var vline = Path()
                    vline.move(to: CGPoint(x: x, y: 0))
                    vline.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(vline, with: .color(.gray.opacity(weekday == 2 ? gridLineOpacity + 0.05 : gridLineOpacity - 0.07)), lineWidth: 0.5)
                }
            }

            // --- Today Marker ---
            if let todayOffset = GanttDateHelpers.todayDayOffset(from: startDate) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= visibleRect.minX && todayX <= visibleRect.maxX {
                    let dashPattern: [CGFloat] = [4, 3]
                    var todayLine = Path()
                    todayLine.move(to: CGPoint(x: todayX, y: 0))
                    todayLine.addLine(to: CGPoint(x: todayX, y: size.height))
                    context.stroke(
                        todayLine,
                        with: .color(.red),
                        style: StrokeStyle(lineWidth: 1.5, dash: dashPattern)
                    )
                }
            }
        }
    }

    private var taskBarsCanvas: some View {
        Canvas { context, size in
            let barInset: CGFloat = 4
            let barHeight = rowHeight - barInset * 2
            let dimOpacity: CGFloat = criticalPathOnly ? 0.15 : 1.0

            // --- Baseline Markers (always visible) ---
            let markerStyle = StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            for row in visibleTaskRows {
                let task = row.task
                let y = CGFloat(row.index) * rowHeight
                guard task.hasBaseline else { continue }

                if let xStart = taskGeometryByID[task.uniqueID]?.baselineStartX {
                    var line = Path()
                    line.move(to: CGPoint(x: xStart, y: y + 6))
                    line.addLine(to: CGPoint(x: xStart, y: y + rowHeight - 6))
                    context.stroke(line, with: .color(.gray.opacity(0.4)), style: markerStyle)
                }

                if let xFinish = taskGeometryByID[task.uniqueID]?.baselineFinishX {
                    var line = Path()
                    line.move(to: CGPoint(x: xFinish, y: y + 6))
                    line.addLine(to: CGPoint(x: xFinish, y: y + rowHeight - 6))
                    context.stroke(line, with: .color(.gray.opacity(0.4)), style: markerStyle)
                }
            }

            // --- Baseline Bars (behind actual bars) ---
            if showBaseline {
                for row in visibleTaskRows {
                    let task = row.task
                    guard let baseRect = taskGeometryByID[task.uniqueID]?.baselineBarRect else { continue }
                    let rr = RoundedRectangle(cornerRadius: 2).path(in: baseRect)
                    context.fill(rr, with: .color(.gray.opacity(baselineOpacity)))
                    context.stroke(rr, with: .color(.gray.opacity(baselineOpacity + 0.15)), lineWidth: 0.5)
                }
            }

            // --- Task Bars ---
            for row in visibleTaskRows {
                let index = row.index
                let task = row.task
                guard let geometry = taskGeometryByID[task.uniqueID] else { continue }
                let y = CGFloat(index) * rowHeight
                let isCritical = task.critical == true
                let taskOpacity = (!criticalPathOnly || isCritical) ? 1.0 : dimOpacity

                guard let xStart = geometry.startX else { continue }

                if editableTaskIDs.contains(task.uniqueID) {
                    continue
                }

                if task.milestone == true {
                    // Diamond
                    let dSize: CGFloat = barHeight * 0.6
                    let cx = xStart
                    let cy = y + rowHeight / 2
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: cx, y: cy - dSize / 2))
                    diamond.addLine(to: CGPoint(x: cx + dSize / 2, y: cy))
                    diamond.addLine(to: CGPoint(x: cx, y: cy + dSize / 2))
                    diamond.addLine(to: CGPoint(x: cx - dSize / 2, y: cy))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.orange.opacity(taskOpacity)))

                    // Right-side label for milestones
                    let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.primary.opacity(taskOpacity))
                    context.draw(
                        context.resolve(label),
                        at: CGPoint(x: cx + dSize / 2 + 4, y: y + rowHeight / 2),
                        anchor: .leading
                    )
                    continue
                }

                guard let width = geometry.width else { continue }

                if task.summary == true {
                    // Summary bracket
                    let bracketH: CGFloat = barHeight * 0.3
                    let bracketY = y + barInset + barHeight * 0.35
                    let rect = CGRect(x: xStart, y: bracketY, width: width, height: bracketH)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.6 * taskOpacity)))

                    // Left/right ticks
                    let tick: CGFloat = 3
                    var leftTick = Path()
                    leftTick.move(to: CGPoint(x: xStart, y: bracketY))
                    leftTick.addLine(to: CGPoint(x: xStart, y: bracketY + bracketH + tick))
                    context.stroke(leftTick, with: .color(.primary.opacity(0.6 * taskOpacity)), lineWidth: 1.5)

                    var rightTick = Path()
                    rightTick.move(to: CGPoint(x: xStart + width, y: bracketY))
                    rightTick.addLine(to: CGPoint(x: xStart + width, y: bracketY + bracketH + tick))
                    context.stroke(rightTick, with: .color(.primary.opacity(0.6 * taskOpacity)), lineWidth: 1.5)
                } else {
                // Regular bar
                let bgColor: Color = isCritical ? .red.opacity(barBgOpacity * taskOpacity) : .blue.opacity(barBgOpacity * taskOpacity)
                let fgColor: Color = isCritical ? .red : .blue

                let barRect = CGRect(x: xStart, y: y + barInset, width: width, height: barHeight)
                let rr = RoundedRectangle(cornerRadius: 3).path(in: barRect)
                context.fill(rr, with: .color(bgColor))
                context.stroke(rr, with: .color(fgColor.opacity(0.4 * taskOpacity)), lineWidth: isCritical && criticalPathOnly ? 1.5 : 0.5)

                // Progress fill
                let pct = (task.percentComplete ?? 0) / 100.0
                if pct > 0 {
                    let fillWidth = width * CGFloat(pct)
                    let fillRect = CGRect(x: xStart, y: y + barInset, width: fillWidth, height: barHeight)
                    let fillRR = RoundedRectangle(cornerRadius: 3).path(in: fillRect)
                    context.fill(fillRR, with: .color(fgColor.opacity(0.6 * taskOpacity)))
                }

                // Task name: inline if enough space, otherwise right of bar
                if width > 60 {
                    let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.primary.opacity(taskOpacity))
                    context.draw(
                        context.resolve(label),
                        at: CGPoint(x: xStart + 4, y: y + rowHeight / 2),
                        anchor: .leading
                    )
                } else {
                    let label = Text(task.displayName).font(.system(size: 9)).foregroundColor(.secondary.opacity(taskOpacity))
                    context.draw(
                        context.resolve(label),
                        at: CGPoint(x: xStart + width + 4, y: y + rowHeight / 2),
                        anchor: .leading
                    )
                }

                if let descriptor = task.baselineVarianceDescriptor, descriptor.days != 0 {
                    drawBaselineBadge(
                        context: context,
                        descriptor: descriptor,
                        x: xStart + width + 8,
                        y: y + barInset,
                        opacity: taskOpacity
                    )
                }
                }
            }
        }
    }

    private var dependencyCanvas: some View {
        Canvas { context, _ in
            for segment in visibleDependencySegments {
                context.stroke(
                    segmentPath(segment),
                    with: .color(.gray.opacity(0.5)),
                    style: StrokeStyle(lineWidth: 0.8)
                )
                context.fill(arrowHeadPath(segment), with: .color(.gray.opacity(0.5)))
            }
        }
    }

    private func refreshLayoutState() {
        layoutState = GanttCanvasLayoutState.build(
            tasks: tasks,
            allTasks: allTasks,
            rowIndexByTaskID: rowIndexByTaskID,
            startDate: startDate,
            totalDays: totalDays,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            showBaseline: showBaseline
        )
    }

    private func drawBaselineBadge(
        context: GraphicsContext,
        descriptor: BaselineVarianceDescriptor,
        x: CGFloat,
        y: CGFloat,
        opacity: Double
    ) {
        let label = Text(descriptor.label)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.primary)
        let resolved = context.resolve(label)
        let badgeWidth = max(CGFloat(descriptor.label.count) * CGFloat(7) + CGFloat(10), CGFloat(32))
        let badgeHeight: CGFloat = 16
        let badgeRect = CGRect(x: x, y: y, width: badgeWidth, height: badgeHeight)
        let border = RoundedRectangle(cornerRadius: badgeHeight / 2).path(in: badgeRect)

        context.fill(border, with: .color(descriptor.color.opacity(0.2 * opacity)))
        context.stroke(border, with: .color(descriptor.color.opacity(0.6 * opacity)), lineWidth: 0.5)
        context.draw(resolved, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
    }
}
