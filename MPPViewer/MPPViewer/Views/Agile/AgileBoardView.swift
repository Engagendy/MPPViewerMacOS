import SwiftUI
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

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

private struct AgileBoardLaneDisplay: Identifiable {
    let lane: String
    let tasks: [NativePlanTask]
    let groups: [AgileSwimlaneGroup]
    let activeTaskCount: Int

    var id: String { lane }
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
    @State private var laneDisplays: [AgileBoardLaneDisplay] = []
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

    private var selectedSprintTasks: [NativePlanTask] {
        guard let selectedSprintID else { return [] }
        return derivedContent.tasksBySprintID[selectedSprintID] ?? []
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
            refreshLaneDisplays()
        }
        .onChange(of: planModel.updatedAt) { _, _ in
            refreshDerivedContent()
            syncAgileInspectorDraft(force: true)
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
        .onChange(of: boardSprintScope) { _, _ in
            refreshLaneDisplays()
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
        modelContext.saveReportingFailures()
    }

    private func withAgileTask(_ taskID: Int, _ update: (PortfolioPlanTask) -> Void) {
        guard let task = planModel.tasks.first(where: { $0.legacyID == taskID }) else { return }
        update(task)
        persistAgileStoreChanges()
    }

    private func withAgileSprint(_ sprintID: Int, _ update: (PortfolioPlanSprint) -> Void) {
        guard let sprint = planModel.sprints.first(where: { $0.legacyID == sprintID }) else { return }
        update(sprint)
        persistAgileStoreChanges()
    }

    private func fullSyncAgilePlan(_ update: (inout NativeProjectPlan) -> Void) {
        var snapshot = planModel.asNativePlan()
        update(&snapshot)
        planModel.update(from: snapshot)
        persistAgileStoreChanges(refreshMetrics: true)
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
                    .hoverHighlight()

                    Button {
                        addSprint()
                    } label: {
                        Label("Add Sprint", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
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
            .hoverHighlight()
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
            .hoverHighlight()
            .help("Group the board by sprint, epic, or parent work item.")

            if boardSwimlaneMode != .none {
                Button("Expand All") {
                    collapsedSwimlaneKeys.removeAll()
                }
                .buttonStyle(.bordered)
                .hoverHighlight()
                .controlSize(.small)

                Button("Collapse All") {
                    collapsedSwimlaneKeys = Set(laneDisplays.flatMap { $0.groups.map(\.key) })
                }
                .buttonStyle(.bordered)
                .hoverHighlight()
                .controlSize(.small)
            }

            Button {
                newBucketName = ""
                isPresentingAddBucketSheet = true
            } label: {
                Label("Add Bucket", systemImage: "rectangle.badge.plus")
            }
            .buttonStyle(.bordered)
            .hoverHighlight()

            Button {
                workflowDesignerScope = .shared
                workflowDraft = workflowColumns
                isPresentingWorkflowDesigner = true
            } label: {
                Label("Workflow", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .hoverHighlight()

            Button {
                showsInspector.toggle()
            } label: {
                Label(showsInspector ? "Hide Details" : "Show Details", systemImage: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .hoverHighlight()

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
                    ForEach(laneDisplays) { laneDisplay in
                        laneColumn(laneDisplay)
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
                .hoverHighlight()
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
                .hoverHighlight()

                Spacer()

                if case .itemType(let itemType) = workflowDesignerScope,
                   hasTypeWorkflowOverride(for: itemType) {
                    Button("Use Shared Rules") {
                        resetTypeWorkflowOverride(itemType: itemType)
                    }
                    .buttonStyle(.bordered)
                    .hoverHighlight()
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
                .hoverHighlight()
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }

    private func laneColumn(_ laneDisplay: AgileBoardLaneDisplay) -> some View {
        let lane = laneDisplay.lane
        let tint = laneColor(for: lane)
        let laneIndex = boardColumns.firstIndex(of: lane)
        let laneWIP = wipLimit(for: lane)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lane)
                        .font(.headline)
                    Text(laneWIP.map { "\(laneDisplay.activeTaskCount) / \($0) active" } ?? "\(laneDisplay.tasks.count) items")
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
                    .buttonStyle(.accessoryBar)
                    .disabled(laneIndex == nil || laneIndex == 0)
                    .accessibilityLabel("Move \(lane) bucket left")
                    .help("Move this bucket left.")

                    Button {
                        moveBucket(lane, direction: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(laneIndex == nil || laneIndex == boardColumns.count - 1)
                    .accessibilityLabel("Move \(lane) bucket right")
                    .help("Move this bucket right.")

                    Button(role: .destructive) {
                        deleteBucket(lane)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.accessoryBar)
                    .disabled(boardColumns.count <= 1)
                    .accessibilityLabel("Delete \(lane) bucket")
                    .accessibilityHint("Moves its tasks to a neighboring lane")
                    .help("Delete this bucket and move its tasks to a neighboring lane.")
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(laneDisplay.groups) { group in
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
                .hoverHighlight()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(boardCardAccessibilityLabel(task, isDone: isDone, isOverdue: isOverdue))
        .accessibilityHint("Selects this card. Use the context menu to move it between buckets or assign a sprint.")
        .accessibilityAddTraits(selectedTaskID == task.id ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            selectBoardTask(task.id)
        }
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

    /// Single VoiceOver sentence for a board card: name, type, bucket, sprint,
    /// points, progress, and overdue/done state.
    private func boardCardAccessibilityLabel(_ task: NativePlanTask, isDone: Bool, isOverdue: Bool) -> String {
        var parts = ["\(task.agileType): \(task.name)", "in \(task.boardStatus)"]
        if let sprintID = task.sprintID, let sprintName = derivedContent.sprintNamesByID[sprintID] {
            parts.append("sprint \(sprintName)")
        } else {
            parts.append("in backlog")
        }
        if let points = task.storyPoints {
            parts.append("\(points) story points")
        }
        parts.append("\(Int(task.percentComplete)) percent complete")
        if isOverdue {
            parts.append("overdue")
        } else if isDone {
            parts.append("done")
        }
        return parts.joined(separator: ", ")
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
                        .hoverHighlight()
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
                                    CalendarDatePicker(title: "Start", date: sprintDateBinding(sprintID: selectedSprintID, keyPath: \.startDate))
                                    CalendarDatePicker(title: "Finish", date: sprintDateBinding(sprintID: selectedSprintID, keyPath: \.endDate))
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
            .hoverHighlight()

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
                            value: "\(derivedContent.totalSprintCapacityPoints)",
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
                                count: derivedContent.agileTypeCounts[type] ?? 0,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: workItem)
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
        derivedContent.normalizedStatusByTaskID[task.id]
            ?? {
                let normalized = task.boardStatus.trimmingCharacters(in: .whitespacesAndNewlines)
                return boardColumns.first(where: { $0.compare(normalized, options: .caseInsensitive) == .orderedSame }) ?? boardColumns.first ?? "Backlog"
            }()
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
            let currentCount = derivedContent.tasksByLane.first(where: { $0.lane == lane })?.tasks.filter {
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
        derivedContent.committedPointsBySprintID[sprintID] ?? 0
    }

    private func completedPoints(for sprintID: Int) -> Int {
        derivedContent.completedPointsBySprintID[sprintID] ?? 0
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

    private func primaryAssigneeName(for task: NativePlanTask) -> String? {
        derivedContent.primaryAssigneeNameByTaskID[task.id]
    }

    private func teamSwimlaneTitle(for task: NativePlanTask) -> String {
        derivedContent.teamTitleByTaskID[task.id] ?? "No Team"
    }

    private func boardTaskAssignmentSummary(_ task: NativePlanTask) -> String? {
        derivedContent.assignmentSummaryByTaskID[task.id]
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

    private func refreshLaneDisplays() {
        laneDisplays = derivedContent.tasksByLane.map { laneGroup in
            let scopedTasks = filterTasksForBoardScope(laneGroup.tasks)
            let activeTaskCount = scopedTasks.filter {
                $0.percentComplete < 100
                    && (derivedContent.normalizedStatusByTaskID[$0.id]?.compare("Done", options: .caseInsensitive) != .orderedSame)
            }.count
            return AgileBoardLaneDisplay(
                lane: laneGroup.lane,
                tasks: scopedTasks,
                groups: swimlaneGroups(for: scopedTasks, lane: laneGroup.lane),
                activeTaskCount: activeTaskCount
            )
        }
    }

    private func refreshDerivedContent() {
        PerformanceMonitor.measure("AgileBoard.RefreshDerived") {
            let nextDerivedContent = AgileBoardDerivedContent.build(
                tasks: nativeTasks,
                assignments: nativeAssignments,
                resources: nativeResources,
                sprints: nativeSprints,
                boardColumns: planModel.boardColumns,
                workflowColumns: workflowColumns,
                typeWorkflowOverrides: typeWorkflowOverrides,
                statusSnapshots: nativeStatusSnapshots
            )
            derivedContent = nextDerivedContent
            refreshLaneDisplays()
        }
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
