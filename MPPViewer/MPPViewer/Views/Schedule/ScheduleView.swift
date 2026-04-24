import SwiftUI

private struct ScheduleVerticalOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScheduleDerivedContent {
    let visibleTasks: [ProjectTask]
    let rowIndexByTaskID: [Int: Int]
    let totalDays: Int
    let dateRange: (start: Date, end: Date)

    static func build(project: ProjectModel, searchText: String, collapsedIDs: Set<Int>) -> ScheduleDerivedContent {
        let filteredTasks: [ProjectTask]
        if searchText.isEmpty {
            filteredTasks = project.rootTasks
        } else {
            filteredTasks = filterTasks(project.rootTasks, searchText: searchText.lowercased())
        }

        let visibleTasks = flattenTasks(filteredTasks, collapsedIDs: collapsedIDs)
        let rowIndexByTaskID = Dictionary(nonThrowingUniquePairs: visibleTasks.enumerated().map { ($1.uniqueID, $0) })
        let dateRange = GanttDateHelpers.dateRange(for: project.tasks)
        return ScheduleDerivedContent(
            visibleTasks: visibleTasks,
            rowIndexByTaskID: rowIndexByTaskID,
            totalDays: GanttDateHelpers.totalDays(for: dateRange),
            dateRange: dateRange
        )
    }

    private static func flattenTasks(_ tasks: [ProjectTask], collapsedIDs: Set<Int>) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty && !collapsedIDs.contains(task.uniqueID) {
                result.append(contentsOf: flattenTasks(task.children, collapsedIDs: collapsedIDs))
            }
        }
        return result
    }

    private static func filterTasks(_ tasks: [ProjectTask], searchText: String) -> [ProjectTask] {
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
}

struct ScheduleView: View {
    let project: ProjectModel
    let searchText: String

    @State private var derivedContent: ScheduleDerivedContent
    @State private var pixelsPerDay: CGFloat = 8
    @State private var timelineViewportWidth: CGFloat = 0
    @State private var shouldAutoFitTimeline = true
    @State private var collapsedIDs: Set<Int> = []
    @State private var verticalScrollOffset: CGFloat = 0
    private let rowHeight: CGFloat = 24

    private var visibleTasks: [ProjectTask] {
        derivedContent.visibleTasks
    }

    private var dateRange: (start: Date, end: Date) {
        derivedContent.dateRange
    }

    private var totalDays: Int {
        derivedContent.totalDays
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * pixelsPerDay
    }

    private var taskRowsContentHeight: CGFloat {
        CGFloat(visibleTasks.count) * rowHeight
    }

    init(project: ProjectModel, searchText: String) {
        self.project = project
        self.searchText = searchText
        self._derivedContent = State(initialValue: ScheduleDerivedContent.build(project: project, searchText: searchText, collapsedIDs: []))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Schedule")
                    .font(.headline)
                Text("(\(visibleTasks.count) tasks)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button("Expand All") {
                        collapsedIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(collapsedIDs.isEmpty)

                    Button("Collapse All") {
                        for task in allTasksFlat(project.rootTasks) where task.summary == true && !task.children.isEmpty {
                            collapsedIDs.insert(task.uniqueID)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if visibleTasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "rectangle.split.2x1")
            } else {
                HSplitView {
                    // Left pane: task list
                    taskListPane
                        .frame(minWidth: 250, idealWidth: 350, maxWidth: 500)

                    // Right pane: Gantt chart
                    ganttPane
                }
            }
        }
        .onAppear {
            refreshDerivedContent()
        }
        .onChange(of: collapsedIDs) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: searchText) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: scheduleRefreshSignature) { _, _ in
            refreshDerivedContent()
        }
    }

    // MARK: - Left Pane: Task List

    private var taskListPane: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Column headers
                HStack(spacing: 0) {
                    Text("ID")
                        .frame(width: 40, alignment: .leading)
                    Text("Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Duration")
                        .frame(width: 70, alignment: .trailing)
                    Text("Start")
                        .frame(width: 80, alignment: .trailing)
                    Text("Finish")
                        .frame(width: 80, alignment: .trailing)
                    Text("% Done")
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                GeometryReader { rowsGeometry in
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleTasks.enumerated()), id: \.element.uniqueID) { index, task in
                            scheduleTaskRow(task: task, index: index)
                        }
                    }
                    .frame(height: taskRowsContentHeight, alignment: .top)
                    .offset(y: -verticalScrollOffset)
                    .frame(width: rowsGeometry.size.width, height: rowsGeometry.size.height, alignment: .topLeading)
                    .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func scheduleTaskRow(task: ProjectTask, index: Int) -> some View {
        let isSummaryWithChildren = task.summary == true && !task.children.isEmpty
        let isCollapsed = collapsedIDs.contains(task.uniqueID)

        return HStack(spacing: 0) {
            Text(task.id.map(String.init) ?? "")
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)

            HStack(spacing: 2) {
                let indent = CGFloat((task.outlineLevel ?? 1) - 1) * 12
                Spacer().frame(width: max(0, indent))

                if isSummaryWithChildren {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }

                if task.summary == true {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                } else if task.milestone == true {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }

                Text(task.displayName)
                    .fontWeight(task.summary == true ? .semibold : .regular)
                    .foregroundStyle(task.critical == true ? .red : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.durationDisplay)
                .frame(width: 70, alignment: .trailing)

            Text(DateFormatting.shortDate(task.start))
                .frame(width: 80, alignment: .trailing)

            Text(DateFormatting.shortDate(task.finish))
                .frame(width: 80, alignment: .trailing)

            Text(task.percentCompleteDisplay)
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(index % 2 == 0 ? Color.gray.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSummaryWithChildren {
                if isCollapsed {
                    collapsedIDs.remove(task.uniqueID)
                } else {
                    collapsedIDs.insert(task.uniqueID)
                }
            }
        }
    }

    // MARK: - Right Pane: Gantt

    private var ganttPane: some View {
        GeometryReader { geometry in
            let viewportWidth = max(geometry.size.width, 1)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ScheduleVerticalOffsetPreferenceKey.self,
                                value: -proxy.frame(in: .named("ScheduleScrollView")).minY
                            )
                    }
                    .frame(height: 0)

                    GanttHeaderView(
                        dateRange: dateRange,
                        pixelsPerDay: pixelsPerDay,
                        totalWidth: timelineWidth
                    )

                    GanttCanvasView(
                        tasks: visibleTasks,
                        allTasks: project.tasksByID,
                        rowIndexByTaskID: derivedContent.rowIndexByTaskID,
                        startDate: dateRange.start,
                        totalDays: totalDays,
                        pixelsPerDay: pixelsPerDay,
                        rowHeight: rowHeight
                    )
                    .frame(width: timelineWidth, height: CGFloat(visibleTasks.count) * rowHeight)
                }
                .frame(minHeight: geometry.size.height, alignment: .topLeading)
            }
            .coordinateSpace(name: "ScheduleScrollView")
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
            .onPreferenceChange(ScheduleVerticalOffsetPreferenceKey.self) { newValue in
                verticalScrollOffset = max(0, newValue)
            }
        }
    }

    // MARK: - Helpers

    private func allTasksFlat(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result: [ProjectTask] = []
        for task in tasks {
            result.append(task)
            if !task.children.isEmpty {
                result.append(contentsOf: allTasksFlat(task.children))
            }
        }
        return result
    }

    private func applyAutoFitIfNeeded() {
        guard shouldAutoFitTimeline, timelineViewportWidth > 0 else { return }
        pixelsPerDay = fittedPixelsPerDay(for: timelineViewportWidth)
    }

    private func fittedPixelsPerDay(for viewportWidth: CGFloat) -> CGFloat {
        max(2, min(100, viewportWidth / CGFloat(max(totalDays, 1))))
    }

    private var scheduleRefreshSignature: Int {
        var hasher = Hasher()
        hasher.combine(project.tasks.count)
        for task in project.tasks {
            hasher.combine(task.uniqueID)
            hasher.combine(task.start ?? "")
            hasher.combine(task.finish ?? "")
            hasher.combine(task.percentComplete ?? 0)
            hasher.combine(task.summary == true)
            hasher.combine(task.children.count)
        }
        return hasher.finalize()
    }

    private func refreshDerivedContent() {
        withAnimation(nil) {
            derivedContent = ScheduleDerivedContent.build(project: project, searchText: searchText, collapsedIDs: collapsedIDs)
        }
    }
}
