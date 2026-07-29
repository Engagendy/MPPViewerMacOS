import SwiftUI
import AppKit

private struct ScheduleVerticalOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScheduleHorizontalOffsetPreferenceKey: PreferenceKey {
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
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var criticalPathOnly: Bool = false
    @State private var showDependencyLinks: Bool = true
    @State private var showBaseline: Bool = false
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    @State private var selectedScheduleTaskID: Int?
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

    private var chartScrollableWidth: CGFloat {
        timelineWidth + 460
    }

    private var ganttHeaderHeight: CGFloat {
        pixelsPerDay < 15 ? 64 : 44
    }

    private var taskRowsContentHeight: CGFloat {
        CGFloat(visibleTasks.count) * rowHeight
    }

    private func clampedVerticalOffset(_ value: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        min(max(0, value), max(0, taskRowsContentHeight - viewportHeight))
    }

    private func scrollScheduleRows(by deltaY: CGFloat, viewportHeight: CGFloat) {
        verticalScrollOffset = clampedVerticalOffset(verticalScrollOffset - deltaY, viewportHeight: viewportHeight)
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
                    .buttonStyle(.accessoryBar)
                    .font(.caption)
                    .disabled(collapsedIDs.isEmpty)

                    Button("Collapse All") {
                        for task in allTasksFlat(project.rootTasks) where task.summary == true && !task.children.isEmpty {
                            collapsedIDs.insert(task.uniqueID)
                        }
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.caption)

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

                    Toggle(isOn: $showBaseline) {
                        Label("Baseline", systemImage: "clock.arrow.2.circlepath")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .hoverHighlight()
                    .buttonStyle(.bordered)
                    .tint(showBaseline ? .gray : nil)
                    .help("Shows the saved baseline schedule as gray bars below the current bars, with start/finish variance badges.")

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
                    .topAlignedEmptyState()
            } else {
                scheduleContent
            }
        }
        .onAppear {
            refreshDerivedContent()
        }
        .onChange(of: collapsedIDs) { _, _ in
            refreshDerivedContent()
        }
        .onChange(of: searchText) { _, _ in
            scheduleSearchRefresh()
        }
        .onChange(of: scheduleRefreshSignature) { _, _ in
            refreshDerivedContent()
        }
    }

    // MARK: - Combined Schedule Content

    private var taskListWidth: CGFloat { 470 }

    /// Matches GanttChartView: trailing area past the last activity so bar
    /// labels of the final tasks stay readable and the chart always has
    /// horizontal room to scroll into.
    private let timelineTrailingLabelWidth: CGFloat = 420

    private var timelineScrollableWidth: CGFloat {
        timelineWidth + timelineTrailingLabelWidth
    }

    /// Two panes side by side, each with its own native scroller: the task
    /// list scrolls vertically on its own, and the timeline scrolls both
    /// axes on its own. Pure SwiftUI, so it stays inside the safe area.
    private var scheduleContent: some View {
        GeometryReader { geometry in
            let viewportWidth = max(geometry.size.width - taskListWidth - 1, 1)

            HStack(spacing: 0) {
                taskListPane

                Divider()

                timelinePane
            }
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
    }

    private var taskListPane: some View {
        VStack(spacing: 0) {
            // Column headers stay pinned while the rows scroll below them.
            HStack(spacing: 0) {
                Text("ID")
                    .frame(width: 40, alignment: .leading)
                Text("Name")
                    .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
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

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleTasks.enumerated()), id: \.element.uniqueID) { index, task in
                        scheduleTaskRow(task: task, index: index)
                    }
                }
            }
        }
        .frame(width: taskListWidth, alignment: .topLeading)
    }

    private var timelinePane: some View {
        BothAxesScrollView(
            contentSize: CGSize(
                width: timelineScrollableWidth,
                height: ganttHeaderHeight + taskRowsContentHeight
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                GanttHeaderView(
                    dateRange: dateRange,
                    pixelsPerDay: pixelsPerDay,
                    totalWidth: timelineScrollableWidth
                )
                .frame(height: ganttHeaderHeight)

                GanttCanvasView(
                    tasks: visibleTasks,
                    allTasks: project.tasksByID,
                    rowIndexByTaskID: derivedContent.rowIndexByTaskID,
                    startDate: dateRange.start,
                    totalDays: totalDays,
                    pixelsPerDay: pixelsPerDay,
                    rowHeight: rowHeight,
                    visibleRect: CGRect(
                        x: 0,
                        y: 0,
                        width: timelineScrollableWidth,
                        height: taskRowsContentHeight
                    ),
                    criticalPathOnly: criticalPathOnly,
                    showBaseline: showBaseline,
                    showDependencyLinks: showDependencyLinks,
                    selectedTaskID: selectedScheduleTaskID,
                    onSelectTask: { selectedScheduleTaskID = $0 }
                )
                .frame(width: timelineScrollableWidth, height: taskRowsContentHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)

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
        .background(
            selectedScheduleTaskID == task.uniqueID
                ? Color.accentColor.opacity(0.16)
                : (index % 2 == 0 ? Color.gray.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedScheduleTaskID = task.uniqueID
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
            verticalScrollOffset = clampedVerticalOffset(verticalScrollOffset, viewportHeight: 1)
        }
    }

    private func scheduleSearchRefresh() {
        searchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            refreshDerivedContent()
        }
        searchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }
}

private struct ScheduleScrollWheelCapture: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class ScrollWheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
                onScroll?(event.scrollingDeltaY)
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}

/// AppKit-backed scroll view with genuine two-axis native scrolling.
/// SwiftUI's ScrollView([.horizontal, .vertical]) fails to provide a working
/// horizontal scroller in this layout on macOS 26, so the timeline pane hosts
/// its SwiftUI content inside an NSScrollView instead.
private struct BothAxesScrollView<Content: View>: NSViewRepresentable {
    private let contentSize: CGSize
    private let content: Content

    init(contentSize: CGSize, @ViewBuilder content: () -> Content) {
        self.contentSize = contentSize
        self.content = content()
    }

    final class Coordinator {
        var hosting: NSHostingView<AnyView>?
        var document: FlippedDocumentView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let document = FlippedDocumentView()
        let hosting = NSHostingView(rootView: anchoredContent)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: document.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        document.setFrameSize(contentSize)
        scrollView.documentView = document

        context.coordinator.hosting = hosting
        context.coordinator.document = document
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let hosting = context.coordinator.hosting,
              let document = context.coordinator.document else { return }
        hosting.rootView = anchoredContent
        document.setFrameSize(contentSize)
    }

    /// The hosting view centers its root view when its bounds exceed the
    /// content's fixed size (which happens transiently while auto-fit
    /// settles); anchoring top-leading keeps the chart pinned to the origin.
    private var anchoredContent: AnyView {
        AnyView(
            content.frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        )
    }

    /// Anchors the document at the top-left so scrolling starts at the top.
    final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }
}
