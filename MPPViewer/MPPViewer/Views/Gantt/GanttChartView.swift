import SwiftUI

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
        let rowIndexByTaskID = Dictionary(uniqueKeysWithValues: flatTasks.enumerated().map { ($1.uniqueID, $0) })
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

struct GanttChartView: View {
    let project: ProjectModel
    let searchText: String
    var nativePlan: Binding<NativeProjectPlan>? = nil

    @State private var derivedContent: GanttDerivedContent

    @State private var pixelsPerDay: CGFloat = 8
    @State private var timelineViewportWidth: CGFloat = 0
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

    private var dateRange: (start: Date, end: Date) {
        derivedContent.dateRange
    }

    private var totalDays: Int {
        derivedContent.totalDays
    }

    private var isNativeEditablePlan: Bool {
        nativePlan != nil
    }

    private var isEditingEnabled: Bool {
        isNativeEditablePlan && interactionMode == .edit
    }

    private var showsEditSidebar: Bool {
        isEditingEnabled
    }

    private var editableTaskIDs: Set<Int> {
        guard isEditingEnabled, let nativePlan else { return [] }
        let nativeTaskIDs = Set(nativePlan.wrappedValue.tasks.map(\.id))
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
        guard let nativePlan, let selectedTaskID else { return nil }
        return nativePlan.wrappedValue.tasks.first(where: { $0.id == selectedTaskID })
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

    init(project: ProjectModel, searchText: String, nativePlan: Binding<NativeProjectPlan>? = nil) {
        self.project = project
        self.searchText = searchText
        self.nativePlan = nativePlan
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        timelineViewportWidth = viewportWidth
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: viewportWidth) { _, newWidth in
                        timelineViewportWidth = newWidth
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: totalDays) { _, _ in
                        applyAutoFitIfNeeded()
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
        .onChange(of: searchText) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: ganttRefreshSignature) { _, _ in
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
    }

    private var ganttRefreshSignature: Int {
        var hasher = Hasher()
        hasher.combine(project.properties.statusDate ?? "")
        hasher.combine(project.tasks.count)
        for task in project.tasks {
            hasher.combine(task.uniqueID)
            hasher.combine(task.start ?? "")
            hasher.combine(task.finish ?? "")
            hasher.combine(task.percentComplete ?? 0)
            hasher.combine(task.summary == true)
            hasher.combine(task.milestone == true)
            hasher.combine(task.predecessors?.count ?? 0)
        }
        return hasher.finalize()
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
                        } else if let nativePlan {
                            let resources = nativePlan.wrappedValue.resources

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
                    criticalPathOnly: criticalPathOnly,
                    showBaseline: showBaseline,
                    editableTaskIDs: editableTaskIDs,
                    selectedTaskID: selectedTaskID,
                    selectedDependency: selectedDependency,
                    pendingLinkSourceTaskID: pendingDependencySourceTaskID,
                    onMoveTask: nativePlan == nil ? nil : moveNativeTask,
                    onResizeTask: nativePlan == nil ? nil : resizeNativeTask,
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
        VStack(alignment: .leading, spacing: 0) {
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

    private func startLinkingFromTask(_ taskID: Int) {
        guard isEditingEnabled else { return }
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
        guard predecessorID != successorID, let nativePlan else { return }

        var plan = nativePlan.wrappedValue
        guard let successorIndex = plan.tasks.firstIndex(where: { $0.id == successorID }) else { return }

        if plan.tasks[successorIndex].predecessorTaskIDs.contains(predecessorID) {
            nativePlan.wrappedValue = plan
            return
        }

        guard !createsDependencyCycle(addingDependencyFrom: predecessorID, to: successorID, tasks: plan.tasks) else {
            return
        }

        plan.tasks[successorIndex].predecessorTaskIDs.append(predecessorID)
        plan.tasks[successorIndex].predecessorTaskIDs = Array(Set(plan.tasks[successorIndex].predecessorTaskIDs)).sorted()
        plan.tasks[successorIndex].manuallyScheduled = false
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedDependency = GanttDependencySelection(predecessorID: predecessorID, successorID: successorID)
    }

    private func removeSelectedDependency() {
        guard let selectedDependency else { return }
        removeDependency(
            predecessorID: selectedDependency.predecessorID,
            successorID: selectedDependency.successorID
        )
    }

    private func removeDependency(predecessorID: Int, successorID: Int) {
        guard let nativePlan,
              let successorIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == successorID }) else { return }

        var plan = nativePlan.wrappedValue
        let originalCount = plan.tasks[successorIndex].predecessorTaskIDs.count
        plan.tasks[successorIndex].predecessorTaskIDs.removeAll { $0 == predecessorID }
        guard plan.tasks[successorIndex].predecessorTaskIDs.count != originalCount else { return }

        plan.tasks[successorIndex].manuallyScheduled = false
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedDependency = nil
        selectedTaskID = successorID
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
        guard let nativePlan else { return }

        var plan = nativePlan.wrappedValue
        let insertionAnchorIndex = selectedNativeTaskIndex(in: plan.tasks)
        let insertionIndex: Int
        let anchorDate: Date
        let outlineLevel: Int

        if let insertionAnchorIndex {
            let range = subtreeRange(for: insertionAnchorIndex, in: plan.tasks)
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
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = newTask.id
        interactionMode = .edit
    }

    private func refreshDerivedContent() {
        derivedContent = GanttDerivedContent.build(project: project, searchText: searchText)
    }

    private func addSubtaskFromGantt() {
        guard let nativePlan else { return }

        if selectedTaskID == nil {
            addTaskFromGantt()
            return
        }

        var plan = nativePlan.wrappedValue
        guard let selectedIndex = selectedNativeTaskIndex(in: plan.tasks) else {
            addTaskFromGantt()
            return
        }

        let range = subtreeRange(for: selectedIndex, in: plan.tasks)
        let parentTask = plan.tasks[selectedIndex]

        var newTask = plan.makeTask(anchoredTo: parentTask.normalizedFinishDate)
        newTask.outlineLevel = parentTask.outlineLevel + 1
        plan.tasks.insert(newTask, at: range.upperBound)
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = newTask.id
        interactionMode = .edit
    }

    private var canDeleteSelectedTask: Bool {
        isEditingEnabled && selectedNativeTaskIndex(in: nativePlan?.wrappedValue.tasks ?? []) != nil
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
        guard let nativePlan else { return }
        var plan = nativePlan.wrappedValue
        guard let insertionAnchorIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let range = subtreeRange(for: insertionAnchorIndex, in: plan.tasks)
        let anchorTask = plan.tasks[insertionAnchorIndex]

        var newTask = plan.makeTask(anchoredTo: anchorTask.normalizedFinishDate)
        newTask.outlineLevel = anchorTask.outlineLevel
        plan.tasks.insert(newTask, at: range.upperBound)
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = newTask.id
        interactionMode = .edit
    }

    private func addSubtask(under taskID: Int) {
        guard let nativePlan else { return }
        var plan = nativePlan.wrappedValue
        guard let selectedIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let range = subtreeRange(for: selectedIndex, in: plan.tasks)
        let parentTask = plan.tasks[selectedIndex]

        var newTask = plan.makeTask(anchoredTo: parentTask.normalizedFinishDate)
        newTask.outlineLevel = parentTask.outlineLevel + 1
        plan.tasks.insert(newTask, at: range.upperBound)
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = newTask.id
        interactionMode = .edit
    }

    private func deleteSelectedTask() {
        guard let selectedTaskID else { return }
        deleteTask(taskID: selectedTaskID)
    }

    private func deleteTask(taskID: Int) {
        guard let nativePlan else { return }

        var plan = nativePlan.wrappedValue
        guard let selectedIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let range = subtreeRange(for: selectedIndex, in: plan.tasks)
        let removedIDs = Set(plan.tasks[range].map(\.id))
        let nextSelectionIndex = range.lowerBound < plan.tasks.count - range.count ? range.lowerBound : max(0, range.lowerBound - 1)

        plan.tasks.removeSubrange(range)
        for index in plan.tasks.indices {
            plan.tasks[index].predecessorTaskIDs.removeAll { removedIDs.contains($0) }
        }
        plan.assignments.removeAll { removedIDs.contains($0.taskID) }
        plan.reschedule()
        nativePlan.wrappedValue = plan

        if let pendingDependencySourceTaskID, removedIDs.contains(pendingDependencySourceTaskID) {
            self.pendingDependencySourceTaskID = nil
        }
        if let selectedDependency,
           removedIDs.contains(selectedDependency.predecessorID) || removedIDs.contains(selectedDependency.successorID) {
            self.selectedDependency = nil
        }
        selectedTaskID = plan.tasks.indices.contains(nextSelectionIndex) ? plan.tasks[nextSelectionIndex].id : nil
    }

    private func canIndent(taskID: Int) -> Bool {
        guard let nativePlan,
              let selectedIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }),
              selectedIndex > 0 else { return false }

        let currentLevel = nativePlan.wrappedValue.tasks[selectedIndex].outlineLevel
        let previousLevel = nativePlan.wrappedValue.tasks[selectedIndex - 1].outlineLevel
        return previousLevel + 1 > currentLevel
    }

    private func indentSelectedTask() {
        guard let selectedTaskID else { return }
        indent(taskID: selectedTaskID)
    }

    private func indent(taskID: Int) {
        guard let nativePlan, canIndent(taskID: taskID),
              let selectedIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        var plan = nativePlan.wrappedValue
        let newLevel = plan.tasks[selectedIndex - 1].outlineLevel + 1
        let delta = newLevel - plan.tasks[selectedIndex].outlineLevel
        adjustSubtreeOutlineLevel(taskID: taskID, by: delta, in: &plan)
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = taskID
    }

    private func canOutdent(taskID: Int) -> Bool {
        guard let nativePlan,
              let selectedIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        return nativePlan.wrappedValue.tasks[selectedIndex].outlineLevel > 1
    }

    private func outdentSelectedTask() {
        guard let selectedTaskID else { return }
        outdent(taskID: selectedTaskID)
    }

    private func outdent(taskID: Int) {
        guard let nativePlan, canOutdent(taskID: taskID) else { return }
        var plan = nativePlan.wrappedValue
        adjustSubtreeOutlineLevel(taskID: taskID, by: -1, in: &plan)
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = taskID
    }

    private func adjustSubtreeOutlineLevel(taskID: Int, by delta: Int, in plan: inout NativeProjectPlan) {
        guard let selectedIndex = plan.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let range = subtreeRange(for: selectedIndex, in: plan.tasks)
        for index in range {
            plan.tasks[index].outlineLevel = max(1, plan.tasks[index].outlineLevel + delta)
        }
    }

    private func clearPredecessors(for taskID: Int) {
        guard let nativePlan,
              let taskIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var plan = nativePlan.wrappedValue
        plan.tasks[taskIndex].predecessorTaskIDs = []
        plan.tasks[taskIndex].manuallyScheduled = false
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = taskID
        if pendingDependencySourceTaskID == taskID {
            pendingDependencySourceTaskID = nil
        }
        if let selectedDependency, selectedDependency.successorID == taskID {
            self.selectedDependency = nil
        }
    }

    private func updateSelectedTask(reschedule: Bool = true, _ transform: (inout NativePlanTask) -> Void) {
        guard let nativePlan,
              let selectedTaskID,
              let taskIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == selectedTaskID }) else { return }

        var plan = nativePlan.wrappedValue
        transform(&plan.tasks[taskIndex])
        if reschedule {
            plan.reschedule()
        }
        nativePlan.wrappedValue = plan
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
                guard let selectedTaskID, let nativePlan else { return }
                let validIDs = Set(nativePlan.wrappedValue.tasks.map(\.id))
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
        guard let nativePlan else { return nil }
        return nativePlan.wrappedValue.assignments.firstIndex(where: { $0.taskID == taskID })
    }

    private var primaryAssignmentUnitsSummary: String {
        guard let selectedTaskID,
              let nativePlan,
              let index = primaryAssignmentIndex(for: selectedTaskID) else {
            return "0%"
        }

        return "\(Int(nativePlan.wrappedValue.assignments[index].units))%"
    }

    private func addPrimaryAssignmentToSelectedTask() {
        guard let nativePlan, let selectedTaskID else { return }
        guard primaryAssignmentIndex(for: selectedTaskID) == nil else { return }
        let defaultResourceID = nativePlan.wrappedValue.resources.first?.id
        guard defaultResourceID != nil else { return }

        var plan = nativePlan.wrappedValue
        plan.assignments.append(plan.makeAssignment(taskID: selectedTaskID, resourceID: defaultResourceID))
        nativePlan.wrappedValue = plan
    }

    private func clearPrimaryAssignmentFromSelectedTask() {
        guard let nativePlan, let selectedTaskID else { return }
        guard let index = primaryAssignmentIndex(for: selectedTaskID) else { return }

        var plan = nativePlan.wrappedValue
        plan.assignments.remove(at: index)
        nativePlan.wrappedValue = plan
    }

    private func selectedTaskPrimaryAssignmentResourceBinding() -> Binding<Int?> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else {
                    return nil
                }

                return nativePlan.wrappedValue.assignments[index].resourceID
            },
            set: { newValue in
                guard let nativePlan, let selectedTaskID else { return }
                var plan = nativePlan.wrappedValue

                if let index = plan.assignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                    if let newValue {
                        plan.assignments[index].resourceID = newValue
                    } else {
                        plan.assignments.remove(at: index)
                    }
                } else if let newValue {
                    plan.assignments.append(plan.makeAssignment(taskID: selectedTaskID, resourceID: newValue))
                }

                nativePlan.wrappedValue = plan
            }
        )
    }

    private func selectedTaskPrimaryAssignmentUnitsBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID,
                      let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else {
                    return ""
                }

                return String(Int(nativePlan.wrappedValue.assignments[index].units))
            },
            set: { newValue in
                guard let nativePlan, let selectedTaskID else { return }

                let digits = newValue.filter(\.isNumber)
                var plan = nativePlan.wrappedValue

                if digits.isEmpty {
                    if let index = plan.assignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                        plan.assignments[index].units = 0
                        nativePlan.wrappedValue = plan
                    }
                    return
                }

                let parsedUnits = min(300.0, max(0.0, Double(digits) ?? 0))
                if let index = plan.assignments.firstIndex(where: { $0.taskID == selectedTaskID }) {
                    plan.assignments[index].units = parsedUnits
                } else {
                    var assignment = plan.makeAssignment(
                        taskID: selectedTaskID,
                        resourceID: plan.resources.first?.id
                    )
                    assignment.units = parsedUnits
                    plan.assignments.append(assignment)
                }

                nativePlan.wrappedValue = plan
            }
        )
    }

    private func selectedTaskPrimaryAssignmentWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID, let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativePlan.wrappedValue.assignments[index].workSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.workSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentActualWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID, let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativePlan.wrappedValue.assignments[index].actualWorkSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.actualWorkSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentRemainingWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID, let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativePlan.wrappedValue.assignments[index].remainingWorkSeconds)
            },
            set: { newValue in
                updatePrimaryAssignmentHours { $0.remainingWorkSeconds = parseHoursInput(newValue) }
            }
        )
    }

    private func selectedTaskPrimaryAssignmentOvertimeWorkBinding() -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskID, let nativePlan,
                      let index = primaryAssignmentIndex(for: selectedTaskID) else { return "" }
                return hoursText(nativePlan.wrappedValue.assignments[index].overtimeWorkSeconds)
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
        guard let nativePlan, let selectedTaskID,
              let index = primaryAssignmentIndex(for: selectedTaskID) else { return }
        var plan = nativePlan.wrappedValue
        transform(&plan.assignments[index])
        nativePlan.wrappedValue = plan
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
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
        guard dayDelta != 0, let nativePlan else { return }
        guard let taskIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        var plan = nativePlan.wrappedValue
        var task = plan.tasks[taskIndex]
        let calendar = Calendar.current
        task.startDate = calendar.date(byAdding: .day, value: dayDelta, to: task.startDate) ?? task.startDate
        task.finishDate = calendar.date(byAdding: .day, value: dayDelta, to: task.finishDate) ?? task.finishDate
        task.startDate = calendar.startOfDay(for: task.startDate)
        task.finishDate = task.isMilestone ? task.startDate : calendar.startOfDay(for: task.finishDate)
        task.manuallyScheduled = true
        plan.tasks[taskIndex] = task
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = taskID
    }

    private func resizeNativeTask(_ taskID: Int, edge: GanttResizeEdge, dayDelta: Int) {
        guard dayDelta != 0, let nativePlan else { return }
        guard let taskIndex = nativePlan.wrappedValue.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        var plan = nativePlan.wrappedValue
        var task = plan.tasks[taskIndex]
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
        plan.tasks[taskIndex] = task
        plan.reschedule()
        nativePlan.wrappedValue = plan
        selectedTaskID = taskID
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

struct GanttCanvasView: View {
    private let canvasCoordinateSpaceName = "GanttCanvasViewSpace"

    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let rowIndexByTaskID: [Int: Int]
    let startDate: Date
    let totalDays: Int
    let pixelsPerDay: CGFloat
    let rowHeight: CGFloat
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

    private var rowShadingOpacity: Double { colorScheme == .dark ? 0.08 : 0.04 }
    private var gridLineOpacity: Double { colorScheme == .dark ? 0.25 : 0.15 }
    private var weekendOpacity: Double { colorScheme == .dark ? 0.12 : 0.06 }
    private var barBgOpacity: Double { colorScheme == .dark ? 0.35 : 0.25 }
    private var baselineOpacity: Double { colorScheme == .dark ? 0.4 : 0.25 }

    private struct DependencySegment: Identifiable {
        let predecessorID: Int
        let successorID: Int
        let start: CGPoint
        let end: CGPoint
        let midX: CGFloat

        var id: String { "\(predecessorID)->\(successorID)" }
    }

    private var dependencySegments: [DependencySegment] {
        let calendar = Calendar.current

        return tasks.flatMap { task in
            guard let predecessors = task.predecessors,
                  let successorIndex = rowIndexByTaskID[task.uniqueID] else { return [DependencySegment]() }

            return predecessors.compactMap { relation in
                guard let predecessorIndex = rowIndexByTaskID[relation.targetTaskUniqueID],
                      let predecessorTask = allTasks[relation.targetTaskUniqueID] else { return nil }

                let predecessorEnd = dayOffsetX(for: predecessorTask.finishDate, calendar: calendar)
                let successorStart = dayOffsetX(for: task.startDate, calendar: calendar)
                let predecessorY = CGFloat(predecessorIndex) * rowHeight + rowHeight / 2
                let successorY = CGFloat(successorIndex) * rowHeight + rowHeight / 2

                return DependencySegment(
                    predecessorID: relation.targetTaskUniqueID,
                    successorID: task.uniqueID,
                    start: CGPoint(x: predecessorEnd, y: predecessorY),
                    end: CGPoint(x: successorStart, y: successorY),
                    midX: predecessorEnd + 6
                )
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvas
            tooltipOverlay
            linkSourceHighlightOverlay
            linkTargetHighlightOverlay
            dependencySelectionOverlay
            editableBarsOverlay
        }
        .coordinateSpace(name: canvasCoordinateSpaceName)
    }

    private var editableBarsOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(tasks.enumerated()), id: \.element.uniqueID) { index, task in
                if editableTaskIDs.contains(task.uniqueID) {
                    GanttBarView(
                        task: task,
                        startDate: startDate,
                        pixelsPerDay: pixelsPerDay,
                        rowIndex: index,
                        rowHeight: rowHeight,
                        coordinateSpaceName: canvasCoordinateSpaceName,
                        isEditable: true,
                        isSelected: selectedTaskID == task.uniqueID,
                        isLinkSource: pendingLinkSourceTaskID == task.uniqueID,
                        onMoveTask: { dayDelta in
                            onMoveTask?(task.uniqueID, dayDelta)
                        },
                        onResizeTask: { edge, dayDelta in
                            onResizeTask?(task.uniqueID, edge, dayDelta)
                        },
                        onSelectTask: {
                            onSelectTask?(task.uniqueID)
                        },
                        onStartLinkingFromTask: {
                            onStartLinkingFromTask?(task.uniqueID)
                        }
                    )
                }
            }
        }
    }

    private var linkTargetHighlightOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let sourceTaskID = pendingLinkSourceTaskID {
                ForEach(Array(tasks.enumerated()), id: \.element.uniqueID) { rowIndex, task in
                    if task.uniqueID != sourceTaskID {
                        let rowRect = CGRect(
                            x: 0,
                            y: CGFloat(rowIndex) * rowHeight,
                            width: CGFloat(totalDays) * pixelsPerDay,
                            height: rowHeight
                        )

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.opacity(0.06))
                            .frame(width: rowRect.width, height: rowRect.height)
                            .position(x: rowRect.midX, y: rowRect.midY)
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
                           let taskBarRect = taskBarRect(for: task, rowIndex: rowIndex) {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.green.opacity(0.45), lineWidth: 1.5)
                                .frame(width: taskBarRect.width + 6, height: taskBarRect.height + 6)
                                .position(x: taskBarRect.midX, y: taskBarRect.midY)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                            Text("Click To Link")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Color.green.opacity(0.95))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.96))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.green.opacity(0.6), lineWidth: 1)
                        )
                        .position(x: rowRect.maxX - 68, y: rowRect.midY)
                    }
                }
            }
        }
    }

    private var linkSourceHighlightOverlay: some View {
        ZStack(alignment: .topLeading) {
            if let sourceTaskID = pendingLinkSourceTaskID,
               let rowIndex = rowIndexByTaskID[sourceTaskID] {
                let rowRect = CGRect(
                    x: 0,
                    y: CGFloat(rowIndex) * rowHeight,
                    width: CGFloat(totalDays) * pixelsPerDay,
                    height: rowHeight
                )

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.08))
                    .frame(width: rowRect.width, height: rowRect.height)
                    .position(x: rowRect.midX, y: rowRect.midY)

                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: rowRect.width - 2, height: rowRect.height - 2)
                    .position(x: rowRect.midX, y: rowRect.midY)

                if let sourceTask = allTasks[sourceTaskID],
                   let taskBarRect = taskBarRect(for: sourceTask, rowIndex: rowIndex) {
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
            ForEach(dependencySegments) { segment in
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.uniqueID) { _, task in
                ZStack {
                    if selectedTaskID == task.uniqueID {
                        Color.accentColor.opacity(0.08)
                    } else {
                        Color.clear
                    }
                }
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                    .help(tooltipFor(task))
                    .onTapGesture {
                        onSelectTask?(task.uniqueID)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func segmentPath(_ segment: DependencySegment) -> Path {
        var path = Path()
        path.move(to: segment.start)
        path.addLine(to: CGPoint(x: segment.midX, y: segment.start.y))
        path.addLine(to: CGPoint(x: segment.midX, y: segment.end.y))
        path.addLine(to: segment.end)
        return path
    }

    private func arrowHeadPath(_ segment: DependencySegment) -> Path {
        let size: CGFloat = 4
        var head = Path()
        head.move(to: segment.end)
        head.addLine(to: CGPoint(x: segment.end.x - size, y: segment.end.y - size))
        head.addLine(to: CGPoint(x: segment.end.x - size, y: segment.end.y + size))
        head.closeSubpath()
        return head
    }

    private func taskBarRect(for task: ProjectTask, rowIndex: Int) -> CGRect? {
        let calendar = Calendar.current
        guard let taskStart = task.startDate else { return nil }
        let barInset: CGFloat = 4
        let barHeight = rowHeight - barInset * 2
        let startDays = calendar.dateComponents([.day], from: startDate, to: taskStart).day ?? 0
        let xStart = CGFloat(startDays) * pixelsPerDay

        if task.milestone == true {
            let dSize: CGFloat = barHeight * 0.6
            return CGRect(
                x: xStart - (dSize / 2),
                y: CGFloat(rowIndex) * rowHeight + (rowHeight - dSize) / 2,
                width: dSize,
                height: dSize
            )
        }

        guard let taskFinish = task.finishDate else { return nil }
        let finishDays = calendar.dateComponents([.day], from: startDate, to: taskFinish).day ?? 0
        let width = max(4, CGFloat(max(1, finishDays - startDays)) * pixelsPerDay)
        return CGRect(
            x: xStart,
            y: CGFloat(rowIndex) * rowHeight + barInset,
            width: width,
            height: barHeight
        )
    }

    private var canvas: some View {
        Canvas { context, size in
            let calendar = Calendar.current
            let barInset: CGFloat = 4
            let barHeight = rowHeight - barInset * 2
            let dimOpacity: CGFloat = criticalPathOnly ? 0.15 : 1.0

            // --- Alternate Row Shading ---
            for row in 0..<tasks.count {
                if row % 2 == 0 {
                    let rowRect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                    context.fill(Path(rowRect), with: .color(.gray.opacity(rowShadingOpacity)))
                }
            }

            // --- Grid ---
            for row in 0...tasks.count {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(gridLineOpacity)), lineWidth: 0.5)
            }

            for day in 0..<totalDays {
                let x = CGFloat(day) * pixelsPerDay
                let date = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
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

            // --- Baseline Markers (always visible) ---
            let markerStyle = StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            for (index, task) in tasks.enumerated() {
                let y = CGFloat(index) * rowHeight
                guard task.hasBaseline else { continue }

                if let bsDate = task.baselineStartDate {
                    let startDays = calendar.dateComponents([.day], from: startDate, to: bsDate).day ?? 0
                    let xStart = CGFloat(startDays) * pixelsPerDay
                    var line = Path()
                    line.move(to: CGPoint(x: xStart, y: y + 6))
                    line.addLine(to: CGPoint(x: xStart, y: y + rowHeight - 6))
                    context.stroke(line, with: .color(.gray.opacity(0.4)), style: markerStyle)
                }

                if let bfDate = task.baselineFinishDate {
                    let finishDays = calendar.dateComponents([.day], from: startDate, to: bfDate).day ?? 0
                    let xFinish = CGFloat(finishDays) * pixelsPerDay
                    var line = Path()
                    line.move(to: CGPoint(x: xFinish, y: y + 6))
                    line.addLine(to: CGPoint(x: xFinish, y: y + rowHeight - 6))
                    context.stroke(line, with: .color(.gray.opacity(0.4)), style: markerStyle)
                }
            }

            // --- Baseline Bars (behind actual bars) ---
            if showBaseline {
                for (index, task) in tasks.enumerated() {
                    guard task.hasBaseline,
                          let bsDate = task.baselineStartDate,
                          let bfDate = task.baselineFinishDate,
                          task.milestone != true,
                          task.summary != true else { continue }

                    let y = CGFloat(index) * rowHeight
                    let bsOffset = calendar.dateComponents([.day], from: startDate, to: bsDate).day ?? 0
                    let bfOffset = calendar.dateComponents([.day], from: startDate, to: bfDate).day ?? 0
                    let xStart = CGFloat(bsOffset) * pixelsPerDay
                    let width = max(4, CGFloat(max(1, bfOffset - bsOffset)) * pixelsPerDay)

                    let baselineBarHeight = barHeight * 0.5
                    let baselineY = y + barInset + barHeight - baselineBarHeight // bottom-aligned
                    let baseRect = CGRect(x: xStart, y: baselineY, width: width, height: baselineBarHeight)
                    let rr = RoundedRectangle(cornerRadius: 2).path(in: baseRect)
                    context.fill(rr, with: .color(.gray.opacity(baselineOpacity)))
                    context.stroke(rr, with: .color(.gray.opacity(baselineOpacity + 0.15)), lineWidth: 0.5)
                }
            }

            // --- Task Bars ---
            var taskIndexMap: [Int: Int] = [:]
            for (index, task) in tasks.enumerated() {
                taskIndexMap[task.uniqueID] = index
                let y = CGFloat(index) * rowHeight
                let isCritical = task.critical == true
                let taskOpacity = (!criticalPathOnly || isCritical) ? 1.0 : dimOpacity

                guard let taskStart = task.startDate else { continue }
                let startDays = calendar.dateComponents([.day], from: startDate, to: taskStart).day ?? 0
                let xStart = CGFloat(startDays) * pixelsPerDay

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

                guard let taskFinish = task.finishDate else { continue }
                let endDays = calendar.dateComponents([.day], from: startDate, to: taskFinish).day ?? 0
                let width = max(4, CGFloat(max(1, endDays - startDays)) * pixelsPerDay)

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

            // --- Today Marker ---
            if let todayOffset = GanttDateHelpers.todayDayOffset(from: startDate) {
                let todayX = todayOffset * pixelsPerDay
                if todayX >= 0 && todayX <= size.width {
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

            // --- Dependency Arrows ---
            for task in tasks {
                guard let predecessors = task.predecessors else { continue }
                guard let succIdx = taskIndexMap[task.uniqueID] else { continue }

                for relation in predecessors {
                    guard let predIdx = taskIndexMap[relation.targetTaskUniqueID] else { continue }
                    guard let pred = allTasks[relation.targetTaskUniqueID] else { continue }

                    let predEnd = dayOffsetX(for: pred.finishDate, calendar: calendar)
                    let succStart = dayOffsetX(for: task.startDate, calendar: calendar)
                    let predY = CGFloat(predIdx) * rowHeight + rowHeight / 2
                    let succY = CGFloat(succIdx) * rowHeight + rowHeight / 2

                    var arrow = Path()
                    arrow.move(to: CGPoint(x: predEnd, y: predY))

                    let midX = predEnd + 6
                    arrow.addLine(to: CGPoint(x: midX, y: predY))
                    arrow.addLine(to: CGPoint(x: midX, y: succY))
                    arrow.addLine(to: CGPoint(x: succStart, y: succY))

                    context.stroke(arrow, with: .color(.gray.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8))

                    // Arrowhead
                    let aSize: CGFloat = 3
                    var head = Path()
                    head.move(to: CGPoint(x: succStart, y: succY))
                    head.addLine(to: CGPoint(x: succStart - aSize, y: succY - aSize))
                    head.addLine(to: CGPoint(x: succStart - aSize, y: succY + aSize))
                    head.closeSubpath()
                    context.fill(head, with: .color(.gray.opacity(0.5)))
                }
            }
        }
    } // end canvas

    private func dayOffsetX(for date: Date?, calendar: Calendar) -> CGFloat {
        guard let date = date else { return 0 }
        let days = calendar.dateComponents([.day], from: startDate, to: date).day ?? 0
        return CGFloat(days) * pixelsPerDay
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
