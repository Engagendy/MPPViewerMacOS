import SwiftUI

struct TaskTableView: View {
    let tasks: [ProjectTask]
    let allTasks: [Int: ProjectTask]
    let searchText: String
    var resources: [ProjectResource] = []
    var assignments: [ResourceAssignment] = []
    @Binding var flaggedTaskIDs: Set<Int>
    var navigateToTaskID: Binding<Int?>? = nil

    @State private var collapsedIDs: Set<Int> = []
    @State private var selectedTaskID: Int? = nil
    @State private var filterCriteria = TaskFilterCriteria()
    @State private var grouping: TaskGrouping = .none
    @State private var visibleCustomColumns: Set<String> = []
    @State private var showColumnPicker = false
    @State private var dependencyBreadcrumbs: [Int] = []
    @AppStorage("selectedTaskViewPreset") private var selectedTaskViewPresetRaw = TaskViewPreset.none.rawValue
    @AppStorage("taskInspectorWidth") private var storedInspectorWidth = 360.0
    @AppStorage(ReviewNotesStore.key) private var taskReviewNotesData: Data = Data()

    private var searchedTasks: [ProjectTask] {
        guard !searchText.isEmpty else { return tasks }
        return filterTasks(tasks, searchText: searchText.lowercased())
    }

    private var hasStructuredFilters: Bool {
        filterCriteria.status != .all ||
        filterCriteria.resourceID != nil ||
        filterCriteria.dateRangeStart != nil ||
        filterCriteria.dateRangeEnd != nil ||
        filterCriteria.criticalOnly ||
        filterCriteria.milestoneOnly ||
        filterCriteria.priorityRange != nil ||
        !filterCriteria.textSearch.isEmpty ||
        filterCriteria.flaggedOnly ||
        filterCriteria.baselineSlippedOnly ||
        filterCriteria.hasDependenciesOnly ||
        filterCriteria.annotatedOnly ||
        filterCriteria.unresolvedOnly ||
        filterCriteria.followUpOnly
    }

    private var statusFilteredTaskIDs: Set<Int>? {
        guard hasStructuredFilters else { return nil }
        return matchingTaskIDs(in: searchedTasks)
    }

    var filteredTasks: [ProjectTask] {
        guard let statusFilteredTaskIDs else { return searchedTasks }
        return searchedTasks.filter { task in
            subtreeContainsMatch(task, matchingIDs: statusFilteredTaskIDs)
        }
    }

    private var selectedTask: ProjectTask? {
        guard let id = selectedTaskID else { return nil }
        return allTasks[id]
    }

    private var reviewAnnotations: [Int: TaskReviewAnnotation] {
        ReviewNotesStore.decodeAnnotations(taskReviewNotesData)
    }

    private var availableCustomFieldKeys: [String] {
        var keys = Set<String>()
        for task in project_tasks(tasks) {
            if let cf = task.customFields {
                keys.formUnion(cf.keys)
            }
        }
        return keys.sorted()
    }

    var body: some View {
        GeometryReader { geometry in
            let inspectorWidth = clampedInspectorWidth(for: geometry.size.width)

            HStack(spacing: 0) {
                // Main table
                VStack(spacing: 0) {
                    // Filter Bar
                    FilterBarView(
                        criteria: $filterCriteria,
                        grouping: $grouping,
                        resources: resources,
                        onClear: {
                            selectedTaskViewPresetRaw = TaskViewPreset.none.rawValue
                        }
                    )
                    Divider()

                    // Toolbar
                    HStack {
                        Button("Expand All") {
                            collapsedIDs.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .disabled(collapsedIDs.isEmpty)

                        Button("Collapse All") {
                            for task in project_tasks(filteredTasks) where task.summary == true && !task.children.isEmpty {
                                collapsedIDs.insert(task.uniqueID)
                            }
                        }
                        .buttonStyle(.borderless)

                        Divider().frame(height: 16)

                        Picker("Preset", selection: Binding(
                            get: { TaskViewPreset(rawValue: selectedTaskViewPresetRaw) ?? .none },
                            set: { newValue in
                                selectedTaskViewPresetRaw = newValue.rawValue
                                filterCriteria.applyPreset(newValue)
                                grouping = .none
                            }
                        )) {
                            ForEach(TaskViewPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .frame(width: 180)
                        .font(.caption)

                        Spacer()

                        HStack(spacing: 14) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.fill").font(.caption2).foregroundStyle(.blue)
                                Text("Summary").font(.caption)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(.orange)
                                Text("Milestone").font(.caption)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("Critical").font(.caption)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(.primary).frame(width: 8, height: 8)
                                Text("Normal").font(.caption)
                            }
                        }
                        .foregroundStyle(.secondary)

                        Divider().frame(height: 16)

                        if !availableCustomFieldKeys.isEmpty {
                            Button {
                                showColumnPicker.toggle()
                            } label: {
                                Label("Columns", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showColumnPicker) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Custom Columns")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.bottom, 4)
                                    ForEach(availableCustomFieldKeys, id: \.self) { key in
                                        Toggle(key, isOn: Binding(
                                            get: { visibleCustomColumns.contains(key) },
                                            set: { isOn in
                                                if isOn && visibleCustomColumns.count < 5 {
                                                    visibleCustomColumns.insert(key)
                                                } else {
                                                    visibleCustomColumns.remove(key)
                                                }
                                            }
                                        ))
                                        .font(.caption)
                                    }
                                }
                                .padding()
                                .frame(minWidth: 180)
                            }

                            Divider().frame(height: 16)
                        }

                        Button {
                            PDFExporter.exportTaskListToPDF(
                                tasks: filteredTasks,
                                allTasks: allTasks,
                                fileName: "Task List \(PDFExporter.fileNameTimestamp).pdf"
                            )
                        } label: {
                            Label("Export PDF", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Export task list as PDF")

                        Button {
                            CSVExporter.exportTasksToCSV(
                                tasks: filteredTasks,
                                allTasks: allTasks,
                                resources: resources,
                                assignments: assignments,
                                fileName: "Task List \(PDFExporter.fileNameTimestamp).csv"
                            )
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                        .buttonStyle(.borderless)
                        .help("Export task list as CSV")

                        Button {
                            printTaskList()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        .buttonStyle(.borderless)
                        .help("Print task list")

                        if selectedTaskID != nil {
                            Divider().frame(height: 16)
                            Button {
                                selectedTaskID = nil
                            } label: {
                                Image(systemName: "sidebar.trailing")
                            }
                            .buttonStyle(.borderless)
                            .help("Hide inspector")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)

                    if visibleTasks.isEmpty {
                        ContentUnavailableView(
                            filteredTasks.isEmpty ? "No Matching Tasks" : "No Visible Tasks",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(emptyStateDescription)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Table(of: ProjectTask.self) {
                        // Flag column
                        TableColumn("") { task in
                            Button {
                                if flaggedTaskIDs.contains(task.uniqueID) {
                                    flaggedTaskIDs.remove(task.uniqueID)
                                } else {
                                    flaggedTaskIDs.insert(task.uniqueID)
                                }
                            } label: {
                                Image(systemName: flaggedTaskIDs.contains(task.uniqueID) ? "flag.fill" : "flag")
                                    .font(.caption2)
                                    .foregroundStyle(flaggedTaskIDs.contains(task.uniqueID) ? .orange : .secondary.opacity(0.4))
                            }
                            .buttonStyle(.borderless)
                        }
                        .width(24)

                        TableColumn("ID") { task in
                            Text(task.id.map(String.init) ?? "")
                                .monospacedDigit()
                        }
                        .width(min: 30, ideal: 50, max: 60)

                        TableColumn("WBS") { task in
                            Text(task.wbs ?? "")
                                .monospacedDigit()
                        }
                        .width(min: 40, ideal: 60, max: 80)

                        TableColumn("Name") { task in
                            let isSummaryWithChildren = task.summary == true && !task.children.isEmpty
                            let isCollapsed = collapsedIDs.contains(task.uniqueID)
                            let isSelected = selectedTaskID == task.uniqueID

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    let indent = CGFloat((task.outlineLevel ?? 1) - 1) * 16
                                    Spacer().frame(width: max(0, indent))

                                    if isSummaryWithChildren {
                                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 12)

                                        Image(systemName: "folder.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.blue)
                                    } else if task.milestone == true {
                                        Spacer().frame(width: 16)
                                        Image(systemName: "diamond.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    } else {
                                        Spacer().frame(width: 16)
                                    }

                                    Text(task.displayName)
                                        .fontWeight(task.summary == true ? .semibold : .regular)
                                        .foregroundStyle(task.critical == true ? .red : .primary)
                                        .lineLimit(1)
                                }
                                HStack(spacing: 6) {
                                    baselineDeltaBadge(for: task)
                                    reviewAnnotationBadges(for: task)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(3)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSummaryWithChildren {
                                    if isCollapsed {
                                        collapsedIDs.remove(task.uniqueID)
                                    } else {
                                        collapsedIDs.insert(task.uniqueID)
                                    }
                                }
                                selectedTaskID = task.uniqueID
                                dependencyBreadcrumbs = [task.uniqueID]
                            }
                            .cursor(isSummaryWithChildren ? .pointingHand : .arrow)
                        }
                        .width(min: 200, ideal: 350)

                        TableColumn("Duration") { task in
                            Text(task.durationDisplay)
                        }
                        .width(min: 60, ideal: 90, max: 120)

                        TableColumn("Start") { task in
                            Text(DateFormatting.shortDate(task.start))
                        }
                        .width(min: 70, ideal: 90, max: 110)

                        TableColumn("Finish") { task in
                            Text(DateFormatting.shortDate(task.finish))
                        }
                        .width(min: 70, ideal: 90, max: 110)

                        TableColumn("% Complete") { task in
                            HStack(spacing: 6) {
                                let pct = task.percentComplete ?? 0
                                ProgressView(value: pct, total: 100)
                                    .frame(width: 50)
                                    .tint(task.isOverdue ? .red : .accentColor)
                                Text(task.percentCompleteDisplay)
                                    .monospacedDigit()
                                    .font(.caption)
                                    .foregroundStyle(task.isOverdue ? .red : .primary)
                            }
                        }
                        .width(min: 80, ideal: 110, max: 140)

                        TableColumn("Predecessors") { task in
                            if let preds = task.predecessors, !preds.isEmpty {
                                let predText = preds.compactMap { rel -> String? in
                                    guard let predTask = allTasks[rel.targetTaskUniqueID] else { return nil }
                                    let taskID = predTask.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
                                    let suffix = rel.type == "FS" ? "" : (rel.type ?? "")
                                    return taskID + suffix
                                }.joined(separator: ", ")
                                Text(predText)
                                    .font(.caption)
                            }
                        }
                        .width(min: 60, ideal: 100, max: 150)
                    } rows: {
                        if grouping != .none {
                            ForEach(groupedTasks, id: \.key) { group in
                                Section(group.key) {
                                    ForEach(group.tasks) { task in
                                        TableRow(task)
                                    }
                                }
                            }
                        } else {
                            ForEach(visibleTasks) { task in
                                TableRow(task)
                            }
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onKeyPress(.escape) {
                    selectedTaskID = nil
                    return .handled
                }

                if let task = selectedTask {
                    inspectorResizeHandle(totalWidth: geometry.size.width)

                    TaskDetailView(
                        task: task,
                        allTasks: allTasks,
                        resources: resources,
                        assignments: assignments,
                        breadcrumbTaskIDs: dependencyBreadcrumbs,
                        onSelectTask: { uniqueID in
                            if selectedTaskID != uniqueID {
                                selectedTaskID = uniqueID
                                appendDependencyBreadcrumb(uniqueID)
                            }
                        },
                        onSelectBreadcrumb: { uniqueID in
                            selectedTaskID = uniqueID
                            trimDependencyBreadcrumbs(to: uniqueID)
                        }
                    )
                    .frame(width: inspectorWidth)
                }
            }
        }
        .onChange(of: navigateToTaskID?.wrappedValue) { _, newID in
            if let id = newID {
                selectedTaskID = id
                if dependencyBreadcrumbs.last != id {
                    appendDependencyBreadcrumb(id)
                }
                navigateToTaskID?.wrappedValue = nil
            }
        }
        .onAppear {
            filterCriteria.applyPreset(TaskViewPreset(rawValue: selectedTaskViewPresetRaw) ?? .none)
            if let selectedTaskID, dependencyBreadcrumbs.isEmpty {
                dependencyBreadcrumbs = [selectedTaskID]
            }
        }
    }

    private var visibleTasks: [ProjectTask] {
        let collapsedSet = statusFilteredTaskIDs == nil ? collapsedIDs : []
        var tasks = flattenTasks(searchedTasks, collapsedIDs: collapsedSet)
        if let statusFilteredTaskIDs {
            tasks = tasks.filter { statusFilteredTaskIDs.contains($0.uniqueID) }
        }
        return tasks
    }

    private func clampedInspectorWidth(for totalWidth: CGFloat) -> CGFloat {
        let minWidth: CGFloat = 320
        let maxWidth = max(minWidth, totalWidth - 420)
        return min(max(CGFloat(storedInspectorWidth), minWidth), maxWidth)
    }

    private func inspectorResizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .overlay {
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let proposedWidth = storedInspectorWidth - value.translation.width
                        storedInspectorWidth = Double(min(max(proposedWidth, 320), totalWidth - 420))
                    }
            )
    }

    private var emptyStateDescription: String {
        if tasks.isEmpty {
            return "This project has no tasks."
        }
        if !searchText.isEmpty || filterCriteria.isActive || grouping != .none {
            return "No tasks match the current search or filters. Adjust the filters above to see tasks again."
        }
        return "There are no tasks to display."
    }

    private func appendDependencyBreadcrumb(_ uniqueID: Int) {
        if let existingIndex = dependencyBreadcrumbs.firstIndex(of: uniqueID) {
            dependencyBreadcrumbs = Array(dependencyBreadcrumbs.prefix(existingIndex + 1))
        } else {
            dependencyBreadcrumbs.append(uniqueID)
        }
    }

    private func trimDependencyBreadcrumbs(to uniqueID: Int) {
        if let existingIndex = dependencyBreadcrumbs.firstIndex(of: uniqueID) {
            dependencyBreadcrumbs = Array(dependencyBreadcrumbs.prefix(existingIndex + 1))
        } else {
            dependencyBreadcrumbs = [uniqueID]
        }
    }

    private func flattenTasks(_ tasks: [ProjectTask], collapsedIDs: Set<Int>) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty && !collapsedIDs.contains(task.uniqueID) {
                result.append(contentsOf: flattenTasks(task.children, collapsedIDs: collapsedIDs))
            }
        }
        return result
    }

    private func project_tasks(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty {
                result.append(contentsOf: project_tasks(task.children))
            }
        }
        return result
    }

    private func filterTasks(_ tasks: [ProjectTask], searchText: String) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            let childMatches = filterTasks(task.children, searchText: searchText)
            let selfMatches = task.name?.lowercased().contains(searchText) == true

            if selfMatches || !childMatches.isEmpty {
                result.append(task)
            }
        }
        return result
    }

    private func applyFilterCriteria(_ tasks: [ProjectTask]) -> [ProjectTask] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [ProjectTask] = []
        for task in tasks {
            if filterCriteria.matches(
                task,
                assignments: assignments,
                resources: resources,
                flaggedTaskIDs: flaggedTaskIDs,
                annotations: reviewAnnotations,
                today: today
            ) {
                result.append(task)
            }
            // Also check children
            for child in task.children {
                if filterCriteria.matches(
                    child,
                    assignments: assignments,
                    resources: resources,
                    flaggedTaskIDs: flaggedTaskIDs,
                    annotations: reviewAnnotations,
                    today: today
                ) {
                    if !result.contains(where: { $0.uniqueID == task.uniqueID }) {
                        result.append(task)
                    }
                }
            }
        }
        return result
    }

    private func matchingTaskIDs(in tasks: [ProjectTask]) -> Set<Int> {
        let today = Calendar.current.startOfDay(for: Date())
        var result = Set<Int>()

        func visit(_ task: ProjectTask) {
            if filterCriteria.matches(
                task,
                assignments: assignments,
                resources: resources,
                flaggedTaskIDs: flaggedTaskIDs,
                annotations: reviewAnnotations,
                today: today
            ) {
                result.insert(task.uniqueID)
            }
            for child in task.children {
                visit(child)
            }
        }

        for task in tasks {
            visit(task)
        }

        return result
    }

    private func subtreeContainsMatch(_ task: ProjectTask, matchingIDs: Set<Int>) -> Bool {
        if matchingIDs.contains(task.uniqueID) {
            return true
        }
        return task.children.contains { subtreeContainsMatch($0, matchingIDs: matchingIDs) }
    }

    @ViewBuilder
    private func baselineDeltaBadge(for task: ProjectTask) -> some View {
        if let descriptor = task.baselineVarianceDescriptor {
            Text(descriptor.label)
                .font(.caption2)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(descriptor.color.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(descriptor.color.opacity(0.7), lineWidth: 0.8)
                )
        }
    }

    @ViewBuilder
    private func reviewAnnotationBadges(for task: ProjectTask) -> some View {
        if let annotation = reviewAnnotations[task.uniqueID], annotation.hasContent {
            Text(annotation.status.rawValue)
                .font(.caption2)
                .foregroundStyle(reviewStatusColor(annotation.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(reviewStatusColor(annotation.status).opacity(0.14))
                )

            if annotation.needsFollowUp {
                Text("Follow-Up")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.14))
                    )
            }
        }
    }

    private func reviewStatusColor(_ status: ReviewStatus) -> Color {
        switch status {
        case .notReviewed:
            return .secondary
        case .inReview:
            return .blue
        case .waiting:
            return .orange
        case .resolved:
            return .green
        }
    }

    private func printTaskList() {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text("Task List")
                .font(.title2)
                .padding(.bottom, 8)
            ForEach(visibleTasks) { task in
                HStack {
                    Text(task.id.map(String.init) ?? "")
                        .frame(width: 40, alignment: .trailing)
                    Text(task.wbs ?? "")
                        .frame(width: 60)
                    Text(task.displayName)
                        .fontWeight(task.summary == true ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(task.durationDisplay)
                        .frame(width: 80)
                    Text(DateFormatting.shortDate(task.start))
                        .frame(width: 90)
                    Text(DateFormatting.shortDate(task.finish))
                        .frame(width: 90)
                    Text(task.percentCompleteDisplay)
                        .frame(width: 50)
                }
                .font(.caption)
                Divider()
            }
        }
        .padding()

        let size = CGSize(width: 792, height: max(612, CGFloat(visibleTasks.count) * 20 + 80))
        PrintManager.printView(content, size: size, title: "Task List")
    }

    private struct TaskGroup: Identifiable {
        let key: String
        let tasks: [ProjectTask]
        var id: String { key }
    }

    private var groupedTasks: [TaskGroup] {
        let flat = visibleTasks
        var groups: [String: [ProjectTask]] = [:]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for task in flat {
            let key: String
            switch grouping {
            case .none:
                key = ""
            case .resource:
                let taskAssignments = assignments.filter { $0.taskUniqueID == task.uniqueID }
                let resourceNames = taskAssignments.compactMap { a in
                    resources.first(where: { $0.uniqueID == a.resourceUniqueID })?.name
                }
                key = resourceNames.isEmpty ? "Unassigned" : resourceNames.joined(separator: ", ")
            case .outlineLevel:
                key = "Level \(task.outlineLevel ?? 0)"
            case .status:
                let pct = task.percentComplete ?? 0
                if pct >= 100 {
                    key = "Complete"
                } else if pct > 0 {
                    key = "In Progress"
                } else if let finish = task.finishDate, finish < today {
                    key = "Overdue"
                } else {
                    key = "Not Started"
                }
            case .priority:
                key = "Priority \(task.priority ?? 500)"
            case .wbsPrefix:
                let wbs = task.wbs ?? ""
                key = String(wbs.prefix(while: { $0 != "." }))
            }
            groups[key, default: []].append(task)
        }

        return groups.sorted { $0.key < $1.key }.map { TaskGroup(key: $0.key, tasks: $0.value) }
    }
}
