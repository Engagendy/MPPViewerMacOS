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

private struct GanttTaskPopover: View {
    let task: ProjectTask
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                taskKindIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayName)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(taskKindText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.accessoryBar)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    detailSection("Schedule") {
                        detailRow("Start", DateFormatting.shortDate(task.start))
                        detailRow("Finish", DateFormatting.shortDate(task.finish))
                        detailRow("Duration", task.durationDisplay.isEmpty ? "-" : task.durationDisplay)
                        detailRow("Complete", task.percentCompleteDisplay)
                        detailRow("Critical", task.critical == true ? "Yes" : "No")
                    }

                    detailSection("Tracking") {
                        detailRow("Work", task.work.map(DurationFormatting.formatSeconds) ?? "-")
                        detailRow("Cost", task.cost.map { String(format: "%.2f", $0) } ?? "-")
                        detailRow("Priority", task.priority.map(String.init) ?? "-")
                        detailRow("Total Slack", task.totalSlackDisplay ?? "-")
                        detailRow("Free Slack", task.freeSlackDisplay ?? "-")
                    }

                    detailSection("Structure") {
                        detailRow("Unique ID", String(task.uniqueID))
                        detailRow("ID", task.id.map(String.init) ?? "-")
                        detailRow("WBS", task.wbs ?? "-")
                        detailRow("Outline", task.outlineNumber ?? task.outlineLevel.map(String.init) ?? "-")
                        detailRow("Predecessors", relationSummary(task.predecessors))
                        detailRow("Successors", relationSummary(task.successors))
                    }

                    if task.hasBaseline {
                        detailSection("Baseline") {
                            detailRow("Status", baselineSummary)
                            detailRow("Start", DateFormatting.shortDate(task.baselineStart))
                            detailRow("Finish", DateFormatting.shortDate(task.baselineFinish))
                        }
                    }

                    if (task.constraintType?.isEmpty == false) || (task.constraintDate?.isEmpty == false) {
                        detailSection("Constraint") {
                            detailRow("Type", task.constraintType ?? "-")
                            detailRow("Date", DateFormatting.shortDate(task.constraintDate))
                        }
                    }

                    if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSection("Notes") {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(maxHeight: 430)
        }
        .padding(18)
        .frame(width: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 16)
    }

    @ViewBuilder
    private var taskKindIcon: some View {
        if task.summary == true {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
        } else if task.milestone == true {
            Image(systemName: "diamond.fill")
                .foregroundStyle(.orange)
        } else if task.critical == true {
            Circle()
                .fill(.red)
                .frame(width: 9, height: 9)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(.blue.opacity(0.65))
                .frame(width: 14, height: 9)
        }
    }

    private var baselineSummary: String {
        if let descriptor = task.baselineVarianceDescriptor {
            return descriptor.label
        }
        return "Captured"
    }

    private var taskKindText: String {
        if task.summary == true { return "Summary" }
        if task.milestone == true { return "Milestone" }
        return "Task"
    }

    private func relationSummary(_ relations: [TaskRelation]?) -> String {
        guard let relations, !relations.isEmpty else { return "-" }
        return relations
            .map { relation in
                let type = relation.type?.isEmpty == false ? " \(relation.type!)" : ""
                return "\(relation.targetTaskUniqueID)\(type)"
            }
            .joined(separator: ", ")
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.caption)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    static func build(
        project: ProjectModel,
        searchText: String,
        focusedTaskID: Int? = nil,
        maxVisibleLevel: Int? = nil
    ) -> GanttDerivedContent {
        var root = if searchText.isEmpty {
            project.rootTasks
        } else {
            project.tasks.filter { $0.name?.localizedCaseInsensitiveContains(searchText) == true }
        }

        // Focus mode isolates a single subtree (e.g. one phase) so you can
        // work on it without the rest of the plan in the way.
        if let focusedTaskID, let focusRoot = project.tasksByID[focusedTaskID] {
            root = [focusRoot]
        }

        var flatTasks = flattenVisible(root)

        // Level filter hides rows deeper than the chosen outline level, giving
        // an executive (phases-only) or working (down to tasks) altitude.
        if let maxVisibleLevel {
            flatTasks = flatTasks.filter { ($0.outlineLevel ?? 1) <= maxVisibleLevel }
        }

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
    // Visual attributes that must also invalidate the cached bars when they
    // change, even if the schedule stayed the same.
    let barColorHex: String?
    let percentComplete: Double
    let critical: Bool
}

private struct GanttDerivedInput: Equatable {
    let searchText: String
    let statusDate: String
    let focusedTaskID: Int?
    let maxVisibleLevel: Int?
    let tasks: [GanttTaskSnapshot]

    init(project: ProjectModel, searchText: String, focusedTaskID: Int?, maxVisibleLevel: Int?) {
        self.searchText = searchText
        self.focusedTaskID = focusedTaskID
        self.maxVisibleLevel = maxVisibleLevel
        self.statusDate = project.properties.statusDate ?? ""
        self.tasks = project.tasks.map {
            GanttTaskSnapshot(
                id: $0.uniqueID,
                name: $0.name ?? "",
                start: $0.start ?? "",
                finish: $0.finish ?? "",
                barColorHex: $0.barColorHex,
                percentComplete: $0.percentComplete ?? 0,
                critical: $0.critical ?? false
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
    @Environment(\.undoManager) private var undoManager

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
    // Breathing room below the final row so the last bar isn't flush against
    // the bottom edge and can still be dragged/dropped past the last task.
    private let ganttTrailingSpace: CGFloat = 40
    @State private var focusedTaskID: Int? = nil
    @State private var maxVisibleLevel: Int? = nil
    @State private var criticalPathOnly: Bool = false
    @State private var showBaseline: Bool = false
    @State private var showDependencyLinks: Bool = true
    @State private var selectedTaskID: Int?
    @State private var multiSelectedTaskIDs: Set<Int> = []
    @FocusState private var isChartFocused: Bool
    @State private var detailPopoverTaskID: Int?
    @State private var detailPopoverAnchor: CGPoint = .zero
    @State private var detailPopoverVisibleRect: CGRect = .zero
    @State private var detailSheetTaskID: Int?
    @State private var pendingDependencySourceTaskID: Int?
    @State private var selectedDependency: GanttDependencySelection?
    @State private var interactionMode: GanttInteractionMode = .view
    @State private var inspectorTab: GanttInspectorTab = .task
    @State private var nativeTaskSnapshot: [NativePlanTask]
    @State private var nativeAssignmentSnapshot: [NativePlanAssignment]
    @State private var nativeResourceSnapshot: [NativePlanResource]
    @State private var nativeEventSnapshot: [PlanTimelineEvent]
    @State private var nativeLeaveSnapshot: [PlanResourceLeave]
    @AppStorage("gantt.showTimelineEvents") private var showTimelineEvents: Bool = false
    @AppStorage("gantt.showResourceLeave") private var showResourceLeave: Bool = false
    @AppStorage("gantt.leaveAsColumns") private var leaveAsColumns: Bool = false
    @State private var isEventLeaveEditorPresented = false
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    @GestureState private var magnifyBy: CGFloat = 1.0

    private let exportTaskListWidth: CGFloat = 280
    private let timelineTrailingLabelWidth: CGFloat = 420
    private let ganttConstraintOptions = ["None", "ASAP", "SNET", "FNET", "MSO", "MFO"]

    private var flatTasks: [ProjectTask] {
        derivedContent.flatTasks
    }

    private var derivedInput: GanttDerivedInput {
        GanttDerivedInput(project: project, searchText: searchText, focusedTaskID: focusedTaskID, maxVisibleLevel: maxVisibleLevel)
    }

    private var availableOutlineLevels: [Int] {
        let levels = Set(project.tasks.map { $0.outlineLevel ?? 1 })
        guard let maxLevel = levels.max(), maxLevel > 1 else { return [] }
        return Array(1...maxLevel)
    }

    private func levelMenuTitle(_ level: Int) -> String {
        switch level {
        case 1: return "Level 1 (phases)"
        default: return "Down to level \(level)"
        }
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
        nativeTaskSnapshot
    }

    private var nativeAssignments: [NativePlanAssignment] {
        nativeAssignmentSnapshot
    }

    private var nativeResources: [NativePlanResource] {
        nativeResourceSnapshot
    }

    /// Visual-only overlay inputs handed to the canvas. Rebuilds the
    /// resource→tasks map so leave bands land on the right rows.
    private var ganttOverlayData: GanttOverlayData {
        guard showTimelineEvents || showResourceLeave else { return .empty }
        var taskIDsByResourceID: [Int: Set<Int>] = [:]
        var resourceNamesByID: [Int: String] = [:]
        if showResourceLeave {
            for assignment in nativeAssignmentSnapshot {
                guard let resourceID = assignment.resourceID else { continue }
                taskIDsByResourceID[resourceID, default: []].insert(assignment.taskID)
            }
            for resource in nativeResourceSnapshot {
                resourceNamesByID[resource.id] = resource.name
            }
        }
        return GanttOverlayData(
            showEvents: showTimelineEvents,
            showLeave: showResourceLeave,
            leaveAsColumns: leaveAsColumns,
            events: showTimelineEvents ? nativeEventSnapshot : [],
            leaves: showResourceLeave ? nativeLeaveSnapshot : [],
            taskIDsByResourceID: taskIDsByResourceID,
            resourceNamesByID: resourceNamesByID
        )
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

    // Summary/phase rows that can be dragged vertically to reorder their whole
    // subtree, in edit mode only.
    private var reorderableSummaryIDs: Set<Int> {
        guard isEditingEnabled else { return [] }
        let nativeTaskIDs = Set(nativeTasks.map(\.id))
        return Set(derivedContent.taskIDs.filter { id in
            guard nativeTaskIDs.contains(id), let task = project.tasksByID[id] else { return false }
            return task.summary == true && !task.children.isEmpty
        })
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    private var chartContentWidth: CGFloat {
        timelineWidth + timelineTrailingLabelWidth
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
        self._derivedContent = State(initialValue: GanttDerivedContent.build(project: project, searchText: searchText, focusedTaskID: nil, maxVisibleLevel: nil))
        self._nativeTaskSnapshot = State(initialValue: planModel?.nativeTasksForUI ?? [])
        self._nativeAssignmentSnapshot = State(initialValue: planModel?.nativeAssignmentsForUI ?? [])
        self._nativeResourceSnapshot = State(initialValue: planModel?.nativeResourcesForUI ?? [])
        self._nativeEventSnapshot = State(initialValue: planModel?.nativeTimelineEventsForUI ?? [])
        self._nativeLeaveSnapshot = State(initialValue: planModel?.nativeResourceLeavesForUI ?? [])
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
                    .topAlignedEmptyState()
            } else {
                GeometryReader { geometry in
                    let viewportWidth = max(geometry.size.width, 1)
                    let taskListWidth = showsEditSidebar ? preferredTaskListWidth(for: viewportWidth) : 0

                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 0) {
                                ganttHeaderRow(taskListWidth: taskListWidth, showsTodayMarker: false)

                                ScrollView(.vertical) {
                                    ganttRowsContent(taskListWidth: taskListWidth)
                                        .frame(minHeight: max(0, geometry.size.height - ganttHeaderHeight), alignment: .topLeading)
                                }
                                .coordinateSpace(name: "GanttVerticalScrollViewport")
                                .frame(
                                    width: taskListWidth + chartContentWidth,
                                    height: max(0, geometry.size.height - ganttHeaderHeight),
                                    alignment: .topLeading
                                )
                            }

                            todayViewportMarker(taskListWidth: taskListWidth, height: geometry.size.height)
                        }
                        .frame(width: taskListWidth + chartContentWidth, height: geometry.size.height, alignment: .topLeading)
                    }
                    .coordinateSpace(name: "GanttHorizontalScrollViewport")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        timelineViewportWidth = viewportWidth
                        timelineViewportHeight = max(0, geometry.size.height - ganttHeaderHeight)
                        applyAutoFitIfNeeded()
                    }
                    .onChange(of: viewportWidth) { _, newWidth in
                        timelineViewportWidth = newWidth
                        timelineViewportHeight = max(0, geometry.size.height - ganttHeaderHeight)
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
            refreshNativeSnapshots()
            refreshDerivedContent()
            interactionMode = .view
            pendingDependencySourceTaskID = nil
            selectedDependency = nil
            if selectedTaskID == nil {
                selectedTaskID = flatTasks.first?.uniqueID
            }
        }
        .onChange(of: derivedInput) { oldValue, newValue in
            let onlySearchChanged = oldValue.tasks == newValue.tasks
                && oldValue.statusDate == newValue.statusDate
                && oldValue.focusedTaskID == newValue.focusedTaskID
                && oldValue.maxVisibleLevel == newValue.maxVisibleLevel
            if onlySearchChanged {
                // Search-only change: debounce so typing doesn't rebuild per keystroke.
                scheduleSearchDebouncedRefresh()
            } else {
                refreshDerivedContent()
            }
        }
        .onChange(of: planModel?.updatedAt) { _, _ in
            refreshNativeSnapshots()
            refreshDerivedContent()
        }
        .onChange(of: interactionMode) { _, mode in
            if mode == .view {
                pendingDependencySourceTaskID = nil
                selectedDependency = nil
                multiSelectedTaskIDs = []
            }
        }
        .focusable(true)
        .focusEffectDisabled()
        .focused($isChartFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: .down) { press in
            guard isEditingEnabled else { return .ignored }
            let magnitude = press.modifiers.contains(.shift) ? 7 : 1
            let delta = press.key == .leftArrow ? -magnitude : magnitude
            return nudgeSelectedTasks(dayDelta: delta) ? .handled : .ignored
        }
        .onChange(of: derivedContent.taskIDs) { _, ids in
            guard !ids.isEmpty else {
                selectedTaskID = nil
                multiSelectedTaskIDs = []
                pendingDependencySourceTaskID = nil
                selectedDependency = nil
                return
            }

            multiSelectedTaskIDs = multiSelectedTaskIDs.intersection(ids)

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
        .overlay {
            taskDetailModalOverlay
        }
        .sheet(isPresented: $isEventLeaveEditorPresented) {
            EventLeaveEditorView(
                events: nativeEventSnapshot,
                leaves: nativeLeaveSnapshot,
                resources: nativeResourceSnapshot,
                onSave: { events, leaves in
                    fullSyncGanttPlan { plan in
                        plan.timelineEvents = events
                        plan.resourceLeaves = leaves
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var taskDetailModalOverlay: some View {
        if let detailSheetTaskID,
           let task = project.tasksByID[detailSheetTaskID] {
            ZStack {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeTaskDetailModal()
                    }

                GanttTaskPopover(task: task) {
                    closeTaskDetailModal()
                }
                .transition(.scale(scale: 0.985).combined(with: .opacity))
            }
            .zIndex(200)
            .animation(.easeOut(duration: 0.12), value: detailSheetTaskID)
        }
    }

    private func closeTaskDetailModal() {
        withAnimation(.easeOut(duration: 0.1)) {
            detailSheetTaskID = nil
        }
    }

    private func persistGanttStoreChanges(refreshMetrics: Bool = true) {
        guard let planModel else { return }
        planModel.updatedAt = Date()
        if refreshMetrics {
            planModel.refreshPortfolioMetrics()
        }
        modelContext.saveReportingFailures()
        refreshNativeSnapshots()
    }

    private func refreshNativeSnapshots() {
        guard let planModel else {
            nativeTaskSnapshot = []
            nativeAssignmentSnapshot = []
            nativeResourceSnapshot = []
            nativeEventSnapshot = []
            nativeLeaveSnapshot = []
            return
        }

        nativeTaskSnapshot = planModel.nativeTasksForUI
        nativeAssignmentSnapshot = planModel.nativeAssignmentsForUI
        nativeResourceSnapshot = planModel.nativeResourcesForUI
        nativeEventSnapshot = planModel.nativeTimelineEventsForUI
        nativeLeaveSnapshot = planModel.nativeResourceLeavesForUI
    }

    private func registerGanttUndoSnapshot() {
        guard let planModel else { return }
        let snapshot = planModel.asNativePlan()
        undoManager?.registerUndo(withTarget: planModel) { _ in
            restoreGanttPlanSnapshot(snapshot)
        }
        undoManager?.setActionName("Gantt Edit")
    }

    private func restoreGanttPlanSnapshot(_ snapshot: NativeProjectPlan) {
        guard let planModel else { return }
        let current = planModel.asNativePlan()
        undoManager?.registerUndo(withTarget: planModel) { _ in
            restoreGanttPlanSnapshot(current)
        }
        undoManager?.setActionName("Gantt Edit")

        planModel.update(from: snapshot)
        planModel.updatedAt = Date()
        planModel.refreshPortfolioMetrics(from: snapshot)
        modelContext.saveReportingFailures()
        nativeTaskSnapshot = snapshot.tasks
        nativeAssignmentSnapshot = snapshot.assignments
        nativeResourceSnapshot = snapshot.resources
        nativeEventSnapshot = snapshot.timelineEvents
        nativeLeaveSnapshot = snapshot.resourceLeaves
        refreshDerivedContent()
    }

    private func withGanttTask(_ taskID: Int, refreshDerived: Bool = true, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel?.tasks.first(where: { $0.legacyID == taskID }) else { return }
        registerGanttUndoSnapshot()
        update(task)
        persistGanttStoreChanges()
        if refreshDerived {
            refreshDerivedContent()
        }
    }

    private func withGanttAssignment(_ assignmentID: Int, refreshDerived: Bool = true, _ update: (PortfolioPlanAssignment) -> Void) {
        guard let assignment = planModel?.tasks.flatMap(\.assignments).first(where: { $0.legacyID == assignmentID }) else { return }
        registerGanttUndoSnapshot()
        update(assignment)
        persistGanttStoreChanges()
        if refreshDerived {
            refreshDerivedContent()
        }
    }

    private func fullSyncGanttPlan(_ update: (inout NativeProjectPlan) -> Void) {
        guard let planModel else { return }
        var snapshot = planModel.asNativePlan()
        undoManager?.registerUndo(withTarget: planModel) { [previous = snapshot] _ in
            restoreGanttPlanSnapshot(previous)
        }
        undoManager?.setActionName("Gantt Edit")
        update(&snapshot)
        planModel.update(from: snapshot)
        planModel.updatedAt = Date()
        planModel.refreshPortfolioMetrics(from: snapshot)
        modelContext.saveReportingFailures()
        nativeTaskSnapshot = snapshot.tasks
        nativeAssignmentSnapshot = snapshot.assignments
        nativeResourceSnapshot = snapshot.resources
        nativeEventSnapshot = snapshot.timelineEvents
        nativeLeaveSnapshot = snapshot.resourceLeaves
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

                Menu {
                    Button {
                        exportToPDF()
                    } label: {
                        Label("Export PDF…", systemImage: "doc.richtext")
                    }
                    Button {
                        exportToSVG()
                    } label: {
                        Label("Export SVG (Vector)…", systemImage: "square.on.square.dashed")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Export the Gantt chart as a PDF or a scalable SVG for decks and design tools.")

                Button {
                    printGantt()
                } label: {
                    Label("Print", systemImage: "printer")
                        .font(.caption)
                }
                .buttonStyle(.accessoryBar)

                Divider().frame(height: 16)

                Toggle(isOn: $criticalPathOnly) {
                    Label("Critical Path", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .hoverHighlight()
                .buttonStyle(.bordered)
                .tint(criticalPathOnly ? .red : nil)
                .help("Highlights tasks marked critical by the imported schedule and dims non-critical tasks.")

                Toggle(isOn: $showDependencyLinks) {
                    Label("Links", systemImage: "link")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .hoverHighlight()
                .buttonStyle(.bordered)
                .tint(showDependencyLinks ? .blue : nil)
                .help("Shows predecessor and successor dependency links between tasks.")
                .onChange(of: showDependencyLinks) { _, isOn in
                    if !isOn {
                        selectedDependency = nil
                        pendingDependencySourceTaskID = nil
                    }
                }

                Toggle(isOn: $showBaseline) {
                    Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .hoverHighlight()
                .buttonStyle(.bordered)
                .tint(showBaseline ? .gray : nil)
                .help("Shows the saved baseline schedule as gray bars below the current bars, with start/finish variance badges.")

                Toggle(isOn: $showTimelineEvents) {
                    Label("Holidays", systemImage: "calendar")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .hoverHighlight()
                .buttonStyle(.bordered)
                .tint(showTimelineEvents ? .purple : nil)
                .help("Overlays holidays, observances (e.g. Ramadan) and events as timeline bands. Visual only — does not reschedule tasks.")

                Toggle(isOn: $showResourceLeave) {
                    Label("Leave", systemImage: "figure.walk.departure")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .hoverHighlight()
                .buttonStyle(.bordered)
                .tint(showResourceLeave ? .orange : nil)
                .help("Overlays each resource's leave on the rows for their assigned tasks, so you can spot conflicts. Visual only.")

                if showResourceLeave {
                    Menu {
                        Picker("Leave display", selection: $leaveAsColumns) {
                            Text("Bars on resource rows").tag(false)
                            Text("Full-height columns").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Image(systemName: leaveAsColumns ? "rectangle.split.3x1" : "rectangle.grid.1x2")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Choose how leave is drawn: as bars on each resource's rows, or as full-height columns like events.")
                }

                if isNativeEditablePlan {
                    Button {
                        isEventLeaveEditorPresented = true
                    } label: {
                        Label("Events…", systemImage: "calendar.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.accessoryBar)
                    .help("Add or edit holidays, observances, events and resource leave.")
                }

                Menu {
                    Button {
                        maxVisibleLevel = nil
                    } label: {
                        Label("All Levels", systemImage: maxVisibleLevel == nil ? "checkmark" : "")
                    }
                    ForEach(availableOutlineLevels, id: \.self) { level in
                        Button {
                            maxVisibleLevel = level
                        } label: {
                            Label(levelMenuTitle(level), systemImage: maxVisibleLevel == level ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(maxVisibleLevel == nil ? "Levels" : "Levels \u{2264} \(maxVisibleLevel!)", systemImage: "list.bullet.indent")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Show only tasks down to a chosen outline level (e.g. phases only, or down to tasks).")

                if let focusedTaskID, let focusName = project.tasksByID[focusedTaskID]?.displayName {
                    Button {
                        self.focusedTaskID = nil
                    } label: {
                        Label("Focusing: \(focusName)", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .help("Exit focus and show the whole plan again.")
                }

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
                HStack(spacing: 8) {
                    Button {
                        addTaskFromGantt()
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!isEditingEnabled)
                    .help("Insert a new task after the selected task or at the end of the plan.")

                    Button {
                        addSubtaskFromGantt()
                    } label: {
                        Label("Add Subtask", systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!isEditingEnabled || selectedTaskID == nil)
                    .help("Insert a child task under the selected task.")

                    Divider().frame(height: 16)

                    Button {
                        indentSelectedTask()
                    } label: {
                        Label("Indent", systemImage: "arrow.right.to.line")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!canIndentSelectedTask)
                    .help("Make the selected task a child of the row above.")

                    Button {
                        outdentSelectedTask()
                    } label: {
                        Label("Outdent", systemImage: "arrow.left.to.line")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!canOutdentSelectedTask)
                    .help("Promote the selected task up one outline level.")

                    Divider().frame(height: 16)

                    Button {
                        linkSelectedTaskToNext()
                    } label: {
                        Label("Link Next", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
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
                    .hoverHighlight()
                    .disabled(!isEditingEnabled || selectedTaskID == nil)
                    .help("Start dependency linking for the selected task, then click the target row or bar.")

                    Button(role: .destructive) {
                        removeSelectedDependency()
                    } label: {
                        Label("Remove Link", systemImage: "link.badge.minus")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!canRemoveSelectedDependency)
                    .help("Remove the selected dependency arrow from the plan.")

                    Divider().frame(height: 16)

                    Button(role: .destructive) {
                        deleteSelectedTask()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
                    .disabled(!canDeleteSelectedTask)
                    .help("Delete the selected task and its child tasks from the plan.")

                    Spacer()

                    Text(editStatusText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
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
            .hoverHighlight()
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
                        CalendarDatePicker(date: selectedTaskStartBinding(), isCompact: true)
                    }
                    .frame(width: 118)

                    VStack(alignment: .leading, spacing: 4) {
                        compactInspectorLabel("Finish")
                        CalendarDatePicker(date: selectedTaskFinishBinding(), isCompact: true)
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
                                CalendarDatePicker(date: selectedTaskConstraintDateBinding(), isCompact: true)
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
                            .hoverHighlight()
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
                            .hoverHighlight()
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
                                        .hoverHighlight()
                                        .help("Add a primary assignment using the first available resource.")
                                    } else {
                                        Button(role: .destructive) {
                                            clearPrimaryAssignmentFromSelectedTask()
                                        } label: {
                                            Label("Clear", systemImage: "xmark")
                                        }
                                        .buttonStyle(.bordered)
                                        .hoverHighlight()
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
                                CalendarDatePicker(date: selectedTaskActualStartBinding(), isCompact: true)
                                    .frame(width: 118)
                                Button("Clear", role: .destructive) {
                                    clearSelectedTaskActualStart()
                                }
                                .buttonStyle(.accessoryBar)
                            }

                            HStack(spacing: 8) {
                                CalendarDatePicker(date: selectedTaskActualFinishBinding(), isCompact: true)
                                    .frame(width: 118)
                                Button("Clear", role: .destructive) {
                                    clearSelectedTaskActualFinish()
                                }
                                .buttonStyle(.accessoryBar)
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
        // The task-list column is only drawn in edit mode; when it isn't, the
        // header/bars start at x=0, so the events lane must use the same width
        // (0) or its title chips shift right by the list width.
        let listWidth = showsEditSidebar ? exportTaskListWidth : 0
        let contentView = ganttContent(taskListWidth: listWidth)
        let contentSize = CGSize(
            width: listWidth + chartContentWidth,
            height: CGFloat(flatTasks.count) * rowHeight + ganttHeaderHeight
        )
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PDFExporter.exportGanttToPDF(
            view: contentView,
            contentSize: contentSize,
            fileName: "\(title) - Gantt \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    private func exportToSVG() {
        let rows: [SVGExporter.GanttRow] = flatTasks.map { task in
            let subtitle: String?
            if let start = task.startDate, let finish = task.finishDate {
                subtitle = "\(DateFormatting.shortDate(start)) – \(DateFormatting.shortDate(finish))"
            } else {
                subtitle = nil
            }
            return SVGExporter.GanttRow(
                name: task.displayName,
                outlineLevel: task.outlineLevel ?? 1,
                start: task.startDate,
                finish: task.finishDate,
                isMilestone: task.milestone == true,
                isSummary: task.summary == true,
                isCritical: task.critical == true,
                percentComplete: task.percentComplete ?? 0,
                colorHex: task.barColorHex,
                subtitle: subtitle
            )
        }
        let title = project.properties.projectTitle ?? "Gantt Chart"
        SVGExporter.exportGantt(
            rows: rows,
            rangeStart: dateRange.start,
            rangeEnd: dateRange.end,
            pixelsPerDay: max(2, pixelsPerDay),
            rowHeight: max(28, rowHeight),
            title: title,
            fileName: "\(title) - Gantt \(PDFExporter.fileNameTimestamp).svg",
            bands: svgOverlayBands
        )
    }

    /// Overlay bands (holidays/events + shown leave) for the SVG export, matching
    /// what's currently toggled on the chart.
    private var svgOverlayBands: [SVGExporter.Band] {
        var bands: [SVGExporter.Band] = []
        if showTimelineEvents {
            for event in nativeEventSnapshot {
                bands.append(SVGExporter.Band(
                    name: event.name,
                    start: event.startDate,
                    finish: event.endDate,
                    colorHex: event.effectiveColorHex
                ))
            }
        }
        if showResourceLeave {
            let names = overlayResourceNamesByID
            for leave in nativeLeaveSnapshot {
                let resourceName = names[leave.resourceID] ?? "Resource"
                let reason = leave.name.trimmingCharacters(in: .whitespaces)
                let hasReason = !reason.isEmpty && reason.caseInsensitiveCompare("Leave") != .orderedSame
                bands.append(SVGExporter.Band(
                    name: hasReason ? "\(resourceName) · \(reason)" : resourceName,
                    start: leave.startDate,
                    finish: leave.endDate,
                    colorHex: leave.effectiveColorHex
                ))
            }
        }
        return bands
    }

    private func printGantt() {
        let listWidth = showsEditSidebar ? exportTaskListWidth : 0
        let contentView = ganttContent(taskListWidth: listWidth)
        let contentSize = CGSize(
            width: listWidth + chartContentWidth,
            height: CGFloat(flatTasks.count) * rowHeight + ganttHeaderHeight
        )
        let title = project.properties.projectTitle ?? "Gantt Chart"
        PrintManager.printView(contentView, size: contentSize, title: title)
    }

    private var ganttHeaderHeight: CGFloat {
        (pixelsPerDay < 15 ? 64 : 44) + eventsLaneHeight
    }

    private struct GanttLaneChip: Identifiable {
        let id: UUID
        let text: String
        let color: Color
        let tooltip: String
        let x: CGFloat
        let laneRow: Int
    }

    private var eventsLaneChipRowHeight: CGFloat { 18 }

    /// Event/leave-column title chips, greedily packed into stacked rows so that
    /// chips whose date ranges are near each other flow onto separate rows
    /// instead of overlapping. Recomputed with zoom (band x depends on it).
    private var eventsLaneChips: [GanttLaneChip] {
        var raw: [(id: UUID, text: String, color: Color, tooltip: String, x: CGFloat)] = []

        if showTimelineEvents {
            for event in nativeEventSnapshot {
                guard let band = headerBandGeometry(from: event.startDate, to: event.endDate) else { continue }
                let range = "\(DateFormatting.shortDate(event.startDate)) – \(DateFormatting.shortDate(event.endDate))"
                raw.append((event.id, "\(event.name)  ·  \(range)", Color(hex: event.effectiveColorHex) ?? .red,
                            "\(event.name) · \(event.kind.label)\n\(range)", band.x))
            }
        }
        if showResourceLeave, leaveAsColumns {
            for leave in nativeLeaveSnapshot {
                guard let band = headerBandGeometry(from: leave.startDate, to: leave.endDate) else { continue }
                let resourceName = overlayResourceNamesByID[leave.resourceID] ?? "Resource"
                let reason = leave.name.trimmingCharacters(in: .whitespaces)
                let hasReason = !reason.isEmpty && reason.caseInsensitiveCompare("Leave") != .orderedSame
                let label = hasReason ? "\(resourceName) · \(reason)" : resourceName
                let range = "\(DateFormatting.shortDate(leave.startDate)) – \(DateFormatting.shortDate(leave.endDate))"
                raw.append((leave.id, "\(label)  ·  \(range)", Color(hex: leave.effectiveColorHex) ?? .orange,
                            "\(resourceName) — \(hasReason ? reason : "Leave")\n\(range)", band.x))
            }
        }

        var laneEnds: [CGFloat] = []
        var result: [GanttLaneChip] = []
        for item in raw.sorted(by: { $0.x < $1.x }) {
            let width = CGFloat(item.text.count) * 6.0 + 14
            var row = laneEnds.firstIndex(where: { item.x >= $0 }) ?? -1
            if row == -1 { row = laneEnds.count; laneEnds.append(0) }
            laneEnds[row] = item.x + width + 6
            result.append(GanttLaneChip(id: item.id, text: item.text, color: item.color, tooltip: item.tooltip, x: item.x, laneRow: row))
        }
        return result
    }

    /// Height reserved beneath the month header for the (possibly multi-row)
    /// event/leave title lane, so titles never overlap each other or the rows.
    private var eventsLaneHeight: CGFloat {
        let rows = (eventsLaneChips.map(\.laneRow).max() ?? -1) + 1
        return rows > 0 ? CGFloat(rows) * eventsLaneChipRowHeight + 4 : 0
    }

    /// Inclusive [from...to] span → x/width in timeline coordinates (relative to
    /// the chart's left edge), clipped to the visible range. Used for the lane.
    private func headerBandGeometry(from: Date, to: Date) -> (x: CGFloat, width: CGFloat)? {
        guard totalDays > 0 else { return nil }
        let cal = Calendar.current
        let origin = cal.startOfDay(for: dateRange.start)
        let s = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: from)).day ?? 0
        let e = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: to)).day ?? 0
        let lo = max(0, min(s, e))
        let hi = min(totalDays - 1, max(s, e))
        guard hi >= lo else { return nil }
        return (CGFloat(lo) * pixelsPerDay, CGFloat(hi - lo + 1) * pixelsPerDay)
    }

    private var overlayResourceNamesByID: [Int: String] {
        Dictionary(nativeResourceSnapshot.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func ganttEventsLane(taskListWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .controlBackgroundColor)

            ForEach(eventsLaneChips) { chip in
                Text(chip.text)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(chip.color.opacity(0.92), in: Capsule())
                    .fixedSize()
                    .contentShape(Capsule())
                    .help(chip.tooltip)
                    .offset(x: taskListWidth + chip.x + 2, y: CGFloat(chip.laneRow) * eventsLaneChipRowHeight + 2)
            }
        }
        .frame(width: taskListWidth + chartContentWidth, height: eventsLaneHeight, alignment: .topLeading)
        .overlay(alignment: .bottom) { Divider() }
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
            ganttHeaderRow(taskListWidth: taskListWidth)

            ganttRowsContent(taskListWidth: taskListWidth)
        }
    }

    private func ganttHeaderRow(taskListWidth: CGFloat, showsTodayMarker: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if showsEditSidebar {
                    taskListHeader(width: taskListWidth)
                }
                GanttHeaderView(
                    dateRange: dateRange,
                    pixelsPerDay: pixelsPerDay,
                    totalWidth: chartContentWidth,
                    showsTodayMarker: showsTodayMarker
                )
            }
            if eventsLaneHeight > 0 {
                ganttEventsLane(taskListWidth: taskListWidth)
            }
        }
    }

    private func todayViewportMarker(taskListWidth: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard let todayOffset = GanttDateHelpers.todayDayOffset(from: dateRange.start) else { return }
            let todayX = taskListWidth + todayOffset * pixelsPerDay
            guard todayX >= taskListWidth, todayX <= taskListWidth + chartContentWidth else { return }

            var line = Path()
            line.move(to: CGPoint(x: todayX, y: 0))
            line.addLine(to: CGPoint(x: todayX, y: size.height))
            context.stroke(
                line,
                with: .color(.red.opacity(0.75)),
                style: StrokeStyle(lineWidth: 1.4, dash: [4, 3])
            )

            let triSize: CGFloat = 7
            let tipY = min(size.height - 2, ganttHeaderHeight + 12)
            var triangle = Path()
            triangle.move(to: CGPoint(x: todayX, y: tipY))
            triangle.addLine(to: CGPoint(x: todayX - triSize, y: tipY - triSize))
            triangle.addLine(to: CGPoint(x: todayX + triSize, y: tipY - triSize))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(.red))
        }
        .frame(width: taskListWidth + chartContentWidth, height: height)
        .allowsHitTesting(false)
    }

    private func ganttTaskDetailOverlay(taskListWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if let detailPopoverTaskID,
               let task = project.tasksByID[detailPopoverTaskID] {
                let origin = detailPopoverOrigin(taskListWidth: taskListWidth, width: 300, height: 190)
                GanttTaskPopover(task: task) {
                    self.detailPopoverTaskID = nil
                }
                .offset(x: origin.x, y: origin.y)
                .zIndex(100)
            }
        }
        .frame(width: taskListWidth + chartContentWidth, height: max(ganttHeaderHeight, timelineViewportHeight + ganttHeaderHeight), alignment: .topLeading)
        .allowsHitTesting(true)
    }

    private func detailPopoverOrigin(taskListWidth: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        let padding: CGFloat = 10
        let visibleRect = popoverVisibleRect
        let bounds = CGRect(
            x: taskListWidth + visibleRect.minX,
            y: ganttHeaderHeight,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let anchor = CGPoint(
            x: taskListWidth + detailPopoverAnchor.x,
            y: ganttHeaderHeight + detailPopoverAnchor.y - visibleRect.minY
        )

        var x = anchor.x + 12
        if x + width + padding > bounds.maxX {
            x = anchor.x - width - 12
        }

        var y = anchor.y + 12
        if y + height + padding > bounds.maxY {
            y = anchor.y - height - 12
        }

        return CGPoint(
            x: min(max(bounds.minX + padding, x), max(bounds.minX + padding, bounds.maxX - width - padding)),
            y: min(max(bounds.minY + padding, y), max(bounds.minY + padding, bounds.maxY - height - padding))
        )
    }

    private var popoverVisibleRect: CGRect {
        if detailPopoverVisibleRect.width > 0, detailPopoverVisibleRect.height > 0 {
            return detailPopoverVisibleRect
        }
        if timelineVisibleRect.width > 0, timelineVisibleRect.height > 0 {
            return timelineVisibleRect
        }
        return CGRect(
            x: 0,
            y: 0,
            width: max(timelineViewportWidth, chartContentWidth),
            height: max(timelineViewportHeight, rowHeight)
        )
    }

    private func ganttRowsContent(taskListWidth: CGFloat) -> some View {
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
                showDependencyLinks: showDependencyLinks,
                editableTaskIDs: editableTaskIDs,
                isEditModeActive: isEditingEnabled,
                selectedTaskID: selectedTaskID,
                selectedTaskIDs: effectiveSelectedTaskIDs,
                selectedDependency: selectedDependency,
                pendingLinkSourceTaskID: pendingDependencySourceTaskID,
                onMoveTask: planModel == nil ? nil : moveNativeTask,
                onReorderTask: planModel == nil ? nil : reorderNativeTask,
                onResizeTask: planModel == nil ? nil : resizeNativeTask,
                onSelectTask: handleTaskSelection,
                onShowTaskDetails: { taskID, anchor, visibleRect in
                    withAnimation(.easeOut(duration: 0.12)) {
                        detailSheetTaskID = taskID
                    }
                    detailPopoverTaskID = taskID
                    detailPopoverAnchor = anchor
                    detailPopoverVisibleRect = visibleRect
                },
                onStartLinkingFromTask: startLinkingFromTask,
                onSetTaskColor: planModel == nil ? nil : { taskID, hex in setTaskBarColor(taskID: taskID, hex: hex) },
                focusedTaskID: focusedTaskID,
                onToggleFocus: { taskID in
                    focusedTaskID = (focusedTaskID == taskID) ? nil : taskID
                },
                reorderableSummaryIDs: reorderableSummaryIDs,
                onSelectDependency: { predecessorID, successorID in
                    selectedDependency = GanttDependencySelection(
                        predecessorID: predecessorID,
                        successorID: successorID
                    )
                    selectedTaskID = successorID
                },
                onRemoveDependency: { predecessorID, successorID in
                    removeDependency(predecessorID: predecessorID, successorID: successorID)
                },
                overlays: ganttOverlayData
            )
            .frame(width: chartContentWidth, height: CGFloat(flatTasks.count) * rowHeight + ganttTrailingSpace, alignment: .top)
            .background(
                GeometryReader { proxy in
                    let horizontalFrame = proxy.frame(in: .named("GanttHorizontalScrollViewport"))
                    let verticalFrame = proxy.frame(in: .named("GanttVerticalScrollViewport"))
                    Color.clear.preference(
                        key: GanttTimelineViewportPreferenceKey.self,
                        value: CGRect(
                            x: max(0, -horizontalFrame.minX),
                            y: max(0, -verticalFrame.minY),
                            width: max(0, timelineViewportWidth - max(0, horizontalFrame.minX)),
                            height: timelineViewportHeight
                        )
                    )
                }
            )
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

            // Keep the task list the same height as the timeline canvas so the
            // two panes scroll in lockstep, including the trailing space.
            Color.clear.frame(height: ganttTrailingSpace)
        }
        .frame(width: width, alignment: .topLeading)
        .background(taskListBackgroundColor)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func taskListRow(_ task: ProjectTask, width: CGFloat) -> some View {
        let isSelected = selectedTaskID == task.uniqueID || effectiveSelectedTaskIDs.contains(task.uniqueID)
        let isPendingSource = pendingDependencySourceTaskID == task.uniqueID
        let isLinkTarget = pendingDependencySourceTaskID != nil && !isPendingSource
        let rowIndent = CGFloat(max(0, (task.outlineLevel ?? 1) - 1)) * 16

        return HStack(spacing: 8) {
            rowIcon(for: task)

            Text(task.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                // Scope the row tooltip to the label so it doesn't cover the
                // trailing action buttons, which have their own tooltips.
                .help(taskRowTooltip(for: task))

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
        // Put the row's tap target BEHIND the content so the inline action
        // buttons stay independent hover targets — otherwise a row-wide
        // contentShape swallows each button's own tooltip.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTaskSelection(task.uniqueID) }
        )
        .contextMenu {
            // Batch actions when several tasks are multi-selected.
            let selection = effectiveSelectedTaskIDs
            if selection.count > 1, selection.contains(task.uniqueID) {
                Section("\(selection.count) Selected Tasks") {
                    Button {
                        setPercentCompleteForSelection(100)
                    } label: {
                        Label("Mark Complete", systemImage: "checkmark.circle")
                    }
                    Button {
                        setPercentCompleteForSelection(0)
                    } label: {
                        Label("Mark Not Started", systemImage: "circle")
                    }

                    if !assignableResources.isEmpty {
                        Menu {
                            ForEach(assignableResources, id: \.id) { resource in
                                Button(resource.name.isEmpty ? "Resource \(resource.id)" : resource.name) {
                                    assignResourceToSelection(resourceID: resource.id)
                                }
                            }
                        } label: {
                            Label("Assign Resource", systemImage: "person.badge.plus")
                        }

                        let assignedIDs = assignedResourceIDs(in: selection)
                        if !assignedIDs.isEmpty {
                            Menu {
                                ForEach(assignableResources.filter { assignedIDs.contains($0.id) }, id: \.id) { resource in
                                    Button(resource.name.isEmpty ? "Resource \(resource.id)" : resource.name) {
                                        unassignResourceFromSelection(resourceID: resource.id)
                                    }
                                }
                            } label: {
                                Label("Unassign Resource", systemImage: "person.badge.minus")
                            }
                        }
                    }
                }
                Divider()
            }

            if task.summary == true && !task.children.isEmpty {
                if focusedTaskID == task.uniqueID {
                    Button {
                        focusedTaskID = nil
                    } label: {
                        Label("Exit Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                } else {
                    Button {
                        selectedTaskID = task.uniqueID
                        focusedTaskID = task.uniqueID
                    } label: {
                        Label("Focus on This Phase", systemImage: "scope")
                    }
                }
                Divider()
            }

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

            Menu {
                ForEach(Self.barColorPresets, id: \.hex) { preset in
                    Button {
                        setTaskBarColor(taskID: task.uniqueID, hex: preset.hex)
                    } label: {
                        Label(preset.name, systemImage: task.barColorHex == preset.hex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
                Divider()
                Button {
                    setTaskBarColor(taskID: task.uniqueID, hex: nil)
                } label: {
                    Label("Default Color", systemImage: "arrow.uturn.backward")
                }
                .disabled(task.barColorHex == nil)
            } label: {
                Label("Bar Color", systemImage: "paintpalette")
            }
            .disabled(!isEditingEnabled)

            Divider()

            Button(role: .destructive) {
                deleteTask(taskID: task.uniqueID)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
            .disabled(!isEditingEnabled)
        }
    }

    // A small, high-contrast palette so bars can be grouped by phase, team,
    // or status at a glance.
    static let barColorPresets: [(name: String, hex: String)] = [
        ("Blue", "#2F6FEB"),
        ("Green", "#2FA84F"),
        ("Orange", "#F5871F"),
        ("Red", "#E5484D"),
        ("Purple", "#8E4EC6"),
        ("Teal", "#12A5A5"),
        ("Pink", "#E93D82"),
        ("Gray", "#8A8F98")
    ]

    private func setTaskBarColor(taskID: Int, hex: String?) {
        guard planModel != nil else { return }
        // If the task is part of a multi-selection, recolor the whole set in
        // one mutation (a single undo step).
        let selection = effectiveSelectedTaskIDs
        let targets: Set<Int> = (selection.count > 1 && selection.contains(taskID)) ? selection : [taskID]
        fullSyncGanttPlan { workingPlan in
            for index in workingPlan.tasks.indices where targets.contains(workingPlan.tasks[index].id) {
                workingPlan.tasks[index].barColorHex = hex
            }
        }
        selectedTaskID = taskID
    }

    private func setPercentCompleteForSelection(_ percent: Double) {
        guard planModel != nil else { return }
        let targets = effectiveSelectedTaskIDs.intersection(editableTaskIDs)
        guard !targets.isEmpty else { return }
        fullSyncGanttPlan { workingPlan in
            for index in workingPlan.tasks.indices where targets.contains(workingPlan.tasks[index].id) {
                workingPlan.tasks[index].percentComplete = percent
            }
            workingPlan.reschedule()
        }
    }

    // Work resources available to assign (excludes material/cost resources).
    private var assignableResources: [NativePlanResource] {
        nativeResources.filter { $0.type.lowercased() == "work" || $0.type.isEmpty }
    }

    // Resources currently assigned to any task in the selection (for unassign).
    private func assignedResourceIDs(in taskIDs: Set<Int>) -> Set<Int> {
        Set(nativeAssignments.compactMap { assignment in
            taskIDs.contains(assignment.taskID) ? assignment.resourceID : nil
        })
    }

    private func assignResourceToSelection(resourceID: Int) {
        guard planModel != nil else { return }
        let targets = effectiveSelectedTaskIDs.intersection(editableTaskIDs)
        guard !targets.isEmpty else { return }
        fullSyncGanttPlan { workingPlan in
            for taskID in targets {
                let alreadyAssigned = workingPlan.assignments.contains {
                    $0.taskID == taskID && $0.resourceID == resourceID
                }
                if !alreadyAssigned {
                    workingPlan.assignments.append(workingPlan.makeAssignment(taskID: taskID, resourceID: resourceID))
                }
            }
            workingPlan.reschedule()
        }
    }

    private func unassignResourceFromSelection(resourceID: Int) {
        guard planModel != nil else { return }
        let targets = effectiveSelectedTaskIDs.intersection(editableTaskIDs)
        guard !targets.isEmpty else { return }
        fullSyncGanttPlan { workingPlan in
            workingPlan.assignments.removeAll {
                targets.contains($0.taskID) && $0.resourceID == resourceID
            }
            workingPlan.reschedule()
        }
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
        .buttonStyle(.accessoryBar)
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

            // Command-click builds a multi-selection in edit mode so several
            // bars can be nudged together with the arrow keys or one drag.
            if isEditingEnabled, NSEvent.modifierFlags.contains(.command) {
                var selection = effectiveSelectedTaskIDs
                if selection.contains(taskID) {
                    selection.remove(taskID)
                } else {
                    selection.insert(taskID)
                }
                multiSelectedTaskIDs = selection
                selectedTaskID = selection.contains(taskID) ? taskID : selection.first
            } else {
                multiSelectedTaskIDs = [taskID]
                selectedTaskID = taskID
            }
            isChartFocused = true
        }
    }

    private var effectiveSelectedTaskIDs: Set<Int> {
        if !multiSelectedTaskIDs.isEmpty {
            return multiSelectedTaskIDs
        }
        if let selectedTaskID {
            return [selectedTaskID]
        }
        return []
    }

    private func nudgeSelectedTasks(dayDelta: Int) -> Bool {
        guard isEditingEnabled else { return false }
        let movable = effectiveSelectedTaskIDs.intersection(editableTaskIDs)
        guard !movable.isEmpty else { return false }
        moveNativeTasks(movable, dayDelta: dayDelta)
        return true
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
            derivedContent = GanttDerivedContent.build(project: project, searchText: searchText, focusedTaskID: focusedTaskID, maxVisibleLevel: maxVisibleLevel)
        }
    }

    private func scheduleSearchDebouncedRefresh() {
        searchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshDerivedContent()
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
            // Demote by a single level, capped at one below the row above, so a
            // single indent is a single step (peer, not grandchild).
            let currentLevel = workingPlan.tasks[selectedIndex].outlineLevel
            let previousLevel = workingPlan.tasks[selectedIndex - 1].outlineLevel
            let newLevel = min(currentLevel + 1, previousLevel + 1)
            adjustSubtreeOutlineLevel(taskID: taskID, by: newLevel - currentLevel, in: &workingPlan)
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
        // Dragging one bar of a multi-selection moves the whole selection.
        let selection = effectiveSelectedTaskIDs
        if selection.count > 1, selection.contains(taskID) {
            moveNativeTasks(selection.intersection(editableTaskIDs), dayDelta: dayDelta)
            selectedTaskID = taskID
            return
        }
        moveNativeTasks([taskID], dayDelta: dayDelta)
        selectedTaskID = taskID
    }

    private func reorderNativeTask(_ taskID: Int, rowDelta: Int) {
        guard rowDelta != 0, planModel != nil else { return }
        guard let currentIndex = flatTasks.firstIndex(where: { $0.uniqueID == taskID }) else { return }
        let targetIndex = max(0, min(flatTasks.count - 1, currentIndex + rowDelta))
        guard targetIndex != currentIndex else { return }
        let anchorTaskID = flatTasks[targetIndex].uniqueID
        guard anchorTaskID != taskID else { return }

        PerformanceMonitor.measure("Gantt.ReorderTask") {
            fullSyncGanttPlan { workingPlan in
                let moved = workingPlan.relocateTaskSubtree(
                    taskID: taskID,
                    anchorTaskID: anchorTaskID,
                    placeAfterAnchor: rowDelta > 0
                )
                guard moved else { return }
                workingPlan.reschedule()
            }
        }
        selectedTaskID = taskID
    }

    private func moveNativeTasks(_ taskIDs: Set<Int>, dayDelta: Int) {
        guard dayDelta != 0, !taskIDs.isEmpty, planModel != nil else { return }

        PerformanceMonitor.measure("Gantt.MoveTask") {
            fullSyncGanttPlan { workingPlan in
                let calendar = Calendar.current
                for taskIndex in workingPlan.tasks.indices where taskIDs.contains(workingPlan.tasks[taskIndex].id) {
                    var task = workingPlan.tasks[taskIndex]
                    task.startDate = calendar.date(byAdding: .day, value: dayDelta, to: task.startDate) ?? task.startDate
                    task.finishDate = calendar.date(byAdding: .day, value: dayDelta, to: task.finishDate) ?? task.finishDate
                    task.startDate = calendar.startOfDay(for: task.startDate)
                    task.finishDate = task.isMilestone ? task.startDate : calendar.startOfDay(for: task.finishDate)
                    task.manuallyScheduled = true
                    workingPlan.tasks[taskIndex] = task
                }
                workingPlan.reschedule()
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
        let calendar = Calendar.current
        let allDates = tasks.compactMap { $0.startDate } + tasks.compactMap { $0.finishDate }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            let now = calendar.startOfDay(for: Date())
            return (now, calendar.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(86400 * 30))
        }
        let normalizedStart = calendar.startOfDay(for: minDate)
        let normalizedEnd = calendar.startOfDay(for: maxDate)
        let paddedStart = calendar.date(byAdding: .day, value: -3, to: normalizedStart) ?? normalizedStart
        let paddedEnd = calendar.date(byAdding: .day, value: 7, to: normalizedEnd) ?? normalizedEnd
        return (paddedStart, paddedEnd)
    }

    static func totalDays(for dateRange: (start: Date, end: Date)) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: dateRange.start)
        let end = calendar.startOfDay(for: dateRange.end)
        return max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 30)
    }

    static func todayDayOffset(from startDate: Date) -> CGFloat? {
        dayOffset(from: Date(), startDate: startDate)
    }

    static func dayOffset(from date: Date, startDate: Date, calendar: Calendar = .current) -> CGFloat {
        let target = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        return CGFloat(days)
    }
}

// MARK: - Legend Bar

struct GanttLegendBar: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(color: .blue, label: "Normal")
            legendItem(color: .red, label: "Critical", help: "Critical tasks are tasks the source schedule marks as driving the project finish.")
            summaryLegendItem()
            milestoneLegendItem()
            progressLegendItem()
            dependencyLegendItem()
            baselineLegendItem()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func legendItem(color: Color, label: String, help: String? = nil) -> some View {
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
        .help(help ?? label)
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

    private func dependencyLegendItem() -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .trailing) {
                Rectangle()
                    .fill(Color.gray.opacity(0.55))
                    .frame(width: 18, height: 1)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.gray)
                    .offset(x: 2)
            }
            Text("Links").font(.caption2).foregroundStyle(.secondary)
        }
        .help("Task dependency links between predecessors and successors.")
    }

    private func baselineLegendItem() -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.35))
                    .frame(width: 18, height: 5)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.65))
                    .frame(width: 18, height: 3)
            }
            Text("Baseline").font(.caption2).foregroundStyle(.secondary)
        }
        .help("Gray bars show saved baseline dates below current task bars.")
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
            .buttonStyle(.accessoryBar)
            .font(.caption)

            Button("Week", action: onShowWeek)
            .buttonStyle(.accessoryBar)
            .font(.caption)

            Button("Month", action: onShowMonth)
            .buttonStyle(.accessoryBar)
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
        .buttonStyle(.accessoryBar)
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
        let baselineBarHeight: CGFloat = 4

        let taskGeometryByID = Dictionary(nonThrowingUniquePairs: tasks.enumerated().map { index, task in
            let rowRect = CGRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: timelineContentWidth,
                height: rowHeight
            )

            let startX = task.startDate.map { date -> CGFloat in
                GanttDateHelpers.dayOffset(from: date, startDate: startDate, calendar: calendar) * pixelsPerDay
            }

            let width: CGFloat? = {
                guard let taskStart = task.startDate, let taskFinish = task.finishDate else { return nil }
                let startDays = GanttDateHelpers.dayOffset(from: taskStart, startDate: startDate, calendar: calendar)
                let finishDays = GanttDateHelpers.dayOffset(from: taskFinish, startDate: startDate, calendar: calendar)
                return max(4, max(1, finishDays - startDays) * pixelsPerDay)
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
                GanttDateHelpers.dayOffset(from: date, startDate: startDate, calendar: calendar) * pixelsPerDay
            }

            let baselineFinishX = task.baselineFinishDate.map { date -> CGFloat in
                GanttDateHelpers.dayOffset(from: date, startDate: startDate, calendar: calendar) * pixelsPerDay
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
                    y: rowRect.maxY - baselineBarHeight - 2,
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
        return GanttDateHelpers.dayOffset(from: date, startDate: startDate, calendar: calendar) * pixelsPerDay
    }
}

/// Visual-only overlay inputs for the Gantt canvas: holiday/observance/event
/// bands (global) and per-resource leave bands. Never affects scheduling.
struct GanttOverlayData: Equatable {
    var showEvents: Bool = false
    var showLeave: Bool = false
    /// When true, leave draws as full-height columns (like events); otherwise as
    /// per-row bars on the resource's assigned tasks.
    var leaveAsColumns: Bool = false
    var events: [PlanTimelineEvent] = []
    var leaves: [PlanResourceLeave] = []
    /// resourceID -> uniqueIDs of tasks assigned to that resource. Used to draw
    /// leave bands only on the rows where that person is actually working.
    var taskIDsByResourceID: [Int: Set<Int>] = [:]
    /// resourceID -> display name, for leave labels/tooltips.
    var resourceNamesByID: [Int: String] = [:]

    static let empty = GanttOverlayData()

    var hasAnythingToDraw: Bool {
        (showEvents && !events.isEmpty) || (showLeave && !leaves.isEmpty)
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
    var showDependencyLinks: Bool = true
    var editableTaskIDs: Set<Int> = []
    var isEditModeActive: Bool = false
    var selectedTaskID: Int? = nil
    var selectedTaskIDs: Set<Int> = []
    var selectedDependency: GanttDependencySelection? = nil
    var pendingLinkSourceTaskID: Int? = nil
    var onMoveTask: ((Int, Int) -> Void)? = nil
    var onReorderTask: ((Int, Int) -> Void)? = nil
    var onResizeTask: ((Int, GanttResizeEdge, Int) -> Void)? = nil
    var onSelectTask: ((Int) -> Void)? = nil
    var onShowTaskDetails: ((Int, CGPoint, CGRect) -> Void)? = nil
    var onStartLinkingFromTask: ((Int) -> Void)? = nil
    var onSetTaskColor: ((Int, String?) -> Void)? = nil
    var focusedTaskID: Int? = nil
    var onToggleFocus: ((Int) -> Void)? = nil
    var reorderableSummaryIDs: Set<Int> = []
    var onSelectDependency: ((Int, Int) -> Void)? = nil
    var onRemoveDependency: ((Int, Int) -> Void)? = nil
    var overlays: GanttOverlayData = .empty

    @Environment(\.colorScheme) var colorScheme
    // Memoized layout keyed by the input it was built from. A reference-type
    // box lets the accessor validate-and-rebuild during body evaluation
    // without state churn, so a stale cache (e.g. auto-fit changing
    // pixelsPerDay before onChange observes) rebuilds exactly once — not on
    // every access — and bars are never drawn at the wrong scale.
    private final class LayoutMemo {
        var input: GanttCanvasLayoutInput?
        var state: GanttCanvasLayoutState?
    }
    @State private var layoutMemo = LayoutMemo()

    private let trailingLabelHitWidth: CGFloat = 420

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
        showDependencyLinks: Bool = true,
        editableTaskIDs: Set<Int> = [],
        isEditModeActive: Bool = false,
        selectedTaskID: Int? = nil,
        selectedTaskIDs: Set<Int> = [],
        selectedDependency: GanttDependencySelection? = nil,
        pendingLinkSourceTaskID: Int? = nil,
        onMoveTask: ((Int, Int) -> Void)? = nil,
        onReorderTask: ((Int, Int) -> Void)? = nil,
        onResizeTask: ((Int, GanttResizeEdge, Int) -> Void)? = nil,
        onSelectTask: ((Int) -> Void)? = nil,
        onShowTaskDetails: ((Int, CGPoint, CGRect) -> Void)? = nil,
        onStartLinkingFromTask: ((Int) -> Void)? = nil,
        onSetTaskColor: ((Int, String?) -> Void)? = nil,
        focusedTaskID: Int? = nil,
        onToggleFocus: ((Int) -> Void)? = nil,
        reorderableSummaryIDs: Set<Int> = [],
        onSelectDependency: ((Int, Int) -> Void)? = nil,
        onRemoveDependency: ((Int, Int) -> Void)? = nil,
        overlays: GanttOverlayData = .empty
    ) {
        self.overlays = overlays
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
        self.showDependencyLinks = showDependencyLinks
        self.editableTaskIDs = editableTaskIDs
        self.isEditModeActive = isEditModeActive
        self.selectedTaskID = selectedTaskID
        self.selectedTaskIDs = selectedTaskIDs
        self.selectedDependency = selectedDependency
        self.pendingLinkSourceTaskID = pendingLinkSourceTaskID
        self.onMoveTask = onMoveTask
        self.onReorderTask = onReorderTask
        self.onResizeTask = onResizeTask
        self.onSelectTask = onSelectTask
        self.onShowTaskDetails = onShowTaskDetails
        self.onStartLinkingFromTask = onStartLinkingFromTask
        self.onSetTaskColor = onSetTaskColor
        self.focusedTaskID = focusedTaskID
        self.onToggleFocus = onToggleFocus
        self.reorderableSummaryIDs = reorderableSummaryIDs
        self.onSelectDependency = onSelectDependency
        self.onRemoveDependency = onRemoveDependency
    }

    /// Maps an inclusive [from...to] date span to an x/width in canvas
    /// coordinates, clipped to the visible timeline. Returns nil when the span
    /// lies entirely outside the chart. Used for holiday/event/leave bands.
    private func bandGeometry(from: Date, to: Date) -> (x: CGFloat, width: CGFloat)? {
        guard totalDays > 0 else { return nil }
        let cal = Calendar.current
        let origin = cal.startOfDay(for: startDate)
        let startOffset = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: from)).day ?? 0
        let endOffset = cal.dateComponents([.day], from: origin, to: cal.startOfDay(for: to)).day ?? 0
        let lo = max(0, min(startOffset, endOffset))
        let hi = min(totalDays - 1, max(startOffset, endOffset))
        guard hi >= lo else { return nil }
        let x = CGFloat(lo) * pixelsPerDay
        let width = CGFloat(hi - lo + 1) * pixelsPerDay
        return (x, width)
    }

    private var rowShadingOpacity: Double { colorScheme == .dark ? 0.08 : 0.04 }
    private var gridLineOpacity: Double { colorScheme == .dark ? 0.25 : 0.15 }
    private var weekendOpacity: Double { colorScheme == .dark ? 0.12 : 0.06 }
    private var barBgOpacity: Double { colorScheme == .dark ? 0.35 : 0.25 }
    private var baselineOpacity: Double { colorScheme == .dark ? 0.4 : 0.25 }

    /// The layout to render with, rebuilt lazily (and exactly once) whenever
    /// the inputs differ from what the memoized layout was built from.
    private var activeLayoutState: GanttCanvasLayoutState {
        let input = layoutInput
        if let cachedInput = layoutMemo.input, cachedInput == input, let cached = layoutMemo.state {
            return cached
        }
        let built = GanttCanvasLayoutState.build(
            tasks: tasks,
            allTasks: allTasks,
            rowIndexByTaskID: rowIndexByTaskID,
            startDate: startDate,
            totalDays: totalDays,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            showBaseline: showBaseline
        )
        layoutMemo.input = input
        layoutMemo.state = built
        return built
    }

    private var timelineContentWidth: CGFloat {
        activeLayoutState.timelineContentWidth
    }

    private var interactiveContentWidth: CGFloat {
        timelineContentWidth + trailingLabelHitWidth
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
        let expandedRect = visibleBounds.insetBy(dx: -120, dy: -rowHeight * 2)
        return activeLayoutState.dependencySegments.filter { segment in
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
        activeLayoutState.taskGeometryByID
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gridCanvas
                .drawingGroup()
            overlayBandFills
            taskBarsCanvas
            if showDependencyLinks {
                dependencyCanvas
            }
            overlayBandLabels
            tooltipOverlay
            linkSourceHighlightOverlay
            if showDependencyLinks {
                linkTargetHighlightOverlay
                dependencySelectionOverlay
            }
            taskRowHitOverlay
            summaryReorderOverlay
            editableBarsOverlay
        }
        .coordinateSpace(name: canvasCoordinateSpaceName)
    }

    private struct OverlayBandLabel: Identifiable {
        let id: UUID
        let text: String
        let tooltip: String
        let x: CGFloat
        let y: CGFloat
        let color: Color
    }

    /// Chips for leave *bars* only (on the resource's rows). Event and
    /// leave-column titles live in the header lane above the rows so they never
    /// overlap the first task/summary bar.
    private var overlayBandLabelItems: [OverlayBandLabel] {
        guard overlays.showLeave, !overlays.leaveAsColumns, !overlays.leaves.isEmpty else { return [] }
        var items: [OverlayBandLabel] = []
        let rowIndexByTaskID: [Int: Int] = Dictionary(
            visibleTaskRows.map { ($0.task.uniqueID, $0.index) },
            uniquingKeysWith: { first, _ in first }
        )
        for leave in overlays.leaves {
            guard let band = bandGeometry(from: leave.startDate, to: leave.endDate),
                  let taskIDs = overlays.taskIDsByResourceID[leave.resourceID],
                  let rowIndex = taskIDs.compactMap({ rowIndexByTaskID[$0] }).min() else { continue }
            let color = Color(hex: leave.effectiveColorHex) ?? .orange
            let resourceName = overlays.resourceNamesByID[leave.resourceID] ?? "Resource"
            let reason = leave.name.trimmingCharacters(in: .whitespaces)
            let hasReason = !reason.isEmpty && reason.caseInsensitiveCompare("Leave") != .orderedSame
            items.append(OverlayBandLabel(
                id: leave.id,
                text: hasReason ? "\(resourceName) · \(reason)" : resourceName,
                tooltip: "\(resourceName) — \(hasReason ? reason : "Leave")\n\(DateFormatting.shortDate(leave.startDate)) – \(DateFormatting.shortDate(leave.endDate))",
                x: band.x + 2,
                y: CGFloat(rowIndex) * rowHeight + 3,
                color: color
            ))
        }
        return items
    }

    private var overlayBandLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(overlayBandLabelItems) { item in
                Text(item.text)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(item.color.opacity(0.92), in: Capsule())
                    .fixedSize()
                    .help(item.tooltip)
                    .offset(x: item.x, y: item.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Full-height event/leave band *fills*, rendered as plain SwiftUI shapes
    /// (outside the drawingGroup grid canvas) so they appear in PDF/print export
    /// as well as on screen. Sits behind the task bars.
    private var overlayBandFills: some View {
        let totalHeight = CGFloat(tasks.count) * rowHeight
        return ZStack(alignment: .topLeading) {
            if overlays.showEvents {
                ForEach(overlays.events) { event in
                    if let band = bandGeometry(from: event.startDate, to: event.endDate) {
                        fullHeightBand(band: band, color: Color(hex: event.effectiveColorHex) ?? .red, height: totalHeight)
                    }
                }
            }
            if overlays.showLeave {
                ForEach(overlays.leaves) { leave in
                    if let band = bandGeometry(from: leave.startDate, to: leave.endDate) {
                        let color = Color(hex: leave.effectiveColorHex) ?? .orange
                        if overlays.leaveAsColumns {
                            fullHeightBand(band: band, color: color, height: totalHeight)
                        } else {
                            ForEach(leaveRowIndices(for: leave.resourceID), id: \.self) { rowIndex in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color.opacity(colorScheme == .dark ? 0.40 : 0.30))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(color.opacity(0.7), lineWidth: 0.75)
                                    )
                                    .frame(width: band.width, height: rowHeight - 4)
                                    .offset(x: band.x, y: CGFloat(rowIndex) * rowHeight + 2)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func fullHeightBand(band: (x: CGFloat, width: CGFloat), color: Color, height: CGFloat) -> some View {
        Rectangle()
            .fill(color.opacity(colorScheme == .dark ? 0.16 : 0.10))
            .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.5)).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(color.opacity(0.5)).frame(width: 1) }
            .frame(width: band.width, height: height, alignment: .topLeading)
            .offset(x: band.x, y: 0)
    }

    private func leaveRowIndices(for resourceID: Int) -> [Int] {
        guard let taskIDs = overlays.taskIDsByResourceID[resourceID] else { return [] }
        return visibleTaskRows.filter { taskIDs.contains($0.task.uniqueID) }.map(\.index)
    }

    private var summaryReorderRows: [(index: Int, task: ProjectTask)] {
        visibleTaskRows.filter { reorderableSummaryIDs.contains($0.task.uniqueID) }
    }

    private var summaryReorderOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(summaryReorderRows, id: \.task.uniqueID) { row in
                GanttBarView(
                    task: row.task,
                    startDate: startDate,
                    pixelsPerDay: pixelsPerDay,
                    rowIndex: row.index,
                    rowHeight: rowHeight,
                    coordinateSpaceName: canvasCoordinateSpaceName,
                    isEditable: true,
                    reorderOnly: true,
                    isSelected: selectedTaskID == row.task.uniqueID || selectedTaskIDs.contains(row.task.uniqueID),
                    onReorderTask: { rowDelta in
                        onReorderTask?(row.task.uniqueID, rowDelta)
                    },
                    onSelectTask: {
                        onSelectTask?(row.task.uniqueID)
                    },
                    onShowTaskDetails: { anchor in
                        onShowTaskDetails?(row.task.uniqueID, detailAnchor(for: anchor), visibleBounds)
                    },
                    onStartLinkingFromTask: {
                        onStartLinkingFromTask?(row.task.uniqueID)
                    }
                )
                .contextMenu {
                    if let onToggleFocus {
                        Button {
                            onToggleFocus(row.task.uniqueID)
                        } label: {
                            Label(
                                focusedTaskID == row.task.uniqueID ? "Exit Focus" : "Focus on This Phase",
                                systemImage: focusedTaskID == row.task.uniqueID ? "arrow.up.left.and.arrow.down.right" : "scope"
                            )
                        }
                    }
                    if onSetTaskColor != nil {
                        barColorMenu(for: row.task)
                    }
                }
            }
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
                    isSelected: selectedTaskID == row.task.uniqueID || selectedTaskIDs.contains(row.task.uniqueID),
                    isLinkSource: pendingLinkSourceTaskID == row.task.uniqueID,
                    onMoveTask: { dayDelta in
                        onMoveTask?(row.task.uniqueID, dayDelta)
                    },
                    onReorderTask: { rowDelta in
                        onReorderTask?(row.task.uniqueID, rowDelta)
                    },
                    onResizeTask: { edge, dayDelta in
                        onResizeTask?(row.task.uniqueID, edge, dayDelta)
                    },
                    onSelectTask: {
                        onSelectTask?(row.task.uniqueID)
                    },
                    onShowTaskDetails: { anchor in
                        let currentVisibleBounds = visibleBounds
                        onShowTaskDetails?(row.task.uniqueID, detailAnchor(for: anchor), currentVisibleBounds)
                    },
                    onStartLinkingFromTask: {
                        onStartLinkingFromTask?(row.task.uniqueID)
                    }
                )
                .contextMenu {
                    barColorMenu(for: row.task)
                }
            }
        }
    }

    @ViewBuilder
    private func barColorMenu(for task: ProjectTask) -> some View {
        Menu {
            ForEach(GanttChartView.barColorPresets, id: \.hex) { preset in
                Button {
                    onSetTaskColor?(task.uniqueID, preset.hex)
                } label: {
                    Label(preset.name, systemImage: task.barColorHex == preset.hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
            Divider()
            Button {
                onSetTaskColor?(task.uniqueID, nil)
            } label: {
                Label("Default Color", systemImage: "arrow.uturn.backward")
            }
            .disabled(task.barColorHex == nil)
        } label: {
            Label("Bar Color", systemImage: "paintpalette")
        }
    }

    private var taskRowHitOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleTaskRows, id: \.task.uniqueID) { row in
                if let geometry = taskGeometryByID[row.task.uniqueID] {
                    Button {
                        let anchor = CGPoint(
                            x: min(max(visibleBounds.midX, geometry.rowRect.minX + 12), interactiveContentWidth - 12),
                            y: geometry.rowRect.midY
                        )
                        onSelectTask?(row.task.uniqueID)
                        // In edit mode a row click only selects; the details
                        // card would sit on top of the bars and get in the
                        // way of dragging and resizing.
                        if !isEditModeActive {
                            onShowTaskDetails?(row.task.uniqueID, detailAnchor(for: anchor), visibleBounds)
                        }
                    } label: {
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: interactiveContentWidth, height: geometry.rowRect.height)
                    }
                    .buttonStyle(.plain)
                    .position(x: interactiveContentWidth / 2, y: geometry.rowRect.midY)
                    .help(tooltipFor(row.task))
                    .contextMenu {
                        if row.task.summary == true, !row.task.children.isEmpty, let onToggleFocus {
                            Button {
                                onToggleFocus(row.task.uniqueID)
                            } label: {
                                Label(
                                    focusedTaskID == row.task.uniqueID ? "Exit Focus" : "Focus on This Phase",
                                    systemImage: focusedTaskID == row.task.uniqueID ? "arrow.up.left.and.arrow.down.right" : "scope"
                                )
                            }
                        }
                        if onSetTaskColor != nil {
                            barColorMenu(for: row.task)
                        }
                    }
                }
            }
        }
    }

    private func detailAnchor(for point: CGPoint) -> CGPoint {
        let bounds = visibleBounds
        guard bounds.width > 0, bounds.height > 0 else {
            return point
        }

        return CGPoint(
            x: min(max(point.x, bounds.minX + 12), bounds.maxX - 12),
            y: min(max(point.y, bounds.minY + 12), bounds.maxY - 12)
        )
    }

    private var taskHelpOverlay: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleTaskRows, id: \.task.uniqueID) { row in
                if let taskRect = taskInteractiveRect(for: row.task) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: taskRect.width, height: taskRect.height)
                        .position(x: taskRect.midX, y: taskRect.midY)
                        .help(tooltipFor(row.task))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func detailAnchor(for taskRect: CGRect, clickLocation: CGPoint) -> CGPoint {
        let localClick = CGPoint(
            x: taskRect.minX + clickLocation.x,
            y: taskRect.minY + clickLocation.y
        )
        let bounds = visibleBounds
        guard bounds.width > 0, bounds.height > 0 else {
            return CGPoint(x: taskRect.maxX, y: taskRect.minY)
        }

        return CGPoint(
            x: min(max(localClick.x, bounds.minX + 12), bounds.maxX - 12),
            y: min(max(localClick.y, bounds.minY + 12), bounds.maxY - 12)
        )
    }

    private var visibleBounds: CGRect {
        if visibleRect != .zero {
            return visibleRect
        }
        return CGRect(x: 0, y: 0, width: interactiveContentWidth, height: CGFloat(tasks.count) * rowHeight)
    }

    private func taskHitRect(for task: ProjectTask) -> CGRect? {
        guard let geometry = taskGeometryByID[task.uniqueID] else { return nil }
        let baseRect = geometry.barRect ?? geometry.rowRect
        let minWidth: CGFloat = task.milestone == true ? 22 : 16
        let width = max(baseRect.width, minWidth)
        return CGRect(
            x: baseRect.midX - width / 2,
            y: baseRect.minY - 4,
            width: width,
            height: baseRect.height + 8
        )
    }

    private func taskInteractiveRect(for task: ProjectTask) -> CGRect? {
        guard let geometry = taskGeometryByID[task.uniqueID],
              let barHitRect = taskHitRect(for: task)
        else { return nil }

        var minX = barHitRect.minX
        var maxX = barHitRect.maxX

        if let baselineRect = geometry.baselineBarRect {
            minX = min(minX, baselineRect.minX - 6)
            maxX = max(maxX, baselineRect.maxX + 6)
        }

        // Canvas-drawn names and baseline variance badges sit outside short bars
        // and milestones. Keep those clicks attached to the same task.
        maxX += 360

        return CGRect(
            x: max(0, minX),
            y: geometry.rowRect.minY,
            width: max(16, min(interactiveContentWidth, maxX) - max(0, minX)),
            height: geometry.rowRect.height
        )
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

            // Holiday/event and leave band *fills* are drawn in `overlayBandFills`
            // (a plain SwiftUI layer, not this drawingGroup canvas) so they also
            // capture in the offscreen PDF/print bitmap.

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

            // --- Baseline Bars and Markers ---
            if showBaseline {
                let markerStyle = StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                for row in visibleTaskRows {
                    let task = row.task
                    let y = CGFloat(row.index) * rowHeight
                    guard task.hasBaseline else { continue }

                    if let xStart = taskGeometryByID[task.uniqueID]?.baselineStartX {
                        var line = Path()
                        line.move(to: CGPoint(x: xStart, y: y + 6))
                        line.addLine(to: CGPoint(x: xStart, y: y + rowHeight - 3))
                        context.stroke(line, with: .color(.gray.opacity(0.55)), style: markerStyle)
                    }

                    if let xFinish = taskGeometryByID[task.uniqueID]?.baselineFinishX {
                        var line = Path()
                        line.move(to: CGPoint(x: xFinish, y: y + 6))
                        line.addLine(to: CGPoint(x: xFinish, y: y + rowHeight - 3))
                        context.stroke(line, with: .color(.gray.opacity(0.55)), style: markerStyle)
                    }
                }

                for row in visibleTaskRows {
                    let task = row.task
                    guard let baseRect = taskGeometryByID[task.uniqueID]?.baselineBarRect else { continue }
                    let rr = RoundedRectangle(cornerRadius: 2).path(in: baseRect)
                    context.fill(rr, with: .color(.gray.opacity(0.65)))
                    context.stroke(rr, with: .color(.gray.opacity(0.85)), lineWidth: 0.5)
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

                if editableTaskIDs.contains(task.uniqueID) || reorderableSummaryIDs.contains(task.uniqueID) {
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
                    let milestoneColor = task.barColorHex.flatMap { Color(hex: $0) } ?? .orange
                    context.fill(diamond, with: .color(milestoneColor.opacity(taskOpacity)))

                    // Right-side label for milestones
                    let varianceDescriptor = showBaseline ? task.baselineVarianceDescriptor.flatMap { $0.days == 0 ? nil : $0 } : nil
                    let badgeWidth = varianceDescriptor.map { baselineBadgeWidth(for: $0) } ?? 0
                    let badgeX = cx + dSize / 2 + 6
                    if let varianceDescriptor {
                        drawBaselineBadge(
                            context: context,
                            descriptor: varianceDescriptor,
                            x: badgeX,
                            y: y + barInset,
                            opacity: taskOpacity
                        )
                    }
                    drawTaskName(
                        context: context,
                        task: task,
                        x: badgeX + (varianceDescriptor == nil ? 0 : badgeWidth + 6),
                        y: y + rowHeight / 2,
                        color: .primary,
                        opacity: taskOpacity
                    )
                    continue
                }

                guard let width = geometry.width else { continue }

                if task.summary == true {
                    // Summary bracket. A custom color highlights the whole phase.
                    let bracketColor = (task.barColorHex.flatMap { Color(hex: $0) } ?? .primary).opacity(0.6 * taskOpacity)
                    let bracketH: CGFloat = barHeight * 0.3
                    let bracketY = y + barInset + barHeight * 0.35
                    let rect = CGRect(x: xStart, y: bracketY, width: width, height: bracketH)
                    context.fill(Path(rect), with: .color(bracketColor))

                    // Left/right ticks
                    let tick: CGFloat = 3
                    var leftTick = Path()
                    leftTick.move(to: CGPoint(x: xStart, y: bracketY))
                    leftTick.addLine(to: CGPoint(x: xStart, y: bracketY + bracketH + tick))
                    context.stroke(leftTick, with: .color(bracketColor), lineWidth: 1.5)

                    var rightTick = Path()
                    rightTick.move(to: CGPoint(x: xStart + width, y: bracketY))
                    rightTick.addLine(to: CGPoint(x: xStart + width, y: bracketY + bracketH + tick))
                    context.stroke(rightTick, with: .color(bracketColor), lineWidth: 1.5)

                    let varianceDescriptor = showBaseline ? task.baselineVarianceDescriptor.flatMap { $0.days == 0 ? nil : $0 } : nil
                    let badgeWidth = varianceDescriptor.map { baselineBadgeWidth(for: $0) } ?? 0
                    let outsideX = xStart + width + 6
                    if let varianceDescriptor {
                        drawBaselineBadge(
                            context: context,
                            descriptor: varianceDescriptor,
                            x: outsideX,
                            y: y + barInset,
                            opacity: taskOpacity
                        )
                    }

                    drawTaskName(
                        context: context,
                        task: task,
                        x: outsideX + (varianceDescriptor == nil ? 0 : badgeWidth + 6),
                        y: y + rowHeight / 2,
                        color: .secondary,
                        opacity: taskOpacity
                    )
                } else {
                // Regular bar. A custom per-task color overrides the default
                // critical (red) / normal (blue) scheme.
                let customColor = task.barColorHex.flatMap { Color(hex: $0) }
                let fgColor: Color = customColor ?? (isCritical ? .red : .blue)
                let bgColor: Color = fgColor.opacity(barBgOpacity * taskOpacity)

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

                let varianceDescriptor = showBaseline ? task.baselineVarianceDescriptor.flatMap { $0.days == 0 ? nil : $0 } : nil
                let badgeWidth = varianceDescriptor.map { baselineBadgeWidth(for: $0) } ?? 0
                let shouldDrawInlineLabel = width >= 92
                let shouldDrawOutsideLabel = !shouldDrawInlineLabel
                let outsideBadgeX = xStart + width + 6

                if shouldDrawInlineLabel {
                    drawTaskName(
                        context: context,
                        task: task,
                        x: xStart + 5,
                        y: y + rowHeight / 2,
                        color: .primary,
                        opacity: taskOpacity
                    )
                }

                if let varianceDescriptor {
                    drawBaselineBadge(
                        context: context,
                        descriptor: varianceDescriptor,
                        x: outsideBadgeX,
                        y: y + barInset,
                        opacity: taskOpacity
                    )
                }

                if shouldDrawOutsideLabel {
                    let labelX = outsideBadgeX + (varianceDescriptor == nil ? 0 : badgeWidth + 6)
                    drawTaskName(
                        context: context,
                        task: task,
                        x: labelX,
                        y: y + rowHeight / 2,
                        color: .secondary,
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
                    with: .color(.secondary.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.25)
                )
                context.fill(arrowHeadPath(segment), with: .color(.secondary.opacity(0.72)))
            }
        }
        .allowsHitTesting(false)
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

    private func baselineBadgeWidth(for descriptor: BaselineVarianceDescriptor) -> CGFloat {
        max(CGFloat(descriptor.label.count) * 7 + 10, 32)
    }

    private func drawTaskName(
        context: GraphicsContext,
        task: ProjectTask,
        x: CGFloat,
        y: CGFloat,
        color: Color,
        opacity: Double
    ) {
        let label = Text(task.displayName)
            .font(.system(size: 9))
            .foregroundColor(color.opacity(opacity))
        context.draw(context.resolve(label), at: CGPoint(x: x, y: y), anchor: .leading)
    }
}

// MARK: - Holidays / Events / Leave editor

/// Authoring surface for visual-only timeline holidays/observances/events and
/// per-resource leave. Edits a working copy and hands the final arrays back via
/// `onSave` when the user commits. Never touches scheduling.
struct EventLeaveEditorView: View {
    enum Section: String, CaseIterable, Identifiable {
        case events = "Holidays & Events"
        case leave = "Resource Leave"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var events: [PlanTimelineEvent]
    @State private var leaves: [PlanResourceLeave]
    @State private var section: Section = .events
    let resources: [NativePlanResource]
    let onSave: ([PlanTimelineEvent], [PlanResourceLeave]) -> Void

    init(
        events: [PlanTimelineEvent],
        leaves: [PlanResourceLeave],
        resources: [NativePlanResource],
        onSave: @escaping ([PlanTimelineEvent], [PlanResourceLeave]) -> Void
    ) {
        self._events = State(initialValue: events)
        self._leaves = State(initialValue: leaves)
        self.resources = resources
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch section {
                case .events: eventsList
                case .leave: leaveList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: 640, height: 480)
    }

    private var header: some View {
        HStack {
            Label("Holidays, Events & Leave", systemImage: "calendar.badge.clock")
                .font(.headline)
            Spacer()
            Text("Visual only — does not reschedule tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button {
                switch section {
                case .events: addEvent()
                case .leave: addLeave()
                }
            } label: {
                Label(section == .events ? "Add Event" : "Add Leave", systemImage: "plus")
            }
            .disabled(section == .leave && resources.isEmpty)

            Menu {
                if section == .events {
                    Button("Download CSV Template") { CSVExporter.exportEventImportTemplateCSV() }
                    Button("Download Excel Template") { CSVExporter.exportEventImportTemplateExcel() }
                } else {
                    Button("Download CSV Template") { CSVExporter.exportLeaveImportTemplateCSV(resources: resources) }
                    Button("Download Excel Template") { CSVExporter.exportLeaveImportTemplateExcel(resources: resources) }
                }
            } label: {
                Label("Template", systemImage: "tablecells")
            }
            .fixedSize()

            Button {
                if section == .events {
                    if let imported = CSVExporter.importTimelineEvents() { events.append(contentsOf: imported) }
                } else {
                    if let imported = CSVExporter.importResourceLeaves(resources: resources) { leaves.append(contentsOf: imported) }
                }
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .disabled(section == .leave && resources.isEmpty)

            if section == .leave && resources.isEmpty {
                Text("Add a resource first to record leave.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                onSave(normalizedEvents, normalizedLeaves)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Events

    private var eventsList: some View {
        Group {
            if events.isEmpty {
                emptyState("No holidays or events yet.", systemImage: "calendar")
            } else {
                List {
                    ForEach($events) { $event in
                        TimelineEventRow(event: $event) {
                            events.removeAll { $0.id == event.id }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: Leave

    private var leaveList: some View {
        Group {
            if leaves.isEmpty {
                emptyState("No resource leave recorded yet.", systemImage: "figure.walk.departure")
            } else {
                List {
                    ForEach($leaves) { $leave in
                        ResourceLeaveRow(leave: $leave, resources: resources) {
                            leaves.removeAll { $0.id == leave.id }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func addEvent() {
        let today = Calendar.current.startOfDay(for: Date())
        events.append(PlanTimelineEvent(name: "New Event", startDate: today, endDate: today))
    }

    private func addLeave() {
        guard let resourceID = resources.first?.id else { return }
        let today = Calendar.current.startOfDay(for: Date())
        leaves.append(PlanResourceLeave(resourceID: resourceID, startDate: today, endDate: today))
    }

    private var normalizedEvents: [PlanTimelineEvent] {
        events.map { event in
            var normalized = event
            if normalized.endDate < normalized.startDate {
                normalized.endDate = normalized.startDate
            }
            return normalized
        }
    }

    private var normalizedLeaves: [PlanResourceLeave] {
        leaves.map { leave in
            var normalized = leave
            if normalized.endDate < normalized.startDate {
                normalized.endDate = normalized.startDate
            }
            return normalized
        }
    }
}

// MARK: - Reusable event / leave row editors

/// One editable holiday/observance/event row (color, name, kind, date range).
struct TimelineEventRow: View {
    @Binding var event: PlanTimelineEvent
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: event.colorHex.isEmpty ? event.effectiveColorHex : event.colorHex) ?? .accentColor },
                set: { event.colorHex = $0.hexString ?? "" }
            ))
            .labelsHidden()
            .frame(width: 40)

            TextField("Name", text: $event.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)

            Picker("", selection: $event.kind) {
                ForEach(PlanTimelineEvent.Kind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)

            DatePicker("", selection: $event.startDate, displayedComponents: .date)
                .labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("", selection: $event.endDate, displayedComponents: .date)
                .labelsHidden()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// One editable resource-leave row (color, resource, reason, date range).
struct ResourceLeaveRow: View {
    @Binding var leave: PlanResourceLeave
    let resources: [NativePlanResource]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { Color(hex: leave.colorHex.isEmpty ? leave.effectiveColorHex : leave.colorHex) ?? .accentColor },
                set: { leave.colorHex = $0.hexString ?? "" }
            ))
            .labelsHidden()
            .frame(width: 40)

            Picker("", selection: $leave.resourceID) {
                ForEach(resources, id: \.id) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 150)

            TextField("Reason", text: $leave.name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 100)

            DatePicker("", selection: $leave.startDate, displayedComponents: .date)
                .labelsHidden()
            Text("→").foregroundStyle(.secondary)
            DatePicker("", selection: $leave.endDate, displayedComponents: .date)
                .labelsHidden()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Full-screen Events & Leave manager (sidebar destination)

/// Sidebar destination for managing holidays/observances/events and per-resource
/// leave. Edits persist directly to the SwiftData-backed plan. Visual only.
struct EventsLeaveManagerView: View {
    @Environment(\.modelContext) private var modelContext
    let planModel: PortfolioProjectPlan

    @State private var events: [PlanTimelineEvent]
    @State private var leaves: [PlanResourceLeave]

    init(planModel: PortfolioProjectPlan) {
        self.planModel = planModel
        _events = State(initialValue: planModel.nativeTimelineEventsForUI)
        _leaves = State(initialValue: planModel.nativeResourceLeavesForUI)
    }

    private var resources: [NativePlanResource] { planModel.nativeResourcesForUI }

    /// Combined events + leave, mapped to timeline rows for the right pane.
    private var timelineItems: [EventsLeaveTimelineView.Item] {
        var result: [EventsLeaveTimelineView.Item] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            result.append(.init(
                id: event.id,
                name: event.name,
                subtitle: event.kind.label,
                start: event.startDate,
                end: event.endDate,
                colorHex: event.effectiveColorHex
            ))
        }
        let names = Dictionary(resources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for leave in leaves.sorted(by: { $0.startDate < $1.startDate }) {
            let resourceName = names[leave.resourceID] ?? "Resource"
            let reason = leave.name.trimmingCharacters(in: .whitespaces)
            let hasReason = !reason.isEmpty && reason.caseInsensitiveCompare("Leave") != .orderedSame
            result.append(.init(
                id: leave.id,
                name: resourceName,
                subtitle: hasReason ? reason : "Leave",
                start: leave.startDate,
                end: leave.endDate,
                colorHex: leave.effectiveColorHex
            ))
        }
        return result
    }

    @State private var isEditing = false

    var body: some View {
        EventsLeaveTimelineView(
            items: timelineItems,
            title: planModel.title.isEmpty ? "Plan" : planModel.title,
            onEdit: { isEditing = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isEditing) {
            EventLeaveEditorView(
                events: events,
                leaves: leaves,
                resources: resources,
                onSave: { newEvents, newLeaves in
                    events = newEvents
                    leaves = newLeaves
                    persist()
                }
            )
        }
    }

    private func persist() {
        planModel.timelineEvents = events.map { event in
            var normalized = event
            if normalized.endDate < normalized.startDate { normalized.endDate = normalized.startDate }
            return normalized
        }
        planModel.resourceLeaves = leaves.map { leave in
            var normalized = leave
            if normalized.endDate < normalized.startDate { normalized.endDate = normalized.startDate }
            return normalized
        }
        planModel.updatedAt = Date()
        try? modelContext.save()
    }
}

// MARK: - Events & Leave timeline (Gantt of only events/leaves)

/// A focused Gantt-style timeline that plots only holidays/observances/events
/// and resource leave — each as its own labelled bar row — with zoom and
/// PDF/SVG export. Used on the right side of the Events & Leave manager.
struct EventsLeaveTimelineView: View {
    struct Item: Identifiable {
        let id: UUID
        let name: String
        let subtitle: String
        let start: Date
        let end: Date
        let colorHex: String
    }

    let items: [Item]
    let title: String
    var onEdit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var pixelsPerDay: CGFloat = 5
    @State private var shouldAutoFit = true
    @State private var viewportWidth: CGFloat = 0

    private let nameColumnWidth: CGFloat = 220
    private let rowHeight: CGFloat = 30
    private let headerHeight: CGFloat = 44

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        guard let minStart = items.map(\.start).min(),
              let maxEnd = items.map(\.end).max() else {
            let today = cal.startOfDay(for: Date())
            return (today, cal.date(byAdding: .day, value: 30, to: today) ?? today)
        }
        let start = cal.date(byAdding: .day, value: -7, to: minStart) ?? minStart
        let end = cal.date(byAdding: .day, value: 7, to: maxEnd) ?? maxEnd
        return (cal.startOfDay(for: start), cal.startOfDay(for: end))
    }

    private var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 1)
    }

    private var timelineWidth: CGFloat { CGFloat(totalDays) * pixelsPerDay }

    private func dayOffset(_ date: Date) -> CGFloat {
        CGFloat(Calendar.current.dateComponents([.day], from: dateRange.start, to: Calendar.current.startOfDay(for: date)).day ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing to Plot",
                    systemImage: "calendar.badge.clock",
                    description: Text("Add holidays, events, or resource leave to see them on the timeline.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        timelineContent
                            .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    }
                    .onAppear { fit(to: geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, w in fit(to: w) }
                    .onChange(of: totalDays) { _, _ in if shouldAutoFit { fit(to: geometry.size.width) } }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Events & Leave")
                .font(.headline)
            Text("(\(items.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "square.and.pencil").font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .help("Add, edit, or remove holidays, events, and resource leave.")

                Divider().frame(height: 16)
            }

            Menu {
                Button { exportPDF() } label: { Label("Export PDF…", systemImage: "doc.richtext") }
                Button { exportSVG() } label: { Label("Export SVG (Vector)…", systemImage: "square.on.square.dashed") }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up").font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(items.isEmpty)

            Divider().frame(height: 16)

            GanttZoomControls(
                pixelsPerDay: pixelsPerDay,
                totalDays: totalDays,
                onFitAll: { shouldAutoFit = true; fit(to: viewportWidth) },
                onShowWeek: { shouldAutoFit = false; pixelsPerDay = 24 },
                onShowMonth: { shouldAutoFit = false; pixelsPerDay = 8 },
                onZoomOut: { shouldAutoFit = false; pixelsPerDay = max(2, pixelsPerDay / 1.5) },
                onZoomIn: { shouldAutoFit = false; pixelsPerDay = min(100, pixelsPerDay * 1.5) }
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var timelineContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Details").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(width: nameColumnWidth, height: headerHeight, alignment: .bottomLeading)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                Divider()

                ForEach(items) { item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: item.colorHex) ?? .accentColor)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.caption).fontWeight(.medium).lineLimit(1)
                            Text("\(item.subtitle) · \(DateFormatting.shortDate(item.start)) – \(DateFormatting.shortDate(item.end))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: nameColumnWidth, height: rowHeight, alignment: .leading)
                    .padding(.horizontal, 8)
                    Divider()
                }
            }
            .frame(width: nameColumnWidth)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                GanttHeaderView(dateRange: dateRange, pixelsPerDay: pixelsPerDay, totalWidth: timelineWidth)
                timelineCanvas
                    .frame(width: timelineWidth, height: CGFloat(items.count) * rowHeight)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var timelineCanvas: some View {
        Canvas { context, size in
            // Row separators
            for row in 0...items.count {
                let y = CGFloat(row) * rowHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
            }

            for (index, item) in items.enumerated() {
                let y = CGFloat(index) * rowHeight
                let x1 = dayOffset(item.start) * pixelsPerDay
                let x2 = (dayOffset(item.end) + 1) * pixelsPerDay
                let w = max(3, x2 - x1)
                let color = Color(hex: item.colorHex) ?? .accentColor
                let rect = CGRect(x: x1, y: y + 5, width: w, height: rowHeight - 10)
                let rr = RoundedRectangle(cornerRadius: 4).path(in: rect)
                context.fill(rr, with: .color(color.opacity(0.85)))
                context.stroke(rr, with: .color(color), lineWidth: 0.75)

                let label = Text(item.name).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                context.draw(context.resolve(label), at: CGPoint(x: x1 + 6, y: y + rowHeight / 2), anchor: .leading)
            }
        }
    }

    private func fit(to width: CGFloat) {
        viewportWidth = width
        guard shouldAutoFit, width > 0 else { return }
        let available = max(50, width - nameColumnWidth - 1)
        pixelsPerDay = max(2, min(100, available / CGFloat(max(1, totalDays))))
    }

    // MARK: Export

    private var exportContentSize: CGSize {
        CGSize(width: nameColumnWidth + 1 + timelineWidth, height: headerHeight + CGFloat(items.count) * rowHeight)
    }

    @MainActor
    private func exportPDF() {
        guard !items.isEmpty else { return }
        PDFExporter.exportGanttToPDF(
            view: timelineContent.frame(width: exportContentSize.width, height: exportContentSize.height, alignment: .topLeading),
            contentSize: exportContentSize,
            fileName: "\(title) - Events \(PDFExporter.fileNameTimestamp).pdf"
        )
    }

    @MainActor
    private func exportSVG() {
        guard !items.isEmpty else { return }
        let rows: [SVGExporter.GanttRow] = items.map { item in
            let dates = "\(DateFormatting.shortDate(item.start)) – \(DateFormatting.shortDate(item.end))"
            let subtitle = item.subtitle.isEmpty ? dates : "\(item.subtitle) · \(dates)"
            return SVGExporter.GanttRow(
                name: item.name,
                outlineLevel: 1,
                start: item.start,
                finish: item.end,
                isMilestone: false,
                isSummary: false,
                isCritical: false,
                percentComplete: 0,
                colorHex: item.colorHex,
                subtitle: subtitle
            )
        }
        SVGExporter.exportGantt(
            rows: rows,
            rangeStart: dateRange.start,
            rangeEnd: dateRange.end,
            pixelsPerDay: max(2, pixelsPerDay),
            rowHeight: rowHeight,
            title: "\(title) — Events & Leave",
            fileName: "\(title) - Events \(PDFExporter.fileNameTimestamp).svg"
        )
    }
}
